const std = @import("std");
const kmp = @import("kmp.zig");
const c = @cImport({
    @cInclude("omp.h");
    @cInclude("omp-tools.h");
});

const in = @import("input_handler.zig");
pub const proc_bind = enum(c_int) {
    default = 1,
    master = 2,
    close = 3,
    spread = 4,
    primary = 5,
};

pub const schedule = enum(c_long) {
    static = 1,
    dynamic = 2,
    guided = 3,
    auto = 4,
    monotonic = 0x80000000,
};

pub const reduction_operators = kmp.reduction_operators;
pub const parallel_opts = struct {
    iff: bool = false,
    proc_bind: proc_bind = .default,
    ex: union {
        reduction: []const reduction_operators,
        loop_opts: parallel_for_opts,
    } = .{ .reduction = &[0]reduction_operators{} },
};

pub const parallel_for_opts = struct {
    idx: type,
    sched: schedule = .static,
    chunk_size: c_int = 1,
    ordered: bool = false,
    reduction: []const reduction_operators = &[0]reduction_operators{},
    nowait: bool = false,
};
pub const ctx = struct {
    global_tid: c_int,
    bound_tid: c_int,
};

pub const critical_options = struct {
    sync: sync_hint_t = .none,
    name: []const u8 = "",
};

threadlocal var global_ctx: ctx = undefined;

pub fn parallel(comptime opts: parallel_opts) type {
    const common = struct {
        const pri_loop = loop(.{
            .idx = opts.ex.loop_opts.idx,
            .sched = opts.ex.loop_opts.sched,
            .chunk_size = opts.ex.loop_opts.chunk_size,
            .reduction = opts.ex.loop_opts.reduction,
            .ordered = opts.ex.loop_opts.ordered,
            .nowait = true,
        });

        inline fn make_args(
            args: anytype,
            comptime f: anytype,
        ) in.zigc_ret(f, @TypeOf(in.normalize_args(args))) {
            in.check_fn_signature(f);

            return .{ .v = in.normalize_args(args) };
        }

        inline fn make_proc_bind(
            id: *const kmp.ident_t,
            comptime bind: proc_bind,
        ) void {
            if (bind != .default) {
                kmp.push_proc_bind(id, kmp.get_tid(), bind);
            }
        }

        inline fn parallel_impl(
            args: anytype,
            comptime f: anytype,
            comptime has_cond: bool,
            cond: bool,
        ) in.copy_ret(f) {
            in.check_fn_signature(f);

            const ret = make_args(args, f);
            const id: kmp.ident_t = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "parallel" ++ @typeName(@TypeOf(f)),
            };
            make_proc_bind(&id, opts.proc_bind);
            const outline = parallel_outline(f, @TypeOf(ret), opts).outline;

            if (has_cond) {
                kmp.fork_call_if(&id, 1, @ptrCast(&outline), @intFromBool(cond), &ret);
            } else {
                kmp.fork_call(&id, 1, @ptrCast(&outline), &ret);
            }

            return ret.ret;
        }

        inline fn parallel_loop_impl(
            lower: opts.ex.loop_opts.idx,
            upper: opts.ex.loop_opts.idx,
            increment: opts.ex.loop_opts.idx,
            args: anytype,
            comptime f: anytype,
            comptime has_cond: bool,
            cond: bool,
        ) in.copy_ret(f) {
            in.check_fn_signature(f);

            const ret_t = struct {
                ret: in.copy_ret(f) = undefined,
                v: @TypeOf(args),
                lower: opts.ex.loop_opts.idx,
                upper: opts.ex.loop_opts.idx,
                increment: opts.ex.loop_opts.idx,
            };
            const ret: ret_t = .{ .ret = undefined, .v = args, .lower = lower, .upper = upper, .increment = increment };

            const id: kmp.ident_t = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "parallel" ++ @typeName(@TypeOf(f)),
            };
            make_proc_bind(&id, opts.proc_bind);
            const outline = parallel_outline(f, @TypeOf(ret), opts).loop_outline;
            if (has_cond) {
                kmp.fork_call_if(&id, 1, @ptrCast(&outline), @intFromBool(cond), &ret);
            } else {
                kmp.fork_call(&id, 1, @ptrCast(&outline), &ret);
            }
            return ret.ret;
        }

        inline fn parallel_outline(
            comptime f: anytype,
            comptime R: type,
            comptime in_opts: parallel_opts,
        ) type {
            const static = struct {
                var lck: kmp.critical_name_t = @bitCast([_]u8{0} ** 32);
            };

            return opaque {
                fn outline(
                    gtid: *c_int,
                    btid: *c_int,
                    args: *R,
                ) callconv(.C) void {
                    global_ctx = .{
                        .global_tid = gtid.*,
                        .bound_tid = btid.*,
                    };

                    var private_copy = in.deep_copy(args.v.private);
                    var reduction_copy = in.deep_copy(args.v.reduction);
                    const true_args = args.v.shared ++ private_copy ++ reduction_copy;

                    if (@typeInfo(in.copy_ret(f)) == .ErrorUnion) {
                        args.ret = @call(.always_inline, f, true_args) catch |err| err;
                    } else {
                        args.ret = @call(.always_inline, f, true_args);
                    }

                    if (opts.ex.reduction.len > 0) {
                        const id: kmp.ident_t = .{
                            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                            .psource = "parallel" ++ @typeName(@TypeOf(f)),
                        };
                        reduce(&id, true, args.v.reduction, reduction_copy, in_opts.ex.reduction, &static.lck);
                    }

                    return;
                }

                fn loop_outline(
                    gtid: *c_int,
                    btid: *c_int,
                    args: *R,
                ) callconv(.C) void {
                    global_ctx = .{
                        .global_tid = gtid.*,
                        .bound_tid = btid.*,
                    };

                    const new_opts = .{
                        .idx = in_opts.ex.loop_opts.idx,
                        .sched = in_opts.ex.loop_opts.sched,
                        .chunk_size = in_opts.ex.loop_opts.chunk_size,
                        .ordered = in_opts.ex.loop_opts.ordered,
                        .reduction = in_opts.ex.loop_opts.reduction,
                        .nowait = true,
                    };
                    _ = new_opts;

                    if (@typeInfo(in.copy_ret(f)) == .ErrorUnion) {
                        // TODO: Figure out how to handle this
                        _ = pri_loop.run(args.lower, args.upper, args.increment, args.v, f) catch |err| err;
                    } else {
                        pri_loop.run(args.lower, args.upper, args.increment, args.v, f);
                    }

                    return;
                }
            };
        }
    };
    if (opts.iff) {
        return struct {
            pub inline fn run(
                cond: bool,
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                return common.parallel_impl(args, f, true, cond);
            }

            pub inline fn run_loop(
                cond: bool,
                lower: opts.ex.loop_opts.idx,
                upper: opts.ex.loop_opts.idx,
                increment: opts.ex.loop_opts.idx,
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                return common.parallel_loop_impl(lower, upper, increment, args, f, true, cond);
            }
        };
    } else {
        return struct {
            pub inline fn run(
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                return common.parallel_impl(args, f, false, false);
            }

            pub inline fn run_loop(
                lower: opts.ex.loop_opts.idx,
                upper: opts.ex.loop_opts.idx,
                increment: opts.ex.loop_opts.idx,
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                return common.parallel_loop_impl(lower, upper, increment, args, f, false, false);
            }
        };
    }
}

