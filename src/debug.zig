const io = @import("io.zig");
const value_mod = @import("value.zig");
const chunk_mod = @import("chunk.zig");
const Chunk = chunk_mod.Chunk;
const OpCode = chunk_mod.OpCode;

/// Print a whole chunk's bytecode.
pub fn disassembleChunk(m: io.Handle, chunk: *const Chunk, name: []const u8) void {
    io.printf(m, "== begin {s} ==\n", .{name});
    var offset: usize = 0;
    while (offset < chunk.code_count) {
        offset = disassembleInstruction(m, chunk, offset);
    }
    io.printf(m, "== end {s} ==\n\n", .{name});
}

/// Disassemble one instruction at `offset`, and return the offset of the next.
pub fn disassembleInstruction(m: io.Handle, chunk: *const Chunk, offset: usize) usize {
    io.printf(m, "{d:0>4} ", .{offset});
    // TODO: put back line numbers

    const op: OpCode = @enumFromInt(chunk.code[offset]);
    return switch (op) {
        .add => simpleInstruction(m, "OP_ADD", offset),
        .band => simpleInstruction(m, "OP_BAND", offset),
        .bnot => simpleInstruction(m, "OP_BNOT", offset),
        .bor => simpleInstruction(m, "OP_BOR", offset),
        .bxor => simpleInstruction(m, "OP_BXOR", offset),
        .collapse => byteInstruction(m, "OP_COLLAPSE", chunk, offset),
        .constant => constantInstruction(m, "OP_CONSTANT", chunk, offset),
        .define_const => shortInstruction(m, "OP_DEFINE_CONST", chunk, offset),
        .define_global => shortInstruction(m, "OP_DEFINE_GLOBAL", chunk, offset),
        .divide => simpleInstruction(m, "OP_DIVIDE", offset),
        .equal => simpleInstruction(m, "OP_EQUAL", offset),
        .exponent => simpleInstruction(m, "OP_EXPONENT", offset),
        .false => simpleInstruction(m, "OP_FALSE", offset),
        .get_builtin => byteInstruction(m, "OP_GET_BUILTIN", chunk, offset),
        .get_global => shortInstruction(m, "OP_GET_GLOBAL", chunk, offset),
        .get_local => byteInstruction(m, "OP_GET_LOCAL", chunk, offset),
        .greater => simpleInstruction(m, "OP_GREATER", offset),
        .in => simpleInstruction(m, "OP_IN", offset),
        .jump => jumpInstruction(m, "OP_JUMP", 1, chunk, offset),
        .jump_if_false => jumpInstruction(m, "OP_JUMP_IF_FALSE", 1, chunk, offset),
        .jump_if_not_nil => jumpInstruction(m, "OP_JUMP_IF_NOT_NIL", 1, chunk, offset),
        .jump_if_true => jumpInstruction(m, "OP_JUMP_IF_TRUE", 1, chunk, offset),
        .less => simpleInstruction(m, "OP_LESS", offset),
        .loop => jumpInstruction(m, "OP_LOOP", -1, chunk, offset),
        .modulo => simpleInstruction(m, "OP_MODULO", offset),
        .multiply => simpleInstruction(m, "OP_MULTIPLY", offset),
        .negate => simpleInstruction(m, "OP_NEGATE", offset),
        .nil => simpleInstruction(m, "OP_NIL", offset),
        .not => simpleInstruction(m, "OP_NOT", offset),
        .pop => simpleInstruction(m, "OP_POP", offset),
        .print => simpleInstruction(m, "OP_PRINT", offset),
        .@"return" => simpleInstruction(m, "OP_RETURN", offset),
        .set_global => shortInstruction(m, "OP_SET_GLOBAL", chunk, offset),
        .set_local => byteInstruction(m, "OP_SET_LOCAL", chunk, offset),
        .shift_left => simpleInstruction(m, "OP_SHIFT_LEFT", offset),
        .shift_right => simpleInstruction(m, "OP_SHIFT_RIGHT", offset),
        .subtract => simpleInstruction(m, "OP_SUBTRACT", offset),
        .true => simpleInstruction(m, "OP_TRUE", offset),
        else => blk: {
            io.printf(m, "Unknown opcode {d}\n", .{chunk.code[offset]});
            break :blk offset + 1;
        },
    };
}

fn byteInstruction(m: io.Handle, name: []const u8, chunk: *const Chunk, offset: usize) usize {
    io.printf(m, "{s} {d}\n", .{ name, chunk.code[offset + 1] });
    return offset + 2;
}

fn shortInstruction(m: io.Handle, name: []const u8, chunk: *const Chunk, offset: usize) usize {
    io.printf(m, "{s} {d}\n", .{ name, readShort(chunk, offset) });
    return offset + 3;
}

fn jumpInstruction(m: io.Handle, name: []const u8, sign: i2, chunk: *const Chunk, offset: usize) usize {
    const jump = readShort(chunk, offset);
    io.printf(m, "{s} {d} -> {d}\n", .{ name, offset, @as(i32, @intCast(offset)) + 3 + sign * @as(i32, jump) });
    return offset + 3;
}

fn simpleInstruction(m: io.Handle, name: []const u8, offset: usize) usize {
    io.printf(m, "{s}\n", .{name});
    return offset + 1;
}

fn constantInstruction(m: io.Handle, name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const index = readShort(chunk, offset);
    io.printf(m, "{s} {d} '", .{ name, index });
    chunk.constants[index].print(m);
    io.print(m, "'\n");
    return offset + 3;
}

/// Reads the two-byte operand of the instruction at `offset`.
fn readShort(chunk: *const Chunk, offset: usize) u16 {
    return (@as(u16, chunk.code[offset + 1]) << 8) | chunk.code[offset + 2];
}
