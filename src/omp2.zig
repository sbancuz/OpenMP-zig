const std = @import("std");
const kmp = @import("kmp.zig");
const c = @cImport({
    @cInclude("omp.h");
    @cInclude("omp-tools.h");
});

const in = @import("input_handler.zig");
pub const proc_bind = enum(c_int) {
    default,
    primary,
    master,
    close,
    spread,
};

pub const reduction_operators = kmp.reduction_operators;
pub const parallel_opts = struct {
    ctx: bool = false,
    iff: bool = false,
    proc_bind: proc_bind = .default,
    reduction: []const reduction_operators = &[0]reduction_operators{},
};

pub const parallel_for_opts = struct {
    sched: kmp.sched_t = kmp.sched_t.StaticNonChunked,
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
                const id = common.id(f);
                const outline = ctx.parallel_outline(f, @TypeOf(ret), opts).outline;

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
                const outline = ctx.parallel_outline(f, @TypeOf(ret), opts).outline;

                kmp.fork_call(&id, 1, @ptrCast(&outline), &ret);

                return ret.ret;
            }
        };
    }
}

pub const ctx = struct {
    const Self = @This();

    global_tid: c_int,
    bound_tid: c_int,

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
                var this: Self = .{
                    .global_tid = gtid.*,
                    .bound_tid = btid.*,
                };

                var private_copy = in.deep_copy(args.v.private);
                var reduction_copy = in.deep_copy(args.v.reduction);
                const true_args = args.v.shared ++ private_copy ++ reduction_copy;

                if (@typeInfo(in.copy_ret(f)) == .ErrorUnion) {
                    args.ret = @call(.always_inline, f, if (opts.use_ctx) .{&this} ++ true_args else true_args) catch |err| err;
                } else {
                    args.ret = @call(.always_inline, f, if (opts.use_ctx) .{&this} ++ true_args else true_args);
                }

                if (opts.red_opts.len > 0) {
                    const id: kmp.ident_t = .{
                        .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                        .psource = "parallel" ++ @typeName(@TypeOf(f)),
                    };
                    this.reduce(&id, args.v.reduction, reduction_copy, opts.red_opts, &static.lck);
                }

                return;
            }
        };
    }

    inline fn reduce(
        this: *Self,
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

    pub inline fn parallel_for(
        this: *Self,
        args: anytype,
        lower: anytype,
        upper: anytype,
        increment: anytype,
        opts: parallel_for_opts,
        comptime f: anytype,
    ) in.copy_ret(f) {
        const T = comptime ret: {
            if (!std.meta.trait.isSignedInt(@TypeOf(lower)) and !std.meta.trait.isUnsignedInt(@TypeOf(lower))) {
                @compileError("Tried to loop over a comptime/non-integer type " ++ @typeName(@TypeOf(lower)));
            }

            break :ret @TypeOf(lower);
        };
        in.check_args(@TypeOf(args));

        in.check_fn_signature(f);

        const f_type_info = @typeInfo(@TypeOf(f));
        if (f_type_info.Fn.params.len < 1 or f_type_info.Fn.params[0].type.? != T) {
            @compileError("Expected function with signature `inline fn(numeric, ...)` or `inline fn(numeric, *omp.ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.\n" ++ @typeName(T) ++ " may be different from the expected type: " ++ @typeName(f_type_info.Fn.params[1].type.?));
        }

        const id = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
            .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
        };

        // TODO: Don't know what will happen with other schedules
        std.debug.assert(opts.sched == kmp.sched_t.StaticNonChunked);
        var sched: c_int = @intFromEnum(opts.sched);

        // This is `1` iside the last thread execution
        var last_iter: c_int = 0;

        // TODO: Figure out how to use all of these values
        var low: T = lower;

        // TODO: Maybe use f64 when we need more precision?
        var upp: T = upper - 1;
        var stri: T = 1;
        var incr: T = increment;
        var chunk: T = 1;

        // std.debug.print("upp: {}\n", .{upp});
        kmp.for_static_init(T, &id, this.global_tid, sched, &last_iter, &low, &upp, &stri, incr, chunk);
        // std.debug.print("upp: {}, low: {}, last_iter: {}\n", .{ upp, low, last_iter });

        // TODO: Figure out how to pass the result
        while (true) {
            const i = @atomicRmw(T, &low, .Add, incr, .AcqRel);
            if (upp < i) {
                break;
            }
            // std.debug.print("upp: {}, i: {}, last_iter: {}, stride: {}\n", .{ upp, i, last_iter, stri });

            const new_args = .{i} ++ args;
            const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);

            if (type_info == .ErrorUnion) {
                _ = try @call(.always_inline, f, new_args);
            } else {
                _ = @call(.always_inline, f, new_args);
            }
        }

        const id_fini = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
            .psource = "parallel_for" ++ @typeName(@TypeOf(f)),
            .reserved_3 = 0x1b,
        };
        kmp.for_static_fini(&id_fini, this.global_tid);

        this.barrier();

        return undefined;
    }

    pub inline fn barrier(
        this: *Self,
    ) void {
        const id: kmp.ident_t = .{
            .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC) | @intFromEnum(kmp.ident_flags.IDENT_WORK_LOOP),
            .psource = "barrier",
        };
        kmp.barrier(&id, this.global_tid);
    }
};
