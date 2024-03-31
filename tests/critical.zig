const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_critical() bool {
    var sum: u32 = 0;
    const known_sum: u32 = 999 * 1000 / 2;

    omp.parallel(parallel_sum, .{ .shared = .{&sum} }, .{}, .{});
    return known_sum == sum;
}

fn parallel_sum(p: *omp.ctx, sum: *u32) void {
    var mysum: u32 = 0;
    p.parallel_for(for_fn, .{&mysum}, @as(u32, 0), @as(u32, 1000), @as(u32, 1), .{});

    p.critical("none", .none, critical_fn, .{ sum, &mysum });
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

fn omp_critical_hint(iter: u32) bool {
    var sum: u32 = 0;
    const known_sum: u32 = (999 * 1000) / 2;

    omp.parallel(parallel_sum_hint, .{ .shared = .{ &sum, iter } }, .{}, .{});
    if (sum != known_sum) {
        std.debug.print("sum: {}, known_sum: {}\n", .{ sum, known_sum });
    }

    return known_sum == sum;
}

fn parallel_sum_hint(p: *omp.ctx, sum: *u32, iter: u32) void {
    var mysum: u32 = 0;
    p.parallel_for(for_fn_hint, .{&mysum}, @as(u32, 0), @as(u32, 1000), @as(u32, 1), .{});

    switch (iter % 4) {
        0 => {
            p.critical("a", .uncontended, critical_fn_hint, .{ sum, &mysum });
        },
        1 => {
            p.critical("b", .contended, critical_fn_hint, .{ sum, &mysum });
        },
        2 => {
            p.critical("c", .nonspeculative, critical_fn_hint, .{ sum, &mysum });
        },
        3 => {
            p.critical("d", .speculative, critical_fn_hint, .{ sum, &mysum });
        },
        else => {
            unreachable;
        },
    }
}

fn for_fn_hint(p: *omp.ctx, i: u32, mysum: *u32) void {
    _ = p;
    mysum.* = mysum.* + i;
}

fn critical_fn_hint(p: *omp.ctx, sum: *u32, mysum: *u32) void {
    _ = p;
    sum.* += mysum.*;
}

test "critical_hint" {
    var num_failed: u32 = 0;

    for (0..params.repetitions) |i| {
        if (!omp_critical_hint(@intCast(i))) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
