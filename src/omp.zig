const std = @import("std");
const kmp = @import("kmp.zig");
const c = @cImport({
    @cInclude("omp.h");
    @cInclude("omp-tools.h");
});
const options = @import("build_options");
const in = @import("input_handler.zig");
const reduce = @import("reduce.zig");
const workshare_env = @import("workshare_env.zig");

const omp = @This();
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

pub const reduction_operators = reduce.operators;
pub const parallel_opts = struct {
    iff: bool = false,
    proc_bind: proc_bind = .default,
    reduction: []const reduction_operators = &[0]reduction_operators{},
    ret_reduction: reduction_operators = .none,
};

pub const task_opts = struct {
    iff: bool = false,
    final: bool = false,
    untied: bool = false,
};

pub const parallel_for_opts = struct {
    sched: schedule = .static,
    chunk_size: c_int = 1,
    ordered: bool = false,
    reduction: []const reduction_operators = &[0]reduction_operators{},
    ret_reduction: reduction_operators = .none,
    nowait: bool = false,
};

pub const sections_opts = struct {
    reduction: []const reduction_operators = &[0]reduction_operators{},
    ret_reduction: reduction_operators = .none,
    nowait: bool = false,
};

pub const critical_options = struct {
    sync: sync_hint_t = .none,
    name: []const u8 = "",
};

