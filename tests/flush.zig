const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

pub fn test_omp_flush() bool {
    var result1: u32 = 0;
    var result2: u32 = 0;
    var dummy: u32 = 0;

    omp.parallel(.{})
        .run(.{ .shared = .{ &result1, &result2, &dummy } }, struct {
        fn f(f_result1: *u32, f_result2: *u32, f_dummy: *u32) void {
            const rank: u32 = omp.get_thread_num();
            omp.barrier();

            if (rank == 1) {
                f_result2.* = 3;
                omp.flush(.{f_result2});
                f_dummy.* = f_result2.*;
            }

            if (rank == 0) {
                std.time.sleep(params.sleep_time);
                omp.flush(.{f_result2});
                f_result1.* = f_result2.*;
            }
        }
    }.f);

    if (result1 != 3 or result2 != 3 or dummy != 3) {
        std.debug.print("result1: {}, result2: {}, dummy: {}\n", .{ result1, result2, dummy });
    }

    return result1 == 3 and result2 == 3 and dummy == 3;
}

test "flush" {
    var num_failed: u32 = 0;
    omp.set_dynamic(false);
    if (omp.get_max_threads() == 1) {
        omp.set_num_threads(2);
    }

    for (0..params.repetitions) |_| {
        if (!test_omp_flush()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
