const std = @import("std");

const omp = @cImport({
    @cInclude("omp.h");
});

const kmp = @import("kmp.zig");

const omp_ctx = struct {
    const Self = @This();

    global_tid: c_int,
    bound_tid: c_int,

    fn make_outline(comptime T: type, comptime f: fn (*omp_ctx, anytype) void) type {
        return opaque {
            fn outline(gtid: *c_int, btid: *c_int, argss: *T) callconv(.C) void {
                var this: Self = .{
                    .global_tid = gtid.*,
                    .bound_tid = btid.*,
                };

                f(&this, argss);
            }
        };
    }

    pub fn parallel(f: anytype, args: anytype) void {
        var id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
            .psource = "parallel",
        };

        kmp.fork_call(&id, 1, @ptrCast(&omp_ctx.make_outline(@TypeOf(args), f).outline), &args);
    }

    pub fn single(this: *Self, f: anytype, args: anytype) void {
        const thread = this.global_tid;
        var single_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
            .psource = "single",
        };
        var barrier_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC) | @intFromEnum(kmp.flags.IDENT_BARRIER_IMPL_SINGLE),
            .psource = "single",
        };

        if (kmp.single(&single_id, thread) == 1) {
            f(args);
            kmp.end_single(&single_id, thread);
        }
        kmp.barrier(&barrier_id, thread);
    }
};

pub fn main() !void {
    omp_ctx.parallel(tes, .{ .string = "ghello" });
}

pub fn tes(om: *omp_ctx, args: anytype) void {
    om.single(tes2, args);
}

pub fn tes2(args: anytype) void {
    std.debug.print("its aliveeee {s}\n", .{args.string});
}
