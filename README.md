# anotherBuildStep (a.k.a ABS)

## Overview

`anotherBuildStep` is a project designed to leverage the Zig build system (`build.zig`) for building projects with various other toolchains. This allows developers to use Zig as a unified build system across different environments and toolsets.

## TODO

- [x] ldc2 support
- [x] rustc (no cargo) support
- [ ] ~~rustc (cargo) support~~ (need to figure out how to get the cargo build system to work)

## Required

- [zig](https://ziglang.org/download) v0.13.0 or master


## Supported

- [ldc2](https://ldc-developers.github.io/) v1.38.0 or latest-CI
- [rustc](https://www.rust-lang.org/tools/install) stable or nightly


## Usage

Make new project or add to existing project:

In project folder, add this package, as dependency on your `build.zig.zon`

```bash
$ zig fetch --save git+https://github.com/kassane/anotherBuildStep
```
- add `@import("anotherBuildStep")` to `build.zig`

```zig
const std = @import("std");
// get build.zig from pkg to extend your build.zig project (only pub content module)
const abs = @import("anotherBuildStep"); 

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = try abs.ldcBuildStep(b, .{
        .name = "helloD",
        .target = target,
        .optimize = optimize,
        .sources = &.{"src/main.d"},
        .dflags = &.{
            "-w",
        },
    });
    b.default_step.dependOn(&exe.step);

    // or

    const exeRust = try abs.rustcBuildStep(b, .{
        .name = "helloRust",
        .target = target,
        .optimize = optimize,
        .source = "src/main.rs",
        .rflags = &.{
            "-C",
            "panic=abort",
        },
    });
    b.default_step.dependOn(&exeRust.step);
}
```
