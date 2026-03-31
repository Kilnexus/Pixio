const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pixio_mod = b.addModule("pixio", .{
        .root_source_file = b.path("src/pixio.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addImport("pixio", pixio_mod);

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run pixio unit tests");
    test_step.dependOn(&run_tests.step);
}
