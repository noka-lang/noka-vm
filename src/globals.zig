//! The VM keeps the values of top-level names in a table in HEAP.
//! The table outlives a single eval, so a REPL can use names declared on earlier lines.

const std = @import("std");
const strings = @import("strings.zig");
const memory = @import("memory.zig");
const Mutability = @import("compiler.zig").Mutability;

pub const slots_max = memory.globals_slots;
const index_max = slots_max * 2;

pub const Name = struct {
    name: *const strings.String,
    mutability: Mutability = .mutable,
    declared: bool = false,
};

pub const Names = struct {
    entries: [slots_max]Name = undefined,
    count: usize = 0,
    index: [index_max]?u16 = @splat(null),

    pub fn reset(self: *Names) void {
        self.count = 0;
        self.index = @splat(null);
    }

    /// Returns the slot owned by `name` (gives `name` the next available slot if it doesn't have
    /// one already).
    /// Returns null when every slot is taken.
    pub fn slot(self: *Names, name: *const strings.String) ?u16 {
        var i: usize = @as(usize, name.hash) & (index_max - 1);
        while (self.index[i]) |s| : (i = (i + 1) & (index_max - 1)) {
            if (self.entries[s].name == name) return s;
        }

        if (self.count == slots_max) return null;

        const s: u16 = @intCast(self.count);
        self.entries[s] = .{ .name = name };
        self.count += 1;
        self.index[i] = s;

        return s;
    }
};

test "a name keeps the slot it was given" {
    var table: strings.Strings = .{};
    var names: Names = .{};
    const x = table.intern("x").?;
    const y = table.intern("y").?;

    try std.testing.expectEqual(0, names.slot(x));
    try std.testing.expectEqual(1, names.slot(y));
    try std.testing.expectEqual(0, names.slot(x));
    try std.testing.expect(!names.entries[0].declared);
}

test "the 1025th name gets no slot" {
    var fakes: [slots_max + 1]strings.String = undefined;
    for (&fakes, 0..) |*f, i| f.* = .{ .bytes = "", .hash = @intCast(i) };
    var names: Names = .{};

    for (fakes[0..slots_max], 0..) |*f, i| try std.testing.expectEqual(@as(?u16, @intCast(i)), names.slot(f));
    try std.testing.expectEqal(null, names.slot(&fakes[slots_max]));
    try std.testing.expectEqual(5, names.slot(&fakes[5]));
}

test "reset forgets every name" {
    var table: strings.Strings = .{};
    var names: Names = .{};
    _ = names.slot(table.intern("x").?);
    _ = names.slot(table.intern("y").?);

    names.reset();

    try std.testing.expectEqual(0, names.slot(table.intern("y").?));
}

