//! SPDX-License-Identifier: MPL-2.0

const std = @import("std");
const builtin = @import("builtin");

// toolchain modules
pub const ldc2 = @import("toolchains/ldmd2.zig");
pub const flang = @import("toolchains/flang.zig");
pub const rust = @import("toolchains/rust.zig");
pub const swift = @import("toolchains/swiftc.zig");

// Send the triple-target to zigcc (if enabled)
pub const zcc = @import("toolchains/zigcc.zig");

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
        .sources = &.{
            "examples/main.d",
        },
        .dflags = &.{
            "-w",
        },
        .betterC = !target.query.isNative(),
        .use_zigcc = true,
        .t_options = try zcc.buildOptions(b, target),
    });
    b.default_step.dependOn(&exeDlang.step);

    const exeFortran = try flang.BuildStep(b, .{
        .name = "fortran_example",
        .target = target,
        .optimize = optimize,
        .sources = &.{
            "examples/main.f90",
        },
        .fflags = &.{},
        .use_zigcc = true,
        .t_options = try zcc.buildOptions(b, target),
    });
    b.default_step.dependOn(&exeFortran.step);

    // experimental (no cross-compilation support)
    const exeSwift = try swift.BuildStep(b, .{
        .name = "swift_example",
        .target = target,
        .optimize = optimize,
        .sources = &.{
            "examples/main.swift",
        },
        .use_zigcc = true,
        .t_options = try zcc.buildOptions(b, target),
    });

    if (target.query.isNative())
        b.default_step.dependOn(&exeSwift.step);

    // TODO: fix (need refactoring to cross-compile)
    const exeRust = try rust.BuildStep(b, .{
        .name = "rust_example",
        .target = target,
        .optimize = optimize,
        .source = "examples/main.rs",
        .rflags = &.{},
        .use_zigcc = true,
        .t_options = try zcc.buildOptions(b, target),
    });
    if (!target.result.cpu.arch.isPowerPC64())
        b.default_step.dependOn(&exeRust.step);
}
