const std = @import("std");
const io = @import("io.zig");

pub const Value = union(enum) {
    boolean: bool,
    nil,
    number: f64,
    // TODO: string, array, object, function, error

    pub fn typeName(self: Value) []const u8 {
        return switch (self) {
            .boolean => "boolean",
            .nil => "nil",
            .number => "number",
            // TODO: string, array, object, function, error
        };
    }

    pub fn equals(self: Value, b: Value) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(b)) return false;

        return switch (self) {
            .boolean => self.boolean == b.boolean,
            .nil => true,
            .number => self.number == b.number,
            // TODO: string, array, object, function, error
        };
    }

    pub fn print(self: Value) void {
        switch (self) {
            .boolean => |b| io.printf("{}", .{b}),
            .nil => io.printf("nil", .{}),
            .number => |n| io.printf("{d}", .{n}),
            // TODO: string, array, object, function, error
        }
    }
};
