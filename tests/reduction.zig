const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn parallel_plus_for(i: u32, sum: *u32) void {
    sum.* += i;
}

fn parallel_default_para(p: *omp.ctx, sum: *u32) void {
    p.parallel_for(parallel_plus_for, .{sum}, @as(u32, 1), @as(u32, params.loop_count + 1), @as(u32, 1), .{});
}

fn test_omp_parallel_default_reduction() bool {
    var sum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel_ctx(parallel_default_para, .{ .reduction = .{&sum} }, .{}, .{ .reduction = &.{.plus} });

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    return known_sum == sum;
}

test "parallel_default_reduction" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!test_omp_parallel_default_reduction()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
