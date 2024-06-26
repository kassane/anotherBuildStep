const std = @import("std");
const builtin = @import("builtin");

// toolchain modules
pub const ldc2 = @import("toolchains/ldmd2.zig");
pub const flang = @import("toolchains/flang.zig");
pub const rust = @import("toolchains/rust.zig");
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

    const exeD = try ldc2.BuildStep(b, .{
        .name = "helloD",
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
    b.default_step.dependOn(&exeD.step);

    const exeFortran = try flang.BuildStep(b, .{
        .name = "hellof",
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

    // TODO: fix (need refactoring to cross-compile)
    // const exeRust = try rust.BuildStep(b, .{
    //     .name = "hellors",
    //     .target = target,
    //     .optimize = optimize,
    //     .source = "examples/main.rs",
    //     .rflags = &.{},
    //     .use_zigcc = true,
    //     .t_options = try zcc.buildOptions(b, target),
    // });
    // b.default_step.dependOn(&exeRust.step);
}