inline fn reduce(
    comptime id: *const kmp.ident_t,
    comptime nowait: bool,
    out_reduction: anytype,
    copies: @TypeOf(out_reduction),
    comptime operators: []const kmp.reduction_operators,
    lck: *kmp.critical_name_t,
) void {
    const res = if (nowait)
        kmp.reduce_nowait(@typeInfo(@TypeOf(out_reduction)).Struct.fields, id, global_ctx.global_tid, copies.len, @sizeOf(@TypeOf(out_reduction)), @ptrCast(@constCast(&copies)), operators, lck)
    else
        kmp.reduce(@typeInfo(@TypeOf(out_reduction)).Struct.fields, id, global_ctx.global_tid, copies.len, @sizeOf(@TypeOf(out_reduction)), @ptrCast(@constCast(&copies)), operators, lck);

    switch (res) {
        1 => {
            kmp.create_reduce(@typeInfo(@TypeOf(out_reduction)).Struct.fields, operators).finalize(out_reduction, copies);
            const end_id = comptime .{
                .flags = id.*.flags,
                .psource = id.*.psource,
                .reserved_3 = 0x1b,
            };
            kmp.end_reduce_nowait(&end_id, global_ctx.global_tid, lck);
        },
        2 => {
            kmp.create_reduce(@typeInfo(@TypeOf(out_reduction)).Struct.fields, operators).finalize_atomic(out_reduction, copies);
            return;
        },
        else => return,
    }
}

