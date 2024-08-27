//! SPDX-License-Identifier: MPL-2.0
const std = @import("std");

// toolchain modules
pub const ldc2 = @import("toolchains/ldmd2.zig");
pub const flang = @import("toolchains/flang.zig");
pub const rust = @import("toolchains/rust.zig");
pub const swift = @import("toolchains/swiftc.zig");

// Send the triple-target to zigcc (if enabled)
pub const zcc = @import("toolchains/zigcc.zig");

pub fn build(b: *std.Build) void {
    _ = b; // autofix
}
