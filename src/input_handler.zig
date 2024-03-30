const std = @import("std");
const omp = @import("omp.zig");

fn get_field_idx(comptime T: type, comptime field_name: []const u8) u32 {
    return comptime brk: {
        var idx: u32 = 0;
        inline for (@typeInfo(T).Struct.fields) |field| {
            if (std.mem.eql(u8, field_name, field.name)) {
                break :brk idx;
            }
            idx += 1;
        }
        break :brk idx;
    };
}

fn normalize_type(comptime T: type) type {
    var param_count: u32 = 0;
    const fields = @typeInfo(T).Struct.fields;
    const shared = val: {
        const idx = get_field_idx(T, "shared");
        if (fields.len > idx) {
            param_count += 1;
            break :val fields[idx].type;
        } else {
            break :val @TypeOf(.{});
        }
    };

    const private = val: {
        const idx = get_field_idx(T, "private");
        if (fields.len > idx) {
            param_count += 1;
            break :val fields[idx].type;
        } else {
            break :val @TypeOf(.{});
        }
    };

    const reduction = val: {
        const idx = get_field_idx(T, "reduction");
        if (fields.len > idx) {
            param_count += 1;
            break :val fields[idx].type;
        } else {
            break :val @TypeOf(.{});
        }
    };

    if (@typeInfo(T) != .Struct or param_count != @typeInfo(T).Struct.fields.len) {
        @compileError("Expected struct like .{ .shared = .{...}, .private = .{...} .reduction = {...} }, got " ++ @typeName(T) ++ " instead.");
    }

    return struct {
        shared: shared,
        private: private,
        reduction: reduction,
    };
}

pub fn normalize_args(args: anytype) normalize_type(@TypeOf(args)) {
    const args_type = @TypeOf(args);
    const shared = val: {
        if (comptime std.meta.trait.hasField("shared")(args_type)) {
            break :val args.shared;
        }
        break :val .{};
    };

    const private = val: {
        if (comptime std.meta.trait.hasField("private")(args_type)) {
            break :val args.private;
        }
        break :val .{};
    };

    const reduction = val: {
        if (comptime std.meta.trait.hasField("reduction")(args_type)) {
            break :val args.reduction;
        }
        break :val .{};
    };

    return .{ .shared = shared, .private = private, .reduction = reduction };
}

// TODO: Remove the need for the `ctx` argument, maybe the user doesn't want to use it
pub fn check_fn_signature(comptime f: anytype) bool {
    const f_type_info = @typeInfo(@TypeOf(f));
    if (f_type_info != .Fn) {
        @compileError("Expected function with signature `fn(ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
    }
    if (f_type_info.Fn.params.len < 1 or f_type_info.Fn.params[0].type.? != *omp.ctx) {
        @compileError("Expected function with signature `fn(ctx, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
    }

    return true;
}

pub fn check_args(comptime T: type) void {
    const args_type_info = @typeInfo(T);
    if (args_type_info != .Struct) {
        @compileError("Expected struct or tuple, got " ++ @typeName(T) ++ " instead.");
    }
}

pub fn copy_ret(comptime f: anytype) type {
    return @typeInfo(@TypeOf(f)).Fn.return_type orelse void;
}

pub fn deep_size_of(comptime T: type) usize {
    var size: usize = @sizeOf(T);
    inline for (@typeInfo(T).Struct.fields) |field| {
        if (@typeInfo(field.type) == .Pointer) {
            size += @sizeOf(@typeInfo(field.type).Pointer.child);
        }
    }
    return size;
}

pub fn deep_copy(comptime T: type, allocator: std.mem.Allocator, original: T) *T {
    var copy = (allocator.create(T) catch @panic("Failed to allocate memory"));
    inline for (original, copy) |og, *v| {
        if (@typeInfo(@TypeOf(og)) == .Pointer) {
            v.* = @constCast((allocator.create(@TypeOf(og.*)) catch @panic("Failed to allocate memory")));
            v.*.* = og.*;
        } else if (@typeInfo(@TypeOf(og)) == .Struct) {
            v.* = (allocator.create(@TypeOf(og)) catch @panic("Failed to allocate memory"));
            v.* = og;
        } else {
            v.* = og;
        }
    }
    return copy;
}