pub inline fn loop(
    comptime opts: parallel_for_opts,
) type {
    const static = struct {
        var lck: kmp.critical_name_t = @bitCast([_]u8{0} ** 32);
    };
    const common = struct {
        pub fn to_kmp_sched(comptime sched: schedule) kmp.sched_t {
            switch (sched) {
                .static => return if (opts.chunk_size > 1) kmp.sched_t.StaticChunked else kmp.sched_t.StaticNonChunked,
                .dynamic => return kmp.sched_t.Dynamic,
                .guided => return kmp.sched_t.Guided,
                .auto => return kmp.sched_t.Runtime,
                else => unreachable,
            }
        }
    };

    if (!std.meta.trait.isSignedInt(opts.idx) and !std.meta.trait.isUnsignedInt(opts.idx)) {
        @compileError("Tried to loop over a comptime/non-integer type " ++ @typeName(opts.idx));
    }
    if (!opts.ordered and opts.sched == .static) {
        return struct {
            pub inline fn run(
                lower: opts.idx,
                upper: opts.idx,
                increment: opts.idx,
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                in.check_args(@TypeOf(args));

                const splat = in.normalize_args(args);
                var private_copy = in.deep_copy(splat.private);
                var reduction_copy = in.deep_copy(splat.reduction);
                const true_args = splat.shared ++ private_copy ++ reduction_copy;

                in.check_fn_signature(f);

                const f_type_info = @typeInfo(@TypeOf(f));
                if (f_type_info.Fn.params.len < 1) {
                    @compileError("Expected function with signature `inline fn(numeric, ...)`" ++ @typeName(@TypeOf(f)) ++ " instead.\n" ++ @typeName(opts.idx) ++ " may be different from the expected type: " ++ @typeName(f_type_info.Fn.params[1].type.?));
                }

                const id = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                    .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
                };

                // This is `1` iside the last thread execution
                var last_iter: c_int = 0;
                var low: opts.idx = lower;
                var upp: opts.idx = upper - 1;
                var stri: opts.idx = 1;
                const incr: opts.idx = increment;

                kmp.for_static_init(opts.idx, &id, global_ctx.global_tid, common.to_kmp_sched(opts.sched), &last_iter, &low, &upp, &stri, incr, opts.chunk_size);

                const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
                if (opts.chunk_size > 1) {
                    while (low + opts.chunk_size < upper) : (low += stri) {
                        inline for (0..opts.chunk_size) |i| {
                            if (type_info == .ErrorUnion) {
                                _ = @call(.always_inline, f, .{low + @as(opts.idx, i)} ++ true_args) catch |err| err;
                            } else {
                                _ = @call(.always_inline, f, .{low + @as(opts.idx, i)} ++ true_args);
                            }
                        }
                    }
                    while (low < upper) : (low += incr) {
                        if (type_info == .ErrorUnion) {
                            _ = @call(.always_inline, f, .{low} ++ true_args) catch |err| err;
                        } else {
                            _ = @call(.always_inline, f, .{low} ++ true_args);
                        }
                    }
                } else {
                    var i: opts.idx = low;
                    while (i <= upp) : (i += incr) {
                        if (type_info == .ErrorUnion) {
                            _ = @call(.always_inline, f, .{i} ++ true_args) catch |err| err;
                        } else {
                            _ = @call(.always_inline, f, .{i} ++ true_args);
                        }
                    }
                }

                const id_fini = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                    .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
                    .reserved_3 = 0x1b,
                };
                kmp.for_static_fini(&id_fini, global_ctx.global_tid);

                // TODO: Figure out a way to remove this when not needed, somehow there is a race condition even though it compiles to the same code as the llvm implementation
                // if (!opts.nowait) {
                // barrier();
                // }

                if (opts.reduction.len > 0) {
                    const redid: kmp.ident_t = comptime .{
                        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | if (opts.nowait) @intFromEnum(kmp.ident_flags.IDENT_ATOMIC_REDUCE) else 0,
                        .psource = id_fini.psource,
                    };
                    reduce(&redid, opts.nowait, splat.reduction, reduction_copy, opts.reduction, &static.lck);
                }

                return undefined;
            }
        };
    } else {
        return struct {
            pub inline fn run(
                lower: opts.idx,
                upper: opts.idx,
                increment: opts.idx,
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                in.check_args(@TypeOf(args));

                const splat = in.normalize_args(args);
                var private_copy = in.deep_copy(splat.private);
                var reduction_copy = in.deep_copy(splat.reduction);
                const true_args = splat.shared ++ private_copy ++ reduction_copy;

                in.check_fn_signature(f);

                const f_type_info = @typeInfo(@TypeOf(f));
                if (f_type_info.Fn.params.len < 1) {
                    @compileError("Expected function with signature `inline fn(numeric, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.\n" ++ @typeName(opts.idx) ++ " may be different from the expected type: " ++ @typeName(f_type_info.Fn.params[1].type.?));
                }

                const id = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                    .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
                };

                // This is `1` iside the last thread execution
                var last_iter: c_int = 0;
                var low: opts.idx = lower;
                var upp: opts.idx = upper - 1;
                var stri: opts.idx = 1;
                var incr: opts.idx = increment;
                kmp.dispatch_init(opts.idx, &id, global_ctx.global_tid, common.to_kmp_sched(opts.sched), low, upp, incr, opts.chunk_size);

                const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
                while (kmp.dispatch_next(opts.idx, &id, global_ctx.global_tid, &last_iter, &low, &upp, &stri) == 1) {
                    defer kmp.dispatch_fini(opts.idx, &id, global_ctx.global_tid);

                    var i: opts.idx = low;
                    while (i <= upp) : (i += incr) {
                        if (type_info == .ErrorUnion) {
                            _ = @call(.always_inline, f, .{i} ++ true_args) catch |err| err;
                        } else {
                            _ = @call(.always_inline, f, .{i} ++ true_args);
                        }
                    }
                }

                if (!opts.nowait) {
                    barrier();
                }

                if (opts.reduction.len > 0) {
                    const redid: kmp.ident_t = comptime .{
                        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | if (opts.nowait) @intFromEnum(kmp.ident_flags.IDENT_ATOMIC_REDUCE) else 0,
                        .psource = "parallel_for_red" ++ @typeName(@TypeOf(f)),
                    };
                    reduce(&redid, opts.nowait, splat.reduction, reduction_copy, opts.reduction, &static.lck);
                }

                return undefined;
            }
        };
    }
}

pub inline fn barrier() void {
    const id: kmp.ident_t = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
        .psource = "barrier",
    };
    kmp.barrier(&id, global_ctx.global_tid);
}

pub inline fn critical(
    comptime opts: critical_options,
) type {
    return struct {
        pub inline fn run(
            args: anytype,
            comptime f: anytype,
        ) in.copy_ret(f) {
            in.check_args(@TypeOf(args));
            in.check_fn_signature(f);

            const id: kmp.ident_t = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                .psource = "barrier",
            };

            const static = struct {
                var lock: kmp.critical_name_t = @bitCast([_]u8{0} ** 32);
            };

            kmp.critical(&id, global_ctx.global_tid, &static.lock, @intFromEnum(opts.sync));
            defer {
                kmp.critical_end(&id, global_ctx.global_tid, &static.lock);
            }

            const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
            const ret = ret: {
                if (type_info == .ErrorUnion) {
                    break :ret try @call(.always_inline, f, args);
                } else {
                    break :ret @call(.always_inline, f, args);
                }
            };

            return ret;
        }
    };
}

pub inline fn single() type {
    return struct {
        pub inline fn run(
            args: anytype,
            comptime f: anytype,
        ) in.copy_ret(f) {
            in.check_args(@TypeOf(args));
            in.check_fn_signature(f);

            const single_id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "single" ++ @typeName(@TypeOf(f)),
            };
            const barrier_id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_BARRIER_IMPL_SINGLE),
                .psource = "single" ++ @typeName(@TypeOf(f)),
            };

            const res = undefined;
            if (kmp.single(&single_id, global_ctx.global_tid) == 1) {
                const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);

                if (type_info == .ErrorUnion) {
                    res = try @call(.always_inline, f, args);
                } else {
                    res = @call(.always_inline, f, args);
                }

                kmp.end_single(&single_id, global_ctx.global_tid);
            }
            kmp.barrier(&barrier_id, global_ctx.global_tid);

            return res;
        }
    };
}

pub inline fn master() type {
    return struct {
        pub inline fn run(
            args: anytype,
            comptime f: anytype,
        ) in.copy_ret(f) {
            return masked.run(only_master, args, f);
        }
    };
}

