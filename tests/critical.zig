const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_critical() bool {
    var sum: u32 = 0;
    const known_sum: u32 = 999 * 1000 / 2;

    omp.parallel_ctx(.{ .shared = .{&sum} }, .{}, .{}, struct {
        fn f(p: *omp.ctx, f_sum: *u32) void {
            var mysum: u32 = 0;

            p.parallel_for(.{&mysum}, @as(u32, 0), @as(u32, 1000), @as(u32, 1), .{}, struct {
                fn f(i: u32, f_mysum: *u32) void {
                    f_mysum.* = f_mysum.* + i;
                }
            }.f);

            p.critical(.{ f_sum, &mysum }, "none", .none, struct {
                fn f(ff_sum: *u32, f_mysum: *u32) void {
                    ff_sum.* += f_mysum.*;
                }
            }.f);
        }
    }.f);
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

    omp.parallel_ctx(.{ .shared = .{ &sum, iter } }, .{}, .{}, struct {
        fn f(p: *omp.ctx, f_sum: *u32, f_iter: u32) void {
            var mysum: u32 = 0;
            p.parallel_for(.{&mysum}, @as(u32, 0), @as(u32, 1000), @as(u32, 1), .{}, struct {
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
                    p.critical(.{ f_sum, &mysum }, "a", .uncontended, fun);
                },
                1 => {
                    p.critical(.{ f_sum, &mysum }, "b", .contended, fun);
                },
                2 => {
                    p.critical(.{ f_sum, &mysum }, "c", .nonspeculative, fun);
                },
                3 => {
                    p.critical(.{ f_sum, &mysum }, "d", .speculative, fun);
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
