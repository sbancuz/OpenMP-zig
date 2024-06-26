const std = @import("std");
const omp = @import("omp.zig");

pub const ident_flags = enum(c_int) {
    // /*! Use trampoline for internal microtasks */
    IDENT_IMB = 0x01,
    // /*! Use c-style ident structure */
    IDENT_KMPC = 0x02,
    // /* 0x04 is no longer used */
    // /*! Entry point generated by auto-parallelization */
    IDENT_AUTOPAR = 0x08,
    // /*! Compiler generates atomic reduction option for kmpc_reduce* */
    IDENT_ATOMIC_REDUCE = 0x10,
    // /*! To mark a 'barrier' directive in user code */
    IDENT_BARRIER_EXPL = 0x20,
    // /*! To Mark implicit barriers. */
    IDENT_BARRIER_IMPL = 0x0040,
    // IDENT_BARRIER_IMPL_MASK = 0x01C0,
    // IDENT_BARRIER_IMPL_FOR = 0x0040,
    IDENT_BARRIER_IMPL_SECTIONS = 0x00C0,

    IDENT_BARRIER_IMPL_SINGLE = 0x0140,
    IDENT_BARRIER_IMPL_WORKSHARE = 0x01C0,

    // /*! To mark a static loop in OMPT callbacks */
    IDENT_WORK_LOOP = 0x200,
    // /*! To mark a sections directive in OMPT callbacks */
    IDENT_WORK_SECTIONS = 0x400,
    // /*! To mark a distribute construct in OMPT callbacks */
    IDENT_WORK_DISTRIBUTE = 0x800,
    // /*! Atomic hint; bottom four bits as omp_sync_hint_t. Top four reserved and
    //     not currently used. If one day we need more bits, then we can use
    //     an invalid combination of hints to mean that another, larger field
    //     should be used in a different flag. */
    // IDENT_ATOMIC_HINT_MASK = 0xFF0000,
    // IDENT_ATOMIC_HINT_UNCONTENDED = 0x010000,
    // IDENT_ATOMIC_HINT_CONTENDED = 0x020000,
    // IDENT_ATOMIC_HINT_NONSPECULATIVE = 0x040000,
    // IDENT_ATOMIC_HINT_SPECULATIVE = 0x080000,
    // IDENT_OPENMP_SPEC_VERSION_MASK = 0xFF000000,
};

pub const sched_t = enum(c_int) {
    StaticChunked = 33,
    StaticNonChunked = 34,
    Dynamic = 35,
    Guided = 36,
    Runtime = 37,
};

pub const ident_t = extern struct {
    // might be used in fortran, we can just keep it 0
    reserved_1: c_int = 0,
    // flags from above
    flags: c_int = 0,
    reserved_2: c_int = 0,
    reserved_3: c_int = 35,
    psource: [*:0]const u8,
};

pub const kmpc_micro_t = fn (global_tid: *c_int, bound_tid: *c_int, args: *align(@alignOf(usize)) anyopaque) callconv(.C) void;

extern "omp" fn __kmpc_fork_call(name: *const ident_t, argc: c_int, fun: *const kmpc_micro_t, ...) void;
pub inline fn fork_call(comptime name: *const ident_t, argc: c_int, fun: *const kmpc_micro_t, args: anytype) void {
    __kmpc_fork_call(name, argc, fun, args);
}
// it's not really variadic, so make sure to pass only one argument
extern "omp" fn __kmpc_fork_call_if(name: *const ident_t, argc: c_int, fun: *const kmpc_micro_t, cond: c_int, ...) void;
pub inline fn fork_call_if(comptime name: *const ident_t, argc: c_int, fun: *const kmpc_micro_t, cond: c_int, args: anytype) void {
    __kmpc_fork_call_if(name, argc, fun, cond, args);
}