pub const only_master: c_int = 0;
pub inline fn masked() type {
    return struct {
        pub inline fn run(
            filter: i32,
            args: anytype,
            comptime f: anytype,
        ) in.copy_ret(f) {
            in.check_args(@TypeOf(args));
            in.check_fn_signature(f);

            const masked_id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "masked" ++ @typeName(@TypeOf(f)),
            };

            if (kmp.masked(&masked_id, global_ctx.global_tid, filter) == 1) {
                const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
                if (type_info == .ErrorUnion) {
                    return try @call(.always_inline, f, args);
                } else {
                    return @call(.always_inline, f, args);
                }
            }
        }
    };
}

pub inline fn task(
    args: anytype,
    comptime f: anytype,
) in.copy_ret(f) {
    const id = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
        .psource = "task" ++ @typeName(@TypeOf(f)),
    };

    in.check_args(@TypeOf(args));
    in.check_fn_signature(f);

    const ret_type = struct {
        ret: in.copy_ret(f) = undefined,
        args: @TypeOf(args),
    };
    const ret: ret_type = .{ .ret = undefined, .args = args };
    const outline = kmp.task_outline(f, ret_type);

    var t = kmp.task_alloc(&id, global_ctx.global_tid, .{ .tiedness = 1 }, outline.size_in_release_debug, 0, outline.task);
    t.shared = @constCast(@ptrCast(&ret));
    _ = kmp.task(&id, global_ctx.global_tid, t);

    return ret.ret;
}

pub inline fn taskyeild() void {
    const id = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
        .psource = "taskyeild",
    };
    kmp.taskyield(&id, global_ctx.global_tid);
}

////////////////////////////////////////////////////////////////////////////////////
/// Runtime API ////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////

/// Setters
pub inline fn set_num_threads(num_threads: u32) void {
    c.omp_set_num_threads(@intCast(num_threads));
}

pub inline fn set_dynamic(dynamic_threads: bool) void {
    c.omp_set_dynamic(@intFromBool(dynamic_threads));
}

pub inline fn set_nested(nested: bool) void {
    c.omp_set_nested(@intFromBool(nested));
}

pub inline fn set_max_active_levels(max_levels: u32) void {
    c.omp_set_max_active_levels(@intCast(max_levels));
}

extern "c" fn omp_set_schedule(kind: schedule, chunk_size: c_int) void;
pub inline fn set_schedule(kind: schedule, chunk_size: u32) void {
    c.omp_set_schedule(kind, chunk_size);
}

/// Getters
pub inline fn get_num_threads() u32 {
    return @intCast(c.omp_get_num_threads());
}

pub inline fn get_dynamic() bool {
    return c.omp_get_dynamic();
}

pub inline fn get_nested() bool {
    return c.omp_get_nested();
}

pub inline fn get_max_threads() u32 {
    return @intCast(c.omp_get_max_threads());
}

pub inline fn get_thread_num() u32 {
    return @intCast(c.omp_get_thread_num());
}

pub inline fn get_num_procs() u32 {
    return @intCast(c.omp_get_num_procs());
}

pub inline fn in_parallel() bool {
    return c.omp_in_parallel();
}

pub inline fn in_final() bool {
    return c.omp_in_final();
}

pub inline fn get_active_level() u32 {
    return @intCast(c.omp_get_active_level());
}

pub inline fn get_level() u32 {
    return @intCast(c.omp_get_level());
}

pub inline fn get_ancestor_thread_num(level: u32) u32 {
    return @intCast(c.omp_get_ancestor_thread_num(@intCast(level)));
}

pub inline fn get_team_size(level: u32) u32 {
    return @intCast(c.omp_get_team_size(@intCast(level)));
}

pub inline fn get_thread_limit() u32 {
    return @intCast(c.omp_get_thread_limit());
}

pub inline fn get_max_active_levels() u32 {
    return @intCast(c.omp_get_max_active_levels());
}
pub inline fn get_schedule(kind: *schedule, chunk_size: *u32) void {
    c.omp_get_schedule(kind, @intCast(chunk_size));
}

pub inline fn get_max_task_priority() u32 {
    return @intCast(c.omp_get_max_task_priority());
}

/// Locks
///     OpenMP 5.0  Synchronization hints
pub const sync_hint_t = enum(c_int) {
    none = 0,
    uncontended = 1,
    contended = 1 << 1,
    nonspeculative = 1 << 2,
    speculative = 1 << 3,
    hle = 1 << 16,
    rtm = 1 << 17,
    adaptive = 1 << 18,
};

/// lock hint type for dynamic user lock
pub const lock_hint_t = sync_hint_t;
const lock_t = extern struct {
    _lk: *anyopaque,
};

pub const lock = struct {
    const Self = @This();
    _lk: lock_t,

    pub inline fn init(this: *Self) void {
        c.omp_init_lock(this._lk);
    }

    pub inline fn set(this: *Self) void {
        c.omp_set_lock(this._lk);
    }

    pub inline fn unset(this: *Self) void {
        c.omp_unset_lock(this._lk);
    }

    pub inline fn destroy(this: *Self) void {
        c.omp_destroy_lock(this._lk);
    }

    pub inline fn test_(this: *Self) bool {
        return c.omp_test_lock(this._lk) != 0;
    }
};

const nest_lock_t = extern struct {
    _lk: *anyopaque,
};

pub const nest_lock = struct {
    const Self = @This();
    _lk: nest_lock_t,

    pub inline fn init(this: *Self) void {
        c.omp_init_nest_lock(this._lk);
    }

    pub inline fn set(this: *Self) void {
        c.omp_set_nest_lock(this._lk);
    }

    pub inline fn unset(this: *Self) void {
        c.omp_unset_nest_lock(this._lk);
    }

    pub inline fn destroy(this: *Self) void {
        c.omp_destroy_nest_lock(this._lk);
    }

    pub inline fn test_(this: *Self) bool {
        return c.omp_test_nest_lock(this._lk) != 0;
    }
};

/// time API functions
pub inline fn get_wtime() f64 {
    return c.omp_get_wtime();
}

pub inline fn get_wtick() f64 {
    return c.omp_get_wtick();
}

