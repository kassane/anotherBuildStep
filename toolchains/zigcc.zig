const std = @import("std");

pub fn buildZigCC(b: *std.Build) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zcc",
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ rootPath(), "..", "tools", "zigcc.zig" }) },
    });
    return exe;
}

fn rootPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
