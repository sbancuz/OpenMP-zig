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
    om.task(tes2, args);

    return 1;
}

var a: c_int = 0;

pub fn tes2(om: *omp.omp_ctx, args: anytype) void {
    _ = args;
    _ = om;
    std.debug.print("its aliveeee {} \n", .{a});
}

pub fn test3(om: *omp.omp_ctx, args: anytype) void {
    _ = args;
    _ = om;
    a += 1;
}

pub fn main() !void {
    const res = try omp.parallel(tes, .{ .string = "gello" }, .{ .num_threads = 8 });
    if (res) |r| {
        std.debug.print("res: {any}\n", .{r});
    } else {
        std.debug.print("sadge\n", .{});
    }
}
