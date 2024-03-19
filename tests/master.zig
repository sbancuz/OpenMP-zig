const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_master() bool {
    var nthreads: u32 = 0;
    var executing_thread: i32 = -1;
    var tid_result: u32 = 0;

    omp.parallel(parallel_master, .{ .shared = .{ &nthreads, &executing_thread, &tid_result } }, .{});
    return (nthreads == 1) and (executing_thread == 0) and (tid_result == 0);
}

fn parallel_master(p: *omp.ctx, nthreads: *u32, executing_thread: *i32, tid_result: *u32) void {
    p.master(master_fn, .{ nthreads, executing_thread, tid_result });
}

fn master_fn(p: *omp.ctx, nthreads: *u32, executing_thread: *i32, tid_result: *u32) void {
    var tid: i32 = @intCast(omp.get_thread_num());
    if (tid != 0) {
        omp.critical("tid_result")(p, .none, critical_tid_result_fn, .{tid_result});
    }

    omp.critical("none")(p, .none, critical_master_fn, .{nthreads});
    executing_thread.* = @intCast(omp.get_thread_num());
}

fn critical_master_fn(p: *omp.ctx, nthreads: *u32) void {
    _ = p;
    nthreads.* += 1;
}

fn critical_tid_result_fn(p: *omp.ctx, tid_result: *u32) void {
    _ = p;
    tid_result.* += 1;
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