pub inline fn parallel(
    comptime opts: parallel_opts,
) type {
    const common = struct {
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

        inline fn parallel_outline(
            comptime f: anytype,
            comptime R: type,
            comptime in_opts: parallel_opts,
        ) type {
            return opaque {
                const red = if (in_opts.ret_reduction == .none) in_opts.reduction else in_opts.reduction ++ .{in_opts.ret_reduction};
                const work = workshare_env.make(red, true, f, in.copy_ret(f), true);

                fn workshare_outline(
                    gtid: *c_int,
                    btid: *c_int,
                    args: *R,
                ) callconv(.C) void {
                    kmp.ctx = .{
                        .global_tid = gtid.*,
                        .bound_tid = btid.*,
                    };

                    const reduction_val_bytes = [_]u8{0} ** @sizeOf(in.copy_ret(f));
                    var reduction_val = std.mem.bytesAsValue(in.copy_ret(f), &reduction_val_bytes).*;
                    const maybe_ret = if (@typeInfo(in.copy_ret(f)) == .ErrorUnion)
                        work.run(true, .{}, args.v, .{}, &reduction_val) catch |err| err
                    else
                        work.run(true, .{}, args.v, .{}, &reduction_val);

                    if (maybe_ret) |r| {
                        args.ret = r;
                    }

                    return;
                }

                fn generic_outline(
                    gtid: *c_int,
                    btid: *c_int,
                    args: *R,
                ) callconv(.C) void {
                    kmp.ctx = .{
                        .global_tid = gtid.*,
                        .bound_tid = btid.*,
                    };

                    args.ret = if (@typeInfo(in.copy_ret(f)) == .ErrorUnion)
                        @call(.always_inline, f, args.*.v) catch |err| err
                    else
                        @call(.always_inline, f, args.*.v);

                    return;
                }
            };
        }

        inline fn parallel_impl(
            args: anytype,
            comptime f: anytype,
            comptime has_cond: bool,
            cond: bool,
        ) in.copy_ret(f) {
            in.check_fn_signature(f);

            var ret = make_args(args, f);
            const id: kmp.ident_t = .{ .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC), .psource = "parallel" ++ @typeName(@TypeOf(f)), .reserved_3 = 0x1e };
            make_proc_bind(&id, opts.proc_bind);
            const outline = parallel_outline(f, @TypeOf(ret), opts).workshare_outline;

            if (has_cond) {
                kmp.fork_call_if(&id, 1, @ptrCast(&outline), @intFromBool(cond), &ret);
            } else {
                kmp.fork_call(&id, 1, @ptrCast(&outline), &ret);
            }

            return ret.ret;
        }

        inline fn parallel_loop_impl(
            comptime T: type,
            lower: T,
            upper: T,
            increment: T,
            args: anytype,
            comptime f: anytype,
            comptime inner_fn: anytype,
            comptime has_cond: bool,
            cond: bool,
        ) in.copy_ret(f) {
            in.check_fn_signature(f);

            const ret_t = struct {
                ret: in.copy_ret(f) = undefined,
                v: @TypeOf(.{ args, lower, upper, increment, inner_fn }),
            };
            const ret: ret_t = .{ .ret = undefined, .v = .{ args, lower, upper, increment, inner_fn } };

            const id: kmp.ident_t = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "parallel" ++ @typeName(@TypeOf(f)),
            };
            make_proc_bind(&id, opts.proc_bind);
            const outline = parallel_outline(f, @TypeOf(ret), opts).generic_outline;
            if (has_cond) {
                kmp.fork_call_if(&id, 1, @ptrCast(&outline), @intFromBool(cond), &ret);
            } else {
                kmp.fork_call(&id, 1, @ptrCast(&outline), &ret);
            }
            return ret.ret;
        }

        inline fn parallel_sections_impl(
            args: anytype,
            comptime f: anytype,
            comptime fs: anytype,
            comptime has_cond: bool,
            cond: bool,
        ) in.copy_ret(f) {
            in.check_fn_signature(f);

            const ret_t = struct {
                ret: in.copy_ret(f) = undefined,
                v: @TypeOf(.{ args, fs }),
            };
            const ret: ret_t = .{ .ret = undefined, .v = .{ args, fs } };

            const id: kmp.ident_t = .{ .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC), .psource = "parallel" ++ @typeName(@TypeOf(f)), .reserved_3 = 0x1e };
            make_proc_bind(&id, opts.proc_bind);
            const outline = parallel_outline(f, @TypeOf(ret), opts).generic_outline;

            if (has_cond) {
                kmp.fork_call_if(&id, 1, @ptrCast(&outline), @intFromBool(cond), &ret);
            } else {
                kmp.fork_call(&id, 1, @ptrCast(&outline), &ret);
            }

            return ret.ret;
        }
    };

    const api = struct {
        pub inline fn run_if(
            args: anytype,
            cond: bool,
            comptime f: anytype,
        ) in.copy_ret(f) {
            return common.parallel_impl(args, f, true, cond);
        }

        pub inline fn run(
            args: anytype,
            comptime f: anytype,
        ) in.copy_ret(f) {
            return common.parallel_impl(args, f, false, false);
        }

        pub inline fn loop(
            comptime idx_T: type,
            comptime loop_args: parallel_for_opts,
        ) type {
            return struct {
                inline fn _run_if(
                    args: anytype,
                    cond: bool,
                    lower: idx_T,
                    upper: idx_T,
                    increment: idx_T,
                    comptime f: anytype,
                ) in.copy_ret(f) {
                    return common.parallel_loop_impl(idx_T, lower, upper, increment, args, omp.loop(idx_T, loop_args).run, f, true, cond);
                }

                inline fn _run(
                    args: anytype,
                    lower: idx_T,
                    upper: idx_T,
                    increment: idx_T,
                    comptime f: anytype,
                ) in.copy_ret(f) {
                    return common.parallel_loop_impl(idx_T, lower, upper, increment, args, omp.loop(idx_T, loop_args).run, f, false, false);
                }

                pub const run = if (opts.iff) _run_if else _run;
            };
        }

        pub inline fn sections(
            comptime sections_args: sections_opts,
        ) type {
            return struct {
                inline fn _run_if(
                    args: anytype,
                    cond: bool,
                    comptime fs: anytype,
                ) in.copy_ret(fs[0]) {
                    return common.parallel_sections_impl(args, omp.sections(sections_args).run, fs, true, cond);
                }

                inline fn _run(
                    args: anytype,
                    comptime fs: anytype,
                ) in.copy_ret(fs[0]) {
                    return common.parallel_sections_impl(args, omp.sections(sections_args).run, fs, false, false);
                }

                pub const run = if (opts.iff) _run_if else _run;
            };
        }
    };

    return struct {
        // omp.para(...).run(...);
        pub const run = if (opts.iff) api.run_if else api.run;

        // omp.para(...).loop(...).run(...);
        pub const loop = api.loop;

        // omp.para(...).sections(...).run(...);
        pub const sections = api.sections;
    };
}

