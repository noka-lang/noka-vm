//! The table of top-level names.
//! The table outlives a single eval, so a REPL can use names declared on earlier lines.

const std = @import("std");
const strings = @import("strings.zig");
const memory = @import("memory.zig");

pub const slots_max = memory.globals_slots;
const table_max = slots_max * 2;

pub const Mutability = enum { mutable, constant };

/// What the VM knows about a top-level name.
/// Its value lives at the same slot of GLOBALS.
pub const Global = struct {
    name: *const strings.String,
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
    pub fn slot(self: *Names, name: *const strings.String) ?u16 {
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
    pub fn find(self: *const Names, name: *const strings.String) ?u16 {
        return self.table[self.probe(name)];
    }

    /// Returns the slot of `name` if a program declared it, or null.
    pub fn findDeclared(self: *const Names, name: *const strings.String) ?u16 {
        const idx = self.find(name) orelse return null;
        return if (self.pool[idx].declared) idx else null;
    }

    /// Returns the table index that holds `name`, or the empty index where it would go.
    fn probe(self: *const Names, name: *const strings.String) usize {
        var i: usize = @as(usize, name.hash) & (table_max - 1);
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
    var table: strings.Strings = .{};
    var names: Names = .{};
    const x = table.intern("x").?;
    const y = table.intern("y").?;

    try std.testing.expectEqual(0, names.slot(x));
    try std.testing.expectEqual(1, names.slot(y));
    try std.testing.expectEqual(0, names.slot(x));
    try std.testing.expect(!names.pool[0].declared);
}

test "a name that exceeds the last slot gets no slot" {
    var fakes: [slots_max + 1]strings.String = undefined;
    for (&fakes, 0..) |*f, i| f.* = .{ .bytes = "", .hash = @intCast(i) };
    var names: Names = .{};

    for (fakes[0..slots_max], 0..) |*f, i| try std.testing.expectEqual(@as(?u16, @intCast(i)), names.slot(f));
    try std.testing.expectEqual(null, names.slot(&fakes[slots_max]));
    try std.testing.expectEqual(5, names.slot(&fakes[5]));
}

test "find never gives a name a slot" {
    var table: strings.Strings = .{};
    var names: Names = .{};
    const x = table.intern("x").?;
    const y = table.intern("y").?;
    _ = names.slot(x);

    try std.testing.expectEqual(0, names.find(x));
    try std.testing.expectEqual(null, names.find(y));
    try std.testing.expectEqual(1, names.slot(y));
}

test "findDeclared skips a name that only has a slot" {
    var table: strings.Strings = .{};
    var names: Names = .{};
    const x = table.intern("x").?;
    const idx = names.slot(x).?;

    try std.testing.expectEqual(null, names.findDeclared(x));
    try names.declare(idx, .mutable);
    try std.testing.expectEqual(idx, names.findDeclared(x));
}

test "reset forgets every name" {
    var table: strings.Strings = .{};
    var names: Names = .{};
    _ = names.slot(table.intern("x").?);
    _ = names.slot(table.intern("y").?);

    names.reset();

    try std.testing.expectEqual(0, names.slot(table.intern("y").?));
}
