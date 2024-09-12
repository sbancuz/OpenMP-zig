const std = @import("std");

fn findOpenMP(b: *std.Build, omp: *std.Build.Module) ![]const u8 {
    const t = omp.resolved_target.?.result;
    const paths = try std.zig.system.NativePaths.detect(b.allocator, t);
    var buf: [20]u8 = undefined;
    var lib_name = try std.fmt.bufPrint(&buf, "{s}omp{s}", .{ t.libPrefix(), t.dynamicLibSuffix() });

    return b.findProgram(&[_][]const u8{lib_name}, paths.lib_dirs.items) catch {
        lib_name = try std.fmt.bufPrint(&buf, "{s}omp{s}", .{ t.libPrefix(), t.staticLibSuffix() });
        return try b.findProgram(&[_][]const u8{lib_name}, paths.lib_dirs.items);
    };
}

const omp_support = struct {
    ompt: bool = false,
    ompd: bool = false,
    gomp: bool = false,
    ompx: bool = false,
    kmp_monitor: bool = false,
};
fn checkSupport(b: *std.Build, path: []const u8) !omp_support {
    // The size doesn't matter since function calls stat
    const lib = try std.fs.Dir.readFileAlloc(std.fs.cwd(), b.allocator, path, 1024 * 1024 * 100);
    return .{
        .ompt = std.mem.containsAtLeast(u8, lib, 1, "ompt_enable"),
        .ompd = std.mem.containsAtLeast(u8, lib, 1, "ompd_init"),
        .gomp = std.mem.containsAtLeast(u8, lib, 1, "GOMP"),
        .ompx = std.mem.containsAtLeast(u8, lib, 1, "ompx"),
        .kmp_monitor = std.mem.containsAtLeast(u8, lib, 1, "__kmp_init_monitor"),
    };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // lib.root_module.addImport("build_options", opts_mod);
    const omp = b.addModule("omp", .{
        .root_source_file = b.path("src/omp.zig"),
        .target = target,
        .optimize = optimize,
    });

    omp.link_libc = true;
    omp.linkSystemLibrary("omp", .{ .needed = true });

    const openmp_path = try findOpenMP(b, omp);
    const support = try checkSupport(b, openmp_path);

    const options = b.addOptions();
    const opts_mod = options.createModule();

    options.addOption(bool, "ompt_support", support.ompt);
    options.addOption(bool, "ompd_support", support.ompd);
    options.addOption(bool, "gomp_support", support.gomp);
    options.addOption(bool, "ompx_support", support.ompx);
    options.addOption(bool, "kmp_monitor_support", support.kmp_monitor);

    omp.addOptions("build_options", options);

    {
        const unit_tests = b.addTest(.{
            .name = "unit-tests",
            .root_source_file = b.path("tests/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        unit_tests.linkLibC();
        unit_tests.linkSystemLibrary("omp");

        omp.addImport("build_options", opts_mod);
        unit_tests.root_module.addImport("omp", omp);
        b.installArtifact(unit_tests);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
}
