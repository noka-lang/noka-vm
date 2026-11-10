//! A machine's HEAP region.
//!
//! GC objects grow up from the bottom, and the permanent region grows down from the top.
//! The heap is out of memory when the two meet.

const std = @import("std");
const memory = @import("memory.zig");
const strings = @import("strings.zig");
const Value = @import("value.zig").Value;

pub const size: u32 = memory.heap.size;

/// An object's offset from the start of HEAP.
pub const Ref = u32;

const alignment = 8;

pub const Kind = enum(u8) { string };

pub const Header = extern struct {
    size: u32,
    forward: Ref = 0,
    kind: Kind,
    marked: bool = false,
};

pub const Heap = struct {
    bytes: *[size]u8,
    top: u32,
    /// Permanent region starting point
    permanent: u32,
    /// Interned strings in the permanent region.
    interned: strings.Index,

    pub fn init(self: *Heap, bytes: *[size]u8) void {
        self.bytes = bytes;
        self.reset();
    }

    pub fn reset(self: *Heap) void {
        self.top = 0;
        self.permanent = size;
        self.interned.reset();
    }

    // Returns the bytes left between the GC objects and the permanent region.
    pub fn free(self: *const Heap) u32 {
        return self.permanent - self.top;
    }

    /// Allocates a GC object of `n` bytes, or returns null if it doesn't fit.
    pub fn alloc(self: *Heap, kind: Kind, n: u32) ?Ref {
        const total = std.mem.alignForward(u32, n, alignment);
        if (total > self.free()) return null;

        const ref = self.top;
        self.top += total;
        self.header(ref).* = .{ .size = total, .kind = kind };
        return ref;
    }

    /// Allocates a permanent object of `n` bytes, or returns null if it doesn't fit.
    pub fn allocPermanent(self: *Heap, kind: Kind, n: u32) ?Ref {
        const total = std.mem.alignForward(u32, n, alignment);
        if (total > self.free()) return null;

        self.permanent -= total;
        self.header(self.permanent).* = .{ .size = total, .kind = kind };
        return self.permanent;
    }

    pub fn releasePermanent(self: *Heap, ref: Ref) void {
        std.debug.assert(ref == self.permanent);
        self.permanent += self.header(ref).size;
    }

    /// Frees every GC object that `roots` can't reach, slides the rest down to the bottom.
    /// Rewrites the refs in `roots` to point at the objects' new locations.
    pub fn collect(self: *Heap, roots: []const []Value) void {
        for (roots) |values| {
            for (values) |*value| {
                const ref = self.gcRef(value) orelse continue;
                self.header(ref.*).marked = true;
            }
        }

        var to: u32 = 0;
        var at: u32 = 0;
        while (at < self.top) : (at += self.header(at).size) {
            const h = self.header(at);
            if (!h.marked) continue;

            h.forward = to;
            to += h.size;
        }

        for (roots) |values| {
            for (values) |*value| {
                const ref = self.gcRef(value) orelse continue;
                ref.* = self.header(ref.*).forward;
            }
        }

        at = 0;
        while (at < self.top) {
            const h = self.header(at);
            const n = h.size;
            if (h.marked) {
                h.marked = false;
                std.mem.copyForwards(u8, self.bytes[h.forward..][0..n], self.bytes[at..][0..n]);
            }
            at += n;
        }

        @memset(self.bytes[to..self.top], undefined);
        self.top = to;
    }

    fn gcRef(self: *const Heap, value: *Value) ?*Ref {
        const ref = value.ref() orelse return null;
        return if (ref.* < self.top) ref else null;
    }

    pub fn header(self: *const Heap, ref: Ref) *Header {
        return self.object(Header, ref);
    }

    pub fn object(self: *const Heap, comptime T: type, ref: Ref) *T {
        return @ptrCast(@alignCast(&self.bytes[ref]));
    }
};

fn testHeap(bytes: *align(alignment) [size]u8) Heap {
    var heap: Heap = undefined;
    heap.init(bytes);
    return heap;
}

test "GC objects grow up from the bottom" {
    var bytes: [size]u8 align(alignment) = undefined;
    var heap = testHeap(&bytes);

    const a = heap.alloc(.string, 12).?;
    const b = heap.alloc(.string, 20).?;

    try std.testing.expectEqual(0, a);
    try std.testing.expectEqual(16, b);
    try std.testing.expectEqual(size - 40, heap.free());
}

test "GC objects and permanent objects meet in the middle" {
    var bytes: [size]u8 align(alignment) = undefined;
    var heap = testHeap(&bytes);

    try std.testing.expect(heap.allocPermanent(.string, size / 2) != null);
    try std.testing.expect(heap.alloc(.string, size / 2) != null);
    try std.testing.expectEqual(0, heap.free());
    try std.testing.expectEqual(null, heap.alloc(.string, 8));
    try std.testing.expectEqual(null, heap.allocPermanent(.string, 8));
}

test "a collection frees the objects the roots can't reach" {
    var bytes: [size]u8 align(alignment) = undefined;
    var heap = testHeap(&bytes);
    _ = heap.alloc(.string, 16).?;
    const b = heap.alloc(.string, 16).?;
    _ = heap.alloc(.string, 16).?;
    var roots = [_]Value{ .{ .string = b }, .{ .string = b }, .{ .number = 1 } };

    heap.collect(&.{&roots});

    try std.testing.expectEqual(size - 16, heap.free());
    try std.testing.expectEqual(0, roots[0].string);
    try std.testing.expectEqual(0, roots[1].string);
}

test "a collection leaves permanent objects alone" {
    var bytes: [size]u8 align(alignment) = undefined;
    var heap = testHeap(&bytes);
    const p = heap.allocPermanent(.string, 16).?;
    _ = heap.alloc(.string, 16).?;
    var roots = [_]Value{.{ .string = p }};

    heap.collect(&.{&roots});

    try std.testing.expectEqual(p, roots[0].string);
    try std.testing.expectEqual(size - 16, heap.free());
}

test "permanent objects grow down from the top" {
    var bytes: [size]u8 align(alignment) = undefined;
    var heap = testHeap(&bytes);

    const a = heap.allocPermanent(.string, 12).?;
    const b = heap.allocPermanent(.string, 20).?;

    try std.testing.expectEqual(size - 16, a);
    try std.testing.expectEqual(size - 16 - 24, b);
    try std.testing.expectEqual(size - 40, heap.free());
}

test "a permanent object that doesn't fit gets no space" {
    var bytes: [size]u8 align(alignment) = undefined;
    var heap = testHeap(&bytes);

    try std.testing.expect(heap.allocPermanent(.string, size - 8) != null);
    try std.testing.expectEqual(null, heap.allocPermanent(.string, 16));
    try std.testing.expect(heap.allocPermanent(.string, 8) != null);
    try std.testing.expectEqual(0, heap.free());
}

test "releasing the last permanent object gives its space back" {
    var bytes: [size]u8 align(alignment) = undefined;
    var heap = testHeap(&bytes);

    const a = heap.allocPermanent(.string, 12).?;
    heap.releasePermanent(heap.allocPermanent(.string, 100).?);

    try std.testing.expectEqual(a - 16, heap.allocPermanent(.string, 12).?);
}
