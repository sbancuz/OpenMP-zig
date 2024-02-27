# OpenMP-zig
An implementation of the OpenMP directives for Zig

## !!! This implementation is incomplete and highly experimental

To support:
- [p] `worksharing constructs` (only shared and privates for parallel region)
- [x] `error return types from directives`
- [x] `early return from directives`
- [x] `#pragma omp parallel`
- [p] `#pragma omp for` (extremely limited for now)
- [ ] `#pragma omp sections`
- [ ] `#pragma omp section`
- [x] `#pragma omp single`
- [x] `#pragma omp master`
- [x] `#pragma omp critical`
- [x] `#pragma omp barrier`
- [p] `#pragma omp task` (extremely limited for now, no dependencies)
- [ ] `proper testing`

## Usage
```zig
const omp = @import("omp.zig");
const std = @import("std");

pub fn main() void {
    const res = omp.parallel(tes, .{ .shared = .{ "hello" } }, .{ .num_threads = 8 });
    if (res) |r| {
        std.debug.print("res: {any}\n", .{r});
    } else {
        std.debug.print("no result :(\n", .{});
    }
}

pub fn tes(om: *omp.omp_ctx, string: []const u8) anyerror!?u32 {
    om.parallel_for(tes2, string, 0, 4, 2, .{});

    return 3;
}

pub fn tes2(om: *omp.omp_ctx, i: c_int, string: []const u8) void {
    std.debug.print("its aliveeee {s} {} \n", .{ string, i });
}


