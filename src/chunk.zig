const std = @import("std");
const Value = @import("value.zig").Value;
const memory = @import("memory.zig");

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
    in,
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
    jump_if_not_nil,
    jump_if_true,
    // built-ins
    get_builtin,
    declare_builtin,
    assign_builtin,
    // globals
    define_global,
    define_const,
    get_global,
    set_global,
    get_local,
    set_local,
    collapse,
    loop,
    print,
    @"return",
    _,
};

pub const Chunk = struct {
    pub const code_max = memory.code.size;
    pub const const_max = memory.const_slots;
    pub const stack_max = 256;

    code: *[code_max]u8,
    code_count: usize = 0,
    constants: *[const_max]Value,
    const_count: usize = 0,
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

    /// Add a constant and return its index, reusing an existing slot when an identical value is
    /// already in the pool. On overflow return null.
    pub fn addConstant(self: *Chunk, value: Value) ?u16 {
        // NOTE: this loop is definitely not efficient but should be fine for now.
        // If it starts to get out of hand replace it with a hash map.
        for (self.constants[0..self.const_count], 0..) |existing, i| {
            if (existing.equals(value)) return @intCast(i);
        }

        if (self.const_count >= const_max) {
            self.overflow = true;
            return null;
        }
        self.constants[self.const_count] = value;
        defer self.const_count += 1;
        return @intCast(self.const_count);
    }
};
