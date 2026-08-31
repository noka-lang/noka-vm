const std = @import("std");

// Strings are stored in a heap, duplicated text is only stored once.
// This heap is a slice of the console's 128 KiB HEAP region.

pub const bytes_max = 48 * 1024;
pub const table_max = 1024;
const load_max = table_max * 3 / 4;

pub const String = struct {
    bytes: []const u8,
    hash: u32,
};

var arena: [bytes_max]u8 = undefined;
var arena_used: usize = 0;

var pool: [table_max]String = undefined;
var pool_count: usize = 0;

var table: [table_max]?u16 = @splat(null);

pub fn reset() void {
    arena_used = 0;
    pool_count = 0;
    table = @splat(null);
}

pub fn intern(text: []const u8) ?*const String {
    const h = std.hash.Fnv1a_32.hash(text);
    if (find(text, h)) |existing| return existing;

    const start = arena_used;
    if (start + text.len > arena.len) return null;
    @memcpy(arena[start..][0..text.len], text);
    arena_used += text.len;

    return insert(arena[start..arena_used], h) orelse {
        arena_used = start;
        return null;
    };
}

pub const Builder = struct {
    start: usize,
    overflow: bool = false,

    pub fn push(self: *Builder, byte: u8) void {
        if (arena_used + 1 > arena.len) {
            self.overflow = true;
            return;
        }
        arena[arena_used] = byte;
        arena_used += 1;
    }

    pub fn pushSlice(self: *Builder, text: []const u8) void {
        if (arena_used + text.len > arena.len) {
            self.overflow = true;
            return;
        }
        @memcpy(arena[arena_used..][0..text.len], text);
        arena_used += text.len;
    }

    pub fn finish(self: *Builder) ?*const String {
        if (self.overflow) {
            self.discard();
            return null;
        }

        const text = arena[self.start..arena_used];
        const h = std.hash.Fnv1a_32.hash(text);
        if (find(text, h)) |existing| {
            self.discard();
            return existing;
        }

        return insert(text, h) orelse {
            self.discard();
            return null;
        };
    }

    pub fn discard(self: *Builder) void {
        arena_used = self.start;
    }
};

pub fn build() Builder {
    return .{ .start = arena_used };
}

fn find(text: []const u8, h: u32) ?*const String {
    var i: usize = @as(usize, h) & (table_max - 1);
    while (table[i]) |idx| : (i = (i + 1) & (table_max - 1)) {
        const s = &pool[idx];
        if (s.hash == h and std.mem.eql(u8, s.bytes, text)) return s;
    }

    return null;
}

fn insert(text: []const u8, h: u32) ?*const String {
    if (pool_count >= load_max) return null;

    const idx: u16 = @intCast(pool_count);
    pool[idx] = .{ .bytes = text, .hash = h };
    pool_count += 1;

    var i: usize = @as(usize, h) & (table_max - 1);
    while (table[i] != null) : (i = (i + 1) & (table_max - 1)) {}
    table[i] = idx;

    return &pool[idx];
}
