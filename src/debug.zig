const io = @import("io.zig");
const value_mod = @import("value.zig");
const chunk_mod = @import("chunk.zig");
const Chunk = chunk_mod.Chunk;
const OpCode = chunk_mod.OpCode;

/// Print a whole chunk's bytecode.
pub fn disassembleChunk(chunk: *const Chunk, name: []const u8) void {
    io.printf("== {s} ==\n", .{name});
    var offset: usize = 0;
    while (offset < chunk.code_count) {
        offset = disassembleInstruction(chunk, offset);
    }
}

/// Disassemble one instruction at `offset`, returning the offset of the next.
pub fn disassembleInstruction(chunk: *const Chunk, offset: usize) usize {
    io.printf("{d:0>4} ", .{offset});

    const op: OpCode = @enumFromInt(chunk.code[offset]);
    return switch (op) {
        .OP_CONSTANT => constantInstruction("OP_CONSTANT", chunk, offset),
        .OP_ADD => simpleInstruction("OP_ADD", offset),
        .OP_SUBTRACT => simpleInstruction("OP_SUBTRACT", offset),
        .OP_MULTIPLY => simpleInstruction("OP_MULTIPLY", offset),
        .OP_DIVIDE => simpleInstruction("OP_DIVIDE", offset),
        .OP_NEGATE => simpleInstruction("OP_NEGATE", offset),
        .OP_RETURN => simpleInstruction("OP_RETURN", offset),
        else => blk: {
            io.printf("unknown opcode {d}\n", .{chunk.code[offset]});
            break :blk offset + 1;
        },
    };
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    io.printf("{s}\n", .{name});
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *const Chunk, offset: usize) usize {
    const index = chunk.code[offset + 1];
    io.printf("{s} {d} '", .{ name, index });
    value_mod.printValue(chunk.constants[index]);
    io.print("'\n");
    return offset + 2;
}
