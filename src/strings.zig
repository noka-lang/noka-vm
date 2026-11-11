//! String objects in HEAP, and the index of interned strings.
//!
//! Interned strings live in the permanent region of HEAP.
//! The index itself lives in the machine header.
//! Strings created at runtime are GC objects and are never interned.

const std = @import("std");
const heap_mod = @import("heap.zig");
const Heap = heap_mod.Heap;
const Ref = heap_mod.Ref;

pub const table_max = 2048;
const load_max = table_max * 3 / 4;

/// A string object.
const Object = extern struct {
    header: heap_mod.Header,
    hash: u32,
    len: u32,
};

pub fn bytes(heap: *const Heap, ref: Ref) []const u8 {
    return buffer(heap, ref);
}

pub fn hash(heap: *const Heap, ref: Ref) u32 {
    return heap.object(Object, ref).hash;
}

/// Allocates a GC string of `len` bytes.
pub fn alloc(heap: *Heap, len: u32) ?Ref {
    const ref = heap.alloc(.string, @sizeOf(Object) + len) orelse return null;
    heap.object(Object, ref).len = len;
    return ref;
}

/// Allocates a permanent string of `len` bytes.
pub fn allocPermanent(heap: *Heap, len: u32) ?Ref {
    const ref = heap.allocPermanent(.string, @sizeOf(Object) + len) orelse return null;
    heap.object(Object, ref).len = len;
    return ref;
}

/// Returns the bytes of the string at `ref`.
pub fn buffer(heap: *const Heap, ref: Ref) []u8 {
    const len = heap.object(Object, ref).len;
    return heap.bytes[ref + @sizeOf(Object) ..][0..len];
}

/// Stores the hash of the string at `ref`.
pub fn seal(heap: *Heap, ref: Ref) void {
    heap.object(Object, ref).hash = std.hash.Fnv1a_32.hash(bytes(heap, ref));
}

/// Returns whether the sealed strings at `a` and `b` have the same text.
pub fn equal(heap: *const Heap, a: Ref, b: Ref) bool {
    if (a == b) return true;

    const x = heap.object(Object, a);
    const y = heap.object(Object, b);
    return x.len == y.len and x.hash == y.hash and std.mem.eql(u8, bytes(heap, a), bytes(heap, b));
}

/// Returns the interned copy of `text`, or null if the heap or the index is full.
/// The copy is added to the permanent region if it's new.
pub fn intern(heap: *Heap, text: []const u8) ?Ref {
    if (lookup(heap, text)) |existing| return existing;

    const ref = allocPermanent(heap, @intCast(text.len)) orelse return null;
    @memcpy(buffer(heap, ref), text);
    seal(heap, ref);
    return heap.interned.insert(heap, ref);
}

/// Interns the sealed string at `ref`, or frees it and returns the existing copy if it is
/// already interned.
pub fn adopt(heap: *Heap, ref: Ref) ?Ref {
    if (heap.interned.find(heap, bytes(heap, ref), hash(heap, ref))) |existing| {
        heap.releasePermanent(ref);
        return existing;
    }

    return heap.interned.insert(heap, ref);
}

pub fn lookup(heap: *const Heap, text: []const u8) ?Ref {
    return heap.interned.find(heap, text, std.hash.Fnv1a_32.hash(text));
}

pub const Index = struct {
    pool: [load_max]Ref = undefined,
    pool_count: usize = 0,
    table: [table_max]?u16 = @splat(null),

    pub fn reset(self: *Index) void {
        self.pool_count = 0;
        self.table = @splat(null);
    }

    fn find(self: *const Index, heap: *const Heap, text: []const u8, h: u32) ?Ref {
        var i: usize = @as(usize, h) & (table_max - 1);
        while (self.table[i]) |idx| : (i = (i + 1) & (table_max - 1)) {
            const ref = self.pool[idx];
            if (hash(heap, ref) == h and std.mem.eql(u8, bytes(heap, ref), text)) return ref;
        }

        return null;
    }

    /// Adds the string at `ref`. Returns null and frees `ref` if the index is full.
    fn insert(self: *Index, heap: *Heap, ref: Ref) ?Ref {
        if (self.pool_count >= load_max) {
            heap.releasePermanent(ref);
            return null;
        }

        const idx: u16 = @intCast(self.pool_count);
        self.pool[idx] = ref;
        self.pool_count += 1;

        var i: usize = @as(usize, hash(heap, ref)) & (table_max - 1);
        while (self.table[i] != null) : (i = (i + 1) & (table_max - 1)) {}
        self.table[i] = idx;

        return ref;
    }
};

fn testHeap(region: *align(8) [heap_mod.size]u8) Heap {
    var heap: Heap = undefined;
    heap.init(region);
    return heap;
}

test "interning the same text twice gives the same string" {
    var region: [heap_mod.size]u8 align(8) = undefined;
    var heap = testHeap(&region);

    const a = intern(&heap, "noka").?;
    const free = heap.free();

    try std.testing.expectEqual(a, intern(&heap, "noka").?);
    try std.testing.expectEqual(free, heap.free());
    try std.testing.expectEqualStrings("noka", bytes(&heap, a));
}

test "adopting a string that is already interned frees it" {
    var region: [heap_mod.size]u8 align(8) = undefined;
    var heap = testHeap(&region);
    const a = intern(&heap, "ab").?;
    const free = heap.free();

    const b = allocPermanent(&heap, 2).?;
    @memcpy(buffer(&heap, b), "ab");
    seal(&heap, b);

    try std.testing.expectEqual(a, adopt(&heap, b).?);
    try std.testing.expectEqual(free, heap.free());
}

fn testString(heap: *Heap, text: []const u8) Ref {
    const ref = alloc(heap, @intCast(text.len)).?;
    @memcpy(buffer(heap, ref), text);
    seal(heap, ref);
    return ref;
}

test "strings with the same text are equal" {
    var region: [heap_mod.size]u8 align(8) = undefined;
    var heap = testHeap(&region);
    const a = intern(&heap, "ab").?;

    try std.testing.expect(equal(&heap, a, a));
    try std.testing.expect(equal(&heap, a, testString(&heap, "ab")));
    try std.testing.expect(!equal(&heap, a, testString(&heap, "ac")));
    try std.testing.expect(!equal(&heap, a, testString(&heap, "abc")));
}

test "a collection keeps the text of the string it keeps" {
    var region: [heap_mod.size]u8 align(8) = undefined;
    var heap = testHeap(&region);
    _ = testString(&heap, "dead");
    var roots = [_]@import("value.zig").Value{.{ .string = testString(&heap, "kept") }};

    heap.collect(&.{&roots});

    try std.testing.expectEqual(0, roots[0].string);
    try std.testing.expectEqualStrings("kept", bytes(&heap, roots[0].string));
}

test "the string index fills at its load limit" {
    var region: [heap_mod.size]u8 align(8) = undefined;
    var heap = testHeap(&region);
    var buf: [8]u8 = undefined;

    for (0..load_max) |i| {
        try std.testing.expect(intern(&heap, try std.fmt.bufPrint(&buf, "g{d}", .{i})) != null);
    }
    const free = heap.free();
    try std.testing.expectEqual(null, intern(&heap, "g1536"));
    try std.testing.expectEqual(free, heap.free());
}
