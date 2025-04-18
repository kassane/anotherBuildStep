//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");
const builtin = @import("builtin");

pub fn dependenciesIterator(lib: *std.Build.Step.Compile, runner: *std.Build.Step.Run) void {
    if (builtin.zig_version.major == 0 and builtin.zig_version.minor < 14) {
        // FIXME: old version, remove after 0.14
        var it = lib.root_module.iterateDependencies(lib, false);
        while (it.next()) |item| {
            for (item.module.link_objects.items) |link_object| {
                switch (link_object) {
                    .other_step => |compile_step| {
                        switch (compile_step.kind) {
                            .lib => {
                                runner.addArtifactArg(compile_step);
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }
        }
    } else {
        for (lib.getCompileDependencies(false)) |item| {
            if (item.kind == .lib) {
                runner.addArtifactArg(item);
            }
        }
    }
}

pub fn path(b: *std.Build, sub_path: []const u8) std.Build.LazyPath {
    if (std.fs.path.isAbsolute(sub_path)) {
        return .{
            .cwd_relative = sub_path,
        };
    } else return .{
        .src_path = .{
            .owner = b,
            .sub_path = sub_path,
        },
    };
}
