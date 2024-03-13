const std = @import("std");

pub const barrier = @import("barrier.zig");

test "barrier" {
    std.testing.refAllDecls(@This());
}
