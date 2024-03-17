const std = @import("std");

pub const barrier = @import("barrier.zig");
pub const critical = @import("critical.zig");
pub const parallel = @import("parallel.zig");
pub const single = @import("master.zig");

test "barrier" {
    std.testing.refAllDecls(@This());
}
