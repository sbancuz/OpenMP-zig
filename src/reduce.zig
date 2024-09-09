const kmp = @import("kmp.zig");
const std = @import("std");

pub const operators = enum(c_int) {
    plus = 0,
    mult = 1,
    minus = 2,
    bitwise_and = 3,
    bitwise_or = 4,
    bitwise_xor = 5,
    logical_and = 6,
    logical_or = 7,
    max = 8,
    min = 9,
    none = 10,
    id = 11,
    custom = 12,
};

pub inline fn reduce(
    comptime id: *const kmp.ident_t,
    comptime nowait: bool,
    out_reduction: anytype,
    copies: @TypeOf(out_reduction),
    comptime ops: []const operators,
    lck: *kmp.critical_name_t,
) c_int {
    const reduction_funcs = create(@typeInfo(@TypeOf(out_reduction)).Struct.fields, ops);
    const kmpc_reduce = if (nowait)
        kmp.reduce_nowait
    else
        kmp.reduce;

    const num_vars = copies.len;
    const reduce_size = @sizeOf(@TypeOf(out_reduction));

    const has_data = kmpc_reduce(
        id,
        kmp.ctx.global_tid,
        num_vars,
        reduce_size,
        @ptrCast(@constCast(&copies)),
        reduction_funcs.for_omp,
        lck,
    );

    switch (has_data) {
        1 => {
            reduction_funcs.finalize(out_reduction, copies);
            const end_id = comptime .{
                .flags = id.*.flags,
                .psource = id.*.psource,
                .reserved_3 = 0x1c,
            };
            kmp.end_reduce_nowait(&end_id, kmp.ctx.global_tid, lck);
        },
        2 => {
            reduction_funcs.finalize_atomic(out_reduction, copies);
        },
        else => {},
    }

    return has_data;
}

pub inline fn create(
    comptime types: []const std.builtin.Type.StructField,
    comptime reduce_operators: []const operators,
) type {
    if (types.len != reduce_operators.len) {
        @compileError("The number of types and operators must match");
    }

    return struct {
        pub inline fn finalize(
            lhs: anytype,
            rhs: @TypeOf(lhs),
        ) void {
            inline for (lhs, rhs) |l, r| {
                inline for (reduce_operators) |op| {
                    switch (op) {
                        .plus => {
                            l.* += r.*;
                        },
                        .mult => {
                            l.* *= r.*;
                        },
                        .minus => {
                            l.* -= r.*;
                        },
                        .bitwise_and => {
                            l.* &= r.*;
                        },
                        .bitwise_or => {
                            l.* |= r.*;
                        },
                        .bitwise_xor => {
                            l.* ^= r.*;
                        },
                        .logical_and => {
                            l.* = l.* and r.*;
                        },
                        .logical_or => {
                            l.* = l.* or r.*;
                        },
                        .max => {
                            l.* = @max(l.*, r.*);
                        },
                        .min => {
                            l.* = @min(l.*, r.*);
                        },
                        .id => {},
                        .custom => l.reduce(r.*),
                        .none => {
                            @compileError("Specify the reduction operator");
                        },
                    }
                }
            }
        }

        pub inline fn single(
            lhs: anytype,
            rhs: @TypeOf(lhs.*),
        ) void {
            inline for (reduce_operators) |op| {
                switch (op) {
                    .plus => {
                        lhs.* += rhs;
                    },
                    .mult => {
                        lhs.* *= rhs;
                    },
                    .minus => {
                        lhs.* -= rhs;
                    },
                    .bitwise_and => {
                        lhs.* &= rhs;
                    },
                    .bitwise_or => {
                        lhs.* |= rhs;
                    },
                    .bitwise_xor => {
                        lhs.* ^= rhs;
                    },
                    .logical_and => {
                        lhs.* = lhs.* and rhs;
                    },
                    .logical_or => {
                        lhs.* = lhs.* or rhs;
                    },
                    .max => {
                        lhs.* = @max(lhs.*, rhs);
                    },
                    .min => {
                        lhs.* = @min(lhs.*, rhs);
                    },
                    .custom => lhs.reduce(rhs.*),
                    .id => {},
                    .none => {},
                }
            }
        }
        pub inline fn finalize_atomic(
            lhs: anytype,
            rhs: @TypeOf(lhs),
        ) void {
            inline for (lhs, rhs) |l, r| {
                inline for (reduce_operators, types) |op, type_field| {
                    const T = @typeInfo(type_field.type).Pointer.child;
                    switch (op) {
                        .plus => {
                            _ = @atomicRmw(T, l, .Add, r.*, .acq_rel);
                        },
                        .mult => {
                            _ = @atomicRmw(T, l, .Mul, r.*, .acq_rel);
                        },
                        .minus => {
                            _ = @atomicRmw(T, l, .Sub, r.*, .acq_rel);
                        },
                        .bitwise_and => {
                            _ = @atomicRmw(T, l, .And, r.*, .acq_rel);
                        },
                        .bitwise_or => {
                            _ = @atomicRmw(T, l, .Or, r.*, .acq_rel);
                        },
                        .bitwise_xor => {
                            _ = @atomicRmw(T, l, .Xor, r.*, .acq_rel);
                        },
                        .logical_and => {
                            _ = @atomicRmw(T, l, .And, r.*, .acq_rel);
                        },
                        .logical_or => {
                            _ = @atomicRmw(T, l, .Or, r.*, .acq_rel);
                        },
                        .max => {
                            _ = @atomicRmw(T, l, .Max, r.*, .acq_rel);
                        },
                        .min => {
                            _ = @atomicRmw(T, l, .Min, r.*, .acq_rel);
                        },
                        .custom => l.atomic_reduce(r.*),
                        .id => {},
                        .none => {
                            @compileError("Specify the reduction operator");
                        },
                    }
                }
            }
        }

        fn for_omp(
            lhs: *anyopaque,
            rhs: *anyopaque,
        ) callconv(.C) void {
            inline for (reduce_operators, types) |op, T| {
                switch (op) {
                    .plus => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* += @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .mult => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* *= @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .minus => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* -= @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .bitwise_and => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* &= @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .bitwise_or => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* |= @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .bitwise_xor => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* ^= @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .logical_and => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* = l.* and @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .logical_or => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* = l.* or @as(*T.type, @ptrCast(@alignCast(rhs))).*.*;
                    },
                    .max => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* = @max(l.*, @as(*T.type, @ptrCast(@alignCast(rhs))).*.*);
                    },
                    .min => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.* = @min(l.*, @as(*T.type, @ptrCast(@alignCast(rhs))).*.*);
                    },
                    .custom => {
                        const l = @as(*T.type, @ptrCast(@alignCast(lhs))).*;
                        l.reduce(@as(*T.type, @ptrCast(@alignCast(rhs))).*.*);
                    },
                    .id => {},
                    .none => {
                        @compileError("Specify the reduction operator");
                    },
                }
            }
        }
    };
}
