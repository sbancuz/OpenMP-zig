const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_parallel_default_reduction() bool {
    var sum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel_ctx(.{ .reduction = .{&sum} }, .{}, .{ .reduction = &.{.plus} }, struct {
        fn f(p: *omp.ctx, f_sum: *u32) void {
            p.parallel_for(.{f_sum}, @as(u32, 1), @as(u32, params.loop_count + 1), @as(u32, 1), .{}, struct {
                fn f(i: u32, ff_sum: *u32) void {
                    ff_sum.* += i;
                }
            }.f);
        }
    }.f);

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
