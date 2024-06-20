const std = @import("std");

pub fn dependenciesIterator(lib: *std.Build.Step.Compile, runner: *std.Build.Step.Run) void {
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
}
