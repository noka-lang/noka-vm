const io = @import("io.zig");
const value_mod = @import("value.zig");
const chunk_mod = @import("chunk.zig");
const Chunk = chunk_mod.Chunk;
const OpCode = chunk_mod.OpCode;

/// Print a whole chunk's bytecode.
pub fn disassembleChunk(chunk: *const Chunk, name: []const u8) void {
    io.printf("== begin {s} ==\n", .{name});
    var offset: usize = 0;
    while (offset < chunk.code_count) {
        offset = disassembleInstruction(chunk, offset);
    }
    io.printf("== end {s} ==\n\n", .{name});
}

/// Disassemble one instruction at `offset`, and return the offset of the next.
pub fn disassembleInstruction(chunk: *const Chunk, offset: usize) usize {
    io.printf("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.lines[offset] == chunk.lines[offset - 1]) {
        io.print("    | ");
    } else {
        io.printf(" {d: >4} ", .{offset});
    }

    const op: OpCode = @enumFromInt(chunk.code[offset]);
    return switch (op) {
        .constant => constantInstruction("OP_CONSTANT", chunk, offset),
        .in => return, // TODO
        .nil => simpleInstruction("OP_NIL", offset),
        .true => simpleInstruction("OP_TRUE", offset),
        .false => simpleInstruction("OP_FALSE", offset),
        .pop => simpleInstruction("OP_POP", offset),
        .equal => simpleInstruction("OP_EQUAL", offset),
        .greater => simpleInstruction("OP_GREATER", offset),
        .less => simpleInstruction("OP_LESS", offset),
        .add => simpleInstruction("OP_ADD", offset),
        .subtract => simpleInstruction("OP_SUBTRACT", offset),
        .multiply => simpleInstruction("OP_MULTIPLY", offset),
        .divide => simpleInstruction("OP_DIVIDE", offset),
        .modulo => simpleInstruction("OP_MODULO", offset),
        .exponent => simpleInstruction("OP_EXPONENT", offset),
        .not => simpleInstruction("OP_NOT", offset),
        .negate => simpleInstruction("OP_NEGATE", offset),
        .band => simpleInstruction("OP_BAND", offset),
        .bnot => simpleInstruction("OP_BNOT", offset),
        .bor => simpleInstruction("OP_BOR", offset),
        .bxor => simpleInstruction("OP_BXOR", offset),
        .shift_left => simpleInstruction("OP_SHIFT_LEFT", offset),
        .shift_right => simpleInstruction("OP_SHIFT_RIGHT", offset),
        .jump => jumpInstruction("OP_JUMP", 1, chunk, offset),
        .jump_if_false => jumpInstruction("OP_JUMP_IF_FALSE", 1, chunk, offset),
        .jump_if_not_nil => jumpInstruction("OP_JUMP_IF_NOT_NIL", 1, chunk, offset),
        .print => simpleInstruction("OP_PRINT", offset),
        .@"return" => simpleInstruction("OP_RETURN", offset),
        else => blk: {
            io.printf("Unknown opcode {d}\n", .{chunk.code[offset]});
            break :blk offset + 1;
        },
    };
}

fn jumpInstruction(name: []const u8, sign: i2, chunk: *const Chunk, offset: usize) usize {
    var jump = @as(u16, chunk.code[offset + 1]) << 8;
    jump |= chunk.code[offset + 2];
    io.printf("{s} {d} -> {d}\n", .{ name, offset, @as(i32, @intCast(offset)) + 3 + sign * @as(i32, jump) });
    return offset + 3;
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    io.printf("{s}\n", .{name});
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const index = (@as(u16, chunk.code[offset + 1]) << 8) | chunk.code[offset + 2];
    io.printf("{s} {d} '", .{ name, index });
    chunk.constants[index].print();
    io.print("'\n");
    return offset + 3;
}
