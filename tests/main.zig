const std = @import("std");

pub const barrier = @import("barrier.zig");
pub const critical = @import("critical.zig");

test "barrier" {
    std.testing.refAllDecls(@This());
}
