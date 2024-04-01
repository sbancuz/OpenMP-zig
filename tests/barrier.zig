const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_barrier() bool {
    var result1: u32 = 0;
    var result2: u32 = 0;

    omp.parallel_ctx(.{ .shared = .{ &result1, &result2 } }, .{}, .{}, struct {
        fn f(p: *omp.ctx, f_result1: *u32, f_result2: *u32) void {
            var rank: u32 = omp.get_thread_num();
            if (rank == 1) {
                std.time.sleep(params.sleep_time);
                f_result2.* = 3;
            }

            p.barrier();
            if (rank == 2) {
                f_result1.* = f_result2.*;
            }
        }
    }.f);

    return result1 == 3;
}

test "barrier" {
    var num_failed: u32 = 0;
    omp.set_dynamic(false);
    omp.set_num_threads(4);
    for (0..params.repetitions) |_| {
        if (!test_omp_barrier()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
