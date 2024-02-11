const std = @import("std");

const omp = @cImport({
    @cInclude("omp.h");
});

const kmp = @import("kmp.zig");

pub const parallel_opts = struct {
    num_threads: ?c_int = undefined,
    condition: ?bool = undefined,
};

pub fn parallel(f: anytype, args: anytype, opts: parallel_opts) void {
    var id = .{
        .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
        .psource = "parallel" ++ @typeName(@TypeOf(f)),
    };
    if (opts.num_threads) |num| {
        kmp.push_num_threads(&id, kmp.get_tid(), num);
    }

    if (opts.condition) |cond| {
        kmp.fork_call_if(&id, 1, @ptrCast(&omp_ctx.make_outline(@TypeOf(args), f).outline), @intFromBool(cond), &args);
    } else {
        kmp.fork_call(&id, 1, @ptrCast(&omp_ctx.make_outline(@TypeOf(args), f).outline), &args);
    }
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
        var single_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
            .psource = "single" ++ @typeName(@TypeOf(f)),
        };
        var barrier_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC) | @intFromEnum(kmp.flags.IDENT_BARRIER_IMPL_SINGLE),
            .psource = "single" ++ @typeName(@TypeOf(f)),
        };

        if (kmp.single(&single_id, this.global_tid) == 1) {
            f(this, args);
            kmp.end_single(&single_id, this.global_tid);
        }
        kmp.barrier(&barrier_id, this.global_tid);
    }

    pub fn master(this: *Self, f: anytype, args: anytype) void {
        var master_id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC),
            .psource = "master" ++ @typeName(@TypeOf(f)),
        };

        if (kmp.master(&master_id, this.global_tid) == 1) {
            f(this, args);
        }
    }

    pub fn parallel_for(this: *Self, f: anytype, args: anytype, lower: anytype, upper: anytype, increment: anytype) void {
        var id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC) | @intFromEnum(kmp.flags.IDENT_WORK_LOOP),
            .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
        };

        var sched: c_int = @intFromEnum(kmp.sched_t.SCHEDULE_STATIC);
        var last_iter: c_int = 0;

        const T = comptime ret: {
            if (std.meta.trait.isSignedInt(@TypeOf(lower))) {
                if (@sizeOf(@TypeOf(lower)) <= 4) {
                    break :ret c_int;
                } else {
                    break :ret c_long;
                }
            } else if (std.meta.trait.isUnsignedInt(@TypeOf(lower))) {
                if (@sizeOf(@TypeOf(lower)) <= 4) {
                    break :ret c_uint;
                } else {
                    break :ret c_ulong;
                }
            } else {
                @panic("Tried to loop over a non-integer type.");
            }
        };

        var low: T = 0;
        var upp: T = @intFromFloat(std.math.ceil(@as(f32, @floatFromInt(upper - lower)) / increment));
        var stri: T = 1;
        var incr: T = 1;
        var chunk: T = 1;

        kmp.for_static_init(T, &id, this.global_tid, sched, &last_iter, &low, &upp, &stri, incr, chunk);
        // No do-while loops in Zig, so we have to do this. Sadge
        f(this, args);
        while (@atomicRmw(T, &low, .Add, incr, .Monotonic) < upp) {
            f(this, args);
        }
        kmp.for_static_fini(&id, this.global_tid);
    }
};

pub fn main() !void {
    parallel(tes, .{ .string = "gello" }, .{ .num_threads = 4 });
}

pub fn tes(om: *omp_ctx, args: anytype) void {
    om.parallel_for(tes2, args, 0, 13, 1);
}

var a: c_int = 0;

pub fn tes2(om: *omp_ctx, args: anytype) void {
    _ = args;
    _ = om;
    std.debug.print("its aliveeee {}\n", .{@atomicRmw(c_int, &a, .Add, 1, .Monotonic)});
}
