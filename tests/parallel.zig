const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_parallel_default() !bool {
    var sum: u32 = 0;
    var mysum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel(parallel_default_para, .{ .shared = .{&sum}, .private = .{&mysum} }, .{});

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    try std.testing.expect(mysum == 0);

    return known_sum == sum;
}

fn parallel_default_para(p: *omp.ctx, sum: *u32, mysum: *u32) void {
    p.parallel_for(parallel_default_for, .{mysum}, @as(u32, 1), @as(u32, @intCast(params.loop_count + 1)), @as(u32, 1), .{});

    omp.critical("para")(p, .none, critical_para, .{ sum, mysum.* });
}

fn parallel_default_for(p: *omp.ctx, i: u32, mysum: *u32) void {
    _ = p;
    mysum.* += i;
}

fn critical_para(p: *omp.ctx, sum: *u32, mysum: u32) void {
    _ = p;
    sum.* += mysum;
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

    omp.parallel(parallel_if_para, .{ .shared = .{&sum}, .private = .{&mysum} }, .{ .condition = control == 0 });

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    try std.testing.expect(mysum == 0);

    return known_sum == sum;
}

fn parallel_if_para(p: *omp.ctx, sum: *u32, mysum: *u32) void {
    for (0..params.loop_count + 1) |i| {
        mysum.* += @as(u32, @intCast(i));
    }

    omp.critical("para")(p, .none, critical_para, .{ sum, mysum.* });
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

    omp.parallel(parallel_nested_para, .{ .shared = .{&counter} }, .{});

    return counter != 0;
}

fn parallel_nested_para(p: *omp.ctx, counter: *i32) void {
    omp.critical("nested")(p, .none, critical_nested_plus, .{counter});

    omp.parallel(parallel_nested_para_nest, .{ .shared = .{counter} }, .{});
}

fn critical_nested_plus(p: *omp.ctx, counter: *i32) void {
    _ = p;
    counter.* += 1;
}

fn parallel_nested_para_nest(p: *omp.ctx, counter: *i32) void {
    omp.critical("nested")(p, .none, critical_nested_minus, .{counter});
}

fn critical_nested_minus(p: *omp.ctx, counter: *i32) void {
    _ = p;
    counter.* -= 1;
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

    omp.parallel(parallel_private_para, .{ .shared = .{ &sum, &num_threads }, .private = .{&sum1} }, .{});

    const known_sum: u32 = ((999 * 1000) / 2) + (7 * num_threads);
    if (known_sum != sum) {
        std.debug.print("NUM_THREADS = {}\n", .{num_threads});
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }
    return known_sum == sum;
}

fn parallel_private_para(p: *omp.ctx, sum: *u32, num_threads: *u32, sum1: *u32) void {
    sum1.* = 7;

    p.parallel_for(parallel_for_private, .{sum1}, @as(u32, 1), @as(u32, 1000), @as(u32, 1), .{});

    omp.critical("para")(p, .none, critical_private, .{ sum, num_threads, sum1.* });
}

fn parallel_for_private(p: *omp.ctx, i: u32, sum1: *u32) void {
    _ = p;
    sum1.* += i;
}

fn critical_private(p: *omp.ctx, sum: *u32, num_threads: *u32, sum1: u32) void {
    _ = p;
    sum.* += sum1;
    num_threads.* += 1;
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
