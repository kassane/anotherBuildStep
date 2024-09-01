//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const zigcc = @import("zigcc.zig");
const dep = @import("depsIterate.zig");

// flang support
pub fn BuildStep(b: *std.Build, options: FlangCompileStep) !*std.Build.Step.InstallDir {
    const flang = try b.findProgram(&.{ "flang-new", "flang" }, &.{});

    // Fortran compiler
    var flang_exec = b.addSystemCommand(&.{flang});
    flang_exec.setName(options.name);

    switch (options.kind) {
        .obj => flang_exec.addArg("-c"),
        else => {},
    }

    // Fortran Sources
    for (options.sources) |src| {
        flang_exec.addFileArg(b.path(src));
    }

    // Flang flags
    if (options.flags) |flags| {
        for (flags) |flag| {
            flang_exec.addArg(flag);
        }
    }

    // Link libraries
    if (options.ldflags) |ldflags| {
        for (ldflags) |ldflag| {
            if (ldflag[0] == '-') {
                @panic("ldflags: add library name only!");
            }
            flang_exec.addArg(b.fmt("-l{s}", .{ldflag}));
        }
    }

    if (b.verbose)
        flang_exec.addArgs(&.{"-v"});

    switch (options.optimize) {
        .Debug => flang_exec.addArgs(&.{
            "-g",
        }),
        .ReleaseSafe => flang_exec.addArgs(&.{
            "-O3",
        }),
        .ReleaseFast => flang_exec.addArgs(&.{
            "-Ofast",
        }),
        .ReleaseSmall => flang_exec.addArgs(&.{
            "-Oz",
        }),
    }

    // object file output (zig-cache/o/{hash_id}/*.o)
    var objpath: []const u8 = undefined;
    if (b.cache_root.path) |path| {
        // immutable state hash
        objpath = b.pathJoin(&.{ path, "o", &b.graph.cache.hash.peek() });
        // flang_exec.addArg(b.fmt("-od={s}", .{objpath}));
        // mutable state hash
        // flang_exec.addArg(b.fmt("-cache={s}", .{b.pathJoin(&.{ path, "o", &b.graph.cache.hash.final() })}));
    }

    // sysroot override
    if (b.sysroot) |sysroot_path| {
        flang_exec.addArgs(&.{
            "-isysroot",
            sysroot_path,
        });
    }

    if (options.artifact) |lib| {

        // library paths
        for (lib.root_module.lib_paths.items) |libDir| {
            if (libDir.getPath(b).len > 0) // skip empty paths
                flang_exec.addArg(b.fmt("-L{s}", .{libDir.getPath(b)}));
        }

        // link system libs
        for (lib.root_module.link_objects.items) |link_object| {
            if (link_object != .system_lib) continue;
            const system_lib = link_object.system_lib;
            flang_exec.addArg(b.fmt("-l{s}", .{system_lib.name}));
        }

        // Darwin frameworks
        if (options.target.result.isDarwin()) {
            var it = lib.root_module.frameworks.iterator();
            while (it.next()) |framework| {
                flang_exec.addArg(b.fmt("-L-framework", .{}));
                flang_exec.addArg(b.fmt("-L{s}", .{framework.key_ptr.*}));
            }
        }

        // if (lib.root_module.sanitize_thread) |tsan| {
        //     if (tsan)
        //         flang_exec.addArg("--fsanitize=thread");
        // }

        // zig enable sanitize=undefined by default
        // if (lib.root_module.sanitize_c) |ubsan| {
        //     if (ubsan)
        //         flang_exec.addArg("--fsanitize=address");
        // }

        if (lib.root_module.omit_frame_pointer) |enabled| {
            if (enabled)
                flang_exec.addArg("-fomit-frame-pointer")
            else
                flang_exec.addArg("-fno-omit-frame-pointer");
        }

        // link-time optimization
        if (lib.want_lto) |enabled| {
            if (enabled) {
                flang_exec.addArgs(&.{"-flto"});
            } else {
                flang_exec.addArgs(&.{"-fno-lto"});
            }
        }
    }

    const target = if (options.target.result.isDarwin())
        b.fmt("{s}-apple-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag) })
    else if (options.target.result.isWasm() and options.target.result.os.tag == .freestanding)
        b.fmt("{s}-unknown-unknown", .{@tagName(options.target.result.cpu.arch)})
    else if (options.target.result.isWasm())
        b.fmt("{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag) })
    else if (options.target.result.cpu.arch.isRISCV())
        b.fmt("{s}-unknown-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) })
    else if (options.target.result.cpu.arch.isX86())
        b.fmt("{s}-pc-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) })
    else
        b.fmt("{s}-unknown-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) });

    flang_exec.addArgs(&.{
        b.fmt("--target={s}", .{target}),
    });
    if (options.target.query.isNative()) {
        flang_exec.addArg(b.fmt("-mcpu={s}", .{options.target.result.cpu.model.llvm_name orelse "generic"}));
    }

    const outputDir = switch (options.kind) {
        .lib => "lib",
        .exe => "bin",
        .@"test" => "test",
        .obj => "obj",
    };

    // output file
    flang_exec.addArg("-o");
    const output = flang_exec.addOutputFileArg(options.name);
    const install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .source_dir = output.dirname(),
        .install_subdir = outputDir,
    });
    install.step.dependOn(&flang_exec.step);

    if (options.artifact) |lib| {
        flang_exec.addArtifactArg(lib);
        dep.dependenciesIterator(lib, flang_exec);
    }

    if (options.use_zigcc) {
        const zcc = zigcc.buildZigCC(b, options.zcc_options.?);
        flang_exec.addArg("-lc++");
        flang_exec.addPrefixedFileArg("-fuse-ld=", zcc.getEmittedBin());
        if (options.runtime) {
            const flang_dep = buildFortranRuntime(b, .{
                .target = options.target,
                .optimize = options.optimize,
            });
            flang_exec.addArtifactArg(flang_dep.artifact("FortranRuntime"));
            flang_exec.addArtifactArg(flang_dep.artifact("FortranDecimal"));
            flang_exec.addArtifactArg(flang_dep.artifact("Fortran_main"));
        }
    }

    const example_run = b.addSystemCommand(&.{b.pathJoin(&.{ b.install_path, outputDir, options.name })});
    example_run.step.dependOn(&install.step);

    const run = if (options.kind != .@"test")
        b.step(b.fmt("run-{s}", .{options.name}), b.fmt("Run {s} example", .{options.name}))
    else
        b.step("test", "Run all tests");
    run.dependOn(&example_run.step);

    return install;
}

pub const FlangCompileStep = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
    kind: std.Build.Step.Compile.Kind = .exe,
    linkage: std.builtin.LinkMode = .static,
    sources: []const []const u8,
    flags: ?[]const []const u8 = null,
    ldflags: ?[]const []const u8 = null,
    name: []const u8,
    artifact: ?*std.Build.Step.Compile = null,
    use_zigcc: bool = false,
    zcc_options: ?*std.Build.Step.Options = null,
    runtime: bool = true,
};

pub fn buildFortranRuntime(b: *std.Build, options: struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
}) *std.Build.Dependency {
    return b.dependency("flang-runtime", .{
        .target = options.target,
        .optimize = options.optimize,
    });
}
