const std = @import("std");
const omp = @import("omp.zig");
const opts = @import("build_options");
const ompt = @import("ompt.zig");

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
    // IDENT_BARRIER_IMPL_FOR = 0x0040,
    IDENT_BARRIER_IMPL = 0x0040,
    IDENT_BARRIER_IMPL_SECTIONS = 0x00C0,

    IDENT_BARRIER_IMPL_SINGLE = 0x0140,
    // IDENT_BARRIER_IMPL_MASK = 0x01C0,
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

// TODO: see this alignment because it seems strange
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
pub const tasking_flags = packed struct {
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

inline fn ifdef(comptime d: bool, t: type) type {
    return if (d) t else void;
}

const cache_line_size = 64;
pub const task_data_t = extern struct {
    td_task_id: c_int, // id, assigned by debugger
    td_flags: tasking_flags, // task flags
    td_team: *anyopaque, // kmp_team_t, // team for this task
    td_alloc_thread: *anyopaque, //   kmp_info_p *td_alloc_thread; // thread that allocated data structures
    // Currently not used except for perhaps IDB

    td_parent: *@This(),
    td_level: c_int,
    td_untied_count: std.atomic.Value(c_int), // untied task active parts counter
    td_ident: *ident_t,
    // Taskwait data.

    td_taskwait_ident: *ident_t,
    td_taskwait_counter: c_int,
    td_taskwait_thread: c_int,
    td_icvs: internal_control align(cache_line_size),
    td_allocated_child_tasks: std.atomic.Value(c_int) align(cache_line_size),
    td_incomplete_child_tasks: std.atomic.Value(c_int),
    //   kmp_taskgroup_t*
    td_taskgroup: *anyopaque, // Each task keeps pointer to its current taskgroup
    //   kmp_dephash_t*
    td_dephash: *anyopaque, // Dependencies for children tasks are tracked from here
    //   kmp_depnode_t*
    td_depnode: *anyopaque, // Pointer to graph node if this task has dependencies
    td_task_team: *anyopaque, // kmp_task_team_t *
    td_size_alloc: usize, // Size of task structure, including shareds etc.
    // 4 or 8 byte integers for the loop bounds in GOMP_taskloop
    td_size_loop_bounds: ifdef(opts.gomp_support, c_int),

    td_last_tied: *@This(), // keep tied task scheduling constraint
    // GOMP sends in a copy function for copy constructors
    td_copy_func: ifdef(opts.gomp_support, *const fn (*anyopaque, *anyopaque) callconv(.C) void),

    td_allow_completion_event: *anyopaque, // kmp_event_t
    ompt_task_info: ifdef(opts.ompt_support, ompt.task_info_t),
    is_taskgraph: ifdef(opts.ompx_support, c_char), // whether the task is within a TDG
    tdg: ifdef(opts.ompx_support, *anyopaque), // kmp_tdg_info_t *// used to associate task with a TDG
    td_target_data: target_data_t,
};

const event_type_t = enum(c_int) {
    KMP_EVENT_UNINITIALIZED = 0,
    KMP_EVENT_ALLOW_COMPLETION = 1,
};

const envent_t = extern struct {
    typ: event_type_t,
    lock: tas_lock,
    task: task_t(void, void),
};
// TODO: SWITCH FOR BIG/LITTLE ENDIAN
const base_tas_lock_t = extern struct {
    // KMP_LOCK_FREE(tas) => unlocked; locked: (gtid+1) of owning thread
    // Flip the ordering of the high and low 32-bit member to be consistent
    // with the memory layout of the address in 64-bit big-endian.
    poll: std.atomic.Value(c_int),
    depth_locked: c_int, // depth locked, for nested locks only
};

const lock_pool_t = extern struct {
    next: *tas_lock, // TODO: This technically is a union of locks, but since I don't want to copy every struct this will suffice
    index: c_int,
};

const tas_lock = union {
    lk: base_tas_lock_t,
    pool: lock_pool_t, // make certain struct is large enough
    lk_align: c_longdouble, // use worst case alignment; no cache line padding
};

const internal_control = extern struct {
    serial_nesting_level: c_char, // /* corresponds to the value of the th_team_serialized field */
    dynamic: c_char, // /* internal control for dynamic adjustment of threads (per thread) */
    bt_set: c_char, // internal control for whether blocktime is explicitly set */
    blocktime: c_int, //* internal control for blocktime */
    bt_intervals: ifdef(opts.kmp_monitor_support, c_int), //* internal control for blocktime intervals */
    nproc: c_int, // internal control for #threads for next parallel region (per //                 thread) */
    thread_limit: c_int, //* internal control for thread-limit-var */
    task_thread_limit: c_int, //; /* internal control for thread-limit-var of a task*/
    max_active_levels: c_int, //; /* internal control for max_active_levels */
    sched: r_sched, //* internal control for runtime schedule {sched,chunk} pair */
    proc_bind: proc_bind_t, //; /* internal control for affinity  */
    default_device: c_int, //* internal control for default device */
    next: *@This(),
};

const proc_bind_t = enum(c_int) {
    proc_bind_false = 0,
    proc_bind_true,
    proc_bind_primary,
    proc_bind_close,
    proc_bind_spread,
    proc_bind_intel, // use KMP_AFFINITY interface
    proc_bind_default,
};

// Technically it's a union but who cares `kmp_r_sched'
const r_sched = isize;

const target_data_t = extern struct {
    async_handle: *anyopaque, // libomptarget async handle for task completion query
};

// This is just the default task struct, since this is polymorphic, just providing the prototype is enough
const kmp_task_t = task_t(void, void, void);

// TODO: Use kmp_task_t and then just cast the types back and forth
extern "omp" fn __kmpc_omp_task(loc_ref: *const ident_t, gtid: c_int, new_task: *anyopaque) c_int;
extern "omp" fn __kmpc_omp_task_begin_if0(loc_ref: *const ident_t, gtid: c_int, new_task: *anyopaque) void;
extern "omp" fn __kmpc_omp_task_complete_if0(loc_ref: *const ident_t, gtid: c_int, new_task: *anyopaque) void;

// Same trick as before, this is not really variadic
extern "omp" fn __kmpc_omp_task_alloc(loc_ref: *const ident_t, gtid: c_int, flags: c_int, sizeof_kmp_task_t: usize, sizeof_shareds: usize, ...) *kmp_task_t;

const opaque_routine_entry_t = *const fn (c_int, *kmp_task_t) callconv(.C) c_int;
const opaque_cmplrdata_t = extern union {
    priority: c_int,
    destructors: opaque_routine_entry_t,
};

pub inline fn promise(comptime ret: type) type {
    return struct {
        const allocator = std.heap.c_allocator;

        result: ret = undefined,
        resolved: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub inline fn init() !*@This() {
            return try allocator.create(@This());
        }

        pub inline fn deinit(self: *@This()) void {
            allocator.free(std.mem.asBytes(self));
        }

        pub fn get(self: *@This()) ret {
            while (self.resolved.cmpxchgStrong(false, true, .seq_cst, .seq_cst)) |val| {
                if (val) break;
                std.atomic.spinLoopHint();
            }

            return self.result;
        }

        pub inline fn release(self: *@This()) void {
            self.resolved.store(true, .release);
        }
    };
}

/// This represents the type `kmp_task_t' or `TaskDescriptorTy' in the source code.
/// It's a polymorphic type that just need `shareds' and `routine' as the preamble to work
/// and then the alloc() will allocate enough space for all the variables that are not explicitally specified
/// in the LLVM source code, like for example the privates here, or part_id
pub inline fn task_t(comptime shareds: type, comptime pri: type, comptime ret: type) type {
    // This is needed because extern structs cannot contain normal structs, but we need
    // the extern struct since it has consitent ABI and won't rearrange the data. This is
    // required for calling the destructor since it's called by C and not by us.
    return extern struct {
        const self_t = @This();
        const routine_entry_t = *const fn (c_int, *self_t) callconv(.C) c_int;
        const cmplrdata_t = extern union {
            priority: c_int,
            destructors: routine_entry_t,
        };

        shareds: *shareds,
        routine: routine_entry_t,
        part_id: c_int,
        data1: cmplrdata_t,
        data2: cmplrdata_t,
        // This can't be a real type since they don't have defined memory structure
        privates: [@sizeOf(pri)]u8,
        result: if (ret == void) void else *promise(ret),

        inline fn outline(comptime f: anytype) type {
            const type_info = @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type.?);

            return opaque {
                pub fn task(gtid: c_int, t: *self_t) callconv(.C) c_int {
                    _ = gtid;

                    const _shareds = t.shareds.*;
                    const _privates: pri = std.mem.bytesAsValue(pri, &t.privates).*;

                    const r = if (type_info == .ErrorUnion)
                        try @call(.always_inline, f, _shareds ++ _privates)
                    else
                        @call(.always_inline, f, _shareds ++ _privates);

                    if (ret != void) {
                        var pro = t.result;
                        pro.result = r;
                    }
                    return 0;
                }
            };
        }

        pub inline fn alloc(
            comptime f: anytype,
            comptime name: *const ident_t,
            gtid: c_int,
            flags: tasking_flags,
        ) *@This() {
            const t = &@This().outline(f).task;
            return @ptrCast(__kmpc_omp_task_alloc(
                name,
                gtid,
                @bitCast(flags),
                @sizeOf(@This()),
                @sizeOf(@TypeOf(shareds)),
                t,
            ));
        }

        pub inline fn set_data(self: *@This(), sh: *shareds, pr: pri) void {
            self.shareds = sh;
            self.privates = std.mem.toBytes(pr);
        }

        pub inline fn make_promise(self: *@This(), pro: *promise(ret)) void {
            const head = self.get_header();
            self.result = pro;
            head.td_flags.destructors_thunk = 1;

            self.data1.destructors = &opaque {
                pub fn notify(gtid: c_int, t: *self_t) callconv(.C) c_int {
                    _ = gtid;

                    t.result.release();
                    return 0;
                }
            }.notify;
        }

        pub inline fn set_priority(self: *@This(), priority: c_int) void {
            self.data2.priority = priority;
            @panic("TODO");
        }

        pub inline fn task(self: *@This(), comptime name: *const ident_t, gtid: c_int) c_int {
            return __kmpc_omp_task(name, gtid, self);
        }

        pub inline fn begin_if0(self: *@This(), comptime name: *const ident_t, gtid: c_int) void {
            __kmpc_omp_task_begin_if0(name, gtid, self);
        }

        pub inline fn complete_if0(self: *@This(), comptime name: *const ident_t, gtid: c_int) void {
            __kmpc_omp_task_complete_if0(name, gtid, self);
        }

        pub inline fn get_header(self: *@This()) *task_data_t {
            const ptr = @intFromPtr(self) - @sizeOf(task_data_t);
            return @ptrFromInt(ptr);
        }
    };
}

