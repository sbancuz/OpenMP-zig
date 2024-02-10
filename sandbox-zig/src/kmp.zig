pub const flags = enum(c_int) {
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

pub const ident_t = extern struct {
    // might be used in fortran, we can just keep it 0
    reserved_1: c_int = 0,
    // flags from above
    flags: c_int = 0,
    reserved_2: c_int = 0,
    reserved_3: c_int = 0x1a,
    psource: [*:0]const u8,
};
pub const kmpc_micro = fn (global_tid: *c_int, bound_tid: *c_int, args: *align(@alignOf(usize)) anyopaque) callconv(.C) void;

extern "C" fn __kmpc_fork_call(name: *ident_t, argc: c_int, fun: *const kmpc_micro, ...) void;
pub fn fork_call(name: *ident_t, argc: c_int, fun: *const kmpc_micro, args: anytype) void {
    __kmpc_fork_call(name, argc, fun, args);
}

extern "C" fn __kmpc_master(loc: *ident_t, global_tid: c_int) c_int;
pub fn master(name: *ident_t, global_tid: c_int) c_int {
    return __kmpc_master(name, global_tid);
}

extern "C" fn __kmpc_end_master(loc: *ident_t, global_tid: c_int) void;
pub fn end_master(name: *ident_t, global_tid: c_int) void {
    __kmpc_end_master(name, global_tid);
}

extern "C" fn __kmpc_single(loc: *ident_t, global_tid: c_int) c_int;
pub fn single(name: *ident_t, global_tid: c_int) c_int {
    return __kmpc_single(name, global_tid);
}

extern "C" fn __kmpc_end_single(loc: *ident_t, global_tid: c_int) void;
pub fn end_single(name: *ident_t, global_tid: c_int) void {
    __kmpc_end_single(name, global_tid);
}

extern "C" fn __kmpc_barrier(loc: *ident_t, global_tid: c_int) void;
pub fn barrier(name: *ident_t, global_tid: c_int) void {
    __kmpc_barrier(name, global_tid);
}

extern "C" fn __kmpc_global_thread_num() c_int;
pub fn get_tid() c_int {
    return __kmpc_global_thread_num();
}

extern "C" fn __kmpc_push_num_threads(loc: *ident_t, global_tid: c_int, num_threads: c_int) void;
pub fn push_num_threads(name: *ident_t, global_tid: c_int, num_threads: c_int) void {
    __kmpc_push_num_threads(name, global_tid, num_threads);
}
