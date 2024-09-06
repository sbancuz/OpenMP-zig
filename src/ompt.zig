const opts = @import("build_options");
const kmp = @import("kmp.zig");

pub const data_t = extern union {
    val: usize,
    ptr: *anyopaque,
};

pub const frame_t = extern struct {
    exit_frame: data_t,
    enter_frame: data_t,
    exit_frame_flags: c_int,
    enter_frame_flags: c_int,
};

pub const dispatch_chunk_t = extern struct {
    start: usize,
    iterations: usize,
};

pub const task_info_t = extern struct {
    frame: frame_t,
    task_data: data_t,
    scheduling_parent: *kmp.task_data_t,
    thread_num: c_int,
    dispatch_chunk: dispatch_chunk_t,
};
