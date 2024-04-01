const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_parallel_default() !bool {
    var sum: u32 = 0;
    var mysum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel_ctx(.{ .shared = .{&sum}, .private = .{&mysum} }, .{}, .{}, struct {
        fn f(p: *omp.ctx, f_sum: *u32, f_mysum: *u32) void {
            p.parallel_for(.{f_mysum}, @as(u32, 0), @as(u32, @intCast(params.loop_count + 1)), @as(u32, 1), .{}, struct {
                fn f(i: u32, ff_mysum: *u32) void {
                    ff_mysum.* += i;
                }
            }.f);

            p.critical(.{ f_sum, f_mysum.* }, "para", .none, struct {
                fn f(ff_sum: *u32, ff_mysum: u32) void {
                    ff_sum.* += ff_mysum;
                }
            }.f);
        }
    }.f);

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    try std.testing.expect(mysum == 0);

    return known_sum == sum;
}

test "parallel_default" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_parallel_default()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_parallel_if() !bool {
    var sum: u32 = 0;
    var mysum: u32 = 0;
    const control: u32 = 1;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel_ctx(.{ .shared = .{&sum}, .private = .{&mysum} }, .{ .condition = control == 0 }, .{}, struct {
        fn f(p: *omp.ctx, f_sum: *u32, f_mysum: *u32) void {
            for (0..params.loop_count + 1) |i| {
                f_mysum.* += @as(u32, @intCast(i));
            }
            p.critical(.{ f_sum, f_mysum.* }, "para", .none, struct {
                fn f(ff_sum: *u32, ff_mysum: u32) void {
                    ff_sum.* += ff_mysum;
                }
            }.f);
        }
    }.f);

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    try std.testing.expect(mysum == 0);

    return known_sum == sum;
}

test "parallel_if" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_parallel_if()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_parallel_nested() !bool {
    if (omp.get_max_threads() > 4) {
        omp.set_num_threads(4);
    } else if (omp.get_max_threads() < 2) {
        omp.set_num_threads(2);
    }

    var counter: i32 = 0;

    omp.set_nested(true);
    omp.set_max_active_levels(omp.get_max_active_levels());

    omp.parallel_ctx(.{ .shared = .{&counter} }, .{}, .{}, struct {
        fn f(p: *omp.ctx, f_counter: *i32) void {
            p.critical(.{f_counter}, "nested", .none, struct {
                fn f(ff_counter: *i32) void {
                    ff_counter.* += 1;
                }
            }.f);

            omp.parallel_ctx(.{ .shared = .{f_counter} }, .{}, .{}, struct {
                fn f(pp: *omp.ctx, pf_counter: *i32) void {
                    pp.critical(.{pf_counter}, "nested", .none, struct {
                        fn f(fpf_counter: *i32) void {
                            fpf_counter.* -= 1;
                        }
                    }.f);
                }
            }.f);
        }
    }.f);

    return counter != 0;
}

test "parallel_nested" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_parallel_nested()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_parallel_private() !bool {
    var sum: u32 = 0;
    var num_threads: u32 = 0;
    var sum1: u32 = 0;

    omp.parallel_ctx(.{ .shared = .{ &sum, &num_threads }, .private = .{&sum1} }, .{}, .{}, struct {
        fn f(p: *omp.ctx, f_sum: *u32, f_num_threads: *u32, f_sum1: *u32) void {
            f_sum1.* = 7;

            p.parallel_for(.{f_sum1}, @as(u32, 1), @as(u32, 1000), @as(u32, 1), .{}, struct {
                fn f(i: u32, ff_sum1: *u32) void {
                    ff_sum1.* += i;
                }
            }.f);

            p.critical(.{ f_sum, f_num_threads, f_sum1.* }, "para", .none, struct {
                fn f(ff_sum: *u32, ff_num_threads: *u32, ff_sum1: u32) void {
                    ff_sum.* += ff_sum1;
                    ff_num_threads.* += 1;
                }
            }.f);
        }
    }.f);

    const known_sum: u32 = ((999 * 1000) / 2) + (7 * num_threads);
    if (known_sum != sum) {
        std.debug.print("NUM_THREADS = {}\n", .{num_threads});
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }
    return known_sum == sum;
}

test "parallel_private" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_parallel_private()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
