const std = @import("std");
const io = @import("io.zig");
const String = @import("strings.zig").String;

pub const Value = union(enum) {
    boolean: bool,
    nil,
    number: f64,
    string: *const String,
    // TODO: array, object, function, error

    pub fn typeName(self: Value) []const u8 {
        return switch (self) {
            .boolean => "boolean",
            .nil => "nil",
            .number => "number",
            .string => "string",
            // TODO: array, object, function, error
        };
    }

    pub fn equals(self: Value, b: Value) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(b)) return false;

        return switch (self) {
            .boolean => self.boolean == b.boolean,
            .nil => true,
            .number => self.number == b.number,
            .string => self.string == b.string,
            // TODO: array, object, function, error
        };
    }

    pub fn print(self: Value) void {
        switch (self) {
            .boolean => |b| io.printf("{}", .{b}),
            .nil => io.printf("nil", .{}),
            .number => |n| io.printf("{d}", .{n}),
            .string => |s| io.print(s.bytes),
            // TODO: array, object, function, error
        }
    }
};
