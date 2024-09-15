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

## Build

```sh
zig fetch --save git+https://github.com/sbancuz/OpenMP-zig
```

```zig
// build.zig
const OpenMP_zig_dep = b.dependency("OpenMP-zig", .{
      .target = target,
      .optimize = optimize,
});
exe.root_module.addImport("omp", OpenMP_zig_dep.module("omp"));
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
- [ ] `#pragma omp simd` NOT POSSIBLE TO IMPLEMENT

To see some other examples of the library check the tests folder.

## Extensions

```zig
fn test_omp_task_error() !bool {
    // The ret reduction parameter tells the directive how it should reduce the return value
    const result = omp.parallel(.{ .ret_reduction = .plus })
        .run(.{}, struct {
        // You can return whatever you want!
        fn f() !usize {
            const maybe = omp.single()
                .run(.{}, struct {
                // Only for tasks, you have to put the explicit error type in the promise,
                // otherwise it won't be able to infer the type
                fn f() *omp.promise(error{WompWomp}!usize) {
                    return omp.task(.{})
                        .run(.{}, struct {
                        // Same deal here
                        fn f() error{WompWomp}!usize {
                            return error.WompWomp;
                        }
                    }.f);
                }
            }.f);
            if (maybe) |pro| {
                defer pro.deinit();
                return pro.get();
            }
            return 0;
        }
    }.f) catch |err| switch (err) {
        error.WompWomp => std.debug.print("Caught an error :^(", .{});
    };

    std.debug.print("No errors here!". /{});
}
```

### Return

All of the directives can return values. To return something you may need to specify the `ret_reduction` parameter.

> [!WARNING]
> The promises that are returned from the `task` directive will be heap allocated. So make sure to deinit() them!

### Errors

All of the directive can return error types.
> [!WARNING]
> Returning more than one type of error from a directive it's clearly a race condition!

## Goal

The goal of this library is to provide at least OpenMP 4.5 to zig and be production ready, along with the mentioned extensions.
