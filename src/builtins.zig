//! This is the "standard library" of functions and vars the VM provides to every program.
//!
//! The built-ins table is read-only, compiled into the VM, and shared by every machine.
//! Built-ins do not count towards a program's GLOBALS slots or HEAP.

const std = @import("std");
const Value = @import("value.zig").Value;

pub const Builtin = struct {
    name: []const u8,
    value: Value,
};

/// The built-ins every machine can see.
pub const common = [_]Builtin{
    .{ .name = "dt", .value = .{ .number = 1.0 / 60.0 } },
    // TODO: add the rest of the built-in functions once function syntax is implemented
};

comptime {
    if (common.len > 256) @compileError("built-in indices must fit in a u8");
    for (common) |builtin| {
        if (builtin.value != .number) @compileError("built-in '" ++ builtin.name ++ "' must be a number");
    }
}

pub fn find(name: []const u8) ?u8 {
    for (common, 0..) |builtin, i| {
        if (std.mem.eql(u8, builtin.name, name)) return @intCast(i);
    }

    return null;
}
