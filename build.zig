const std = @import("std");

const env_to_check = &[_][]const u8{
    "LD_LIBRARY_PATH",
    "LIBRARY_PATH",
    "CMAKE_LIBRARY_PATH",
    "PATH",
};

// TODO: Find a better way to do this, idk how the compiler does it, but it would be nice to use the same mechanism
fn findOpenMP(b: *std.Build) ![]const u8 {
    for (env_to_check) |env| {
        if (std.process.getEnvVarOwned(b.allocator, env)) |val| {
            if (!std.mem.containsAtLeast(u8, val, 1, "openmp")) {
                continue;
            }

            var it = std.mem.splitAny(u8, val, ":");
            while (it.next()) |p| {
                if (std.mem.containsAtLeast(u8, p, 1, "openmp")) {
                    return try b.findProgram(&[_][]const u8{"libomp.so"}, &[_][]const u8{p});
                }
            }
        } else |_| {}
    }

    return error.NotFound;
}

const omp_support = struct {
    ompt: bool = false,
    ompd: bool = false,
};
fn checkSupport(b: *std.Build, path: []const u8) !omp_support {
    // The size doesn't matter since function calls stat
    const lib = try std.fs.Dir.readFileAlloc(std.fs.cwd(), b.allocator, path, 1024 * 1024 * 100);
    return .{
        .ompt = std.mem.containsAtLeast(u8, lib, 1, "ompt_initialize"),
        .ompd = std.mem.containsAtLeast(u8, lib, 1, "ompd_init"),
    };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const openmp_path = try findOpenMP(b);
    const support = try checkSupport(b, openmp_path);

    // const use_openssl = b.option(bool, "openssl", "Use system-installed openssl for TLS support in zap") orelse blk: {
    //     // Alternatively, use an os env var to determine whether to build openssl support
    //     if (std.process.getEnvVarOwned(b.allocator, "ZAP_USE_OPENSSL")) |val| {
    //         defer b.allocator.free(val);
    //         if (std.mem.eql(u8, val, "true")) break :blk true;
    //     } else |_| {}
    //     break :blk false;
    // };

    const lib = b.addStaticLibrary(.{
        .name = "omp-zig",
        .root_source_file = b.path("src/omp.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.linkSystemLibrary("omp");

    const options = b.addOptions();
    options.addOption(bool, "ompt_support", support.ompt);
    options.addOption(bool, "ompd_support", support.ompd);
    const opts_mod = options.createModule();

    lib.root_module.addImport("build_options", opts_mod);

    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .name = "unit-tests",
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.linkLibC();
    unit_tests.linkSystemLibrary("omp");

    const omp = b.addModule("omp", .{ .root_source_file = b.path("src/omp.zig") });

    omp.addImport("build_options", opts_mod);
    unit_tests.root_module.addImport("omp", omp);
    b.installArtifact(unit_tests);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