extern "omp" fn __kmpc_for_static_init_4(loc: *const ident_t, gtid: c_int, schedtype: c_int, plastiter: *c_int, plower: *c_int, pupper: *c_int, pstride: *c_int, incr: c_int, chunk: c_int) void;
extern "omp" fn __kmpc_for_static_init_4u(loc: *const ident_t, gtid: c_int, schedtype: c_int, plastiter: *c_int, plower: *c_uint, pupper: *c_uint, pstride: *c_int, incr: c_int, chunk: c_int) void;
extern "omp" fn __kmpc_for_static_init_8(loc: *const ident_t, gtid: c_int, schedtype: c_int, plastiter: *c_int, plower: *c_long, pupper: *c_long, pstride: *c_long, incr: c_long, chunk: c_long) void;
extern "omp" fn __kmpc_for_static_init_8u(loc: *const ident_t, gtid: c_int, schedtype: c_int, plastiter: *c_int, plower: *c_ulong, pupper: *c_ulong, pstride: *c_long, incr: c_long, chunk: c_long) void;
pub inline fn for_static_init(comptime T: type, comptime loc: *const ident_t, gtid: c_int, schedtype: sched_t, plastiter: *c_int, plower: *T, pupper: *T, pstride: *T, incr: T, chunk: T) void {
    if (@typeInfo(T).Int.signedness == .signed)
        if (@typeInfo(T).Int.bits <= 32) {
            __kmpc_for_static_init_4(loc, gtid, @intFromEnum(schedtype), plastiter, @ptrCast(plower), @ptrCast(pupper), @ptrCast(pstride), @bitCast(incr), @bitCast(chunk));
        } else if (@typeInfo(T).Int.bits <= 64) {
            __kmpc_for_static_init_8(loc, gtid, @intFromEnum(schedtype), plastiter, @ptrCast(plower), @ptrCast(pupper), @ptrCast(pstride), @bitCast(incr), @bitCast(chunk));
        } else {
            @compileError("Unsupported integer size");
        }
    else if (@typeInfo(T).Int.signedness == .unsigned) {
        if (@typeInfo(T).Int.bits <= 32) {
            __kmpc_for_static_init_4u(loc, gtid, @intFromEnum(schedtype), plastiter, @ptrCast(plower), @ptrCast(pupper), @ptrCast(pstride), @bitCast(incr), @bitCast(chunk));
        } else if (@typeInfo(T).Int.bits <= 64) {
            __kmpc_for_static_init_8u(loc, gtid, @intFromEnum(schedtype), plastiter, @ptrCast(plower), @ptrCast(pupper), @ptrCast(pstride), @bitCast(incr), @bitCast(chunk));
        } else {
            @compileError("Unsupported unsigned integer size");
        }
    } else {
        unreachable;
    }
}

extern "omp" fn __kmpc_for_static_fini(loc: *const ident_t, global_tid: c_int) void;
pub inline fn for_static_fini(comptime name: *const ident_t, global_tid: c_int) void {
    __kmpc_for_static_fini(name, global_tid);
}

extern "omp" fn __kmpc_dispatch_init_4(loc: *const ident_t, gtid: c_int, schedule: c_int, lb: c_int, ub: c_int, st: c_int, chunk: c_int) void;
extern "omp" fn __kmpc_dispatch_init_4u(loc: *const ident_t, gtid: c_int, schedule: c_int, lb: c_uint, ub: c_uint, st: c_int, chunk: c_int) void;
extern "omp" fn __kmpc_dispatch_init_8(loc: *const ident_t, gtid: c_int, schedule: c_int, lb: c_long, ub: c_long, st: c_long, chunk: c_long) void;
extern "omp" fn __kmpc_dispatch_init_8u(loc: *const ident_t, gtid: c_int, schedule: c_int, lb: c_ulong, ub: c_ulong, st: c_long, chunk: c_long) void;
pub inline fn dispatch_init(comptime T: type, comptime loc: *const ident_t, gtid: c_int, schedule: sched_t, lb: T, ub: T, st: T, chunk: T) void {
    if (@typeInfo(T).Int.signedness == .signed) {
        if (@typeInfo(T).Int.bits <= 32) {
            __kmpc_dispatch_init_4(loc, gtid, @intFromEnum(schedule), @intCast(lb), @intCast(ub), @intCast(st), @intCast(chunk));
        } else if (@typeInfo(T).Int.bits <= 64) {
            __kmpc_dispatch_init_8(loc, gtid, @intFromEnum(schedule), @intCast(lb), @intCast(ub), @intCast(st), @intCast(chunk));
        } else {
            @compileError("Unsupported integer size");
        }
    } else if (@typeInfo(T).Int.signedness == .unsigned) {
        if (@typeInfo(T).Int.bits <= 32) {
            __kmpc_dispatch_init_4u(loc, gtid, @intFromEnum(schedule), @intCast(lb), @intCast(ub), @intCast(st), @intCast(chunk));
        } else if (@typeInfo(T).Int.bits <= 64) {
            __kmpc_dispatch_init_8u(loc, gtid, @intFromEnum(schedule), @intCast(lb), @intCast(ub), @intCast(st), @intCast(chunk));
        } else {
            @compileError("Unsupported unsigned integer size");
        }
    } else {
        unreachable;
    }
}

