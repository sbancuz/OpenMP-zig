const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_parallel_return() !bool {
    const sum = omp.parallel(.{
        .ret_reduction = .plus,
    }).run(.{}, struct {
        fn f() usize {
            return 1;
        }
    }.f);

    return omp.get_max_threads() == sum;
}

test "parallel_return" {
    var num_failed: u32 = 0;
    if (!try test_omp_parallel_return()) {
        num_failed += 1;
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_single_default() !bool {
    const result = omp.parallel(.{ .ret_reduction = .plus })
        .run(.{}, struct {
        fn f() usize {
            const maybe = omp.single()
                .run(.{}, struct {
                fn f() usize {
                    return 1;
                }
            }.f);
            if (maybe) |r| {
                return r;
            }
            return 0;
        }
    }.f);

    return result == 1;
}

test "single_default" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_single_default()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_task_default() !bool {
    const result = omp.parallel(.{ .ret_reduction = .plus })
        .run(.{}, struct {
        fn f() usize {
            const maybe = omp.single()
                .run(.{}, struct {
                fn f() *omp.promise(usize) {
                    return omp.task(.{})
                        .run(.{}, struct {
                        fn f() usize {
                            return 1;
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
    }.f);

    return result == 1;
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

fn test_omp_loop_default() !bool {
    const res = omp.parallel(.{ .ret_reduction = .plus })
        .run(.{}, struct {
        fn f() usize {
            const a = omp.loop(.{ .idx = u32, .ret_reduction = .plus })
                .run(.{}, 0, params.loop_count, 1, struct {
                fn f(i: u32) usize {
                    _ = i;
                    return 1;
                }
            }.f);

            return a;
        }
    }.f);

    return params.loop_count == res;
}

test "loop_default" {
    if (omp.get_max_threads() < 2) {
        omp.set_num_threads(8);
    }

    var num_failed: u32 = 0;
    for (0..1) |_| {
        if (!try test_omp_loop_default()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
