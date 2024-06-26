# anotherBuildStep (a.k.a aBS)

## Overview

`anotherBuildStep` is a project designed to leverage the Zig build system (`build.zig`) for building projects with various other toolchains. This allows developers to use Zig as a unified build system across different environments and toolsets.

## TODO

- [x] ldc2 support
- [x] flang-new support
- [x] rustc (no cargo) support
- [ ] ~~rustc (cargo) support~~ (need to figure out how to get the cargo build system to work)

## Required

- [zig](https://ziglang.org/download) v0.13.0 or master


## Supported

- [ldc2](https://ldc-developers.github.io/) v1.38.0 or latest-CI
- [flang](https://flang.llvm.org) (a.k.a flang-new) LLVM-18.1.3 or master
- [rustc](https://www.rust-lang.org/tools/install) stable or nightly


## Usage

Make new project or add to existing project:

In project folder, add this package as dependency on your `build.zig.zon`

```bash
$ zig fetch --save=abs git+https://github.com/kassane/anotherBuildStep
```
- add `const abs = @import("abs")` in `build.zig`

```zig
const std = @import("std");
// get build.zig from pkg to extend your build.zig project (only pub content module)
const abs = @import("abs");
// Dlang
const ldc2 = abs.ldc2;
// Fortran
const flang = abs.flang;
// Rust
const rustc = abs.rust;
// zig-cc wrapper
const zcc = abs.zcc;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const exeD = try ldc2.BuildStep(b, .{
        .name = "helloD",
        .target = target,
        .optimize = optimize,
        .sources = &.{
            "src/main.d",
        },
        .dflags = &.{
            "-w",
        },
    });
    b.default_step.dependOn(&exeD.step);

    // or
    
    const exeFortran = try flang.BuildStep(b, .{
        .name = "hellof",
        .target = target,
        .optimize = optimize,
        .sources = &.{
            "src/main.f90",
        },
        .fflags = &.{},
        .use_zigcc = true,
        .t_options = try zcc.buildOptions(b, target),
    });
    b.default_step.dependOn(&exeFortran.step);

    // or

    const exeRust = try rustc.BuildStep(b, .{
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
