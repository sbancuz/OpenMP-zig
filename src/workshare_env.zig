const reduce = @import("reduce.zig");
const kmp = @import("kmp.zig");
const in = @import("input_handler.zig");

pub const options = struct {
    return_optional: bool,
    do_copy: bool,
    is_omp_func: bool = false,
};

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

            var ret = if (@typeInfo(ret_t) == .ErrorUnion)
                @call(.always_inline, f, true_args) catch |err| err
            else
                @call(.always_inline, f, true_args);

            const id: kmp.ident_t = .{
                .flags = @intFromEnum(kmp.ident_flags.IDENT_KMPC),
                .psource = "parallel" ++ @typeName(@TypeOf(f)),
            };

            if (red.len > 0 or ret_t != void) {
                if (ret_t != void) {
                    // TODO: Figure out why do I need to do this... I feel like something in the comptime eval is broken
                    var sus = ret_reduction.*;
                    const reduce_args = if (ret_t == void) reduction_copy else reduction_copy ++ .{&ret};
                    const reduce_dest = if (ret_t == void) args.reduction else args.reduction ++ .{&sus};
                    const has_result = reduce.reduce(&id, true, reduce_dest, reduce_args, red, &static.lck);

                    if (has_result > 0) {
                        ret_reduction.* = sus;
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
