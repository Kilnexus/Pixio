const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pixio_mod = b.addModule("Pixio", .{
        .root_source_file = b.path("src/Pixio.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = if (target.result.os.tag == .windows) true else null,
    });
    if (target.result.os.tag == .windows) {
        pixio_mod.linkSystemLibrary("ole32", .{});
        pixio_mod.linkSystemLibrary("windowscodecs", .{});
    }

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addImport("Pixio", pixio_mod);

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run Pixio unit tests");
    test_step.dependOn(&run_tests.step);
}
