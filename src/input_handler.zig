const std = @import("std");
const omp = @import("omp.zig");

fn get_field_idx(comptime T: type, comptime field_name: []const u8) u32 {
    return comptime brk: {
        var idx: u32 = 0;
        for (@typeInfo(T).Struct.fields) |field| {
            if (std.mem.eql(u8, field_name, field.name)) {
                break :brk idx;
            }
            idx += 1;
        }
        break :brk idx;
    };
}

pub fn zigc_ret(comptime f: anytype, comptime args_type: type) type {
    const f_type_info = @typeInfo(@TypeOf(f));
    if (f_type_info != .Fn) {
        @compileError("Expected function with signature `fn(, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
    }
    return struct {
        ret: copy_ret(f) = undefined,
        v: args_type = undefined,
    };
}

pub fn copy_ret(comptime f: anytype) type {
    return @typeInfo(@TypeOf(f)).Fn.return_type orelse void;
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

pub fn has_field(comptime T: type, comptime field_name: []const u8) bool {
    for (std.meta.fieldNames(T)) |field| {
        if (std.mem.eql(u8, field_name, field)) {
            return true;
        }
    }
    return false;
}

pub fn normalize_args(args: anytype) normalize_type(@TypeOf(args)) {
    const args_type = @TypeOf(args);
    const shared = val: {
        if (comptime has_field(args_type, "shared")) {
            break :val args.shared;
        }
        break :val .{};
    };

    const private = val: {
        if (comptime has_field(args_type, "private")) {
            break :val args.private;
        }
        break :val .{};
    };

    const reduction = val: {
        if (comptime has_field(args_type, "reduction")) {
            break :val args.reduction;
        }
        break :val .{};
    };

    return .{ .shared = shared, .private = private, .reduction = reduction };
}

pub fn check_fn_signature(comptime f: anytype) void {
    const f_type_info = @typeInfo(@TypeOf(f));
    if (f_type_info != .Fn) {
        @compileError("Expected function with signature `fn(, ...)`, got " ++ @typeName(@TypeOf(f)) ++ " instead.");
    }
}

pub fn check_args(comptime T: type) void {
    const args_type_info = @typeInfo(T);
    if (args_type_info != .Struct) {
        @compileError("Expected struct or tuple, got " ++ @typeName(T) ++ " instead.");
    }
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

/// Deep copy a struct with pointers
/// This function will copy the struct and all the pointers it contains
/// but it won't go more than one level deep
///
/// WARNING: This function may be not memory safe if it doesn't get inlined
pub inline fn shallow_copy(original: anytype) @TypeOf(original) {
    var copy: @TypeOf(original) = .{} ++ original;
    inline for (original, &copy) |og, *v| {
        if (@typeInfo(@TypeOf(og)) == .Pointer) {
            var tmp = og.*;
            v.* = &tmp;
        } else {
            v.* = og;
        }
    }
    return copy;
}
