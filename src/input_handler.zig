const std = @import("std");

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
