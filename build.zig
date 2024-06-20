const std = @import("std");
const builtin = @import("builtin");
const d = @import("config/ldmd2.zig");
const flang = @import("config/flang.zig");
const rust = @import("config/rust.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{ .default_target = if (builtin.os.tag == .windows) try std.Target.Query.parse(.{ .arch_os_abi = "native-windows-msvc" }) else .{} });
    const optimize = b.standardOptimizeOption(.{});

    const exeD = try d.BuildStep(b, .{
        .name = "helloD",
        .target = target,
        .optimize = optimize,
        .sources = &.{"src/main.d"},
        .dflags = &.{
            "-w",
        },
        .betterC = if (target.query.isNative()) false else true,
        .use_zigcc = true,
    });
    b.default_step.dependOn(&exeD.step);

    // const exeFortran = try flang.BuildStep(b, .{
    //     .name = "hellof",
    //     .target = target,
    //     .optimize = optimize,
    //     .sources = &.{
    //         "src/main.f90",
    //     },
    //     .fflags = &.{},
    //     .use_zigcc = true,
    // });
    // b.default_step.dependOn(&exeFortran.step);

    const exeRust = try rust.BuildStep(b, .{
        .name = "hellors",
        .target = target,
        .optimize = optimize,
        .source = "src/main.rs",
        .rflags = &.{
            "-C",
            "panic=abort",
        },
        .use_zigcc = true,
    });
    b.default_step.dependOn(&exeRust.step);
}
