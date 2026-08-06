const io = @import("io.zig");

pub const Value = union(enum) {
    nil,
    boolean: bool,
    number: f64,
    // TODO: string, array, object, function, error

    fn @"type"(self: Value) []const u8 {
        return switch (self) {
            Value.nil => "nil",
            Value.boolean => "boolean",
            Value.number => "number",
            // TODO: string, array, object, function, error
        };
    }
};

pub fn printValue(value: Value) void {
    switch (value) {
        .boolean => |b| io.printf("{}", .{b}),
        .number => |n| io.printf("{d}", .{n}),
        .nil => io.printf("nil", .{}),
        // TODO: string, array, object, function, error
    }
}

// --- Type checking ----------------------------------------------------------

pub fn IS_BOOL(value: Value) bool {
    return value == Value.boolean;
}

pub fn IS_NIL(value: Value) bool {
    return value == Value.nil;
}

pub fn IS_NUMBER(value: Value) bool {
    return value == Value.number;
}
