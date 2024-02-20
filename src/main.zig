const omp = @import("omp.zig");
const std = @import("std");

test "main" {
    // const something = .{ 1, 2, "hello" };
    // const some_type_info = @typeInfo(@TypeOf(something));
    // if (some_type_info != .Struct) {
    //     std.debug.print("Expected struct, got {}\n", .{some_type_info});
    //     return 1;
    // }
    //
    // const new_args = .{1} ++ something;
    // std.debug.print("new_args: {any}\n", .{new_args});

    const res = try omp.parallel(tes, .{"gello"}, .{ .num_threads = 8 });
    if (res) |r| {
        std.debug.print("res: {any}\n", .{r});
    } else {
        std.debug.print("sadge\n", .{});
    }
}

pub fn tes(om: *omp.omp_ctx, str: []const u8) error{Unimplemented}!?u34 {
    om.task(tes2, .{str});

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
