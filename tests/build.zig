//! SPDX-License-Identifier: MPL-2.0

const std = @import("std");
const builtin = @import("builtin");
const abs = @import("abs");

// toolchain modules
const ldc2 = abs.ldc2;
const swift = abs.swift;
const flang = abs.flang;
const rust = abs.rust;

const zcc = abs.zcc;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = if (builtin.os.tag == .windows)
            try std.Target.Query.parse(.{
                .arch_os_abi = "native-windows-msvc",
            })
        else
            .{},
    });
    const optimize = b.standardOptimizeOption(.{});

    const exeDlang = try ldc2.BuildStep(b, .{
        .name = "d_example",
        .target = target,
        .optimize = optimize,
        .sources = &.{"main.d"},
        .betterC = !target.query.isNative(),
        .use_zigcc = true,
        .zcc_options = try zcc.buildOptions(b, target),
    });
    b.default_step.dependOn(&exeDlang.step);

    const exeFortran = try flang.BuildStep(b, .{
        .name = "fortran_example",
        .target = target,
        .optimize = optimize,
        .sources = &.{"main.f90"},
        .use_zigcc = true,
        .zcc_options = try zcc.buildOptions(b, target),
    });
    b.default_step.dependOn(&exeFortran.step);

    // TODO: fix (need refactoring to cross-compile)
    const exeRust = try rust.BuildStep(b, .{
        .name = "rust_example",
        .target = target,
        .optimize = optimize,
        .source = "main.rs",
        .use_zigcc = true,
        .zcc_options = try zcc.buildOptions(b, target),
    });
    if (target.query.isNative())
        b.default_step.dependOn(&exeRust.step);

    const exeSwift = try swift.BuildStep(b, .{
        .name = "swift_example",
        .target = target,
        .optimize = optimize,
        .sources = &.{"main.swift"},
        .use_zigcc = true,
        .zcc_options = try zcc.buildOptions(b, b.host),
    });
    if (target.query.isNative())
        b.default_step.dependOn(&exeSwift.step);

    try libzig2swift(b);
}

fn libzig2swift(b: *std.Build) !void {
    const lib = b.addStaticLibrary(.{
        .name = "zig_abi",
        .target = b.host,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("swift_ffi/zig_abi.zig"),
    });
    lib.linkLibC();

    const exeSwift = try swift.BuildStep(b, .{
        .name = "swift_ffi",
        .target = b.host,
        .optimize = .ReleaseSmall,
        .sources = &.{"swift_ffi/main.swift"},
        .bridging_header = b.path("swift_ffi/c_include.h"),
        .use_zigcc = true,
        .zcc_options = try zcc.buildOptions(b, b.host),
        .artifact = lib,
    });
    b.default_step.dependOn(&exeSwift.step);
}

// WIP: get musl libc headers in zig_path

// const arch_name = std.zig.target.muslArchNameHeaders(target.result.cpu.arch);
// const os_name = @tagName(target.result.os.tag);
// const triple = b.fmt("{s}-{s}-musl", .{ arch_name, os_name });
// const libpath = try b.graph.zig_lib_directory.join(b.allocator, &[_][]const u8{
//     "libc",
//     "include",
//     triple,
// });

// std.debug.print("ZIG LIBPATH: {s}\n", .{libpath});