/// OpenMP 4.0
pub inline fn get_default_device() u32 {
    return @intCast(c.omp_get_default_device());
}

pub inline fn set_default_device(device: u32) void {
    c.omp_set_default_device(@intCast(device));
}

pub inline fn is_initial_device() bool {
    return c.omp_is_initial_device();
}

pub inline fn get_num_devices() u32 {
    return @intCast(c.omp_get_num_devices());
}

pub inline fn get_num_teams() u32 {
    return @intCast(c.omp_get_num_teams());
}

pub inline fn get_team_num() u32 {
    return @intCast(c.omp_get_team_num());
}

pub inline fn get_cancellation() bool {
    return c.omp_get_cancellation();
}

//     /* OpenMP 4.5 */
pub inline fn get_initial_device() u32 {
    return @intCast(c.omp_get_initial_device());
}

inline fn target_alloc(size: usize, device_num: u32) *u8 {
    return c.omp_target_alloc(size, @intCast(device_num));
}

inline fn target_free(ptr: *anyopaque, device_num: u32) void {
    c.omp_target_free(ptr, @intCast(device_num));
}

inline fn target_is_present(ptr: *anyopaque, device_num: u32) bool {
    return c.omp_target_is_present(ptr, @intCast(device_num)) != 0;
}

inline fn target_memcpy(dst: *u8, src: *const u8, length: usize, dst_offset: usize, src_offset: usize, device_num: u32) void {
    c.omp_target_memcpy(dst, src, length, dst_offset, src_offset, @intCast(device_num));
}

inline fn target_memcpy_rect(
    dst: *u8,
    src: *const u8,
    element_size: usize,
    num_dims: c_int,
    volume: *usize,
    dst_offsets: *usize,
    src_offsets: *usize,
    dst_dimensions: *usize,
    src_dimensions: *usize,
    dst_device_num: u32,
    src_device_num: u32,
) void {
    c.omp_target_memcpy_rect(
        dst,
        src,
        element_size,
        num_dims,
        volume,
        dst_offsets,
        src_offsets,
        dst_dimensions,
        src_dimensions,
        @intCast(dst_device_num),
        @intCast(src_device_num),
    );
}

inline fn target_associate_ptr(host_ptr: *const anyopaque, device_ptr: *const anyopaque, size: usize, device_num: u32) void {
    c.omp_target_associate_ptr(host_ptr, device_ptr, size, @intCast(device_num));
}

inline fn target_disassociate_ptr(ptr: *const anyopaque, device_num: u32) void {
    c.omp_target_disassociate_ptr(ptr, @intCast(device_num));
}

///     OpenMP 5.0
pub inline fn get_device_num() u32 {
    return @intCast(c.omp_get_device_num());
}

///     typedef void * omp_depend_t;
pub const depend_t = *anyopaque;

///     OpenMP 5.1 interop
// TODO: Maybe `usize` is better here, but intptr_t is supposed to be an int
pub const intptr_t = isize;
/// 0..omp_get_num_interop_properties()-1 are reserved for implementation-defined properties
pub const interop_property_t = enum(c_int) {
    fr_id = -1,
    fr_name = -2,
    vendor = -3,
    vendor_name = -4,
    device_num = -5,
    platform = -6,
    device = -7,
    device_context = -8,
    targetsync = -9,
    first = -9,
};

pub const interop_rc_t = enum(c_int) {
    no_value = 1,
    success = 0,
    empty = -1,
    out_of_range = -2,
    type_int = -3,
    type_ptr = -4,
    type_str = -5,
    other = -6,
};

pub const interop_fr = enum(c_int) {
    cuda = 1,
    cuda_driver = 2,
    opencl = 3,
    sycl = 4,
    hip = 5,
    level_zero = 6,
    last = 7,
};

pub const interop = *opaque {
    const Self = @This();

    /// None is defined as '&0' in the C API
    inline fn init() Self {
        return @bitCast(0);
    }

    ///
    /// The `omp_get_num_interop_properties` routine retrieves the number of implementation-defined properties available for an `omp_interop_t` object
    ///
    inline fn get_num_interop_properties(this: Self) interop_property_t {
        return @enumFromInt(c.omp_get_num_interop_properties(this));
    }

    ///
    /// The `omp_get_interop_int` routine retrieves an integer property from an `omp_interop_t` object.
    ///
    inline fn get_int(this: Self, property: interop_property_t, ret_code: *c_int) intptr_t {
        return c.omp_get_interop_int(this, property, ret_code);
    }

    ///
    /// The `omp_get_interop_ptr` routine retrieves a pointer property from an `omp_interop_t` object.
    ///
    inline fn get_interop_ptr(this: Self, property: interop_property_t, ret_code: *c_int) *anyopaque {
        return c.omp_get_interop_ptr(this, property, ret_code);
    }

    ///
    /// The `omp_get_interop_str` routine retrieves a string property from an `omp_interop_t` object.
    ///
    inline fn get_str(this: Self, property: interop_property_t, ret_code: *c_int) [:0]const u8 {
        return c.omp_get_interop_str(this, property, ret_code);
    }

    ///
    /// The `omp_get_interop_name` routine retrieves a property name from an `omp_interop_t` object.
    ///
    inline fn get_name(this: Self, property: interop_property_t) [:0]const u8 {
        return c.omp_get_interop_name(this, property);
    }

    ///
    /// The `omp_get_interop_type_desc` routine retrieves a description of the type of a property associated with an `omp_interop_t` object.
    ///
    inline fn get_type_desc(this: Self, property: interop_property_t) [:0]const u8 {
        return c.omp_get_interop_type_desc(this, property);
    }

    ///
    /// The `omp_get_interop_rc_desc` routine retrieves a description of the return code associated with an `omp_interop_t` object.
    ///
    inline fn get_rc_desc(this: Self, ret_code: interop_rc_t) [:0]const u8 {
        return c.omp_get_interop_rc_desc(this, ret_code);
    }
};

