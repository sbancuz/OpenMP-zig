const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_critical() bool {
    var sum: u32 = 0;
    const known_sum: u32 = 999 * 1000 / 2;

    omp.parallel(parallel_sum, .{ .shareds = .{&sum} }, .{});
    return known_sum == sum;
}

fn parallel_sum(p: *omp.ctx, sum: *u32) void {
    var mysum: u32 = 0;
    p.parallel_for(for_fn, .{&mysum}, @as(u32, 0), @as(u32, 1000), @as(u32, 1), .{});

    p.critical(critical_fn, .{ sum, &mysum });
}

fn for_fn(p: *omp.ctx, i: u32, mysum: *u32) void {
    _ = p;
    mysum.* = mysum.* + i;
}

fn critical_fn(p: *omp.ctx, sum: *u32, mysum: *u32) void {
    _ = p;
    sum.* += mysum.*;
}

test "critical" {
    var num_failed: u32 = 0;

    for (params.repetitions) |_| {
        if (!test_omp_critical()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
