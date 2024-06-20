//! zig-cc wrapper for ldc2
//! Copyright (c) 2023 Matheus Catarino França <matheus-catarino@hotmail.com>
//! Zlib license

const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = std.debug.assert(gpa.deinit() == .ok); // ok or leak
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // skip arg[0]

    var cmds = std.ArrayList([]const u8).init(allocator);
    defer cmds.deinit();

    try cmds.append("zig");
    try cmds.append("cc");

    if (builtin.os.tag != .windows) {
        // not working on msvc target (nostdlib++)
        try cmds.append("-lunwind");
    }
    // LDC2 not setting triple targets on host build to cc/linker, except Apple (why?)
    var isNative = true;
    while (args.next()) |arg| {
        // MacOS M1/M2 target, replace aarch64 to arm64
        if (std.mem.startsWith(u8, arg, "aarch64-apple-") or std.mem.startsWith(u8, arg, "arm64-apple-")) {
            if (!isNative)
                try cmds.append("aarch64-macos")
            else
                try cmds.append("native-native");
        } else if (std.mem.startsWith(u8, arg, "x86_64-apple-")) {
            if (!isNative)
                try cmds.append("x86_64-macos")
            else
                try cmds.append("native-native");
        } else if (std.mem.endsWith(u8, arg, "rv64gc") or std.mem.endsWith(u8, arg, "rv32i_zicsr_zifencei")) {
            // NOT CHANGE!!
        } else if (std.mem.eql(u8, arg, "-target")) {
            isNative = false;
            try cmds.append(arg); // get "-target" flag
        } else if (std.mem.eql(u8, arg, std.fmt.comptimePrint("{s}-pc-{s}-{s}", .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag), @tagName(builtin.abi) }))) {
            try cmds.append(std.fmt.comptimePrint("{s}-{s}-{s}", .{
                @tagName(builtin.cpu.arch),
                @tagName(builtin.os.tag),
                @tagName(builtin.abi),
            }));
        } else if (std.mem.endsWith(u8, arg, ".cpp") or std.mem.endsWith(u8, arg, ".cc")) {
            try cmds.append("-x");
            try cmds.append("c++");
        } else if (std.mem.endsWith(u8, arg, "gnu")) {
            // NOT CHANGE!!
        } else if (std.mem.startsWith(u8, arg, "--build-id")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "whole-archive")) {
            // NOT CHANGE!!
        } else if (std.mem.startsWith(u8, arg, "--eh-frame-hdr")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "as-needed")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "gcc") or std.mem.endsWith(u8, arg, "gcc_s")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "crtendS.o") or std.mem.endsWith(u8, arg, "crtn.o")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "crtbeginS.o") or std.mem.endsWith(u8, arg, "crti.o") or std.mem.endsWith(u8, arg, "Scrt1.o")) {
            // NOT CHANGE!!
        } else if (std.mem.startsWith(u8, arg, "-m") or std.mem.startsWith(u8, arg, "elf_")) {
            // NOT CHANGE!!
        } else {
            try cmds.append(arg);
        }

        //usr/lib/gcc/x86_64-linux-gnu/13/crtendS.o /lib/x86_64-linux-gnu/crtn.o
    }
    // Why native? See: https://github.com/kassane/sokol-d/issues/1
    if (isNative) {
        try cmds.append("-target");
        if (builtin.os.tag == .windows)
            try cmds.append("native-native-msvc")
        else {
            try cmds.append("native-native");
        }
    }

    var proc = std.process.Child.init(cmds.items, allocator);

    // See all flags
    std.debug.print("debug flags: ", .{});
    for (cmds.items) |cmd|
        std.debug.print("{s} ", .{cmd});
    std.debug.print("\n", .{});

    _ = try proc.spawnAndWait();
}
