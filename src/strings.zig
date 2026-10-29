const std = @import("std");

// Strings are stored in a heap, duplicated text is only stored once.
// This heap is a slice of the console's 128 KiB HEAP region.

pub const bytes_max = 48 * 1024;
pub const table_max = 2048;
const load_max = table_max * 3 / 4;

pub const String = struct {
    bytes: []const u8,
    hash: u32,
};

pub const Strings = struct {
    arena: [bytes_max]u8 = undefined,
    arena_used: usize = 0,
    pool: [load_max]String = undefined,
    pool_count: usize = 0,
    table: [table_max]?u16 = @splat(null),

    pub fn reset(self: *Strings) void {
        self.arena_used = 0;
        self.pool_count = 0;
        self.table = @splat(null);
    }

    pub fn intern(self: *Strings, text: []const u8) ?*const String {
        const h = std.hash.Fnv1a_32.hash(text);
        if (self.find(text, h)) |existing| return existing;

        const start = self.arena_used;
        if (start + text.len > self.arena.len) return null;
        @memcpy(self.arena[start..][0..text.len], text);
        self.arena_used += text.len;

        return self.insert(self.arena[start..self.arena_used], h) orelse {
            self.arena_used = start;
            return null;
        };
    }

    pub fn build(self: *Strings) Builder {
        return .{ .strings = self, .start = self.arena_used };
    }

    fn find(self: *const Strings, text: []const u8, h: u32) ?*const String {
        var i: usize = @as(usize, h) & (table_max - 1);
        while (self.table[i]) |idx| : (i = (i + 1) & (table_max - 1)) {
            const s = &self.pool[idx];
            if (s.hash == h and std.mem.eql(u8, s.bytes, text)) return s;
        }

        return null;
    }

    fn insert(self: *Strings, text: []const u8, h: u32) ?*const String {
        if (self.pool_count >= load_max) return null;

        const idx: u16 = @intCast(self.pool_count);
        self.pool[idx] = .{ .bytes = text, .hash = h };
        self.pool_count += 1;

        var i: usize = @as(usize, h) & (table_max - 1);
        while (self.table[i] != null) : (i = (i + 1) & (table_max - 1)) {}
        self.table[i] = idx;

        return &self.pool[idx];
    }
};

pub const Builder = struct {
    strings: *Strings,
    start: usize,
    overflow: bool = false,

    pub fn push(self: *Builder, byte: u8) void {
        const s = self.strings;
        if (s.arena_used + 1 > s.arena.len) {
            self.overflow = true;
            return;
        }
        s.arena[s.arena_used] = byte;
        s.arena_used += 1;
    }

    pub fn pushSlice(self: *Builder, text: []const u8) void {
        const s = self.strings;
        if (s.arena_used + text.len > s.arena.len) {
            self.overflow = true;
            return;
        }
        @memcpy(s.arena[s.arena_used..][0..text.len], text);
        s.arena_used += text.len;
    }

    pub fn finish(self: *Builder) ?*const String {
        if (self.overflow) {
            self.discard();
            return null;
        }

        const s = self.strings;
        const text = s.arena[self.start..s.arena_used];
        const h = std.hash.Fnv1a_32.hash(text);
        if (s.find(text, h)) |existing| {
            self.discard();
            return existing;
        }

        return s.insert(text, h) orelse {
            self.discard();
            return null;
        };
    }

    pub fn discard(self: *Builder) void {
        self.strings.arena_used = self.start;
    }
};

test "the string table fills at its load limit" {
    var table: Strings = .{};
    var buf: [8]u8 = undefined;

    for (0..load_max) |i| {
        try std.testing.expect(table.intern(try std.fmt.bufPrint(&buf, "g{d}", .{i})) != null);
    }
    try std.testing.expectEqual(null, table.intern("g1536"));
}