/// OpenMP 5.1 device memory routines
///
/// The `omp_target_memcpy_async` routine asynchronously performs a copy between any combination of host and device pointers.
///
inline fn target_memcpy_async(
    dst: *u8,
    src: *const u8,
    length: usize,
    dst_offset: usize,
    src_offset: usize,
    device_num: c_int,
    dep: *depend_t,
) c_int {
    return c.omp_target_memcpy_async(dst, src, length, dst_offset, src_offset, device_num, dep);
}

///
/// The `omp_target_memcpy_rect_async` routine asynchronously performs a copy between any combination of host and device pointers.
///
inline fn target_memcpy_rect_async(
    dst: *u8,
    src: *const u8,
    element_size: usize,
    num_dims: c_int,
    volume: *usize,
    dst_offsets: *usize,
    src_offsets: *usize,
    dst_dimensions: *usize,
    src_dimensions: *usize,
    dst_device_num: c_int,
    src_device_num: c_int,
    dep: *depend_t,
) c_int {
    return c.omp_target_memcpy_rect_async(
        dst,
        src,
        element_size,
        num_dims,
        volume,
        dst_offsets,
        src_offsets,
        dst_dimensions,
        src_dimensions,
        dst_device_num,
        src_device_num,
        dep,
    );
}

/// OpenMP 6.0 device memory routines
pub inline fn target_memsset(ptr: *u8, value: c_int, size: usize, device_num: c_int) *u8 {
    return c.omp_target_memset(ptr, value, size, device_num);
}
pub inline fn target_memsset_async(ptr: *u8, value: c_int, size: usize, device_num: c_int, dep: *depend_t) *u8 {
    return c.omp_target_memset_async(ptr, value, size, device_num, dep);
}
///
/// The `omp_get_mapped_ptr` routine returns the device pointer that is associated with a host pointer for a given device.
///
inline fn get_mapped_ptr(ptr: *const anyopaque, device_num: c_int) *anyopaque {
    return c.omp_get_mapped_ptr(ptr, device_num);
}
///
/// The `omp_target_associate_ptr` routine associates a host pointer with a device pointer.
inline fn target_is_accessible(ptr: *const anyopaque, size: usize, device_num: c_int) c_int {
    return c.omp_target_is_accessible(ptr, size, device_num);
}