extern "omp" fn __kmpc_dispatch_next_4(loc: *const ident_t, gtid: c_int, p_last: *c_int, p_lb: *c_int, p_ub: *c_int, p_st: *c_int) c_int;
extern "omp" fn __kmpc_dispatch_next_4u(loc: *const ident_t, gtid: c_int, p_last: *c_int, p_lb: *c_uint, p_ub: *c_uint, p_st: *c_int) c_int;
extern "omp" fn __kmpc_dispatch_next_8(loc: *const ident_t, gtid: c_int, p_last: *c_int, p_lb: *c_long, p_ub: *c_long, p_st: *c_long) c_int;
extern "omp" fn __kmpc_dispatch_next_8u(loc: *const ident_t, gtid: c_int, p_last: *c_int, p_lb: *c_ulong, p_ub: *c_ulong, p_st: *c_long) c_int;
pub inline fn dispatch_next(comptime T: type, comptime loc: *const ident_t, gtid: c_int, p_last: *c_int, p_lb: *T, p_ub: *T, p_st: *T) c_int {
    if (std.meta.trait.issingedInt(T)) {
        if (@typeInfo(T).Int.bits <= 32) {
            return __kmpc_dispatch_next_4(loc, gtid, p_last, @ptrCast(p_lb), @ptrCast(p_ub), @ptrCast(p_st));
        } else if (@typeInfo(T).Int.bits <= 64) {
            return __kmpc_dispatch_next_8(loc, gtid, p_last, @ptrCast(p_lb), @ptrCast(p_ub), @ptrCast(p_st));
        } else {
            @compileError("Unsupported integer size");
        }
    } else if (std.meta.trait.isUnsignedInt(T)) {
        if (@typeInfo(T).Int.bits <= 32) {
            return __kmpc_dispatch_next_4u(loc, gtid, p_last, @ptrCast(p_lb), @ptrCast(p_ub), @ptrCast(p_st));
        } else if (@typeInfo(T).Int.bits <= 64) {
            return __kmpc_dispatch_next_8u(loc, gtid, p_last, @ptrCast(p_lb), @ptrCast(p_ub), @ptrCast(p_st));
        } else {
            @compileError("Unsupported unsigned integer size");
        }
    } else {
        unreachable;
    }
}

extern "omp" fn __kmpc_dispatch_fini_4(loc: *const ident_t, gtid: c_int) void;
extern "omp" fn __kmpc_dispatch_fini_4u(loc: *const ident_t, gtid: c_int) void;
extern "omp" fn __kmpc_dispatch_fini_8(loc: *const ident_t, gtid: c_int) void;
extern "omp" fn __kmpc_dispatch_fini_8u(loc: *const ident_t, gtid: c_int) void;
pub inline fn dispatch_fini(comptime T: type, comptime loc: *const ident_t, gtid: c_int) void {
    if (@typeInfo(T).Int.signedness == .signed) {
        if (@typeInfo(T).Int.bits <= 32) {
            __kmpc_dispatch_fini_4(loc, gtid);
        } else if (@typeInfo(T).Int.bits <= 64) {
            __kmpc_dispatch_fini_8(loc, gtid);
        } else {
            @compileError("Unsupported integer size");
        }
    } else if (@typeInfo(T).Int.signedness == .unsigned) {
        if (@typeInfo(T).Int.bits <= 32) {
            __kmpc_dispatch_fini_4u(loc, gtid);
        } else if (@typeInfo(T).Int.bits <= 64) {
            __kmpc_dispatch_fini_8u(loc, gtid);
        } else {
            @compileError("Unsupported unsigned integer size");
        }
    } else {
        unreachable;
    }
}

extern "omp" fn __kmpc_ordered(loc: *const ident_t, global_tid: c_int) void;
pub inline fn ordered(comptime name: *const ident_t, global_tid: c_int) void {
    __kmpc_ordered(name, global_tid);
}

extern "omp" fn __kmpc_end_ordered(loc: *const ident_t, global_tid: c_int) void;
pub inline fn end_ordered(comptime name: *const ident_t, global_tid: c_int) void {
    __kmpc_end_ordered(name, global_tid);
}

