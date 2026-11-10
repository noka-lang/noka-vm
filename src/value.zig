const std = @import("std");
const io = @import("io.zig");
const heap_mod = @import("heap.zig");
const strings = @import("strings.zig");

pub const Value = union(enum) {
    boolean: bool,
    nil,
    number: f64,
    string: heap_mod.Ref,
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

    pub fn equals(self: Value, b: Value, heap: *const heap_mod.Heap) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(b)) return false;

        return switch (self) {
            .boolean => self.boolean == b.boolean,
            .nil => true,
            .number => self.number == b.number,
            .string => strings.equal(heap, self.string, b.string),
            // TODO: array, object, function, error
        };
    }

    pub fn print(self: Value, m: io.Handle, heap: *const heap_mod.Heap) void {
        switch (self) {
            .boolean => |b| io.printf(m, "{}", .{b}),
            .nil => io.print(m, "nil"),
            .number => |n| io.printf(m, "{d}", .{n}),
            .string => |s| io.print(m, strings.bytes(heap, s)),
            // TODO: array, object, function, error
        }
    }
};
