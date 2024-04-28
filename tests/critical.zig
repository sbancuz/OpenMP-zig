const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_critical() bool {
    var sum: u32 = 0;
    const known_sum: u32 = 999 * 1000 / 2;

    omp.parallel(.{})
        .run(.{ .shared = .{&sum} }, struct {
        fn f(f_sum: *u32) void {
            var mysum: u32 = 0;

            omp.loop(.{ .idx = u32 })
                .run(.{ .shared = .{&mysum} }, 1, params.loop_count, 1, struct {
                fn f(i: u32, f_mysum: *u32) void {
                    f_mysum.* = f_mysum.* + i;
                }
            }.f);

            omp.critical(.{})
                .run(.{ f_sum, &mysum }, struct {
                fn f(ff_sum: *u32, f_mysum: *u32) void {
                    ff_sum.* += f_mysum.*;
                }
            }.f);
        }
    }.f);

    if (sum != known_sum) {
        std.debug.print("sum: {}, known_sum: {}\n", .{ sum, known_sum });
    }

    return known_sum == sum;
}

test "critical" {
    var num_failed: u32 = 0;

    for (params.repetitions) |_| {
        if (!test_omp_critical()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn omp_critical_hint(iter: u32) bool {
    var sum: u32 = 0;
    const known_sum: u32 = (999 * 1000) / 2;

    omp.parallel(.{})
        .run(.{ .shared = .{ &sum, iter } }, struct {
        fn f(f_sum: *u32, f_iter: u32) void {
            var mysum: u32 = 0;
            omp.loop(.{ .idx = u32 })
                .run(.{ .shared = .{&mysum} }, 0, params.loop_count, 1, struct {
                fn f(i: u32, f_mysum: *u32) void {
                    f_mysum.* = f_mysum.* + i;
                }
            }.f);

            const fun = struct {
                fn f(ff_sum: *u32, f_mysum: *u32) void {
                    ff_sum.* += f_mysum.*;
                }
            }.f;

            switch (f_iter % 4) {
                0 => {
                    omp.critical(.{ .name = "a", .sync = .uncontended }).run(.{ f_sum, &mysum }, fun);
                },
                1 => {
                    omp.critical(.{ .name = "b", .sync = .contended }).run(.{ f_sum, &mysum }, fun);
                },
                2 => {
                    omp.critical(.{ .name = "c", .sync = .nonspeculative }).run(.{ f_sum, &mysum }, fun);
                },
                3 => {
                    omp.critical(.{ .name = "d", .sync = .speculative }).run(.{ f_sum, &mysum }, fun);
                },
                else => {
                    unreachable;
                },
            }
        }
    }.f);

    if (sum != known_sum) {
        std.debug.print("sum: {}, known_sum: {}\n", .{ sum, known_sum });
    }

    return known_sum == sum;
}

test "critical_hint" {
    var num_failed: u32 = 0;

    for (0..params.repetitions) |i| {
        if (!omp_critical_hint(@intCast(i))) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
