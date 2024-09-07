const std = @import("std");

pub const barrier = @import("barrier.zig");
pub const flush = @import("flush.zig");
pub const masked = @import("masked.zig");
pub const task = @import("task.zig");
pub const critical = @import("critical.zig");
pub const parallel = @import("parallel.zig");
pub const reduction = @import("reduction.zig");
pub const sections = @import("sections.zig");
pub const return_ = @import("return.zig");

test "all" {
    std.testing.refAllDecls(@This());
}
