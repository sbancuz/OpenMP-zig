const std = @import("std");
const omp = @import("omp");
const params = @import("params.zig");

fn test_omp_sections_default() !bool {
    var sum: u32 = 7;
    const known_sum: u32 = @as(u32, (params.loop_count * (params.loop_count - 1)) / 2) + sum;

    omp.parallel(.{})
        .run(.{ .shared = .{&sum} }, struct {
        fn f(f_sum: *u32) void {
            var mysum: u32 = 0;
            var i: u32 = 0;
            const summer = struct {
                fn f(s: *u32, ms: *u32) void {
                    s.* += ms.*;
                }
            }.f;

            omp.sections(.{})
                .run(.{ .shared = .{f_sum}, .firstprivate = .{ &mysum, &i } }, .{
                &struct {
                    fn section(ff_sum: *u32, ff_mysum: *u32, ff_i: *u32) void {
                        ff_i.* = 1;
                        while (ff_i.* < 400) : (ff_i.* += 1) {
                            ff_mysum.* += ff_i.*;
                        }
                        omp.critical(.{ .name = "c1" }).run(.{ ff_sum, ff_mysum }, summer);
                    }
                }.section,
                &struct {
                    fn section(ff_sum: *u32, ff_mysum: *u32, ff_i: *u32) void {
                        ff_i.* = 400;
                        while (ff_i.* < 700) : (ff_i.* += 1) {
                            ff_mysum.* += ff_i.*;
                        }
                        omp.critical(.{ .name = "c2" }).run(.{ ff_sum, ff_mysum }, summer);
                    }
                }.section,
                &struct {
                    fn section(ff_sum: *u32, ff_mysum: *u32, ff_i: *u32) void {
                        ff_i.* = 700;
                        while (ff_i.* < 1000) : (ff_i.* += 1) {
                            ff_mysum.* += ff_i.*;
                        }
                        omp.critical(.{ .name = "c3" }).run(.{ ff_sum, ff_mysum }, summer);
                    }
                }.section,
            });
        }
    }.f);

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    return known_sum == sum;
}

test "sections_default" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_sections_default()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}

fn test_omp_parallel_sections_default() !bool {
    var sum: u32 = 7;
    const known_sum: u32 = @as(u32, (params.loop_count * (params.loop_count - 1)) / 2) + sum;

    var mysum: u32 = 0;
    var i: u32 = 0;
    const summer = struct {
        fn f(s: *u32, ms: *u32) void {
            s.* += ms.*;
        }
    }.f;

    omp.parallel(.{})
        .sections(.{})
        .run(.{ .shared = .{&sum}, .firstprivate = .{ &mysum, &i } }, .{
        &struct {
            fn section(ff_sum: *u32, ff_mysum: *u32, ff_i: *u32) void {
                ff_i.* = 1;
                while (ff_i.* < 400) : (ff_i.* += 1) {
                    ff_mysum.* += ff_i.*;
                }
                omp.critical(.{ .name = "c1" }).run(.{ ff_sum, ff_mysum }, summer);
            }
        }.section,
        &struct {
            fn section(ff_sum: *u32, ff_mysum: *u32, ff_i: *u32) void {
                ff_i.* = 400;
                while (ff_i.* < 700) : (ff_i.* += 1) {
                    ff_mysum.* += ff_i.*;
                }
                omp.critical(.{ .name = "c2" }).run(.{ ff_sum, ff_mysum }, summer);
            }
        }.section,
        &struct {
            fn section(ff_sum: *u32, ff_mysum: *u32, ff_i: *u32) void {
                ff_i.* = 700;
                while (ff_i.* < 1000) : (ff_i.* += 1) {
                    ff_mysum.* += ff_i.*;
                }
                omp.critical(.{ .name = "c3" }).run(.{ ff_sum, ff_mysum }, summer);
            }
        }.section,
    });

    if (known_sum != sum) {
        std.debug.print("KNOWN_SUM = {}\n", .{known_sum});
        std.debug.print("SUM = {}\n", .{sum});
    }

    return known_sum == sum;
}

test "parallel_sections_default" {
    var num_failed: u32 = 0;
    for (0..params.repetitions) |_| {
        if (!try test_omp_parallel_sections_default()) {
            num_failed += 1;
        }
    }

    try std.testing.expect(num_failed == 0);
}
