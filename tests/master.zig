const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_master() bool {
    var nthreads: u32 = 0;
    var executing_thread: i32 = -1;
    var tid_result: u32 = 0;

    omp.parallel_ctx(.{ .shared = .{ &nthreads, &executing_thread, &tid_result } }, .{}, .{}, struct {
        fn f(p: *omp.ctx, f_nthreads: *u32, f_executing_thread: *i32, f_tid_result: *u32) void {
            p.master_ctx(.{ f_nthreads, f_executing_thread, f_tid_result }, struct {
                fn f(pp: *omp.ctx, ff_nthreads: *u32, ff_executing_thread: *i32, ff_tid_result: *u32) void {
                    var tid: i32 = @intCast(omp.get_thread_num());

                    if (tid != 0) {
                        pp.critical(.{ff_tid_result}, "tid_result", .none, struct {
                            fn f(fff_tid_result: *u32) void {
                                fff_tid_result.* += 1;
                            }
                        }.f);
                    }

                    pp.critical(.{ff_nthreads}, "none", .none, struct {
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

test "master" {
    var num_failed: u32 = 0;

    for (params.repetitions) |_| {
        if (!test_omp_master()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