extern "omp" fn __kmpc_masked(loc: *const ident_t, global_tid: c_int, filter: c_int) c_int;
pub inline fn masked(comptime name: *const ident_t, global_tid: c_int, filter: c_int) c_int {
    return __kmpc_masked(name, global_tid, filter);
}

extern "omp" fn __kmpc_end_masked(loc: *const ident_t, global_tid: c_int) void;
pub inline fn end_masked(comptime name: *const ident_t, global_tid: c_int) void {
    __kmpc_end_masked(name, global_tid);
}

extern "omp" fn __kmpc_single(loc: *const ident_t, global_tid: c_int) c_int;
pub inline fn single(comptime name: *const ident_t, global_tid: c_int) c_int {
    return __kmpc_single(name, global_tid);
}

extern "omp" fn __kmpc_end_single(loc: *const ident_t, global_tid: c_int) void;
pub inline fn end_single(comptime name: *const ident_t, global_tid: c_int) void {
    __kmpc_end_single(name, global_tid);
}

extern "omp" fn __kmpc_barrier(loc: *const ident_t, global_tid: c_int) void;
pub inline fn barrier(comptime name: *const ident_t, global_tid: c_int) void {
    __kmpc_barrier(name, global_tid);
}

extern "omp" fn __kmpc_global_thread_num() c_int;
pub inline fn get_tid() c_int {
    return __kmpc_global_thread_num();
}

extern "omp" fn __kmpc_push_num_threads(loc: *const ident_t, global_tid: c_int, num_threads: c_int) void;
pub inline fn push_num_threads(comptime name: *const ident_t, global_tid: c_int, num_threads: c_int) void {
    __kmpc_push_num_threads(name, global_tid, num_threads);
}

pub const critical_name_t = [8]c_int; // This seems to be just a lock, so I give up on ever using it
extern "omp" fn __kmpc_critical_with_hint(loc: *const ident_t, global_tid: c_int, crit: *critical_name_t, hint: c_int) void;
pub inline fn critical(comptime loc: *const ident_t, global_tid: c_int, crit: *critical_name_t, hint: c_int) void {
    __kmpc_critical_with_hint(loc, global_tid, crit, hint);
}

extern "omp" fn __kmpc_end_critical(loc: *const ident_t, global_tid: c_int, crit: *critical_name_t) void;
pub inline fn critical_end(comptime loc: *const ident_t, global_tid: c_int, crit: *critical_name_t) void {
    __kmpc_end_critical(loc, global_tid, crit);
}

extern "omp" fn __kmpc_flush(loc: *const ident_t) void;
pub inline fn flush(comptime name: *const ident_t) void {
    __kmpc_flush(name);
}
// Todo: invert for big endian
const kmp_tasking_flags = packed struct {
    tiedness: u1 = 0, // task is either tied (1) or untied (0) */
    final: u1 = 0, // task is final(1) so execute immediately */
    merged_if0: u1 = 0, // no __kmpc_task_{begin/complete}_if0 calls in if0               code path */
    destructors_thunk: u1 = 0, // set if the compiler creates a thunk toinvoke destructors from the runtime */
    proxy: u1 = 0, // task is a proxy task (it will be executed outside thecontext of the RTL) */
    priority_specified: u1 = 0, // set if the compiler provides priority setting for the task */
    detachable: u1 = 0, // 1 == can detach */
    hidden_helper: u1 = 0, // 1 == hidden helper task */
    reserved: u8 = 0, // reserved for compiler use */

    // Library flags */ /* Total library flags must be 1 = 0,6 bits */
    tasktype: u1 = 0, // task is either explicit(1) or implicit (0) */
    task_serial: u1 = 0, // task is executed immediately (1) or deferred (0)
    tasking_ser: u1 = 0, // all tasks in team are either executed immediately
    // (1 = 0,) or may be deferred (0)
    team_serial: u1 = 0, // entire team is serial (1) [1 thread] or parallel
    // (0) [>= 2 threads]
    // If either team_serial or tasking_ser is set = 0, task team may be NULL */
    // Task State Flags: u*/
    started: u1 = 0, // 1==started, 0==not started     */
    executing: u1 = 0, // 1==executing, 0==not executing */
    complete: u1 = 0, // 1==complete, 0==not complete   */
    freed: u1 = 0, // 1==freed, 0==allocated        */
    native: u1 = 0, // 1==gcc-compiled task, 0==intel */
    onced: u1 = 0, // 1==ran once already, 0==never ran, record & replay purposes */
    reserved31: u6 = 0, // reserved for library use */
};
const kmp_routine_entry_t = *const fn (c_int, *anyopaque) callconv(.C) c_int;
pub const kmp_task_t = extern struct {
    shareds: *anyopaque,
    routine: kmp_routine_entry_t,
    part_id: c_int,
    data1: kmp_routine_entry_t,
    data2: kmp_routine_entry_t,
};

