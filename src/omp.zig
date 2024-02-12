const std = @import("std");

const omp = @cImport({
    @cInclude("omp.h");
});

const kmp = @import("kmp.zig");

pub const parallel_opts = struct {
    num_threads: ?c_int = undefined,
    condition: ?bool = undefined,
};

pub const parallel_for_opts = struct {
    sched: kmp.sched_t = kmp.sched_t.StaticNonChunked,
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

pub const omp_ctx = struct {
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

    pub fn parallel_for(this: *Self, f: anytype, args: anytype, lower: anytype, upper: anytype, increment: anytype, opts: parallel_for_opts) void {
        var id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC) | @intFromEnum(kmp.flags.IDENT_WORK_LOOP),
            .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
        };

        // TODO: Don't know what will happen with other schedules
        std.debug.assert(opts.sched == kmp.sched_t.StaticNonChunked);
        var sched: c_int = @intFromEnum(opts.sched);
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

        // TOOD: Figure out how to use all of these values
        var low: T = 0;
        var upp: T = @intFromFloat(std.math.ceil(@as(f32, @floatFromInt(upper - lower - 1)) / increment));
        var stri: T = 1;
        var incr: T = increment;
        var chunk: T = 1;

        kmp.for_static_init(T, &id, this.global_tid, sched, &last_iter, &low, &upp, &stri, incr, chunk);
        while (@atomicRmw(T, &low, .Add, incr, .AcqRel) <= upp) {
            f(this, args);
        }

        var id_fini = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC) | @intFromEnum(kmp.flags.IDENT_WORK_LOOP),
            .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
            .reserved_3 = 0x1b,
        };
        kmp.for_static_fini(&id_fini, this.global_tid);

        // Figure out a way to not use this when not needed
        kmp.barrier(&id, this.global_tid);
    }

    pub fn barrier(this: *Self) void {
        var id = .{
            .flags = @intFromEnum(kmp.flags.IDENT_KMPC) | @intFromEnum(kmp.flags.IDENT_WORK_LOOP),
            .psource = "barrier",
        };
        kmp.barrier(&id, this.global_tid);
    }

    pub fn critical(this: *Self, f: anytype, args: anytype) void {
        kmp.critical();
        f(this, args);
        kmp.critical_end();
    }
};
