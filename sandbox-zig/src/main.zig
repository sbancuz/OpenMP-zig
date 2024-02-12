const omp = @import("omp.zig");
const std = @import("std");

test "main" {
    omp.parallel(tes, .{ .string = "gello" }, .{ .num_threads = 8 });
}

pub fn tes(om: *omp.omp_ctx, args: anytype) void {
    om.parallel_for(tes2, args, 0, 4, 2, .{});
}

var a: c_int = 0;

pub fn tes2(om: *omp.omp_ctx, args: anytype) void {
    _ = args;
    om.critical(test3, .{});
    std.debug.print("its aliveeee {}\n", .{a});
}

pub fn test3(om: *omp.omp_ctx, args: anytype) void {
    _ = args;
    _ = om;
    a += 1;
}
