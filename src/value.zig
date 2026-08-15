const std = @import("std");
const io = @import("io.zig");

pub const Value = union(enum) {
    nil,
    boolean: bool,
    number: f64,
    // TODO: string, array, object, function, error

    pub fn typeName(self: Value) []const u8 {
        return switch (self) {
            .nil => "nil",
            .boolean => "boolean",
            .number => "number",
            // TODO: string, array, object, function, error
        };
    }
};

pub fn valuesEqual(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;

    return switch (a) {
        .nil => true,
        .boolean => a.boolean == b.boolean,
        .number => a.number == b.number,
    };
}

pub fn printValue(value: Value) void {
    switch (value) {
        .boolean => |b| io.printf("{}", .{b}),
        .number => |n| io.printf("{d}", .{n}),
        .nil => io.printf("nil", .{}),
        // TODO: string, array, object, function, error
    }
}
