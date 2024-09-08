# OpenMP-zig

This wrapper implements (almost all) the OpenMP directives up-to version 3.1 and some newer stuff.
All of this is (mostly, see below) without any allocation from the zig part.

This is implemented using the `libomp' library of LLVM. (Gomp support is not planned) **Disclaimer** This project is not affiliated with LLVM in any capacity.

```zig
const std = @import("std");
const omp = @import("omp");

fn main() void {
    omp.parallel(.{})
        .run(.{}, struct {
        fn f() void {
            std.debug.print("Hello world {}!", .{omp.get_thread_num()});
        }
    }.f);
}
```

## Features
- [x] `#pragma omp parallel`
- [x] `All reductions`
- [x] `#pragma omp for`
- [x] `#pragma omp sections`
- [x] `#pragma omp single`
- [x] `#pragma omp master/masked`
- [x] `#pragma omp critical`
- [x] `#pragma omp barrier`
- [x] `#pragma omp task`
- [ ] `#pragma omp atomic` NOT POSSIBLE TO IMPLEMENT
      
To see some other examples of the library check the tests folder.

## Extensions

### Return

All of the directives can return values. To return something you may need to specify the `ret_reduction` parameter.

> [!WARNING]
> The promises that are returned from the `task` directive will be heap allocated. So make sure to deinit() them!

### Errors

All of the directive can return error type, though it's not fully implemented yet for all directives.

## Goal

The goal of this library is to provide at least OpenMP 4.5 to zig and be production ready, along with the mentioned extensions.
