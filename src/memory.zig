//! Noka Machine memory map.
//!
//! Every machine owns one 512 KiB block, and each region below lives at a fixed offset inside it.
//! Hosts should import these offsets as a source of truth.

const std = @import("std");
const Value = @import("value.zig").Value;
const strings = @import("strings.zig");
const globals_mod = @import("globals.zig");

pub const Region = struct {
    offset: usize,
    size: usize,

    pub fn end(self: Region) usize {
        return self.offset + self.size;
    }
};

const KiB = 1024;

pub const size = 512 * KiB;

// zig fmt: off
pub const disc =       Region{ .offset = 0x00000, .size = 64 * KiB };
pub const code =       Region{ .offset = 0x10000, .size = 64 * KiB };
pub const constants =  Region{ .offset = 0x20000, .size = 64 * KiB };
pub const vram =       Region{ .offset = 0x30000, .size = 48 * KiB };
pub const sprites =    Region{ .offset = 0x3C000, .size = 16 * KiB };
pub const map =        Region{ .offset = 0x40000, .size = 8 * KiB };
pub const sfx =        Region{ .offset = 0x42000, .size = 16 * KiB };
pub const palette_io = Region{ .offset = 0x46000, .size = 4 * KiB };
pub const stack =      Region{ .offset = 0x47000, .size = 64 * KiB };
pub const frames =     Region{ .offset = 0x57000, .size = 16 * KiB };
pub const globals =    Region{ .offset = 0x5B000, .size = 16 * KiB };
pub const heap =       Region{ .offset = 0x5F000, .size = 128 * KiB };
pub const font =       Region{ .offset = 0x7F000, .size = 2 * KiB };
pub const reserved =   Region{ .offset = 0x7F800, .size = 2 * KiB };
// zig fmt: on

pub const const_slots = constants.size / @sizeOf(Value); // 4096
pub const stack_slots = stack.size / @sizeOf(Value); // 4096
pub const globals_slots = globals.size / @sizeOf(Value); // 1024

/// The tables at the start of HEAP.
pub const Heap = struct {
    strings: strings.Strings = .{},
    names: globals_mod.Names = .{},

    pub fn reset(self: *Heap) void {
        self.strings.reset();
        self.names.reset();
    }
};

comptime {
    const all = [_]Region{ disc, code, constants, vram, sprites, map, sfx, palette_io, stack, frames, globals, heap, font, reserved };

    var at: usize = 0;
    for (all) |r| {
        if (r.offset != at) @compileError(std.fmt.comptimePrint("region at 0x{X} should start at 0x{X}", .{ r.offset, at }));
        at = r.end();
    }
    if (at != size) @compileError(std.fmt.comptimePrint("regions end at 0x{X}, not 0x{X}", .{ at, size }));
    if (@sizeOf(Heap) > heap.size) @compileError("the string and name tables don't fit in HEAP");
    if (@sizeOf(Value) != 16) @compileError(std.fmt.comptimePrint("Value is {d} B, the memory map assumes 16", .{@sizeOf(Value)}));
}
