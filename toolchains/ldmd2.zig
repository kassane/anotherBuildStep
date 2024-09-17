//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const zigcc = @import("zigcc.zig");
const dep = @import("depsIterate.zig");
const artifact = @import("artifact.zig"); // TODO: replace 'Step.Run' to 'Step.Compile'

// Use LDC2 (https://github.com/ldc-developers/ldc) to compile the D examples
pub fn BuildStep(b: *std.Build, options: DCompileStep) !*std.Build.Step.InstallDir {
    // ldmd2: ldc2 wrapped w/ dmd flags
    const ldc = try b.findProgram(&.{"ldmd2"}, &.{});

    if (options.use_zigcc and options.use_lld)
        @panic("link-internally overrides linker=zigcc");

    // D compiler
    var ldc_exec = b.addSystemCommand(&.{ldc});
    ldc_exec.setName(options.name);

    // set kind of build
    switch (options.kind) {
        .@"test" => ldc_exec.addArgs(&.{
            "-unittest",
            "-main",
        }),
        .obj => ldc_exec.addArg("-c"),
        else => {},
    }

    if (options.kind == .lib) {
        if (options.linkage == .dynamic) {
            ldc_exec.addArg("-shared");
            if (options.target.result.os.tag == .windows) {
                ldc_exec.addArgs(&.{
                    "-fvisibility=public",
                    "--dllimport=all",
                });
            }
        } else {
            ldc_exec.addArg("-lib");
            if (options.target.result.os.tag == .windows)
                ldc_exec.addArg("--dllimport=defaultLibsOnly");
            ldc_exec.addArg("-fvisibility=hidden");
        }
    }

    if (options.dflags) |dflags| {
        for (dflags) |dflag| {
            ldc_exec.addArg(dflag);
        }
    }

    if (options.ldflags) |ldflags| {
        for (ldflags) |ldflag| {
            if (ldflag[0] == '-') {
                @panic("ldflags: add library name only!");
            }
            ldc_exec.addArg(b.fmt("-L-l{s}", .{ldflag}));
        }
    }

    if (options.versions) |versions| {
        for (versions) |version| {
            if (version[0] == '-') {
                @panic("versions: add version name only!");
            }
            ldc_exec.addArg(b.fmt("--d-version={s}", .{version}));
        }
    }

    // C++ standard for name mangling compatibility
    if (options.cxx_interop) |version| {
        ldc_exec.addArg(b.fmt("--extern-std={s}", .{switch (version) {
            .cxx11 => "c++11",
            .cxx14 => "c++14",
            .cxx17 => "c++17",
            .cxx20 => "c++20",
            .cxx23 => "c++23",
            .legacy => "c++98",
        }}));
    }

    // D Imports & C Includes
    if (options.importPaths) |imports| {
        for (imports) |import| {
            if (import[0] == '-') {
                @panic("Import: add import paths only!");
            }
            ldc_exec.addArg(b.fmt("-I{s}", .{import}));
        }
    }

    if (options.cIncludePaths) |includes| {
        for (includes) |include| {
            if (include[0] == '-') {
                @panic("Include: add C include paths only!");
            }
            ldc_exec.addArg(b.fmt("-P-I{s}", .{include}));
        }
    }

    // betterC disable druntime and phobos
    if (options.betterC)
        ldc_exec.addArg("-betterC");

    switch (options.optimize) {
        .Debug => ldc_exec.addArgs(&.{
            "-debug",
            "-d-debug",
            "-gc",
            "-g",
            "-gf",
            "-gs",
            "-vgc",
            "-vtls",
            "-boundscheck=on",
        }),
        .ReleaseSafe => ldc_exec.addArgs(&.{
            "-O",
            "-enable-inlining",
            "-boundscheck=safeonly",
        }),
        .ReleaseFast => ldc_exec.addArgs(&.{
            "-O3",
            "-boundscheck=off",
        }),
        .ReleaseSmall => ldc_exec.addArgs(&.{
            "-Oz",
            "-boundscheck=off",
        }),
    }

    // Print character (column) numbers in diagnostics
    ldc_exec.addArg("-vcolumns");

    // object file output (zig-cache/o/{hash_id}/*.o)
    var objpath: []const u8 = undefined; // needed for wasm build
    if (b.cache_root.path) |path| {
        // immutable state hash
        objpath = b.pathJoin(&.{
            path,
            "o",
            &b.graph.cache.hash.peek(),
        });
        ldc_exec.addArg(b.fmt("-od={s}", .{objpath}));
        // mutable state hash (ldc2 cache - llvm-ir2obj)
        ldc_exec.addArg(b.fmt("-cache={s}", .{b.pathJoin(&.{
            path,
            "o",
            &b.graph.cache.hash.final(),
        })}));
    }

    // disable LLVM-IR verifier
    // https://llvm.org/docs/Passes.html#verify-module-verifier

    ldc_exec.addArgs(&.{
        "-disable-verify",
        "-Hkeep-all-bodies",
        "-verrors=context",
        "-i",
    });

    // D-packages include path
    if (options.d_packages) |d_packages| {
        for (d_packages) |pkg| {
            ldc_exec.addArg(b.fmt("-I{s}", .{pkg}));
        }
    }

    // D Source files
    for (options.sources) |src| {
        ldc_exec.addFileArg(dep.path(b, src));
    }

    // linker flags
    if (options.use_lld) {
        ldc_exec.addArg("-link-internally");
    }
    //MS Linker
    if (options.target.result.abi == .msvc and options.optimize == .Debug and !options.use_zigcc) {
        ldc_exec.addArg("-L-lmsvcrtd");
        ldc_exec.addArg("-L/NODEFAULTLIB:libcmt.lib");
        ldc_exec.addArg("-L/NODEFAULTLIB:libvcruntime.lib");
    }
    // GNU LD
    if (options.target.result.os.tag == .linux and !options.use_zigcc and !options.use_lld) {
        ldc_exec.addArg("-L--no-as-needed");
    }
    // LLD (not working in zld)
    if (options.target.result.isDarwin() and !options.use_zigcc) {
        // https://github.com/ldc-developers/ldc/issues/4501
        ldc_exec.addArg("-L-w"); // hide linker warnings
    }

    if (options.target.result.isWasm()) {
        ldc_exec.addArg("-L-allow-undefined");
        // ldc2 enable use_lld by default on wasm target.
        // Need use --no-entry
        ldc_exec.addArg("-L--no-entry");
    }

    if (b.verbose) {
        ldc_exec.addArg("-vdmd");
        ldc_exec.addArg("-Xcc=-v");
    }

    if (options.artifact) |lib| {
        {
            if (lib.linkage == .dynamic or options.linkage == .dynamic) {
                // linking the druntime/Phobos as dynamic libraries
                ldc_exec.addArg("-link-defaultlib-shared");
            }
        }

        // C include path
        for (lib.root_module.include_dirs.items) |include_dir| {
            if (include_dir == .other_step) continue;
            const path = if (include_dir == .path)
                include_dir.path.getPath(b)
            else if (include_dir == .path_system)
                include_dir.path_system.getPath(b)
            else
                include_dir.path_after.getPath(b);
            ldc_exec.addArg(b.fmt("-P-I{s}", .{path}));
        }

        // library paths
        for (lib.root_module.lib_paths.items) |libDir| {
            if (libDir.getPath(b).len > 0) // skip empty paths
                ldc_exec.addArg(b.fmt("-L-L{s}", .{libDir.getPath(b)}));
        }

        // link system libs
        for (lib.root_module.link_objects.items) |link_object| {
            if (link_object != .system_lib) continue;
            const system_lib = link_object.system_lib;
            ldc_exec.addArg(b.fmt("-L-l{s}", .{system_lib.name}));
        }
        // C flags
        for (lib.root_module.link_objects.items) |link_object| {
            if (link_object != .c_source_file) continue;
            const c_source_file = link_object.c_source_file;
            for (c_source_file.flags) |flag|
                if (flag.len > 0) // skip empty flags
                    ldc_exec.addArg(b.fmt("-Xcc={s}", .{flag}));
            break;
        }
        // C defines
        for (lib.root_module.c_macros.items) |cdefine| {
            if (cdefine.len > 0) // skip empty cdefines
                ldc_exec.addArg(b.fmt("-P-D{s}", .{cdefine}));
            break;
        }

        if (lib.dead_strip_dylibs) {
            ldc_exec.addArg("-L=-dead_strip");
        }
        // Darwin frameworks
        if (options.target.result.isDarwin()) {
            var it = lib.root_module.frameworks.iterator();
            while (it.next()) |framework| {
                ldc_exec.addArg(b.fmt("-L-framework", .{}));
                ldc_exec.addArg(b.fmt("-L{s}", .{framework.key_ptr.*}));
            }
        }

        if (lib.root_module.sanitize_thread) |tsan| {
            if (tsan)
                ldc_exec.addArg("--fsanitize=thread");
        }

        // zig enable sanitize=undefined by default
        if (lib.root_module.sanitize_c) |ubsan| {
            if (ubsan)
                ldc_exec.addArg("--fsanitize=address");
        }

        if (lib.root_module.omit_frame_pointer) |enabled| {
            if (enabled)
                ldc_exec.addArg("--frame-pointer=none")
            else
                ldc_exec.addArg("--frame-pointer=all");
        }

        // link-time optimization
        if (lib.want_lto) |enabled|
            if (enabled) ldc_exec.addArg("--flto=full");
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
        b.fmt("i686-unknown-{s}-{s}", .{ @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) })
    else
        b.fmt("{s}-unknown-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) });

    ldc_exec.addArg(b.fmt("-mtriple={s}", .{mtriple}));

    // cpu model (e.g. "generic" or )
    ldc_exec.addArg(b.fmt("-mcpu={s}", .{options.target.result.cpu.model.llvm_name orelse "generic"}));

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

    const extFile = switch (options.kind) {
        .exe, .@"test" => options.target.result.exeFileExt(),
        .lib => if (options.linkage == .static) options.target.result.staticLibSuffix() else options.target.result.dynamicLibSuffix(),
        .obj => if (options.target.result.os.tag == .windows) ".obj" else ".o",
    };

    // output file
    const output = ldc_exec.addPrefixedOutputFileArg("-of=", try std.mem.concat(b.allocator, u8, &.{ outputName, extFile }));
    const install = b.addInstallDirectory(.{
        .install_dir = .prefix,
        .source_dir = output.dirname(),
        .install_subdir = outputDir,
        .exclude_extensions = &.{ "o", "obj" },
    });
    install.step.dependOn(&ldc_exec.step);

    if (options.use_zigcc) {
        const zcc = zigcc.buildZigCC(b, options.zcc_options.?);
        ldc_exec.addPrefixedFileArg("--gcc=", zcc.getEmittedBin());
        ldc_exec.addPrefixedFileArg("--linker=", zcc.getEmittedBin());
    }

    if (options.artifact) |lib| {
        ldc_exec.addArtifactArg(lib);
        dep.dependenciesIterator(lib, ldc_exec);
    }

    const example_run = b.addSystemCommand(&.{b.pathJoin(&.{ b.install_path, outputDir, options.name })});
    example_run.setName(options.name);
    example_run.step.dependOn(&install.step);

    const run = if (options.kind != .@"test")
        b.step(b.fmt("run-{s}", .{options.name}), b.fmt("Run {s} example", .{options.name}))
    else
        b.step("test", "Run all tests");
    run.dependOn(&example_run.step);

    return install;
}

pub const DCompileStep = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
    kind: std.Build.Step.Compile.Kind = .exe,
    linkage: std.builtin.LinkMode = .static,
    betterC: bool = false,
    sources: []const []const u8,
    dflags: ?[]const []const u8 = null,
    ldflags: ?[]const []const u8 = null,
    versions: ?[]const []const u8 = null,
    name: []const u8,
    d_packages: ?[]const []const u8 = null,
    cIncludePaths: ?[]const []const u8 = null,
    importPaths: ?[]const []const u8 = null,
    artifact: ?*std.Build.Step.Compile = null,
    use_zigcc: bool = false,
    use_lld: bool = false,
    zcc_options: ?*std.Build.Step.Options = null,
    cxx_interop: ?CxxVersion = null,
};

/// C++ standard for name mangling compatibility
const CxxVersion = enum {
    legacy,
    cxx11,
    cxx14,
    cxx17,
    cxx20,
    /// C++23 is not yet supported by LDC2
    cxx23,
};
