const std = @import("std");

pub const barrier = @import("barrier.zig");
pub const critical = @import("critical.zig");
pub const master = @import("master.zig");
pub const parallel = @import("parallel.zig");
pub const reduction = @import("reduction.zig");

test "all" {
    std.testing.refAllDecls(@This());
}
