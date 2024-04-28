const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_masked() bool {
    var nthreads: u32 = 0;
    var executing_thread: i32 = -1;
    var tid_result: u32 = 0;

    omp.parallel(.{})
        .run(.{ .shared = .{ &nthreads, &executing_thread, &tid_result } }, struct {
        fn f(f_nthreads: *u32, f_executing_thread: *i32, f_tid_result: *u32) void {
            omp.masked()
                .run(.{ f_nthreads, f_executing_thread, f_tid_result }, omp.only_master, struct {
                fn f(ff_nthreads: *u32, ff_executing_thread: *i32, ff_tid_result: *u32) void {
                    const tid: i32 = @intCast(omp.get_thread_num());

                    if (tid != 0) {
                        omp.critical(.{})
                            .run(.{ff_tid_result}, struct {
                            fn f(fff_tid_result: *u32) void {
                                fff_tid_result.* += 1;
                            }
                        }.f);
                    }

                    omp.critical(.{})
                        .run(.{ff_nthreads}, struct {
                        fn f(fff_nthreads: *u32) void {
                            fff_nthreads.* += 1;
                        }
                    }.f);
                    ff_executing_thread.* = @intCast(omp.get_thread_num());
                }
            }.f);
        }
    }.f);

    return (nthreads == 1) and (executing_thread == 0) and (tid_result == 0);
}

test "masked" {
    var num_failed: u32 = 0;

    for (params.repetitions) |_| {
        if (!test_omp_masked()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
