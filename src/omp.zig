const std = @import("std");
const kmp = @import("kmp.zig");

pub const parallel_opts = struct {
    num_threads: ?c_int = undefined,
    condition: ?bool = undefined,
};

pub const parallel_for_opts = struct {
    sched: kmp.sched_t = kmp.sched_t.StaticNonChunked,
};

pub fn parallel(comptime f: anytype, args: anytype, opts: parallel_opts) copy_ret(f) {
    const args_type_info = @typeInfo(@TypeOf(args));
    if (args_type_info != .Struct) {
        @compileError("Expected struct or tuple, got " ++ @typeName(@TypeOf(args)) ++ " instead.");
    }
    const f_type_info = @typeInfo(@TypeOf(f));
    if (f_type_info != .Fn) {
        @compileError("Expected function, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
    }
    if (f_type_info.Fn.params.len < 1 or f_type_info.Fn.params[0].type.? != *omp_ctx) {
        @compileError("Expected function with signature `fn(omp_ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
    }

    var id = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
        .psource = "parallel" ++ @typeName(@TypeOf(f)),
    };
    if (opts.num_threads) |num| {
        kmp.push_num_threads(&id, kmp.get_tid(), num);
    }

    const ret_type = struct {
        ret: copy_ret(f) = undefined,
        args: @TypeOf(args),
    };

    var ret: ret_type = .{ .args = args };

    if (opts.condition) |cond| {
        kmp.fork_call_if(&id, 1, @ptrCast(&omp_ctx.make_outline(@TypeOf(ret), copy_ret(f), f).outline), @intFromBool(cond), &ret);
    } else {
        kmp.fork_call(&id, 1, @ptrCast(&omp_ctx.make_outline(@TypeOf(ret), copy_ret(f), f).outline), &ret);
    }

    if (copy_ret(f) != void) {
        return ret.ret;
    }
}

inline fn copy_ret(comptime f: anytype) type {
    return @typeInfo(@TypeOf(f)).Fn.return_type orelse void;
}

inline fn call_fn(comptime f: anytype, args: anytype) copy_ret(f) {
    const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
    if (copy_ret(f) != void) {
        if (type_info == .ErrorUnion) {
            return try @call(.auto, f, args);
        } else {
            if (@call(.auto, f, args)) |ret| {
                return ret;
            }
        }
    } else {
        if (type_info == .ErrorSet) {
            try @call(.auto, f, args);
        } else {
            @call(.auto, f, args);
        }
    }
}

noinline fn call_fn_no_inline(comptime f: anytype, args: anytype) copy_ret(f) {
    const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
    if (copy_ret(f) != void) {
        if (type_info == .ErrorUnion) {
            return try @call(.auto, f, args);
        } else {
            if (@call(.auto, f, args)) |ret| {
                return ret;
            }
        }
    } else {
        if (type_info == .ErrorSet) {
            try @call(.auto, f, args);
        } else {
            @call(.auto, f, args);
        }
    }
}

pub const omp_ctx = struct {
    const Self = @This();

    global_tid: c_int,
    bound_tid: c_int,

    fn make_outline(comptime T: type, comptime R: type, comptime f: anytype) type {
        std.debug.assert(R == void or @typeInfo(R) == .Optional or @typeInfo(R) == .ErrorSet or @typeInfo(R) == .ErrorUnion);

        return opaque {
            fn outline(gtid: *c_int, btid: *c_int, argss: *T) callconv(.C) void {
                var this: Self = .{
                    .global_tid = gtid.*,
                    .bound_tid = btid.*,
                };
                var true_args = argss.args;

                argss.ret = call_fn(f, .{&this} ++ true_args) catch |err| err;
                return;
            }
        };
    }

    pub fn single(this: *Self, f: anytype, args: anytype) copy_ret(f) {
        const args_type_info = @typeInfo(@TypeOf(args));
        if (args_type_info != .Struct) {
            @compileError("Expected struct or tuple, got " ++ @typeName(@TypeOf(args)) ++ " instead.");
        }

        const f_type_info = @typeInfo(@TypeOf(f));
        if (f_type_info != .Fn) {
            @compileError("Expected function, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }
        if (f_type_info.Fn.params.len < 1 or f_type_info.Fn.params[0].type.? != *omp_ctx) {
            @compileError("Expected function with signature `fn(omp_ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }

        const single_id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
            .psource = "single" ++ @typeName(@TypeOf(f)),
        };
        const barrier_id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_BARRIER_IMPL_SINGLE),
            .psource = "single" ++ @typeName(@TypeOf(f)),
        };

        if (kmp.single(&single_id, this.global_tid) == 1) {
            try call_fn(f, .{this} ++ args);
            kmp.end_single(&single_id, this.global_tid);
        }
        kmp.barrier(&barrier_id, this.global_tid);

        if (copy_ret(f) != void) {
            return undefined;
        }
    }

    pub fn master(this: *Self, f: anytype, args: anytype) copy_ret(f) {
        const args_type_info = @typeInfo(@TypeOf(args));
        if (args_type_info != .Struct) {
            @compileError("Expected struct or tuple, got " ++ @typeName(@TypeOf(args)) ++ " instead.");
        }

        const f_type_info = @typeInfo(@TypeOf(f));
        if (f_type_info != .Fn) {
            @compileError("Expected function, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }
        if (f_type_info.Fn.params.len < 1 or f_type_info.Fn.params[0].type.? != *omp_ctx) {
            @compileError("Expected function with signature `fn(omp_ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }

        const master_id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
            .psource = "master" ++ @typeName(@TypeOf(f)),
        };

        if (kmp.master(&master_id, this.global_tid) == 1) {
            try call_fn(f, .{this} ++ args);
        }

        if (copy_ret(f) != void) {
            return undefined;
        }
    }

    pub fn parallel_for(this: *Self, f: anytype, args: anytype, lower: anytype, upper: anytype, increment: anytype, opts: parallel_for_opts) copy_ret(f) {
        const args_type_info = @typeInfo(@TypeOf(args));
        if (args_type_info != .Struct) {
            @compileError("Expected struct or tuple, got " ++ @typeName(@TypeOf(args)) ++ " instead.");
        }

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
                @compileError("Tried to loop over a non-integer type " ++ @typeName(@TypeOf(lower)));
            }
        };

        const f_type_info = @typeInfo(@TypeOf(f));
        if (f_type_info != .Fn) {
            @compileError("Expected function, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }
        if (f_type_info.Fn.params.len < 2 or f_type_info.Fn.params[0].type.? != *omp_ctx or f_type_info.Fn.params[1].type.? != @TypeOf(T)) {
            @compileError("Expected function with signature `fn(omp_ctx, numeric, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }

        var id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
            .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
        };

        // TODO: Don't know what will happen with other schedules
        std.debug.assert(opts.sched == kmp.sched_t.StaticNonChunked);
        var sched: c_int = @intFromEnum(opts.sched);
        var last_iter: c_int = 0;

        // TOOD: Figure out how to use all of these values
        var low: T = 0;
        var upp: T = @intFromFloat(std.math.ceil(@as(f32, @floatFromInt(upper - lower - 1)) / increment));
        var stri: T = 1;
        var incr: T = increment;
        var chunk: T = 1;

        kmp.for_static_init(T, &id, this.global_tid, sched, &last_iter, &low, &upp, &stri, incr, chunk);

        while (@atomicRmw(T, &low, .Add, incr, .AcqRel) <= upp) {
            try call_fn(f, .{ this, upp } ++ args);
        }

        const id_fini = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
            .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
            .reserved_3 = 0x1b,
        };
        kmp.for_static_fini(&id_fini, this.global_tid);

        // Figure out a way to not use this when not needed
        kmp.barrier(&id, this.global_tid);

        if (copy_ret(f) != void) {
            return undefined;
        }
    }

    pub fn barrier(this: *Self) void {
        const id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
            .psource = "barrier",
        };
        kmp.barrier(&id, this.global_tid);
    }

    pub fn critical(this: *Self, f: anytype, args: anytype) copy_ret(f) {
        kmp.critical();

        try call_fn(f, .{this} ++ args);
        kmp.critical_end();

        if (copy_ret(f) != void) {
            return undefined;
        }
    }

    fn outline(comptime f: anytype, comptime ret_type: type) type {
        return opaque {
            // This comes from decompiling the outline with ghidra
            // It should never really change since it's just a wrapper around the actual function
            // and it can't inline anything even if it wanted to
            //
            // remember to update the size_in_release_debug if the function changes, can't really enforce it though
            const size_in_release_debug = 42;
            fn task(gtid: c_int, pass: *ret_type) callconv(.C) c_int {
                _ = gtid;

                pass.ret = call_fn_no_inline(f, pass.args);
                return 0;
            }
        };
    }

    pub fn task(this: *Self, f: anytype, args: anytype) copy_ret(f) {
        var id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
            .psource = "task" ++ @typeName(@TypeOf(f)),
        };

        const f_type_info = @typeInfo(@TypeOf(f));
        if (f_type_info != .Fn) {
            @compileError("Expected function, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }
        if (f_type_info.Fn.params.len < 1 or f_type_info.Fn.params[0].type.? != *omp_ctx) {
            @compileError("Expected function with signature `fn(omp_ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
        }

        const new_args = .{this} ++ args;
        const ret_type = struct {
            ret: copy_ret(f) = undefined,
            args: @TypeOf(new_args),
        };
        const ret: ret_type = .{ .ret = undefined, .args = new_args };
        const task_outline = outline(f, ret_type);

        var t = kmp.task_alloc(&id, this.global_tid, .{ .tiedness = 1 }, task_outline.size_in_release_debug, 0, task_outline.task);
        t.shareds = @constCast(@ptrCast(&ret));
        _ = kmp.task(&id, this.global_tid, t);

        if (copy_ret(f) != void) {
            return ret.ret;
        }
    }

    pub fn taskyeild(this: *Self) void {
        const id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
            .psource = "taskyeild",
        };
        kmp.taskyield(&id, this.global_tid);
    }
};