// / kmp API functions
// extern "c" inline fn kmp_get_stacksize          (void)int    ;
// extern "c" inline fn kmp_set_stacksize          (int)void   ;
// extern "c" inline fn kmp_get_stacksize_s        (void)size_t ;
// extern "c" inline fn kmp_set_stacksize_s        (size_t)void   ;
// extern "c" inline fn kmp_get_blocktime          (void)int    ;
// extern "c" inline fn kmp_get_library            (void)int    ;
// extern "c" inline fn kmp_set_blocktime          (int)void   ;
// extern "c" inline fn kmp_set_library            (int)void   ;
// extern "c" inline fn kmp_set_library_serial     (void)void   ;
// extern "c" inline fn kmp_set_library_turnaround (void)void   ;
// extern "c" inline fn kmp_set_library_throughput (void)void   ;
// extern "c" inline fn kmp_set_defaults           (char const *)void   ;
// extern "c" inline fn kmp_set_disp_num_buffers   (int)void   ;
// //
// //     /* Intel affinity API */
// //     typedef void * kmp_affinity_mask_t;
// //
// //     extern int    __KAI_KMPC_CONVENTION  kmp_set_affinity             (kmp_affinity_mask_t *);
// //     extern int    __KAI_KMPC_CONVENTION  kmp_get_affinity             (kmp_affinity_mask_t *);
// //     extern int    __KAI_KMPC_CONVENTION  kmp_get_affinity_max_proc    (void);
// //     extern void   __KAI_KMPC_CONVENTION  kmp_create_affinity_mask     (kmp_affinity_mask_t *);
// //     extern void   __KAI_KMPC_CONVENTION  kmp_destroy_affinity_mask    (kmp_affinity_mask_t *);
// //     extern int    __KAI_KMPC_CONVENTION  kmp_set_affinity_mask_proc   (int, kmp_affinity_mask_t *);
// //     extern int    __KAI_KMPC_CONVENTION  kmp_unset_affinity_mask_proc (int, kmp_affinity_mask_t *);
// //     extern int    __KAI_KMPC_CONVENTION  kmp_get_affinity_mask_proc   (int, kmp_affinity_mask_t *);
// //
// //     /* OpenMP 4.0 affinity API */
// //     typedef enum omp_proc_bind_t {
// //         omp_proc_bind_false = 0,
// //         omp_proc_bind_true = 1,
// //         omp_proc_bind_master = 2,
// //         omp_proc_bind_close = 3,
// //         omp_proc_bind_spread = 4
// //     } omp_proc_bind_t;
// //
// //     extern omp_proc_bind_t __KAI_KMPC_CONVENTION omp_get_proc_bind (void);
// //
// //     /* OpenMP 4.5 affinity API */
// //     extern int  __KAI_KMPC_CONVENTION omp_get_num_places (void);
// //     extern int  __KAI_KMPC_CONVENTION omp_get_place_num_procs (int);
// //     extern void __KAI_KMPC_CONVENTION omp_get_place_proc_ids (int, int *);
// //     extern int  __KAI_KMPC_CONVENTION omp_get_place_num (void);
// //     extern int  __KAI_KMPC_CONVENTION omp_get_partition_num_places (void);
// //     extern void __KAI_KMPC_CONVENTION omp_get_partition_place_nums (int *);
// //
// //     extern void * __KAI_KMPC_CONVENTION  kmp_malloc  (size_t);
// //     extern void * __KAI_KMPC_CONVENTION  kmp_aligned_malloc  (size_t, size_t);
// //     extern void * __KAI_KMPC_CONVENTION  kmp_calloc  (size_t, size_t);
// //     extern void * __KAI_KMPC_CONVENTION  kmp_realloc (void *, size_t);
// //     extern void   __KAI_KMPC_CONVENTION  kmp_free    (void *);
// //
// //     extern void   __KAI_KMPC_CONVENTION  kmp_set_warnings_on(void);
// //     extern void   __KAI_KMPC_CONVENTION  kmp_set_warnings_off(void);
// //
// //     /* OpenMP 5.0 Tool Control */
// //     typedef enum omp_control_tool_result_t {
// //         omp_control_tool_notool = -2,
// //         omp_control_tool_nocallback = -1,
// //         omp_control_tool_success = 0,
// //         omp_control_tool_ignored = 1
// //     } omp_control_tool_result_t;
// //
// //     typedef enum omp_control_tool_t {
// //         omp_control_tool_start = 1,
// //         omp_control_tool_pause = 2,
// //         omp_control_tool_flush = 3,
// //         omp_control_tool_end = 4
// //     } omp_control_tool_t;
// //
// //     extern int __KAI_KMPC_CONVENTION omp_control_tool(int, int, void*);
// //
// //     /* OpenMP 5.0 Memory Management */
// //     typedef uintptr_t omp_uintptr_t;
// //
// //     typedef enum {
// //         omp_atk_sync_hint = 1,
// //         omp_atk_alignment = 2,
// //         omp_atk_access = 3,
// //         omp_atk_pool_size = 4,
// //         omp_atk_fallback = 5,
// //         omp_atk_fb_data = 6,
// //         omp_atk_pinned = 7,
// //         omp_atk_partition = 8
// //     } omp_alloctrait_key_t;
// //
// //     typedef enum {
// //         omp_atv_false = 0,
// //         omp_atv_true = 1,
// //         omp_atv_contended = 3,
// //         omp_atv_uncontended = 4,
// //         omp_atv_serialized = 5,
// //         omp_atv_sequential = omp_atv_serialized, // (deprecated)
// //         omp_atv_private = 6,
// //         omp_atv_all = 7,
// //         omp_atv_thread = 8,
// //         omp_atv_pteam = 9,
// //         omp_atv_cgroup = 10,
// //         omp_atv_default_mem_fb = 11,
// //         omp_atv_null_fb = 12,
// //         omp_atv_abort_fb = 13,
// //         omp_atv_allocator_fb = 14,
// //         omp_atv_environment = 15,
// //         omp_atv_nearest = 16,
// //         omp_atv_blocked = 17,
// //         omp_atv_interleaved = 18
// //     } omp_alloctrait_value_t;
// //     #define omp_atv_default ((omp_uintptr_t)-1)
// //
// //     typedef struct {
// //         omp_alloctrait_key_t key;
// //         omp_uintptr_t value;
// //     } omp_alloctrait_t;
// //
// // #   if defined(_WIN32)
// //     // On Windows cl and icl do not support 64-bit enum, let's use integer then.
// //     typedef omp_uintptr_t omp_allocator_handle_t;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_null_allocator;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_default_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_large_cap_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_const_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_high_bw_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_low_lat_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_cgroup_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_pteam_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const omp_thread_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const llvm_omp_target_host_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const llvm_omp_target_shared_mem_alloc;
// //     extern __KMP_IMP omp_allocator_handle_t const llvm_omp_target_device_mem_alloc;
// //
// //     typedef omp_uintptr_t omp_memspace_handle_t;
// //     extern __KMP_IMP omp_memspace_handle_t const omp_default_mem_space;
// //     extern __KMP_IMP omp_memspace_handle_t const omp_large_cap_mem_space;
// //     extern __KMP_IMP omp_memspace_handle_t const omp_const_mem_space;
// //     extern __KMP_IMP omp_memspace_handle_t const omp_high_bw_mem_space;
// //     extern __KMP_IMP omp_memspace_handle_t const omp_low_lat_mem_space;
// //     extern __KMP_IMP omp_memspace_handle_t const llvm_omp_target_host_mem_space;
// //     extern __KMP_IMP omp_memspace_handle_t const llvm_omp_target_shared_mem_space;
// //     extern __KMP_IMP omp_memspace_handle_t const llvm_omp_target_device_mem_space;
// // #   else
// // #       if __cplusplus >= 201103
// //     typedef enum omp_allocator_handle_t : omp_uintptr_t
// // #       else
// //     typedef enum omp_allocator_handle_t
// // #       endif
// //     {
// //       omp_null_allocator = 0,
// //       omp_default_mem_alloc = 1,
// //       omp_large_cap_mem_alloc = 2,
// //       omp_const_mem_alloc = 3,
// //       omp_high_bw_mem_alloc = 4,
// //       omp_low_lat_mem_alloc = 5,
// //       omp_cgroup_mem_alloc = 6,
// //       omp_pteam_mem_alloc = 7,
// //       omp_thread_mem_alloc = 8,
// //       llvm_omp_target_host_mem_alloc = 100,
// //       llvm_omp_target_shared_mem_alloc = 101,
// //       llvm_omp_target_device_mem_alloc = 102,
// //       KMP_ALLOCATOR_MAX_HANDLE = UINTPTR_MAX
// //     } omp_allocator_handle_t;
// // #       if __cplusplus >= 201103
// //     typedef enum omp_memspace_handle_t : omp_uintptr_t
// // #       else
// //     typedef enum omp_memspace_handle_t
// // #       endif
// //     {
// //       omp_default_mem_space = 0,
// //       omp_large_cap_mem_space = 1,
// //       omp_const_mem_space = 2,
// //       omp_high_bw_mem_space = 3,
// //       omp_low_lat_mem_space = 4,
// //       llvm_omp_target_host_mem_space = 100,
// //       llvm_omp_target_shared_mem_space = 101,
// //       llvm_omp_target_device_mem_space = 102,
// //       KMP_MEMSPACE_MAX_HANDLE = UINTPTR_MAX
// //     } omp_memspace_handle_t;
// // #   endif
// //     extern omp_allocator_handle_t __KAI_KMPC_CONVENTION omp_init_allocator(omp_memspace_handle_t m,
// //                                                        int ntraits, omp_alloctrait_t traits[]);
// //     extern void __KAI_KMPC_CONVENTION omp_destroy_allocator(omp_allocator_handle_t allocator);
// //
// //     extern void __KAI_KMPC_CONVENTION omp_set_default_allocator(omp_allocator_handle_t a);
// //     extern omp_allocator_handle_t __KAI_KMPC_CONVENTION omp_get_default_allocator(void);
// // #   ifdef __cplusplus
// //     extern void *__KAI_KMPC_CONVENTION omp_alloc(size_t size, omp_allocator_handle_t a = omp_null_allocator);
// //     extern void *__KAI_KMPC_CONVENTION omp_aligned_alloc(size_t align, size_t size,
// //                                                          omp_allocator_handle_t a = omp_null_allocator);
// //     extern void *__KAI_KMPC_CONVENTION omp_calloc(size_t nmemb, size_t size,
// //                                                   omp_allocator_handle_t a = omp_null_allocator);
// //     extern void *__KAI_KMPC_CONVENTION omp_aligned_calloc(size_t align, size_t nmemb, size_t size,
// //                                                           omp_allocator_handle_t a = omp_null_allocator);
// //     extern void *__KAI_KMPC_CONVENTION omp_realloc(void *ptr, size_t size,
// //                                                    omp_allocator_handle_t allocator = omp_null_allocator,
// //                                                    omp_allocator_handle_t free_allocator = omp_null_allocator);
// //     extern void __KAI_KMPC_CONVENTION omp_free(void * ptr, omp_allocator_handle_t a = omp_null_allocator);
// // #   else
// //     extern void *__KAI_KMPC_CONVENTION omp_alloc(size_t size, omp_allocator_handle_t a);
// //     extern void *__KAI_KMPC_CONVENTION omp_aligned_alloc(size_t align, size_t size,
// //                                                          omp_allocator_handle_t a);
// //     extern void *__KAI_KMPC_CONVENTION omp_calloc(size_t nmemb, size_t size, omp_allocator_handle_t a);
// //     extern void *__KAI_KMPC_CONVENTION omp_aligned_calloc(size_t align, size_t nmemb, size_t size,
// //                                                           omp_allocator_handle_t a);
// //     extern void *__KAI_KMPC_CONVENTION omp_realloc(void *ptr, size_t size, omp_allocator_handle_t allocator,
// //                                                    omp_allocator_handle_t free_allocator);
// //     extern void __KAI_KMPC_CONVENTION omp_free(void *ptr, omp_allocator_handle_t a);
// // #   endif
// //
// //     /* OpenMP 5.0 Affinity Format */
// //     extern void __KAI_KMPC_CONVENTION omp_set_affinity_format(char const *);
// //     extern size_t __KAI_KMPC_CONVENTION omp_get_affinity_format(char *, size_t);
// //     extern void __KAI_KMPC_CONVENTION omp_display_affinity(char const *);
// //     extern size_t __KAI_KMPC_CONVENTION omp_capture_affinity(char *, size_t, char const *);
// //
// //     /* OpenMP 5.0 events */
// // #   if defined(_WIN32)
// //     // On Windows cl and icl do not support 64-bit enum, let's use integer then.
// //     typedef omp_uintptr_t omp_event_handle_t;
// // #   else
// //     typedef enum omp_event_handle_t { KMP_EVENT_MAX_HANDLE = UINTPTR_MAX } omp_event_handle_t;
// // #   endif
// //     extern void __KAI_KMPC_CONVENTION omp_fulfill_event ( omp_event_handle_t event );
// //
// //     /* OpenMP 5.0 Pause Resources */
// //     typedef enum omp_pause_resource_t {
// //       omp_pause_resume = 0,
// //       omp_pause_soft = 1,
// //       omp_pause_hard = 2
// //     } omp_pause_resource_t;
// //     extern int __KAI_KMPC_CONVENTION omp_pause_resource(omp_pause_resource_t, int);
// //     extern int __KAI_KMPC_CONVENTION omp_pause_resource_all(omp_pause_resource_t);
// //
// //     extern int __KAI_KMPC_CONVENTION omp_get_supported_active_levels(void);
// //
// //     /* OpenMP 5.1 */
// //     extern void __KAI_KMPC_CONVENTION omp_set_num_teams(int num_teams);
// //     extern int __KAI_KMPC_CONVENTION omp_get_max_teams(void);
// //     extern void __KAI_KMPC_CONVENTION omp_set_teams_thread_limit(int limit);
// //     extern int __KAI_KMPC_CONVENTION omp_get_teams_thread_limit(void);
// //
// //     /* OpenMP 5.1 Display Environment */
// //     extern void omp_display_env(int verbose);
// //
// // #   if defined(_OPENMP) && _OPENMP >= 201811
// //     #pragma omp begin declare variant match(device={kind(host)})
// //     static inline int omp_is_initial_device(void) { return 1; }
// //     #pragma omp end declare variant
// //     #pragma omp begin declare variant match(device={kind(nohost)})
// //     static inline int omp_is_initial_device(void) { return 0; }
// //     #pragma omp end declare variant
// // #   endif
// //
// //     /* OpenMP 5.2 */
// //     extern int __KAI_KMPC_CONVENTION omp_in_explicit_task(void);
// //
// //     /* LLVM Extensions */
// //     extern void *llvm_omp_target_dynamic_shared_alloc(void);
// //
// // #   undef __KAI_KMPC_CONVENTION
// // #   undef __KMP_IMP
// //
// //     /* Warning:
// //        The following typedefs are not standard, deprecated and will be removed in a future release.
// //     */
// //     typedef int     omp_int_t;
// //     typedef double  omp_wtime_t;
// //
// // #   ifdef __cplusplus
// //     }
// // #   endif
// //
// // #endif /* __OMP_H */
