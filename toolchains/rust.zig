//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const zigcc = @import("zigcc.zig");
const dep = @import("depsIterate.zig");

// Rustc support
pub fn BuildStep(b: *std.Build, options: RustCompileStep) !*std.Build.Step.Run {

    //fixme: why detecting rustup? rustc alias?
    // const rustc = try b.findProgram(&.{"rustc"}, &.{});
    const rustup = try b.findProgram(&.{"rustup"}, &.{});

    var cmds = std.ArrayList([]const u8).init(b.allocator);
    defer cmds.deinit();

    // Rust compiler
    var rustc_exec = b.addSystemCommand(&.{"rustc"});
    rustc_exec.setName(options.name);

    rustc_exec.addArg("--edition");
    switch (options.edition) {
        .@"2015" => rustc_exec.addArg("2015"),
        .@"2018" => rustc_exec.addArg("2018"),
        .@"2021" => rustc_exec.addArg("2021"),
        .@"2024" => rustc_exec.addArg("2024"),
    }

    // set kind of build
    switch (options.kind) {
        .@"test" => rustc_exec.addArg("--test"),
        .obj => rustc_exec.addArg("--emit=obj"),
        .exe => rustc_exec.addArg("--crate-type=bin"),
        .lib => {
            if (options.linkage == .static)
                rustc_exec.addArg("--crate-type=staticlib")
            else
                rustc_exec.addArg("--crate-type=dylib");
        },
    }

    // no bitcode
    rustc_exec.addArgs(&.{ "-C", "embed-bitcode=no" });

    switch (options.optimize) {
        .Debug => {
            rustc_exec.addArg("-g");
        },
        .ReleaseSafe => rustc_exec.addArgs(&.{
            "-C",
            "opt-level=3",
            "-C",
            "embed-bitcode=no",
        }),
        .ReleaseFast, .ReleaseSmall => rustc_exec.addArgs(&.{
            "-C",
            "opt-level=z",
            "-C",
            "strip=debuginfo",
            "-C",
            "strip=symbols",
        }),
    }

    if (b.verbose)
        rustc_exec.addArg("-v");

    if (options.rflags) |flags| {
        for (flags) |flag| {
            rustc_exec.addArg(flag);
        }
    }

    if (options.ldflags) |ldflags| {
        for (ldflags) |ldflag| {
            if (ldflag[0] == '-') {
                @panic("ldflags: add library name only!");
            }
            rustc_exec.addArg(b.fmt("-l{s}", .{ldflag}));
        }
    }

    // Rust Source file
    rustc_exec.addFileArg(options.source);

    // sysroot override
    if (b.sysroot) |sysroot_path| {
        rustc_exec.addArg(b.fmt("--sysroot={s}", .{sysroot_path}));
    }

    if (options.artifact) |lib| {

        // library paths
        for (lib.root_module.lib_paths.items) |libDir| {
            if (libDir.getPath(b).len > 0) // skip empty paths
                rustc_exec.addArg(b.fmt("-L{s}", .{libDir.getPath(b)}));
        }

        // link system libs
        for (lib.root_module.link_objects.items) |link_object| {
            if (link_object != .system_lib) continue;
            const system_lib = link_object.system_lib;
            rustc_exec.addArg(b.fmt("-l{s}", .{system_lib.name}));
        }

        // Darwin frameworks
        if (options.target.result.os.tag.isDarwin()) {
            var it = lib.root_module.frameworks.iterator();
            while (it.next()) |framework| {
                rustc_exec.addArg(b.fmt("-L-framework", .{}));
                rustc_exec.addArg(b.fmt("-L{s}", .{framework.key_ptr.*}));
            }
        }

        if (lib.root_module.sanitize_thread) |tsan| {
            if (tsan)
                rustc_exec.addArg("--fsanitize=thread");
        }

        // zig enable sanitize=undefined by default
        if (lib.root_module.sanitize_c) |ubsan| {
            if (ubsan)
                rustc_exec.addArg("--fsanitize=address");
        }

        if (lib.root_module.omit_frame_pointer) |enabled| {
            if (enabled)
                rustc_exec.addArg("--frame-pointer=none")
            else
                rustc_exec.addArg("--frame-pointer=all");
        }

        // link-time optimization
        if (lib.want_lto) |enabled| {
            if (enabled) {
                rustc_exec.addArgs(&.{ "-C", "-lto=true" });
            } else {
                rustc_exec.addArgs(&.{ "-C", "-lto=false" });
            }
        }
    }

    const target = if (options.target.result.os.tag.isDarwin())
        b.fmt("{s}-apple-darwin", .{@tagName(options.target.result.cpu.arch)})
    else if (options.target.result.cpu.arch.isWasm() and options.target.result.os.tag == .freestanding)
        b.fmt("{s}-unknown-unknown", .{@tagName(options.target.result.cpu.arch)})
    else if (options.target.result.cpu.arch.isWasm())
        b.fmt("{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag) })
    else if (options.target.result.cpu.arch.isRISCV())
        b.fmt("{s}gc-unknown-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) })
    else if (options.target.result.os.tag == .windows)
        b.fmt("{s}-pc-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) })
    else
        b.fmt("{s}-unknown-{s}-{s}", .{ @tagName(options.target.result.cpu.arch), @tagName(options.target.result.os.tag), @tagName(options.target.result.abi) });

    rustc_exec.addArgs(&.{ "--target", target });

    if (options.target.result.isMuslLibC()) {
        rustc_exec.addArgs(&.{
            "-C",
            "target-feature=+crt-static",
        });
    }

    // cpu model (e.g. "baseline")
    rustc_exec.addArg("-C");
    rustc_exec.addArg(b.fmt("target-cpu={s}", .{options.target.result.cpu.model.llvm_name orelse "generic"}));

    const outputDir = switch (options.kind) {
        .lib => "lib",
        .exe => "bin",
        .@"test" => "test",
        .obj => "obj",
    };

    // object file output (zig-cache/o/{hash_id}/*.o)
    if (b.cache_root.path) |path| {
        rustc_exec.addArgs(&.{
            "-L",
            b.fmt("dependency={s}", .{b.pathJoin(&.{
                path,
                "o",
                &b.graph.cache.hash.peek(),
            })}),
        });
        rustc_exec.addArgs(&.{ "-C", b.fmt("incremental={s}", .{b.pathJoin(&.{
            path,
            "o",
            &b.graph.cache.hash.final(),
        })}) });
    }

    // output filename
    rustc_exec.addArg(b.fmt("--out-dir={s}", .{b.pathJoin(&.{ b.install_path, outputDir })}));
    rustc_exec.addArg(b.fmt("--crate-name={s}", .{options.name}));

    if (options.use_zigcc) {
        const zcc_opt = try zigcc.buildOptions(b, options.target);
        const zcc = zigcc.buildZigCC(b, zcc_opt);
        rustc_exec.addArg("-C");
        rustc_exec.addPrefixedFileArg("linker=", zcc.getEmittedBin());
    }

    if (!options.target.query.isNative()) {
        const rustup_exec = b.addSystemCommand(&.{ rustup, "target", "add", target });
        rustup_exec.setName("rustup");
        rustc_exec.step.dependOn(&rustup_exec.step);
    }

    if (options.artifact) |lib| {
        rustc_exec.addArtifactArg(lib);
        dep.dependenciesIterator(lib, rustc_exec);
    }

    const example_run = b.addSystemCommand(&.{b.pathJoin(&.{ b.install_path, outputDir, options.name })});
    example_run.step.dependOn(&rustc_exec.step);

    const run = if (options.kind != .@"test")
        b.step(b.fmt("run-{s}", .{options.name}), b.fmt("Run {s} example", .{options.name}))
    else
        b.step("test", "Run all tests");
    run.dependOn(&example_run.step);

    return rustc_exec;
}

pub const RustCompileStep = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode = .Debug,
    kind: std.Build.Step.Compile.Kind = .exe,
    linkage: std.builtin.LinkMode = .static,
    source: std.Build.LazyPath,
    rflags: ?[]const []const u8 = null,
    ldflags: ?[]const []const u8 = null,
    name: []const u8,
    rs_packages: ?[]const []const u8 = null,
    artifact: ?*std.Build.Step.Compile = null,
    edition: rustEdition = .@"2021",
    use_zigcc: bool = false,
};

pub const rustEdition = enum {
    @"2015",
    @"2018",
    @"2021",
    @"2024",
};