inline fn task_outline(comptime f: anytype, comptime ret_type: type) type {
    return opaque {
        /// This comes from decompiling the outline with ghidra
        /// It should never really change since it's just a wrapper around the actual function
        /// and it can't inline anything even if it wanted to
        ///
        /// remember to update the size_in_release_debug if the function changes, can't really enforce it though
        const size_in_release_debug = 42;
        noinline fn task(gtid: c_int, pass: *ret_type) callconv(.C) c_int {
            _ = gtid;

            // TODO: CHECK WITH GHIDRA THE NEW SIZE
            const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);
            if (type_info == .ErrorUnion) {
                pass.ret = try @call(.never_inline, f, pass.args);
            } else {
                pass.ret = @call(.never_inline, f, pass.args);
            }
            return 0;
        }
    };
}
extern "omp" fn __kmpc_omp_task(loc_ref: *const ident_t, gtid: c_int, new_task: *kmp_task_t) c_int;
pub inline fn task(comptime name: *const ident_t, gtid: c_int, new_task: *kmp_task_t) c_int {
    return __kmpc_omp_task(name, gtid, new_task);
}

// Same trick as before, this is not really variadic
extern "omp" fn __kmpc_omp_task_alloc(loc_ref: *const ident_t, gtid: c_int, flags: c_int, sizeof_kmp_task_t: usize, sizeof_shareds: usize, ...) *kmp_task_t;
pub inline fn task_alloc(comptime name: *const ident_t, gtid: c_int, flags: kmp_tasking_flags, sizeof_kmp_task_t: usize, sizeof_shareds: usize, task_entry: anytype) *kmp_task_t {
    return __kmpc_omp_task_alloc(name, gtid, @bitCast(flags), sizeof_kmp_task_t, sizeof_shareds, task_entry);
}

extern "omp" fn __kmpc_omp_taskyield(loc_ref: *const ident_t, gtid: c_int, end_part: c_int) c_int;
pub inline fn taskyield(comptime name: *const ident_t, gtid: c_int) c_int {
    // Not really sure what end_part is, so always set it to 0. Even whithin the runtime it's used only in logging
    return __kmpc_omp_taskyield(name, gtid, 0);
}
// extern "omp" fn __kmpc_omp_target_task_alloc(loc_ref: *const ident_t, gtid: c_int, flags: c_int, sizeof_kmp_task_t: usize, sizeof_shareds: usize, task_entry: kmp_routine_entry_t, device_id: i64) *kmp_task_t;
// pub inline fn target_task_alloc(comptime name: *const ident_t, gtid: c_int, flags: kmp_tasking_flags, sizeof_kmp_task_t: usize, sizeof_shareds: usize, task_entry: kmp_routine_entry_t, device_id: i64) *kmp_task_t {
//     return __kmpc_omp_target_task_alloc(name, gtid, flags, sizeof_kmp_task_t, sizeof_shareds, task_entry, device_id);
// }
//
// extern "omp" fn __kmpc_omp_task_begin_if0(loc_ref: *const ident_t, gtid: c_int, new_task: *kmp_task_t) void;
// pub inline fn task_begin_if0(comptime name: *const ident_t, gtid: c_int, new_task: *kmp_task_t) void {
//     __kmpc_omp_task_begin_if0(name, gtid, new_task);
// }
//
// extern "omp" fn __kmpc_omp_task_complete_if0(loc_ref: *const ident_t, gtid: c_int, new_task: *kmp_task_t) void;
// pub inline fn task_complete_if0(comptime name: *const ident_t, gtid: c_int, new_task: *kmp_task_t) void {
//     __kmpc_omp_task_complete_if0(name, gtid, new_task);
// }
//
// extern "omp" fn __kmpc_omp_task_parts(loc_ref: *const ident_t, gtid: c_int, new_task: *kmp_task_t, part: *kmp_task_t) c_int;
// pub inline fn task_parts(comptime name: *const ident_t, gtid: c_int, new_task: *kmp_task_t, part: *kmp_task_t) c_int {
//     return __kmpc_omp_task_parts(name, gtid, new_task, part);
// }
//
// extern "omp" fn __kmpc_omp_taskwait(loc_ref: *const ident_t, gtid: c_int) c_int;
// pub inline fn taskwait(comptime name: *const ident_t, gtid: c_int) c_int {
//     return __kmpc_omp_taskwait(name, gtid);
// }
//
// extern "omp" fn __kmpc_omp_taskyield(loc_ref: *const ident_t, gtid: c_int, end_part: c_int) c_int;
// pub inline fn taskyield(comptime name: *const ident_t, gtid: c_int, end_part: c_int) c_int {
//     return __kmpc_omp_taskyield(name, gtid, end_part);
// }