pub inline fn loop(
    comptime idx_T: type,
    comptime opts: parallel_for_opts,
) type {
    return _loop(idx_T, opts, false);
}

inline fn _loop(
    comptime idx_T: type,
    comptime opts: parallel_for_opts,
    comptime is_from_sections: bool,
) type {
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

        inline fn static_impl(
            args: anytype,
            lower: idx_T,
            upper: idx_T,
            increment: idx_T,
            comptime f: anytype,
        ) in.copy_ret(f) {
            const sections_flag = if (is_from_sections) @intFromEnum(kmp.ident_flags.IDENT_WORK_SECTIONS) else 0;
            const id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP) | sections_flag,
                .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
            };

            // This is `1` iside the last thread execution
            var last_iter: c_int = 0;
            var low: idx_T = lower;
            var upp: idx_T = upper - 1;
            var stri: idx_T = 1;
            const incr: idx_T = increment;

            kmp.for_static_init(
                idx_T,
                &id,
                kmp.ctx.global_tid,
                to_kmp_sched(opts.sched),
                &last_iter,
                &low,
                &upp,
                &stri,
                incr,
                opts.chunk_size,
            );

            const to_ret_bytes = [_]u8{0} ** @sizeOf(in.copy_ret(f));
            var to_ret = std.mem.bytesAsValue(in.copy_ret(f), &to_ret_bytes).*;

            const red = reduce.create(@typeInfo(@TypeOf(.{to_ret})).Struct.fields, &.{opts.ret_reduction});
            if (opts.chunk_size > 1) {
                while (low + opts.chunk_size < upper) : (low += stri) {
                    inline for (0..opts.chunk_size) |i| {
                        red.single(&to_ret, @call(.always_inline, f, .{low + @as(idx_T, i)} ++ args) catch |err| err);
                    }
                }
                while (low < upper) : (low += incr) {
                    red.single(&to_ret, @call(.always_inline, f, .{low} ++ args));
                }
            } else {
                var i: idx_T = low;
                while (i <= upp) : (i += incr) {
                    red.single(&to_ret, @call(.always_inline, f, .{i} ++ args));
                }
            }

            const id_fini = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
                .reserved_3 = 0x1c,
            };
            kmp.for_static_fini(&id_fini, kmp.ctx.global_tid);

            if (!opts.nowait) {
                barrier();
            }

            return to_ret;
        }

        pub inline fn dynamic_impl(
            args: anytype,
            lower: idx_T,
            upper: idx_T,
            increment: idx_T,
            comptime f: anytype,
        ) in.copy_ret(f) {
            const id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
            };

            // This is `1` iside the last thread execution
            var last_iter: c_int = 0;
            var low: idx_T = lower;
            var upp: idx_T = upper - 1;
            var stri: idx_T = 1;
            const incr: idx_T = increment;
            kmp.dispatch_init(idx_T, &id, kmp.ctx.global_tid, to_kmp_sched(opts.sched), low, upp, incr, opts.chunk_size);

            const to_ret_bytes = [_]u8{0} ** @sizeOf(in.copy_ret(f));
            var to_ret = std.mem.bytesAsValue(in.copy_ret(f), &to_ret_bytes).*;

            const red = kmp.create(@typeInfo(std.builtin.Type.Struct{in.copy_ret(f)}).Struct.fields, &.{opts.ret_reduction});
            while (kmp.dispatch_next(idx_T, &id, kmp.ctx.global_tid, &last_iter, &low, &upp, &stri) == 1) {
                defer kmp.dispatch_fini(idx_T, &id, kmp.ctx.global_tid);

                var i: idx_T = low;
                while (i <= upp) : (i += incr) {
                    red.single(&to_ret, @call(.always_inline, f, .{i} ++ args));
                }
            }

            return to_ret;
        }

        pub inline fn static(
            args: anytype,
            lower: idx_T,
            upper: idx_T,
            increment: idx_T,
            comptime f: anytype,
        ) in.copy_ret(f) {
            in.check_args(@TypeOf(args));
            in.check_fn_signature(f);

            const f_type_info = @typeInfo(@TypeOf(f));
            if (f_type_info.Fn.params.len < 1) {
                @compileError("Expected function with signature `inline fn(numeric, ...)`" ++ @typeName(@TypeOf(f)) ++ " instead.\n" ++ @typeName(idx_T) ++ " may be different from the expected type: " ++ @typeName(f_type_info.Fn.params[0].type.?));
            }
            const do_copy = comptime !is_from_sections;
            const red = if (opts.ret_reduction == .none) opts.reduction else opts.reduction ++ .{opts.ret_reduction};

            const st = struct {
                const reduction_val_bytes = [_]u8{0} ** @sizeOf(in.copy_ret(f));
                var reduction_val = std.mem.bytesAsValue(in.copy_ret(f), &reduction_val_bytes).*;
            };

            const work = workshare_env.make(
                red,
                do_copy,
                static_impl,
                in.copy_ret(f),
                false,
            );

            _ = work.run(false, .{}, in.normalize_args(args), .{ lower, upper, increment, f }, &st.reduction_val);
            if (!opts.nowait) {
                barrier();
            }

            return st.reduction_val;
        }

        pub inline fn dynamic(
            args: anytype,
            lower: idx_T,
            upper: idx_T,
            increment: idx_T,
            comptime f: anytype,
        ) in.copy_ret(f) {
            std.debug.assert(is_from_sections == false);

            in.check_args(@TypeOf(args));
            in.check_fn_signature(f);

            const f_type_info = @typeInfo(@TypeOf(f));
            if (f_type_info.Fn.params.len < 1) {
                @compileError("Expected function with signature `inline fn(numeric, ...)`" ++ @typeName(@TypeOf(f)) ++ " instead.\n" ++ @typeName(idx_T) ++ " may be different from the expected type: " ++ @typeName(f_type_info.Fn.params[0].type.?));
            }

            const st = struct {
                const reduction_val_bytes = [_]u8{0} ** @sizeOf(in.copy_ret(f));
                var reduction_val = std.mem.bytesAsValue(in.copy_ret(f), &reduction_val_bytes).*;
            };
            const red = if (opts.ret_reduction == .none) opts.reduction else opts.reduction ++ .{opts.ret_reduction};
            const work = workshare_env.make(
                red,
                true,
                dynamic_impl,
                in.copy_ret(f),
                false,
            );

            _ = work.run(false, .{}, in.normalize_args(args), .{ lower, upper, increment, f }, &st.reduction_val);
            if (!opts.nowait) {
                barrier();
            }

            return st.reduction_val;
        }
    };

    return struct {
        pub const run = if (opts.chunk_size == 1 and opts.sched == .static) common.static else common.dynamic;
    };
}

