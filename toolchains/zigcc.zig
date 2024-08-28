//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");

pub fn buildZigCC(b: *std.Build, targezcc_options: *std.Build.Step.Options) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zcc",
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .root_source_file = b.path("../tools/zigcc.zig"),
    });
    exe.root_module.addOptions("build_options", targezcc_options);
    return exe;
}

pub fn buildOptions(b: *std.Build, target: std.Build.ResolvedTarget) !*std.Build.Step.Options {
    const zigcc_options = b.addOptions();

    // Native target, zig can read 'zig libc' contents and also link system libraries.
    const native = if (target.query.isNative()) switch (target.result.abi) {
        .msvc => "native-native-msvc",
        else => "native-native",
    } else try target.result.zigTriple(b.allocator);
    zigcc_options.addOption(
        ?[]const u8,
        "triple",
        native,
    );
    zigcc_options.addOption(
        ?[]const u8,
        "cpu",
        target.result.cpu.model.name,
    );
    return zigcc_options;
}