pub const reduction_operators = enum(c_int) {
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
};

pub inline fn create_reduce(
    comptime types: []const std.builtin.Type.StructField,
    comptime reduce_operators: []const reduction_operators,
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
                    }
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
                    }
                }
            }
        }

        fn f(
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
                }
            }
        }
    };
}

extern "omp" fn __kmpc_reduce_nowait(
    loc: *const ident_t,
    global_tid: c_int,
    num_vars: c_int,
    reduce_size: usize,
    reduce_data: *anyopaque,
    reduce_func: *const fn (*anyopaque, *anyopaque) callconv(.C) void,
    lck: *critical_name_t,
) c_int;
/// This call il synchronized and will only occur in the main thread, so we don't need to worry about the reduce_func being called concurrently or use atomics
pub inline fn reduce_nowait(
    comptime types: []const std.builtin.Type.StructField,
    comptime loc: *const ident_t,
    global_tid: c_int,
    num_vars: c_int,
    reduce_size: usize,
    reduce_data: *anyopaque,
    comptime reduce_operators: []const reduction_operators,
    lck: *critical_name_t,
) c_int {
    const reduce_t = create_reduce(types, reduce_operators);
    return __kmpc_reduce_nowait(loc, global_tid, num_vars, reduce_size, reduce_data, reduce_t.f, lck);
}

extern "omp" fn __kmpc_end_reduce_nowait(loc: *const ident_t, global_tid: c_int, lck: *critical_name_t) void;
pub inline fn end_reduce_nowait(comptime loc: *const ident_t, global_tid: c_int, lck: *critical_name_t) void {
    __kmpc_end_reduce_nowait(loc, global_tid, lck);
}

extern "omp" fn __kmpc_reduce(
    loc: *const ident_t,
    global_tid: c_int,
    num_vars: c_int,
    reduce_size: usize,
    reduce_data: *anyopaque,
    reduce_func: *const fn (*anyopaque, *anyopaque) callconv(.C) void,
    lck: *critical_name_t,
) c_int;
/// This call il synchronized and will only occur in the main thread, so we don't need to worry about the reduce_func being called concurrently or use atomics
pub inline fn reduce(
    comptime types: []const std.builtin.Type.StructField,
    comptime loc: *const ident_t,
    global_tid: c_int,
    num_vars: c_int,
    reduce_size: usize,
    reduce_data: *anyopaque,
    comptime reduce_operators: []const reduction_operators,
    lck: *critical_name_t,
) c_int {
    const reduce_t = create_reduce(types, reduce_operators);
    return __kmpc_reduce(loc, global_tid, num_vars, reduce_size, reduce_data, reduce_t.f, lck);
}

extern "omp" fn __kmpc_end_reduce(loc: *const ident_t, global_tid: c_int, lck: *critical_name_t) void;
pub inline fn end_reduce(comptime loc: *const ident_t, global_tid: c_int, lck: *critical_name_t) void {
    __kmpc_end_reduce(loc, global_tid, lck);
}
extern "omp" fn __kmpc_push_proc_bind(loc: *const ident_t, global_tid: c_int, proc_bind: c_int) void;
pub inline fn push_proc_bind(comptime loc: *const ident_t, global_tid: c_int, proc_bind: omp.proc_bind) void {
    __kmpc_push_proc_bind(loc, global_tid, @intFromEnum(proc_bind));
}