pub inline fn barrier() void {
    const id: kmp.ident_t = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_BARRIER_EXPL),
        .psource = "barrier",
        .reserved_3 = 0x1e,
    };
    kmp.barrier(&id, kmp.ctx.global_tid);
}

pub inline fn flush(vars: anytype) void {
    _ = vars; // Just ignore this, it's only used to define the ordering of operations when compiling, I hope...
    const id: kmp.ident_t = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
        .psource = "flush",
        .reserved_3 = 0x1e,
    };
    kmp.flush(&id);
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

            kmp.critical(&id, kmp.ctx.global_tid, &static.lock, @intFromEnum(opts.sync));
            defer {
                kmp.critical_end(&id, kmp.ctx.global_tid, &static.lock);
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

pub inline fn sections(
    comptime opts: sections_opts,
) type {
    return struct {
        pub inline fn run(
            args: anytype,
            comptime fs: anytype,
        ) in.copy_ret(fs[0]) {
            const args_type = @TypeOf(args);

            in.check_args(args_type);
            comptime std.debug.assert(@typeInfo(@TypeOf(fs)) == .Struct);
            inline for (fs) |f| {
                in.check_fn_signature(f);
            }

            const runner = struct {
                const _fs: [fs.len]@TypeOf(fs[0]) = fs;

                pub inline fn f(idx: usize, a: @TypeOf(in.normalize_args(args))) in.copy_ret(fs[0]) {
                    const private_copy = in.make_another(a.private);
                    const firstprivate_copy = in.shallow_copy(a.firstprivate);
                    const reduction_copy = in.shallow_copy(a.reduction);
                    const true_args = .{a.shared ++ private_copy ++ firstprivate_copy ++ reduction_copy};

                    const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
                    const ret = ret: {
                        if (type_info == .ErrorUnion) {
                            break :ret try @call(.auto, _fs[idx], true_args[0]);
                        } else {
                            break :ret @call(.auto, _fs[idx], true_args[0]);
                        }
                    };

                    return ret;
                }
            }.f;

            return _loop(usize, .{
                .nowait = opts.nowait,
                .reduction = opts.reduction,
                .sched = .static,
            }, true).run(args, 0, fs.len, 1, runner);
        }
    };
}

pub inline fn single() type {
    return struct {
        pub inline fn run(
            args: anytype,
            comptime f: anytype,
        ) void_or_opt(in.copy_ret(f)) {
            in.check_args(@TypeOf(args));
            in.check_fn_signature(f);

            const single_id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "single" ++ @typeName(@TypeOf(f)),
            };
            const barrier_id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_BARRIER_IMPL_SINGLE),
                .psource = "single" ++ @typeName(@TypeOf(f)),
                .reserved_3 = 0x27,
            };

            if (kmp.single(&single_id, kmp.ctx.global_tid) == 1) {
                defer {
                    kmp.end_single(&single_id, kmp.ctx.global_tid);
                    kmp.barrier(&barrier_id, kmp.ctx.global_tid);
                }
                const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);

                return if (type_info == .ErrorUnion)
                    try @call(.always_inline, f, args)
                else
                    @call(.always_inline, f, args);
            }

            kmp.barrier(&barrier_id, kmp.ctx.global_tid);
            if (in.copy_ret(f) != void) {
                return null;
            }
        }
    };
}

