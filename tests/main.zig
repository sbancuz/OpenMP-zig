const std = @import("std");

pub const barrier = @import("barrier.zig");
pub const critical = @import("critical.zig");
pub const masked = @import("masked.zig");
pub const parallel = @import("parallel.zig");
pub const reduction = @import("reduction.zig");
pub const flush = @import("flush.zig");
pub const sections = @import("sections.zig");

test "all" {
    std.testing.refAllDecls(@This());
}
