const omp = @import("omp.zig");
const std = @import("std");

test "main" {
    var foo: u8 = 1;
    _ = foo;
    const res = try omp.parallel(tes, .{ .shareds = .{"hallow"}, .privates = .{1} }, .{ .num_threads = 8 });
    if (res) |r| {
        std.debug.print("res: {any}\n", .{r});
    } else {
        std.debug.print("sadge\n", .{});
    }
}

pub fn tes(om: *omp.omp_ctx, str: []const u8, str2: u32) error{Unimplemented}!?u34 {
    _ = str;
    _ = om;
    // str2.* += 1;
    std.debug.print("its aliveeee {} {}\n", .{ str2, str2 });

    return 1;
}

var a: c_int = 0;

pub fn tes2(om: *omp.omp_ctx, str: []const u8) void {
    _ = om;
    std.debug.print("its aliveeee {s} \n", .{str});
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
