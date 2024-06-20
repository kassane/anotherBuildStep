const std = @import("std");

pub fn buildZigCC(b: *std.Build) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zcc",
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .root_source_file = .{ .cwd_relative = b.fmt("{s}/tools/zigcc.zig", .{b.pathFromRoot(".")}) },
    });
    return exe;
}
