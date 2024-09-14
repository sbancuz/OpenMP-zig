const std = @import("std");
const reduce = @import("reduce.zig");
const kmp = @import("kmp.zig");
const in = @import("input_handler.zig");

pub const options = struct {
    return_optional: bool,
    do_copy: bool,
    is_omp_func: bool = false,
};

inline fn no_error(comptime T: type) type {
    comptime {
        const info = @typeInfo(T);
        if (info != .ErrorUnion) {
            return T;
        }

        return info.ErrorUnion.payload;
    }
}

pub inline fn make(
    comptime red: []const reduce.operators,
    comptime f: anytype,
    comptime ret_t: type,
    comptime opts: options,
) type {
    return struct {
        const static = struct {
            var lck: kmp.critical_name_t = @bitCast([_]u8{0} ** 32);
        };

        pub inline fn run(
            pre: anytype,
            args: anytype,
            post: anytype,
            ret_reduction: *ret_t,
        ) if (opts.return_optional) ?ret_t else ret_t {
            const private_copy = if (opts.do_copy) in.make_another(args.private) else args.private;
            const firstprivate_copy = if (opts.do_copy) in.shallow_copy(args.firstprivate) else args.firstprivate;
            const reduction_copy = if (opts.do_copy) in.shallow_copy(args.reduction) else args.reduction;
            const true_args = pre ++ brk: {
                const r = if (opts.do_copy)
                    args.shared ++ private_copy ++ firstprivate_copy ++ reduction_copy
                else
                    .{args};

                break :brk if (opts.is_omp_func) r else .{r};
            } ++ post;

            const ret = @call(.always_inline, f, true_args);

            const id: kmp.ident_t = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "parallel" ++ @typeName(@TypeOf(f)),
            };

            const no_err_ret_t = no_error(ret_t);

            if (red.len > 0 or no_err_ret_t != void) {
                if (no_err_ret_t != void) {
                    // If it's an error_union AND we caught an error just reduce the other parameters that need to be reduced.
                    // This has to happen since once a reduce starts, every thread needs to call the proper kmp function calls
                    // to signal to OMP that the reduce actually happened.
                    //
                    // Also apparently there needs to be the same memory structure for all the reduce args, so we just pass in
                    // fake data that won't do anything
                    var ret_no_err = if (@typeInfo(ret_t) == .ErrorUnion) ret catch |err| {
                        var tmp: no_err_ret_t = undefined;
                        var tmp2: no_err_ret_t = undefined;

                        const reduce_args = if (no_err_ret_t == void) reduction_copy else reduction_copy ++ .{&tmp2};
                        const reduce_dest = if (no_err_ret_t == void) args.reduction else args.reduction ++ .{&tmp};
                        _ = reduce.reduce(&id, true, reduce_dest, reduce_args, red[0 .. red.len - 1] ++ .{.id}, &static.lck);

                        ret_reduction.* = err;
                        return ret_reduction.*;
                    } else ret;

                    // If an error didn't occur then we can just append the return_reduce parameter to the end and proceed normally
                    var tmp: no_err_ret_t = if (@typeInfo(ret_t) != .ErrorUnion) ret_reduction.* else ret_reduction.* catch unreachable;
                    const reduce_args = if (no_err_ret_t == void) reduction_copy else reduction_copy ++ .{&ret_no_err};
                    const reduce_dest = if (no_err_ret_t == void) args.reduction else args.reduction ++ .{&tmp};
                    const has_result = reduce.reduce(&id, true, reduce_dest, reduce_args, red, &static.lck);

                    if (has_result > 0) {
                        ret_reduction.* = tmp;
                        return ret_reduction.*;
                    }
                } else {
                    const has_result = reduce.reduce(&id, true, args.reduction, reduction_copy, red, &static.lck);
                    if (has_result > 0) {
                        return ret_reduction.*;
                    }
                }
            }

            if (ret_t != void) {
                if (opts.return_optional) {
                    return null;
                }
                return ret;
            }
        }
    };
}