pub inline fn void_or_opt(comptime T: type) type {
    return if (T == void) void else ?T;
}

pub inline fn master() type {
    return struct {
        pub inline fn run(
            args: anytype,
            comptime f: anytype,
        ) void_or_opt(in.copy_ret(f)) {
            return masked.run(only_master, args, f);
        }
    };
}

pub const only_master: c_int = 0;
pub inline fn masked() type {
    return struct {
        pub inline fn run(
            args: anytype,
            filter: i32,
            comptime f: anytype,
        ) void_or_opt(in.copy_ret(f)) {
            in.check_args(@TypeOf(args));
            in.check_fn_signature(f);

            const masked_id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "masked" ++ @typeName(@TypeOf(f)),
            };

            if (kmp.masked(&masked_id, kmp.ctx.global_tid, filter) == 1) {
                const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
                if (type_info == .ErrorUnion) {
                    return try @call(.always_inline, f, args);
                } else {
                    return @call(.always_inline, f, args);
                }
            }
            if (void_or_opt(in.copy_ret(f)) != void) {
                return null;
            }
        }
    };
}

pub const promise = kmp.promise;
inline fn void_or_promise_ptr(comptime T: type) type {
    return if (T == void) void else *promise(T);
}

pub inline fn task(
    comptime opts: task_opts,
) type {
    const api = struct {
        inline fn run_impl(
            args: anytype,
            comptime f: anytype,
            cond: bool,
            fin: bool,
        ) void_or_promise_ptr(in.copy_ret(f)) {
            const id = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "task" ++ @typeName(@TypeOf(f)),
            };
            var norm = in.normalize_args(args);

            const private_copy = in.make_another(norm.private);
            const firstprivate_copy = in.shallow_copy(norm.firstprivate);
            const private_args = private_copy ++ firstprivate_copy;

            // in.check_args(@TypeOf(private_args));
            in.check_fn_signature(f);

            const t_type = kmp.task_t(
                @TypeOf(norm.shared),
                @TypeOf(private_args),
                in.copy_ret(f),
            );

            const flags = kmp.tasking_flags{
                .tiedness = @intFromBool(!opts.untied),
                .final = @intFromBool(fin),
            };

            const real_task = t_type.alloc(
                f,
                &id,
                kmp.ctx.global_tid,
                flags,
            );
            real_task.set_data(&norm.shared, private_args);

            // TODO: do something better with this error...
            var pro: void_or_promise_ptr(in.copy_ret(f)) = if (in.copy_ret(f) == void) undefined else promise(in.copy_ret(f)).init() catch @panic("Buy more RAM lol");
            if (@TypeOf(pro) == *kmp.promise(in.copy_ret(f))) {
                real_task.make_promise(pro);
            }

            if (comptime opts.iff) {
                if (!cond) {
                    real_task.begin_if0(&id, kmp.ctx.global_tid);

                    if (@typeInfo(in.copy_ret(f)) == .ErrorUnion) {
                        _ = @call(.always_inline, f, norm.shared ++ private_args) catch |err| err;
                    } else {
                        _ = @call(.always_inline, f, norm.shared ++ private_args);
                    }

                    real_task.complete_if0(&id, kmp.ctx.global_tid);
                }

                if (@TypeOf(pro) == *promise(in.copy_ret(f))) {
                    pro.release();
                }
                return pro;
            }

            _ = real_task.task(&id, kmp.ctx.global_tid);
            return pro;
        }

        pub inline fn run(
            args: anytype,
            comptime f: anytype,
        ) void_or_promise_ptr(in.copy_ret(f)) {
            return run_impl(args, f, false, false);
        }

        pub inline fn run_if(
            cond: bool,
            args: anytype,
            comptime f: anytype,
        ) void_or_promise_ptr(in.copy_ret(f)) {
            return run_impl(args, f, cond, false);
        }

        pub inline fn run_final(
            final: bool,
            args: anytype,
            comptime f: anytype,
        ) void_or_promise_ptr(in.copy_ret(f)) {
            return run_impl(args, f, false, final);
        }

        pub inline fn run_if_final(
            cond: bool,
            final: bool,
            args: anytype,
            comptime f: anytype,
        ) void_or_promise_ptr(in.copy_ret(f)) {
            return run_impl(args, f, cond, final);
        }
    };

    return struct {
        // TODO: Find a way to format it better
        pub const run = if (opts.iff and opts.final) api.run_if_final else if (opts.iff and !opts.final) api.run_if else if (!opts.iff and opts.final) api.run_final else api.run;
    };
}

pub inline fn taskyeild() void {
    const id = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
        .psource = "taskyeild",
    };
    kmp.taskyield(&id, kmp.ctx.global_tid);
}

pub inline fn taskwait() void {
    const id = .{
        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
        .psource = "taskwait",
    };
    kmp.taskwait(&id, kmp.ctx.global_tid);
}

// //////////////////////////////////////////////////////////////////////////////////
// / Runtime API ////////////////////////////////////////////////////////////////////
// //////////////////////////////////////////////////////////////////////////////////

// Setters
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

// Getters
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

// Locks
//     OpenMP 5.0  Synchronization hints
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

//     OpenMP 5.0
pub inline fn get_device_num() u32 {
    return @intCast(c.omp_get_device_num());
}

//     typedef void * omp_depend_t;
pub const depend_t = *anyopaque;

//     OpenMP 5.1 interop
// TODO: Maybe `usize` is better here, but intptr_t is supposed to be an int
pub const intptr_t = isize;
// 0..omp_get_num_interop_properties()-1 are reserved for implementation-defined properties
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

// OpenMP 6.0 device memory routines
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
