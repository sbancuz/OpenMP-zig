const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn parallel_reduction_plus() bool {
    var sum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel(.{})
        .run(.{ .shared = .{&sum} }, struct {
        fn f(f_sum: *u32) void {
            omp.loop(.{ .idx = u32, .reduction = &.{.plus} })
                .run(.{ .reduction = .{f_sum} }, 1, params.loop_count + 1, 1, struct {
                fn f(i: u32, ff_sum: *u32) void {
                    ff_sum.* += i;
                }
            }.f);
        }
    }.f);

    if (known_sum != sum) {
        std.debug.print("red KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    return known_sum == sum;
}

test "parallel_reduction_plus" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!parallel_reduction_plus()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn parallel_loop_reduction_plus() bool {
    var sum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel(.{})
        .loop(.{ .idx = u32, .reduction = &.{.plus} })
        .run(.{ .reduction = .{&sum} }, 1, params.loop_count + 1, 1, struct {
        fn f(i: u32, f_sum: *u32) void {
            f_sum.* += i;
        }
    }.f);

    if (known_sum != sum) {
        std.debug.print("red KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    return known_sum == sum;
}

test "parallel_loop_reduction_plus" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!parallel_loop_reduction_plus()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