extern "omp" fn __kmpc_omp_taskyield(loc_ref: *const ident_t, gtid: c_int, end_part: c_int) c_int;
pub inline fn taskyield(comptime name: *const ident_t, gtid: c_int) c_int {
    // Not really sure what end_part is, so always set it to 0. Even whithin the runtime it's used only in logging
    return __kmpc_omp_taskyield(name, gtid, 0);
}

extern "omp" fn __kmpc_omp_taskwait(loc_ref: *const ident_t, gtid: c_int) c_int;
pub inline fn taskwait(comptime name: *const ident_t, gtid: c_int) c_int {
    return __kmpc_omp_taskwait(name, gtid);
}
// extern "omp" fn __kmpc_omp_target_task_alloc(loc_ref: *const ident_t, gtid: c_int, flags: c_int, sizeof_kmp_task_t: usize, sizeof_shareds: usize, task_entry: kmp_routine_entry_t, device_id: i64) *kmp_task_t;
// pub inline fn target_task_alloc(comptime name: *const ident_t, gtid: c_int, flags: kmp_tasking_flags, sizeof_kmp_task_t: usize, sizeof_shareds: usize, task_entry: kmp_routine_entry_t, device_id: i64) *kmp_task_t {
//     return __kmpc_omp_target_task_alloc(name, gtid, flags, sizeof_kmp_task_t, sizeof_shareds, task_entry, device_id);
// }
//

// extern "omp" fn __kmpc_omp_task_parts(loc_ref: *const ident_t, gtid: c_int, new_task: *kmp_task_t, part: *kmp_task_t) c_int;
// pub inline fn task_parts(comptime name: *const ident_t, gtid: c_int, new_task: *kmp_task_t, part: *kmp_task_t) c_int {
//     return __kmpc_omp_task_parts(name, gtid, new_task, part);
// }
//

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
    none = 10,
    id = 11,
    custom = 12,
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
