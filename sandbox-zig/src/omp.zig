const std = @import("std");

const omp = @cImport({
    @cInclude("omp.h");
});

const kmp = @import("kmp.zig");

pub const parallel_opts = struct {
    num_threads: c_int = -1,
};

pub fn parallel(f: anytype, args: anytype, opts: parallel_opts) void {
    var id = .{
        .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
        .psource = "parallel" ++ @typeName(@TypeOf(f)),
    };
    if (opts.num_threads != -1) {
        kmp.push_num_threads(&id, kmp.get_tid(), opts.num_threads);
    }

    kmp.fork_call(&id, 1, @ptrCast(&omp_ctx.make_outline(@TypeOf(args), f).outline), &args);
}

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

    pub fn single(this: *Self, f: anytype, args: anytype) void {
        const thread = this.global_tid;
        var single_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
            .psource = "single" ++ @typeName(@TypeOf(f)),
        };
        var barrier_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC) | @intFromEnum(kmp.flags.IDENT_BARRIER_IMPL_SINGLE),
            .psource = "single" ++ @typeName(@TypeOf(f)),
        };

        if (kmp.single(&single_id, thread) == 1) {
            f(args);
            kmp.end_single(&single_id, thread);
        }
        kmp.barrier(&barrier_id, thread);
    }

    pub fn master(this: *Self, f: anytype, args: anytype) void {
        const thread = this.global_tid;
        var master_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
            .psource = "master" ++ @typeName(@TypeOf(f)),
        };

        if (kmp.master(&master_id, thread) == 1) {
            f(args);
        }
    }
};

pub fn main() !void {
    parallel(tes2, .{ .string = "ghello" }, .{ .num_threads = 4 });
}

// pub fn tes(om: *omp_ctx, args: anytype) void {
//     om.master(tes2, args);
// }
//
pub fn tes2(om: *omp_ctx, args: anytype) void {
    _ = om;
    std.debug.print("its aliveeee {s}\n", .{args.string});
}
