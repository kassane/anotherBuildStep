//! zig-cc wrapper for ldc2
//! Copyright (c) 2023 Matheus Catarino França <matheus-catarino@hotmail.com>
//! Zlib license

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

// [NOT CHANGE!!] => skip flag
// replace system-provider resources to zig provider resources

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

    // HACK: ldmd2 emit '-target' flag for Darwin, but zigcc already have it
    var target_count: usize = 0;

    while (args.next()) |arg| {
        // MacOS M1/M2 target, replace aarch64 to arm64
        if (std.mem.startsWith(u8, arg, "aarch64-apple-") or std.mem.startsWith(u8, arg, "arm64-apple-")) {
            try cmds.append(build_options.triple);
        } else if (std.mem.startsWith(u8, arg, "x86_64-apple-")) {
            try cmds.append(build_options.triple);
        } else if (std.mem.startsWith(u8, arg, "-target")) {
            defer target_count += 1;
            if (target_count < 1) {
                try cmds.append(arg); // add target flag
            }
        } else if (std.mem.endsWith(u8, arg, "rv64gc") or std.mem.endsWith(u8, arg, "rv32i_zicsr_zifencei")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, ".cpp") or std.mem.endsWith(u8, arg, ".cc")) {
            try cmds.append("-x");
            try cmds.append("c++");
        } else if (std.mem.endsWith(u8, arg, "gnu")) { // hash-style
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
        } else if (std.mem.startsWith(u8, arg, "-lFortran")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "linkonceodr-outlining")) {
            // NOT CHANGE!!
        } else if (std.mem.startsWith(u8, arg, "aarch64linux") or std.mem.startsWith(u8, arg, "elf")) {
            // NOT CHANGE!!
        } else if (std.mem.startsWith(u8, arg, "/lib/ld-") or std.mem.startsWith(u8, arg, "-dynamic-linker")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "crtendS.o") or std.mem.endsWith(u8, arg, "crtn.o")) {
            // NOT CHANGE!!
        } else if (std.mem.endsWith(u8, arg, "crtbeginS.o") or std.mem.endsWith(u8, arg, "crti.o") or std.mem.endsWith(u8, arg, "Scrt1.o")) {
            // NOT CHANGE!!
        } else if (std.mem.startsWith(u8, arg, "-m") or std.mem.startsWith(u8, arg, "elf_")) {
            // NOT CHANGE!!
        } else {
            try cmds.append(arg); // add (compat) flag
        }
    }

    if (target_count < 1) {
        try cmds.append("-target");
        try cmds.append(build_options.triple);
    }

    if (builtin.os.tag != .windows) {
        // not working on msvc target (nostdlib++)
        try cmds.append("-lunwind");
    }

    var proc = std.process.Child.init(cmds.items, allocator);

    // See all flags
    std.debug.print("[zig cc] flags: \"", .{});
    for (cmds.items) |cmd| {
        // skip 'zig cc'
        if (std.mem.startsWith(u8, cmd, "zig")) continue;
        if (std.mem.startsWith(u8, cmd, "cc")) continue;
        std.debug.print("{s} ", .{cmd});
    }
    std.debug.print("\"\n", .{});

    _ = try proc.spawnAndWait();
}
