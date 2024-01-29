const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{ .default_target = if (builtin.os.tag == .windows) try std.Target.Query.parse(.{ .arch_os_abi = "native-windows-msvc" }) else .{} });
    const optimize = b.standardOptimizeOption(.{});
    const exed = try ldcBuildStep(b, .{
        .name = "helloD",
        .target = target,
        .optimize = optimize,
        .sources = &.{"src/main.d"},
        .dflags = &.{
            "-w",
        },
    });
    b.default_step.dependOn(&exed.step);

    // TODO
    // const exer = try rustcBuildStep(b, .{
    //     .name = "hellors",
    //     .target = target,
    //     .optimize = optimize,
    //     .sources = &.{"src/main.rs"},
    //     .rflags = &.{
    //     },
    // });
}

// Use LDC2 (https://github.com/ldc-developers/ldc) to compile the D examples
pub fn ldcBuildStep(b: *std.Build, options: DCompileStep) !*std.Build.Step.Run {
    // ldmd2: ldc2 wrapped w/ dmd flags
    const ldc = try b.findProgram(&.{"ldmd2"}, &.{});

    var cmds = std.ArrayList([]const u8).init(b.allocator);
    defer cmds.deinit();

    // D compiler
    try cmds.append(ldc);

    // set kind of build
    switch (options.kind) {
        .@"test" => {
            try cmds.append("-unittest");
            try cmds.append("-main");
        },
        .obj => try cmds.append("-c"),
        else => {},
    }

    if (options.kind == .lib) {
        if (options.linkage == .dynamic) {
            try cmds.append("-shared");
            if (options.target.result.os.tag == .windows) {
                try cmds.append("-fvisibility=public");
                try cmds.append("--dllimport=all");
            }
        } else {
            try cmds.append("-lib");
            if (options.target.result.os.tag == .windows)
                try cmds.append("--dllimport=defaultLibsOnly");
            try cmds.append("-fvisibility=hidden");
        }
    }

    for (options.dflags) |dflag| {
        try cmds.append(dflag);
    }

    if (options.ldflags) |ldflags| {
        for (ldflags) |ldflag| {
            if (ldflag[0] == '-') {
                @panic("ldflags: add library name only!");
            }
            try cmds.append(b.fmt("-L-l{s}", .{ldflag}));
        }
    }

    // betterC disable druntime and phobos
    if (options.betterC)
        try cmds.append("-betterC");

    switch (options.optimize) {
        .Debug => {
            try cmds.append("-debug");
            try cmds.append("-d-debug");
            try cmds.append("-gc"); // debuginfo for non D dbg
            try cmds.append("-g"); // debuginfo for D dbg
            try cmds.append("-gf");
            try cmds.append("-gs");
            try cmds.append("-vgc");
            try cmds.append("-vtls");
            try cmds.append("-verrors=context");
            try cmds.append("-boundscheck=on");
        },
        .ReleaseSafe => {
            try cmds.append("-O3");
            try cmds.append("-release");
            try cmds.append("-enable-inlining");
            try cmds.append("-boundscheck=safeonly");
        },
        .ReleaseFast => {
            try cmds.append("-O3");
            try cmds.append("-release");
            try cmds.append("-enable-inlining");
            try cmds.append("-boundscheck=off");
        },
        .ReleaseSmall => {
            try cmds.append("-Oz");
            try cmds.append("-release");
            try cmds.append("-enable-inlining");
            try cmds.append("-boundscheck=off");
        },
    }

    // Print character (column) numbers in diagnostics
    try cmds.append("-vcolumns");

    // object file output (zig-cache/o/{hash_id}/*.o)
    var objpath: []const u8 = undefined; // needed for wasm build
    if (b.cache_root.path) |path| {
        // immutable state hash
        objpath = b.pathJoin(&.{ path, "o", &b.cache.hash.peek() });
        try cmds.append(b.fmt("-od={s}", .{objpath}));
        // mutable state hash (ldc2 cache - llvm-ir2obj)
        try cmds.append(b.fmt("-cache={s}", .{b.pathJoin(&.{ path, "o", &b.cache.hash.final() })}));
    }
    // name object files uniquely (so the files don't collide)
    try cmds.append("-oq");

    // remove object files after success build, and put them in a unique temp directory
    if (options.kind != .obj)
        try cmds.append("-cleanup-obj");

    // disable LLVM-IR verifier
    // https://llvm.org/docs/Passes.html#verify-module-verifier
    try cmds.append("-disable-verify");

    // keep all function bodies in .di files
    try cmds.append("-Hkeep-all-bodies");

    // automatically finds needed library files and builds
    try cmds.append("-i");

    // sokol include path
    try cmds.append(b.fmt("-I{s}", .{b.pathJoin(&.{ rootPath(), "src" })}));

    // D-packages include path
    if (options.d_packages) |d_packages| {
        for (d_packages) |pkg| {
            try cmds.append(b.fmt("-I{s}", .{pkg}));
        }
    }

    // D Source files
    for (options.sources) |src| {
        try cmds.append(src);
    }

    // linker flags
    // GNU LD
    if (options.target.result.os.tag == .linux and !options.zig_cc) {
        try cmds.append("-L--no-as-needed");
    }
    // LLD (not working in zld)
    if (options.target.result.isDarwin() and !options.zig_cc) {
        // https://github.com/ldc-developers/ldc/issues/4501
        try cmds.append("-L-w"); // hide linker warnings
    }

    if (options.target.result.isWasm()) {
        try cmds.append("--d-version=CarelessAlocation");
        try cmds.append("-L-allow-undefined");
    }

    if (b.verbose) {
        try cmds.append("-vdmd");
        try cmds.append("-Xcc=-v");
    }

    if (options.artifact) |lib_sokol| {
        if (lib_sokol.linkage == .dynamic or options.linkage == .dynamic) {
            // linking the druntime/Phobos as dynamic libraries
            try cmds.append("-link-defaultlib-shared");
        }

        // C include path
        for (lib_sokol.root_module.include_dirs.items) |include_dir| {
            if (include_dir == .other_step) continue;
            const path = if (include_dir == .path)
                include_dir.path.getPath(b)
            else if (include_dir == .path_system)
                include_dir.path_system.getPath(b)
            else
                include_dir.path_after.getPath(b);
            try cmds.append(b.fmt("-P-I{s}", .{path}));
        }

        // library paths
        for (lib_sokol.root_module.lib_paths.items) |libpath| {
            if (libpath.path.len > 0) // skip empty paths
                try cmds.append(b.fmt("-L-L{s}", .{libpath.path}));
        }

        // link system libs
        for (lib_sokol.root_module.link_objects.items) |link_object| {
            if (link_object != .system_lib) continue;
            const system_lib = link_object.system_lib;
            try cmds.append(b.fmt("-L-l{s}", .{system_lib.name}));
        }
        // C flags
        for (lib_sokol.root_module.link_objects.items) |link_object| {
            if (link_object != .c_source_file) continue;
            const c_source_file = link_object.c_source_file;
            for (c_source_file.flags) |flag|
                if (flag.len > 0) // skip empty flags
                    try cmds.append(b.fmt("-Xcc={s}", .{flag}));
            break;
        }
        // C defines
        for (lib_sokol.root_module.c_macros.items) |cdefine| {
            if (cdefine.len > 0) // skip empty cdefines
                try cmds.append(b.fmt("-P-D{s}", .{cdefine}));
            break;
        }

        if (lib_sokol.dead_strip_dylibs) {
            try cmds.append("-L=-dead_strip");
        }
        // Darwin frameworks
        if (options.target.result.isDarwin()) {
            var it = lib_sokol.root_module.frameworks.iterator();
            while (it.next()) |framework| {
                try cmds.append(b.fmt("-L-framework", .{}));
                try cmds.append(b.fmt("-L{s}", .{framework.key_ptr.*}));
            }
        }

        if (lib_sokol.root_module.sanitize_thread) |tsan| {
            if (tsan)
                try cmds.append("--fsanitize=thread");
        }

        // zig enable sanitize=undefined by default
        if (lib_sokol.root_module.sanitize_c) |ubsan| {
            if (ubsan)
                try cmds.append("--fsanitize=address");
        }

        if (lib_sokol.root_module.omit_frame_pointer) |enabled| {
            if (enabled)
                try cmds.append("--frame-pointer=none")
            else
                try cmds.append("--frame-pointer=all");
        }

        // link-time optimization
        if (lib_sokol.want_lto) |enabled|
            if (enabled) try cmds.append("--flto=full");
    }

    // ldc2 doesn't support zig native (a.k.a: native-native or native)
    const mtriple = if (options.target.result.isDarwin())
        b.fmt("{s}-apple-{s}", .{ if (options.target.result.cpu.arch.isAARCH64()) "arm64" else @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag) })
    else if (options.target.result.isWasm())
        b.fmt("{s}-unknown-unknown-wasm", .{@tagName(options.target.result.cpu.arch)})
    else if (options.target.result.isWasm() and options.target.result.os.tag == .wasi)
        b.fmt("{s}-unknown-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag) })
    else
        b.fmt("{s}-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) });

    try cmds.append(b.fmt("-mtriple={s}", .{mtriple}));

    // cpu model (e.g. "baseline")
    if (options.target.query.isNative())
        try cmds.append(b.fmt("-mcpu={s}", .{options.target.result.cpu.model.name}));

    const outputDir = switch (options.kind) {
        .lib => "lib",
        .exe => "bin",
        .@"test" => "test",
        .obj => "obj",
    };

    // output file
    if (options.kind != .obj)
        try cmds.append(b.fmt("-of={s}", .{b.pathJoin(&.{ b.install_prefix, outputDir, options.name })}));

    // run the command
    var ldc_exec = b.addSystemCommand(cmds.items);
    ldc_exec.setName(options.name);

    if (options.artifact) |lib_sokol| {
        ldc_exec.addArtifactArg(lib_sokol);
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
    linkage: std.Build.Step.Compile.Linkage = .static,
    betterC: bool = false,
    sources: []const []const u8,
    dflags: []const []const u8,
    ldflags: ?[]const []const u8 = null,
    name: []const u8,
    zig_cc: bool = false,
    d_packages: ?[]const []const u8 = null,
    artifact: ?*std.Build.Step.Compile = null,
    emsdk: ?*std.Build.Dependency = null,
};
pub fn addArtifact(b: *std.Build, options: DCompileStep) *std.Build.Step.Compile {
    return std.Build.Step.Compile.create(b, .{
        .name = options.name,
        .root_module = .{
            .target = options.target,
            .optimize = options.optimize,
        },
        .linkage = options.linkage,
        .kind = options.kind,
    });
}

fn rootPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
