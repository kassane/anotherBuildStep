//! Any copyright is dedicated to the Public Domain.
//! https://creativecommons.org/publicdomain/zero/1.0/

const std = @import("std");

export fn println(str: [*:0]const u8) callconv(.C) void {
    _ = std.c.printf("%s\n", str);
}
