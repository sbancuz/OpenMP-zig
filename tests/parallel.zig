const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_parallel_default() !bool {
    var sum: u32 = 0;
    var mysum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel(parallel_default_para, .{ .shareds = .{&sum}, .privates = .{&mysum} }, .{});

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    try std.testing.expect(mysum == 0);

    return known_sum == sum;
}

fn parallel_default_para(p: *omp.ctx, sum: *u32, mysum: *u32) void {
    p.parallel_for(parallel_default_for, .{mysum}, @as(u32, 0), @as(u32, @intCast(params.loop_count + 1)), @as(u32, 1), .{});

    p.critical("para", .none, critical_para, .{ sum, mysum.* });
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
    omp.set_dynamic(false);
    omp.set_num_threads(4);
    for (0..params.repetitions) |_| {
        if (!try test_omp_parallel_default()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
