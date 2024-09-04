const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_task_default() !bool {
    var tids = [_]u32{0} ** params.num_tasks;

    omp.parallel(.{})
        .run(.{ .shared = .{&tids} }, struct {
        fn f(f_tids: *[params.num_tasks]u32) void {
            omp.single()
                .run(.{f_tids}, struct {
                fn f(ff_tids: *[params.num_tasks]u32) void {
                    for (0..params.num_tasks) |i| {
                        // First we have to store the value of the loop index in a new variable
                        // which will be private for each task because otherwise it will be overwritten
                        // if the execution of the task takes longer than the time which is needed to
                        // enter the next step of the loop!

                        const myi = i;
                        omp.task(.{}).run(.{ .shared = .{ff_tids}, .firstprivate = .{myi} }, struct {
                            fn f(fff_tids: *[params.num_tasks]u32, f_myi: usize) void {
                                std.time.sleep(params.sleep_time);
                                fff_tids[f_myi] = omp.get_thread_num();
                            }
                        }.f);
                    }
                }
            }.f);
        }
    }.f);

    var uses_only_one_thread = true;
    for (tids) |t| {
        uses_only_one_thread = uses_only_one_thread and t == tids[0];
    }

    try std.testing.expect(!uses_only_one_thread);

    return true;
}

test "task_default" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_task_default()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_task_if() !bool {
    var count: usize = 0;
    var result: usize = 0;

    omp.parallel(.{})
        .run(.{ .shared = .{ &count, &result } }, struct {
        fn f(f_count: *usize, f_result: *usize) void {
            omp.single()
                .run(.{ f_count, f_result }, struct {
                fn f(ff_count: *usize, ff_result: *usize) void {
                    // Try to see if the if makes it so that the task is never deferred
                    // to another thread, in fact the critical block below must wait the sleep to run
                    omp.task(.{ .iff = true }).run(false, .{ .shared = .{ ff_count, ff_result } }, struct {
                        fn f(fff_count: *usize, fff_result: *usize) void {
                            std.time.sleep(params.sleep_time);
                            omp.critical(.{}).run(.{ fff_count, fff_result }, struct {
                                fn f(_count: *usize, _result: *usize) void {
                                    _result.* = if (_count.* == 0) 1 else 0;
                                }
                            }.f);
                        }
                    }.f);

                    // Now that the task is finished we can update the count
                    omp.critical(.{}).run(.{ff_count}, struct {
                        fn f(_count: *usize) void {
                            _count.* = 1;
                        }
                    }.f);
                }
            }.f);
        }
    }.f);

    return result == 1;
}

test "task_if" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_task_if()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_task_result() !bool {
    const t_type = *[params.num_tasks]u32;
    var tids = [_]u32{0} ** params.num_tasks;
    var include_tids = [_]u32{0} ** params.num_tasks;
    var err: usize = 0;

    omp.parallel(.{})
        .run(.{ .shared = .{ &tids, &include_tids } }, struct {
        fn f(f_tids: t_type, f_inctids: t_type) void {
            omp.single()
                .run(.{ f_tids, f_inctids }, struct {
                fn f(ff_tids: t_type, ff_inctids: t_type) void {
                    for (0..params.num_tasks) |i| {
                        // First we have to store the value of the loop index in a new variable
                        // which will be private for each task because otherwise it will be overwritten
                        // if the execution of the task takes longer than the time which is needed to
                        // enter the next step of the loop!

                        const myi = i;
                        omp.task(.{})
                            .run_final(i >= 5, .{ .shared = .{ ff_tids, ff_inctids }, .firstprivate = .{myi} }, struct {
                            fn f(fff_tids: t_type, fff_inctids: t_type, f_myi: usize) void {
                                fff_tids[f_myi] = omp.get_thread_num();

                                if (f_myi >= 5) {
                                    const included = f_myi;

                                    omp.task(.{})
                                        .run(.{ .shared = .{fff_inctids}, .firstprivate = .{included} }, struct {
                                        fn f(_inctids: t_type, f_included: usize) void {
                                            std.time.sleep(params.sleep_time);
                                            _inctids[f_included] = omp.get_thread_num();
                                        }
                                    }.f);

                                    std.time.sleep(params.sleep_time);
                                }
                            }
                        }.f);
                    }
                }
            }.f);
        }
    }.f);

    // Now we ckeck if more than one thread executed the final task and its included task.
    for (5..params.num_tasks) |t| {
        if (include_tids[t] != tids[t]) {
            err += 1;
        }
    }

    return err == 0;
}

test "task_result" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_task_result()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
