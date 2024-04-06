const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_parallel_default_reduction() bool {
    var sum: u32 = 0;
    const known_sum: u32 = (params.loop_count * (params.loop_count + 1)) / 2;

    omp.parallel(.{ .reduction = &.{.plus} }).run(.{ .reduction = .{&sum} }, struct {
        fn f(f_sum: *u32) void {
            omp.loop(u32, .{ .sched = .auto, .chunk_size = 17 }).run(1, 1000 + 1, 1, .{ .shared = .{f_sum} }, struct {
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
