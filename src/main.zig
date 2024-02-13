const omp = @import("omp.zig");
const std = @import("std");

test "main" {
    const res = try omp.parallel(tes, .{ .string = "gello" }, .{ .num_threads = 8 });
    if (res) |r| {
        std.debug.print("res: {any}\n", .{r});
    } else {
        std.debug.print("sadge\n", .{});
    }
}

pub fn tes(om: *omp.omp_ctx, args: anytype) error{Unimplemented}!?u34 {
    _ = args;
    _ = om;
    // om.parallel_for(tes2, args, 0, 4, 2, .{});

    return 1;
}

var a: c_int = 0;

pub fn tes2(om: *omp.omp_ctx, i: c_int, args: anytype) void {
    _ = i;
    _ = om;
    _ = args;
    // om.critical(test3, .{});
    // std.debug.print("its aliveeee {} {}\n", .{ a, i });
}

pub fn test3(om: *omp.omp_ctx, args: anytype) void {
    _ = args;
    _ = om;
    a += 1;
}
