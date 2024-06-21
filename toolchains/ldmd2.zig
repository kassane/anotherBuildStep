const std = @import("std");
const zigcc = @import("zigcc.zig");
const dep = @import("depsIterate.zig");

// Use LDC2 (https://github.com/ldc-developers/ldc) to compile the D examples
pub fn BuildStep(b: *std.Build, options: DCompileStep) !*std.Build.Step.Run {
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

    for (options.dflags) |dflag| {
        ldc_exec.addArg(dflag);
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
            "-verrors=context",
            "-boundscheck=on",
        }),
        .ReleaseSafe => ldc_exec.addArgs(&.{
            "-O3",
            "-release",
            "-enable-inlining",
            "-boundscheck=safeonly",
        }),
        .ReleaseFast => ldc_exec.addArgs(&.{
            "-O",
            "-release",
            "-enable-inlining",
            "-boundscheck=off",
        }),
        .ReleaseSmall => ldc_exec.addArgs(&.{
            "-Oz",
            "-release",
            "-enable-inlining",
            "-boundscheck=off",
        }),
    }

    // Print character (column) numbers in diagnostics
    ldc_exec.addArg("-vcolumns");

    // object file output (zig-cache/o/{hash_id}/*.o)
    var objpath: []const u8 = undefined; // needed for wasm build
    if (b.cache_root.path) |path| {
        // immutable state hash
        objpath = b.pathJoin(&.{ path, "o", &b.graph.cache.hash.peek() });
        ldc_exec.addArg(b.fmt("-od={s}", .{objpath}));
        // mutable state hash (ldc2 cache - llvm-ir2obj)
        ldc_exec.addArg(b.fmt("-cache={s}", .{b.pathJoin(&.{ path, "o", &b.graph.cache.hash.final() })}));
    }

    // disable LLVM-IR verifier
    // https://llvm.org/docs/Passes.html#verify-module-verifier

    ldc_exec.addArg("-disable-verify");

    // keep all function bodies in .di files

    ldc_exec.addArg("-Hkeep-all-bodies");

    // automatically finds needed library files and builds
    ldc_exec.addArg("-i");

    // D-packages include path
    if (options.d_packages) |d_packages| {
        for (d_packages) |pkg| {
            ldc_exec.addArg(b.fmt("-I{s}", .{pkg}));
        }
    }

    // D Source files
    for (options.sources) |src| {
        ldc_exec.addArg(src);
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
    else
        b.fmt("{s}-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) });

    ldc_exec.addArg(b.fmt("-mtriple={s}", .{mtriple}));

    // cpu model (e.g. "generic" or )
    ldc_exec.addArg(b.fmt("-mcpu={s}", .{options.target.result.cpu.model.llvm_name orelse "generic"}));

    const outputDir = switch (options.kind) {
        .lib => "lib",
        .exe => "bin",
        .@"test" => "test",
        .obj => "obj",
    };

    // output file
    if (options.kind != .obj)
        ldc_exec.addArg(b.fmt("-of={s}", .{b.pathJoin(&.{ b.install_prefix, outputDir, options.name })}));

    if (options.use_zigcc) {
        const zcc = zigcc.buildZigCC(b, options.t_options.?);
        const install = b.addInstallArtifact(zcc, .{ .dest_dir = .{ .override = .{ .custom = "tools" } } });
        const zcc_path = b.pathJoin(&.{ b.install_prefix, "tools", if (options.target.result.os.tag == .windows) "zcc.exe" else "zcc" });
        const zcc_exists = !std.meta.isError(std.fs.accessAbsolute(zcc_path, .{}));
        if (!zcc_exists)
            ldc_exec.step.dependOn(&install.step);
        ldc_exec.addArg(b.fmt("--gcc={s}", .{zcc_path}));
        ldc_exec.addArg(b.fmt("--linker={s}", .{zcc_path}));
    }

    if (options.artifact) |lib| {
        ldc_exec.addArtifactArg(lib);
        dep.dependenciesIterator(lib, ldc_exec);
    }

    const example_run = b.addSystemCommand(&.{b.pathJoin(&.{ b.install_path, outputDir, options.name })});
    example_run.step.dependOn(&ldc_exec.step);

    const run = if (options.kind != .@"test")
        b.step(b.fmt("run-{s}", .{options.name}), b.fmt("Run {s} example", .{options.name}))
    else
        b.step("test", "Run all tests");
    run.dependOn(&example_run.step);

    return ldc_exec;
}

pub const DCompileStep = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
    kind: std.Build.Step.Compile.Kind = .exe,
    linkage: std.builtin.LinkMode = .static,
    betterC: bool = false,
    sources: []const []const u8,
    dflags: []const []const u8,
    ldflags: ?[]const []const u8 = null,
    versions: ?[]const []const u8 = null,
    name: []const u8,
    d_packages: ?[]const []const u8 = null,
    artifact: ?*std.Build.Step.Compile = null,
    use_zigcc: bool = false,
    use_lld: bool = false,
    t_options: ?*std.Build.Step.Options = null,
};
