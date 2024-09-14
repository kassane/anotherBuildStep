//! This Source Code Form is subject to the terms of the Mozilla Public
//! License, v. 2.0. If a copy of the MPL was not distributed with this
//! file, You can obtain one at https://mozilla.org/MPL/2.0/.

const std = @import("std");

pub fn buildZigCC(b: *std.Build, options: *std.Build.Step.Options) *std.Build.Step.Compile {
    const zigcc = b.addWriteFiles();

    const exe = b.addExecutable(.{
        .name = "zcc",
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
        .root_source_file = zigcc.add("zcc.zig", generated_zcc),
    });
    exe.root_module.addOptions("build_options", options);
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

const generated_zcc =
    \\ const std = @import("std");
    \\ const builtin = @import("builtin");
    \\ const build_options = @import("build_options");
    \\ // [NOT CHANGE!!] => skip flag
    \\ // replace system-provider resources to zig provider resources
    \\
    \\ pub fn main() !void {
    \\     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    \\     defer _ = std.debug.assert(gpa.deinit() == .ok); // ok or leak
    \\     const allocator = gpa.allocator();
    \\
    \\     var args = try std.process.argsWithAllocator(allocator);
    \\     defer args.deinit();
    \\
    \\     _ = args.skip(); // skip arg[0]
    \\
    \\     var cmds = std.ArrayList([]const u8).init(allocator);
    \\     defer cmds.deinit();
    \\
    \\     try cmds.append("zig");
    \\     try cmds.append("cc");
    \\
    \\     while (args.next()) |arg| {
    \\         // HACK: ldmd2 emit '-target' flag for Darwin, but zigcc already have it
    \\         if (std.mem.startsWith(u8, arg, "arm64-apple-") or
    \\             std.mem.startsWith(u8, arg, "x86_64-apple-"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "-target")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "-group")) {
    \\             try cmds.appendSlice(&.{
    \\                 "-Wl,--start-group",
    \\                 "-Wl,--end-group",
    \\             });
    \\         } else if (std.mem.endsWith(u8, arg, "-dynamic")) {
    \\             try cmds.append("-Wl,--export-dynamic");
    \\         } else if (std.mem.eql(u8, arg, "--exclude-libs") or std.mem.eql(u8, arg, "ALL")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "rv64gc") or
    \\             std.mem.endsWith(u8, arg, "rv32i_zicsr_zifencei"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "--hash-style")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "--build-id")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "whole-archive")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "--eh-frame-hdr")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "as-needed")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "gcc") or
    \\             std.mem.endsWith(u8, arg, "gcc_s"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "-lFortran")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "linkonceodr-outlining")) {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "aarch64linux") or
    \\             std.mem.startsWith(u8, arg, "elf"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "/lib/ld-") or
    \\             std.mem.startsWith(u8, arg, "-dynamic-linker"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "crtendS.o") or
    \\             std.mem.endsWith(u8, arg, "crtn.o"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.endsWith(u8, arg, "crtbeginS.o") or
    \\             std.mem.endsWith(u8, arg, "crti.o") or
    \\             std.mem.endsWith(u8, arg, "Scrt1.o"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else if (std.mem.startsWith(u8, arg, "-m") or
    \\             std.mem.startsWith(u8, arg, "elf_"))
    \\         {
    \\             // NOT CHANGE!!
    \\         } else {
    \\             try cmds.append(arg);
    \\         }
    \\     }
    \\
    \\     if (build_options.triple) |triple_target| {
    \\         try cmds.append("-target");
    \\         try cmds.append(triple_target);
    \\     }
    \\     if (build_options.cpu) |cpu| {
    \\         try cmds.append(std.fmt.comptimePrint("-mcpu={s}", .{cpu}));
    \\     }
    \\
    \\     if (builtin.os.tag != .windows) {
    \\         try cmds.append("-lunwind");
    \\     }
    \\
    \\     var proc = std.process.Child.init(cmds.items, allocator);
    \\
    \\     try std.io.getStdOut().writer().print("[zig cc] flags: \"", .{});
    \\     for (cmds.items) |cmd| {
    \\         if (std.mem.startsWith(u8, cmd, "zig")) continue;
    \\         if (std.mem.startsWith(u8, cmd, "cc")) continue;
    \\         try std.io.getStdOut().writer().print("{s} ", .{cmd});
    \\     }
    \\     try std.io.getStdOut().writer().print("\"\n", .{});
    \\
    \\     _ = try proc.spawnAndWait();
    \\ }
;
