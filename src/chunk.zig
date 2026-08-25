const std = @import("std");

const Value = @import("value.zig").Value;

// TODO: add remaining opcodes
pub const OpCode = enum(u8) {
    constant,
    nil,
    // booleans
    true,
    false,
    // TODO: label
    pop,
    // operators
    equal,
    greater,
    less,
    add,
    subtract,
    multiply,
    divide,
    modulo,
    exponent,
    not,
    negate,
    // binary operators
    band,
    bnot,
    bor,
    bxor,
    shift_left,
    shift_right,
    // TODO: label
    jump,
    jump_if_false,
    print,
    @"return",
    _,
};

pub const Chunk = struct {
    pub const code_max = 1 << 16; // 64 KiB of bytecode
    pub const const_max = 1 << 12; // 4096 constant slots

    code: [code_max]u8 = undefined,
    code_count: usize = 0,
    constants: [const_max]Value = undefined,
    const_count: usize = 0,
    lines: [code_max]u32 = undefined,
    overflow: bool = false,

    pub fn writeByte(self: *Chunk, byte: u8) void {
        if (self.code_count >= code_max) {
            self.overflow = true;
            return;
        }
        self.code[self.code_count] = byte;
        self.code_count += 1;
    }

    pub fn writeOp(self: *Chunk, op: OpCode) void {
        self.writeByte(@intFromEnum(op));
    }

    /// Add a constant and return its index, reusing an existing slot when an
    /// identical value is already in the pool. On overflow return null.
    pub fn addConstant(self: *Chunk, value: Value) ?u16 {
        // NOTE: this loop is definitely not efficient but should be fine for now.
        // If it starts to get out of hand replace it with a hash map.
        for (self.constants[0..self.const_count], 0..) |existing, i| {
            if (sameConstant(existing, value)) return @intCast(i);
        }

        if (self.const_count >= const_max) {
            self.overflow = true;
            return null;
        }
        self.constants[self.const_count] = value;
        defer self.const_count += 1;
        return @intCast(self.const_count);
    }

    fn sameConstant(a: Value, b: Value) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;

        return switch (a) {
            .nil => true,
            .boolean => a.boolean == b.boolean,
            .number => @as(u64, @bitCast(a.number)) == @as(u64, @bitCast(b.number)),
        };
    }
};
