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

pub const reduction_operators = kmp.reduction_operators;
pub const parallel_opts = struct {
    ctx: bool = false,
    iff: bool = false,
    proc_bind: proc_bind = .default,
    reduction: []const reduction_operators = &[0]reduction_operators{},
};

pub const parallel_for_opts = struct {
    ctx: bool = false,
    sched: kmp.sched_t = kmp.sched_t.StaticNonChunked,
    ordered: bool = false,
    chunk_size: c_int = 1,
};

pub fn parallel(comptime opts: parallel_opts) type {
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
    };
    if (opts.iff) {
        return struct {
            pub inline fn run(
                cond: bool,
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                in.check_fn_signature(f);

                const ret = common.make_args(args, f);
                const id: kmp.ident_t = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                    .psource = "parallel" ++ @typeName(@TypeOf(f)),
                };
                common.make_proc_bind(&id, opts.proc_bind);
                const outline = parallel_outline(f, @TypeOf(ret), opts).outline;

                kmp.fork_call_if(&id, 1, @ptrCast(&outline), @intFromBool(cond), &ret);

                return ret.ret;
            }
        };
    } else {
        return struct {
            pub inline fn run(
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                in.check_fn_signature(f);

                const ret = common.make_args(args, f);
                const id: kmp.ident_t = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                    .psource = "parallel" ++ @typeName(@TypeOf(f)),
                };
                common.make_proc_bind(&id, opts.proc_bind);
                const outline = parallel_outline(f, @TypeOf(ret), opts).outline;

                kmp.fork_call(&id, 1, @ptrCast(&outline), &ret);

                return ret.ret;
            }
        };
    }
}

inline fn parallel_outline(
    comptime f: anytype,
    comptime R: type,
    comptime opts: parallel_opts,
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
            var this: ctx = .{
                .global_tid = gtid.*,
                .bound_tid = btid.*,
            };

            var private_copy = in.deep_copy(args.v.private);
            var reduction_copy = in.deep_copy(args.v.reduction);
            const true_args = args.v.shared ++ private_copy ++ reduction_copy;

            if (@typeInfo(in.copy_ret(f)) == .ErrorUnion) {
                args.ret = @call(.always_inline, f, if (opts.ctx) .{this} ++ true_args else true_args) catch |err| err;
            } else {
                args.ret = @call(.always_inline, f, if (opts.ctx) .{this} ++ true_args else true_args);
            }

            if (opts.reduction.len > 0) {
                const id: kmp.ident_t = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                    .psource = "parallel" ++ @typeName(@TypeOf(f)),
                };
                reduce(this, &id, args.v.reduction, reduction_copy, opts.reduction, &static.lck);
            }

            return;
        }
    };
}

inline fn reduce(
    this: ctx,
    comptime id: *const kmp.ident_t,
    out_reduction: anytype,
    copies: @TypeOf(out_reduction),
    comptime operators: []const kmp.reduction_operators,
    lck: *kmp.critical_name_t,
) void {
    const res = kmp.reduce_nowait(@typeInfo(@TypeOf(out_reduction)).Struct.fields, id, this.global_tid, copies.len, @sizeOf(@TypeOf(out_reduction)), @ptrCast(@constCast(&copies)), operators, lck);
    if (res == 2) {
        @panic("Atomic reduce not implemented");
    }

    if (res == 0) {
        return;
    }

    kmp.create_reduce(@typeInfo(@TypeOf(out_reduction)).Struct.fields, operators).finalize(out_reduction, copies);
    kmp.end_reduce_nowait(id, this.global_tid, lck);
}

pub inline fn loop(
    comptime index_type: type,
    comptime opts: parallel_for_opts,
) type {
    if (!std.meta.trait.isSignedInt(index_type) and !std.meta.trait.isUnsignedInt(index_type)) {
        @compileError("Tried to loop over a comptime/non-integer type " ++ @typeName(index_type));
    }
    if (!opts.ordered) {
        return struct {
            pub inline fn run(
                p: ctx,
                lower: index_type,
                upper: index_type,
                increment: index_type,
                args: anytype,
                comptime f: anytype,
            ) in.copy_ret(f) {
                in.check_args(@TypeOf(args));

                in.check_fn_signature(f);

                const f_type_info = @typeInfo(@TypeOf(f));
                if (f_type_info.Fn.params.len < 1 or f_type_info.Fn.params[0].type.? != index_type) {
                    @compileError("Expected function with signature `inline fn(numeric, ...)` or `inline fn(numeric, *omp.ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.\n" ++ @typeName(index_type) ++ " may be different from the expected type: " ++ @typeName(f_type_info.Fn.params[1].type.?));
                }

                const id = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                    .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
                };

                // This is `1` iside the last thread execution
                var last_iter: c_int = 0;
                var low: index_type = lower;
                var upp: index_type = upper - 1;
                var stri: index_type = 1;
                const incr: index_type = increment;

                kmp.for_static_init(index_type, &id, p.global_tid, opts.sched, &last_iter, &low, &upp, &stri, incr, opts.chunk_size);

                const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
                while (@atomicLoad(index_type, &low, .Acquire) <= upp) {
                    // TODO: Figure out how to pass the result without chekcing each iteration
                    if (type_info == .ErrorUnion) {
                        _ = @call(
                            .always_inline,
                            f,
                            if (opts.ctx) .{ p, @atomicRmw(index_type, &low, .Add, incr, .Release) } ++ args else .{@atomicRmw(index_type, &low, .Add, incr, .Release)} ++ args,
                        ) catch |err| err;
                    } else {
                        _ = @call(
                            .always_inline,
                            f,
                            if (opts.ctx) .{ p, @atomicRmw(index_type, &low, .Add, incr, .Release) } ++ args else .{@atomicRmw(index_type, &low, .Add, incr, .Release)} ++ args,
                        );
                    }
                }

                const id_fini = .{
                    .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
                    .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
                    .reserved_3 = 0x1b,
                };
                kmp.for_static_fini(&id_fini, p.global_tid);

                p.barrier();

                return undefined;
            }
        };
    } else {
        @compileError("Ordered parallel for not implemented");
    }
}

pub const ctx = struct {
    global_tid: c_int,
    bound_tid: c_int,

    pub inline fn barrier(
        this: ctx,
    ) void {
        const id: kmp.ident_t = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
            .psource = "barrier",
        };
        kmp.barrier(&id, this.global_tid);
    }
};
