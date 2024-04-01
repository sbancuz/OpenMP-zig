# OpenMP-zig
An implementation of the OpenMP directives for Zig

## !!! This implementation is incomplete and highly experimental

To support:
- [x] `worksharing constructs` 
- [x] `error return types from directives`
- [x] `early return from directives`
- [x] `#pragma omp parallel`
- [x] `#pragma omp for` (missing only schedules I believe)
- [ ] `#pragma omp sections`
- [ ] `#pragma omp section`
- [x] `#pragma omp single`
- [x] `#pragma omp master`
- [x] `#pragma omp critical`
- [x] `#pragma omp barrier`
- [x] `#pragma omp task` (extremely limited for now, no dependencies)
- [ ] `proper testing` (WIP)

## Usage

!!! Outdated, since the API will change frequently and I don't want to update this README every time please refer to the test folder for some up to date examples

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


