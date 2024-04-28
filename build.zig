const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const omp = b.addModule("omp", .{ .root_source_file = b.path("src/omp.zig") });

    const lib = b.addStaticLibrary(.{
        .name = "omp-zig",
        .root_source_file = b.path("src/omp.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.linkSystemLibrary("omp");

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "omp-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkSystemLibrary("omp");
    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.linkLibC();
    unit_tests.linkSystemLibrary("omp");

    unit_tests.root_module.addImport("omp", omp);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
