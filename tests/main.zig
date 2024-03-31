const std = @import("std");

pub const reduction = @import("reduction.zig");
pub const barrier = @import("barrier.zig");
pub const critical = @import("critical.zig");
pub const master = @import("master.zig");
pub const parallel = @import("parallel.zig");

test "all" {
    std.testing.refAllDecls(@This());
}
