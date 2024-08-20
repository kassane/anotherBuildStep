//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const zigcc = @import("zigcc.zig");
const dep = @import("depsIterate.zig");
const artifact = @import("artifact.zig"); // TODO: replace 'Step.Run' to 'Step.Compile'

// Swiftc 6
pub fn BuildStep(b: *std.Build, options: SwiftCompileStep) !*std.Build.Step.Run {
    var swiftc_exec = b.addSystemCommand(&.{"swiftc"});
    swiftc_exec.setName(options.name);

    swiftc_exec.setEnvironmentVariable("LD_LIBRARY_PATH", "/home/kassane/Downloads/swift-6.0-DEVELOPMENT-SNAPSHOT-2024-08-19-a-ubuntu22.04/lib");

    // set kind of build
    switch (options.kind) {
        .@"test" => swiftc_exec.addArg("-enable-testing"),
        .lib => swiftc_exec.addArg("-emit-library"),
        .obj => swiftc_exec.addArg("-emit-object"),
        // .exe => swiftc_exec.addArg("-emit-executable"),
        else => {},
    }

    if (options.flags) |flags| {
        for (flags) |flag| {
            swiftc_exec.addArg(flag);
        }
    }

    if (options.ldflags) |ldflags| {
        for (ldflags) |ldflag| {
            if (ldflag[0] == '-') {
                @panic("ldflags: add library name only!");
            }
            swiftc_exec.addArg(b.fmt("-L-l{s}", .{ldflag}));
        }
    }

    // Swift Imports & C Includes
    if (options.importPaths) |imports| {
        for (imports) |import| {
            if (import[0] == '-') {
                @panic("Import: add import paths only!");
            }
            swiftc_exec.addArg(b.fmt("-I{s}", .{import}));
        }
    }

    if (options.cIncludePaths) |includes| {
        for (includes) |include| {
            if (include[0] == '-') {
                @panic("Include: add C include paths only!");
            }
            swiftc_exec.addArgs(&.{ "-Xcc", b.fmt("-I{s}", .{include}) });
        }
    }

    switch (options.optimize) {
        .Debug => swiftc_exec.addArgs(&.{"-g"}),
        .ReleaseSafe => swiftc_exec.addArgs(&.{"-O"}),
        .ReleaseFast => swiftc_exec.addArgs(&.{"-Ounchecked"}),
        .ReleaseSmall => swiftc_exec.addArgs(&.{"-Osize"}),
    }

    // object file output (zig-cache/o/{hash_id}/*.o)
    if (b.cache_root.path) |path| {
        swiftc_exec.addArg("-cache-compile-job");
        // immutable state hash
        swiftc_exec.addArgs(&.{
            "-clang-scanner-module-cache-path", b.pathJoin(&.{ path, "o", &b.graph.cache.hash.peek() }),
        });
        // mutable state hash
        swiftc_exec.addArgs(&.{
            "-module-cache-path",
            b.pathJoin(&.{ path, "o", &b.graph.cache.hash.final() }),
        });
    }

    // swift-packages include path
    if (options.swift_packages) |d_packages| {
        for (d_packages) |pkg| {
            swiftc_exec.addArg(b.fmt("-I{s}", .{pkg}));
        }
    }

    // Swift Source files
    for (options.sources) |src| {
        swiftc_exec.addArg(src);
    }

    // MS Linker
    if (options.target.result.abi == .msvc and options.optimize == .Debug and !options.use_zigcc) {
        swiftc_exec.addArgs(&.{ "-Xlinker", "-lmsvcrtd" });
        swiftc_exec.addArgs(&.{ "-Xlinker", "/NODEFAULTLIB:libcmt.lib" });
        swiftc_exec.addArgs(&.{ "-Xlinker", "/NODEFAULTLIB:libvcruntime.lib" });
    }
    // GNU LD
    if (options.target.result.os.tag == .linux and !options.use_zigcc) {
        // swiftc_exec.addArgs(&.{ "-Xlinker", "--no-as-needed" });
    }
    // LLD
    if (options.target.result.isDarwin() and !options.use_zigcc) {
        swiftc_exec.addArgs(&.{ "-Xlinker", "-w" }); // hide linker warnings
    }

    if (options.target.result.isWasm()) {
        swiftc_exec.addArgs(&.{ "-Xlinker", "-allow-undefined" });
        swiftc_exec.addArgs(&.{ "-Xlinker", "--no-entry" });
    }

    if (b.verbose) {
        swiftc_exec.addArg("-v");
    }

    if (options.artifact) |lib| {
        // C include path
        for (lib.root_module.include_dirs.items) |include_dir| {
            if (include_dir == .other_step) continue;
            const path = if (include_dir == .path)
                include_dir.path.getPath(b)
            else if (include_dir == .path_system)
                include_dir.path_system.getPath(b)
            else
                include_dir.path_after.getPath(b);
            swiftc_exec.addArgs(&.{
                "-Xcc",
                b.fmt("-I{s}", .{path}),
            });
        }

        // library paths
        for (lib.root_module.lib_paths.items) |libDir| {
            if (libDir.getPath(b).len > 0) // skip empty paths
                swiftc_exec.addArg(b.fmt("-L{s}", .{libDir.getPath(b)}));
        }

        // link system libs
        for (lib.root_module.link_objects.items) |link_object| {
            if (link_object != .system_lib) continue;
            const system_lib = link_object.system_lib;
            swiftc_exec.addArg(b.fmt("-l{s}", .{system_lib.name}));
        }
        // C flags
        for (lib.root_module.link_objects.items) |link_object| {
            if (link_object != .c_source_file) continue;
            const c_source_file = link_object.c_source_file;
            for (c_source_file.flags) |flag|
                if (flag.len > 0) // skip empty flags
                    swiftc_exec.addArgs(&.{ "-Xcc", flag });
            break;
        }
        // C defines
        for (lib.root_module.c_macros.items) |cdefine| {
            if (cdefine.len > 0) // skip empty cdefines
                swiftc_exec.addArgs(&.{
                    "-Xcc",
                    b.fmt("-D{s}", .{cdefine}),
                });
            // swiftc_exec.addArgs(&.{ "-define-availability", cdefine });
            break;
        }

        // Darwin frameworks
        if (options.target.result.isDarwin()) {
            var it = lib.root_module.frameworks.iterator();
            while (it.next()) |framework| {
                swiftc_exec.addArg(b.fmt("-framework", .{}));
                swiftc_exec.addArg(b.fmt("{s}", .{framework.key_ptr.*}));
            }
        }

        if (lib.root_module.sanitize_thread) |tsan| {
            if (tsan)
                swiftc_exec.addArg("-sanitize=thread");
        }

        // zig enable sanitize=undefined by default
        if (lib.root_module.sanitize_c) |ubsan| {
            if (ubsan)
                swiftc_exec.addArg("-sanitize=address");
        }

        // link-time optimization
        if (lib.want_lto) |enabled|
            if (enabled) swiftc_exec.addArg("-lto=llvm-full");
    }

    if (options.target.result.os.tag == .freestanding) {
        swiftc_exec.addArgs(&.{
            "-enable-experimental-feature",
            "Embedded",
        });
    } else {
        swiftc_exec.addArg("-static-stdlib");
    }

    // ldc2 doesn't support zig native (a.k.a: native-native or native)
    const mtriple = if (options.target.result.isDarwin())
        b.fmt("{s}-apple-{s}", .{ if (options.target.result.cpu.arch.isAARCH64()) "arm64" else @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag) })
    else if (options.target.result.isWasm() and options.target.result.os.tag == .freestanding)
        b.fmt("{s}-unknown-unknown-wasm", .{@tagName(options.target.result.cpu.arch)})
    else if (options.target.result.isWasm())
        b.fmt("{s}-unknown-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag) })
    else if (options.target.result.cpu.arch.isRISCV())
        b.fmt("{s}-unknown-{s}", .{ @tagName(options.target.result.cpu.arch), if (options.target.result.os.tag == .freestanding) "elf" else @tagName(options.target.result.os.tag) })
    else if (options.target.result.cpu.arch == .x86)
        b.fmt("i686-{s}-{s}", .{ @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) })
    else
        b.fmt("{s}-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) });
    _ = mtriple; // autofix

    // swiftc_exec.addArgs(&.{ "-target", mtriple });
    // cpu model (e.g. "generic" or )
    // swiftc_exec.addArg(b.fmt("-mcpu={s}", .{options.target.result.cpu.model.llvm_name orelse "generic"}));

    const outputDir = switch (options.kind) {
        .lib => "lib",
        .exe => "bin",
        .@"test" => "test",
        .obj => "obj",
    };
    const outputName = switch (options.kind) {
        .lib => if (options.target.result.abi != .msvc) try std.mem.join(b.allocator, "", &.{ outputDir, options.name }) else options.name,
        else => options.name,
    };

    // output file
    if (options.kind != .obj)
        swiftc_exec.addArgs(&.{
            "-o", b.pathJoin(&.{ b.install_prefix, outputDir, outputName }),
        });

    if (options.use_zigcc) {
        const zcc = zigcc.buildZigCC(b, options.t_options.?);
        swiftc_exec.addPrefixedFileArg("-use-ld=", zcc.getEmittedBin());
    }

    if (options.artifact) |lib| {
        swiftc_exec.addArtifactArg(lib);
        dep.dependenciesIterator(lib, swiftc_exec);
    }

    const example_run = b.addSystemCommand(&.{b.pathJoin(&.{ b.install_path, outputDir, options.name })});
    example_run.step.dependOn(&swiftc_exec.step);

    const run = if (options.kind != .@"test")
        b.step(b.fmt("run-{s}", .{options.name}), b.fmt("Run {s} example", .{options.name}))
    else
        b.step("test", "Run all tests");
    run.dependOn(&example_run.step);

    return swiftc_exec;
}

pub const SwiftCompileStep = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
    kind: std.Build.Step.Compile.Kind = .exe,
    linkage: std.builtin.LinkMode = .static,
    sources: []const []const u8,
    flags: ?[]const []const u8 = null,
    ldflags: ?[]const []const u8 = null,
    name: []const u8,
    swift_packages: ?[]const []const u8 = null,
    cIncludePaths: ?[]const []const u8 = null,
    importPaths: ?[]const []const u8 = null,
    artifact: ?*std.Build.Step.Compile = null,
    use_zigcc: bool = false,
    t_options: ?*std.Build.Step.Options = null,
};
