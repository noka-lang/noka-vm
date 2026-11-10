//! The table of top-level names.
//! The table outlives a single eval, so a REPL can use names declared on earlier lines.

const std = @import("std");
const Ref = @import("heap.zig").Ref;
const memory = @import("memory.zig");

pub const slots_max = memory.globals_slots;
const table_max = slots_max * 2;

pub const Mutability = enum { mutable, constant };

/// What the VM knows about a top-level name.
/// Its value lives at the same slot of GLOBALS.
pub const Global = struct {
    name: Ref,
    mutability: Mutability = .mutable,
    declared: bool = false,
};

pub const Names = struct {
    pool: [slots_max]Global = undefined,
    pool_count: usize = 0,
    table: [table_max]?u16 = @splat(null),

    pub fn reset(self: *Names) void {
        self.pool_count = 0;
        self.table = @splat(null);
    }

    /// Returns the slot owned by `name` (gives `name` the next available slot if it doesn't have
    /// one already).
    /// Returns null when every slot is taken.
    pub fn slot(self: *Names, name: Ref) ?u16 {
        const i = self.probe(name);
        if (self.table[i]) |idx| return idx;

        if (self.pool_count == slots_max) return null;

        const idx: u16 = @intCast(self.pool_count);
        self.pool[idx] = .{ .name = name };
        self.pool_count += 1;
        self.table[i] = idx;

        return idx;
    }

    /// Returns the slot owned by `name`, or null. Does not give `name` a slot.
    pub fn find(self: *const Names, name: Ref) ?u16 {
        return self.table[self.probe(name)];
    }

    /// Returns the slot of `name` if a program declared it, or null.
    pub fn findDeclared(self: *const Names, name: Ref) ?u16 {
        const idx = self.find(name) orelse return null;
        return if (self.pool[idx].declared) idx else null;
    }

    /// Returns the table index that holds `name`, or the empty index where it would go.
    fn probe(self: *const Names, name: Ref) usize {
        var i: usize = @as(usize, std.hash.int(name)) & (table_max - 1);
        while (self.table[i]) |idx| : (i = (i + 1) & (table_max - 1)) {
            if (self.pool[idx].name == name) return i;
        }

        return i;
    }

    /// Marks the global at `idx` as declared and gives it `mutability`.
    pub fn declare(self: *Names, idx: u16, mutability: Mutability) error{AlreadyDeclared}!void {
        const global = &self.pool[idx];
        if (global.declared) return error.AlreadyDeclared;

        global.declared = true;
        global.mutability = mutability;
    }
};

test "a name keeps the slot it was given" {
    var names: Names = .{};

    try std.testing.expectEqual(0, names.slot(100));
    try std.testing.expectEqual(1, names.slot(200));
    try std.testing.expectEqual(0, names.slot(100));
    try std.testing.expect(!names.pool[0].declared);
}

test "a name that exceeds the last slot gets no slot" {
    var names: Names = .{};

    for (0..slots_max) |i| try std.testing.expectEqual(@as(?u16, @intCast(i)), names.slot(@intCast(i)));
    try std.testing.expectEqual(null, names.slot(slots_max));
    try std.testing.expectEqual(5, names.slot(5));
}

test "find never gives a name a slot" {
    var names: Names = .{};
    _ = names.slot(100);

    try std.testing.expectEqual(0, names.find(100));
    try std.testing.expectEqual(null, names.find(200));
    try std.testing.expectEqual(1, names.slot(200));
}

test "findDeclared skips a name that only has a slot" {
    var names: Names = .{};
    const idx = names.slot(100).?;

    try std.testing.expectEqual(null, names.findDeclared(100));
    try names.declare(idx, .mutable);
    try std.testing.expectEqual(idx, names.findDeclared(100));
}

test "reset forgets every name" {
    var names: Names = .{};
    _ = names.slot(100);
    _ = names.slot(200);

    names.reset();

    try std.testing.expectEqual(0, names.slot(200));
}
