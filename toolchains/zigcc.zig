//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

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

pub fn buildOptions(b: *std.Build, target: std.Build.ResolvedTarget) !*std.Build.Step.Options {
    const zigcc_options = b.addOptions();

    zigcc_options.addOption(
        ?[]const u8,
        "triple",
        if (target.query.isNative()) b.fmt(
            "native-native-{s}",
            .{@tagName(target.result.abi)},
        ) else try target.result.linuxTriple(b.allocator),
    );
    zigcc_options.addOption(
        ?[]const u8,
        "cpu",
        target.result.cpu.model.name,
    );
    return zigcc_options;
}
