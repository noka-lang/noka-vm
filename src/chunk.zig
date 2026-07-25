const Value = @import("value.zig").Value;

// TODO: add remaining opcodes
pub const OpCode = enum(u8) {
    constant,
    nil,
    // booleans
    true,
    false,
    // operators
    equal,
    greater,
    less,
    add,
    subtract,
    multiply,
    divide,
    modulo,
    not,
    negate,
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

    /// Add a constant and return its index. On overflow returns 0 and flags
    /// the chunk.
    pub fn addConstant(self: *Chunk, value: Value) u8 {
        if (self.const_count >= const_max) {
            self.overflow = true;
            return 0;
        }
        self.constants[self.const_count] = value;
        self.const_count += 1;
        return @intCast(self.const_count - 1);
    }
};
