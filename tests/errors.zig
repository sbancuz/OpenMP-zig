const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_parallel_error() !bool {
    _ = omp.parallel(.{
        .ret_reduction = .plus,
    }).run(.{}, struct {
        fn f() !usize {
            if (omp.get_thread_num() % 2 == 0) {
                return error.WompWomp;
            } else {
                return 1;
            }
        }
    }.f) catch |err| switch (err) {
        error.WompWomp => return true,
        else => return false,
    };

    return false;
}

test "parallel_error" {
    omp.set_num_threads(8);
    var num_failed: u32 = 0;
    for (0..params.repetitions * 100) |_| {
        if (!try test_omp_parallel_error()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_single_error() !bool {
    _ = omp.parallel(.{ .ret_reduction = .plus })
        .run(.{}, struct {
        fn f() !usize {
            const maybe = omp.single()
                .run(.{}, struct {
                fn f() !usize {
                    return error.WompWomp;
                }
            }.f);
            if (maybe) |r| {
                return r;
            }
            return 0;
        }
    }.f) catch |err| switch (err) {
        error.WompWomp => return true,
    };

    return false;
}

test "single_error" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..params.repetitions * 100) |_| {
        if (!try test_omp_single_error()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_task_error() !bool {
    _ = omp.parallel(.{ .ret_reduction = .plus })
        .run(.{}, struct {
        fn f() !usize {
            const maybe = omp.single()
                .run(.{}, struct {
                fn f() *omp.promise(error{WompWomp}!usize) {
                    return omp.task(.{})
                        .run(.{}, struct {
                        fn f() error{WompWomp}!usize {
                            return error.WompWomp;
                        }
                    }.f);
                }
            }.f);
            if (maybe) |pro| {
                defer pro.deinit();
                return pro.get();
            }
            return 0;
        }
    }.f) catch |err| switch (err) {
        error.WompWomp => return true,
    };

    return false;
}

test "task_error" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_task_error()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_loop_error() !bool {
    _ = omp.parallel(.{ .ret_reduction = .plus })
        .run(.{}, struct {
        fn f() !usize {
            const a = omp.loop(u32, .{ .ret_reduction = .plus })
                .run(.{}, 0, params.loop_count, 1, struct {
                fn f(i: u32) error{WompWomp}!usize {
                    _ = i;
                    return error.WompWomp;
                }
            }.f);
            return a;
        }
    }.f) catch |err| switch (err) {
        error.WompWomp => return true,
    };

    return false;
}

test "loop_error" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..1) |_| {
        if (!try test_omp_loop_error()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
