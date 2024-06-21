const std = @import("std");

pub fn buildZigCC(b: *std.Build, target_options: *std.Build.Step.Options) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zcc",
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ rootPath(), "..", "tools", "zigcc.zig" }) },
    });
    exe.root_module.addOptions("build_options", target_options);
    return exe;
}

fn rootPath() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}
