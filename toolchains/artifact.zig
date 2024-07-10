//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");

pub fn addArtifact(b: *std.Build, options: anytype) *std.Build.Step.Compile {
    return std.Build.Step.Compile.create(b, .{
        .name = options.name,
        .root_module = .{
            .target = options.target,
            .optimize = options.optimize,
        },
        .linkage = options.linkage,
        .kind = options.kind,
    });
}
