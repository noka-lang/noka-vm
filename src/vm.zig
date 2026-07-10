const std = @import("std");
const io = @import("io.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Compiler = @import("compiler.zig").Compiler;
const debug = @import("debug.zig");
const Value = @import("value.zig").Value;
const printValue = @import("./value.zig").printValue;

const debug_print_bytecode = false;
const debug_trace_execution = false;

var heap_buffer: [1 << 20]u8 = undefined; // 1 MiB
var fba = std.heap.FixedBufferAllocator.init(&heap_buffer);
var disc: [64 * 1024]u8 = undefined; // 64 KiB, a disc's worth of source

export fn disc_ptr() [*]u8 {
    return &disc;
}

export fn disc_cap() usize {
    return disc.len;
}

export fn init() void {
    fba.reset();
    //TODO: once the VM holds globals / interned strings / a heap, reset
    // them here too so each run (or REPL line) starts clean.
}

var chunk: Chunk = undefined;

/// Compile and run the `len` bytes the host placed in `disc`.
/// Returns 0 on success, non-zero on error.
/// The host calls `init()` before calling this.
export fn eval(len: usize) i32 {
    if (len > disc.len) {
        io.print("source too large\n");
        return 1;
    }

    return compileAndRun(disc[0..len]);
}

/// Compile and run the given source code (a disc).
pub fn interpretSource(source: []const u8) i32 {
    init();

    return compileAndRun(source);
}

fn compileAndRun(source: []const u8) i32 {
    chunk = Chunk{};

    if (!Compiler.compile(source, &chunk)) return 1;
    if (debug_print_bytecode) debug.disassembleChunk(&chunk, "code");

    var vm = VM{ .chunk = &chunk };

    return if (vm.run()) 0 else 1;
}

// --- VM ---------------------------------------------------------------------

const stack_max = 256;

const VM = struct {
    chunk: *const Chunk,
    ip: usize = 0,
    stack: [stack_max]Value = undefined,
    sp: usize = 0,

    fn push(self: *VM, value: Value) void {
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    fn pop(self: *VM) Value {
        self.sp -= 1;
        return self.stack[self.sp];
    }

    fn readByte(self: *VM) u8 {
        const byte = self.chunk.code[self.ip];
        self.ip += 1;
        return byte;
    }

    fn readConstant(self: *VM) Value {
        return self.chunk.constants[self.readByte()];
    }

    fn run(self: *VM) bool {
        while (true) {
            if (debug_trace_execution) {
                _ = debug.disassembleInstruction(self.chunk, self.ip);
            }

            const op: OpCode = @enumFromInt(self.readByte());
            switch (op) {
                .OP_CONSTANT => self.push(self.readConstant()),
                // TODO: binary ops currently assume two numbers. Once Value is
                // a union, type-check operands and raise a runtime error on
                // mismatch.
                .OP_ADD => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a + b);
                },
                .OP_SUBTRACT => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a - b);
                },
                .OP_MULTIPLY => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a * b);
                },
                .OP_DIVIDE => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a / b);
                },
                .OP_NEGATE => self.push(-self.pop()),
                .OP_RETURN => {
                    // Temporary: print the result of the top-level expression.
                    // TODO: real `return` belongs to function calls; a
                    // top-level program should print via an explicit print
                    // statement/op instead of leaning on OP_RETURN.
                    printValue(self.pop());
                    io.print("\n");
                    return true;
                },
                else => {
                    io.print("runtime error: unknown opcode\n");
                    return false;
                },
            }
        }
    }
};

// --- TESTS ------------------------------------------------------------------

const testing = @import("std").testing;

fn expectOutput(source: []const u8, expected: []const u8) !void {
    io.beginCapture();
    defer io.endCapture();
    _ = interpretSource(source);
    try testing.expectEqualStrings(expected, io.captured());
}

test "arithmetic" {
    try expectOutput("1 + 2", "3\n");
    try expectOutput("7 - 9", "-2\n");
    try expectOutput("6 * 7", "42\n");
    try expectOutput("10 / 4", "2.5\n");
}

test "precedence and grouping" {
    try expectOutput("1 + 2 * 3", "7\n");
    try expectOutput("(1 + 2) * 3", "9\n");
    try expectOutput("8 / 4 / 2", "1\n");
}

test "unary minus" {
    try expectOutput("-5", "-5\n");
    try expectOutput("--5", "5\n");
    try expectOutput("-2 * 3", "-6\n");
}

test "compile errors are reported, not executed" {
    try expectOutput("(1 + 2", "compile error at end: expected ')' after expression\n");
    try expectOutput("1 +", "compile error at end: expected an expression\n");
    // Scanner error tokens awkwardly carry their message in `lexeme`, so it lands where
    // the offending text would normally go. Pinned here so a fix shows up as
    // a deliberate test change.
    try expectOutput("$", "compile error at 'unexpected character': unexpected character\n");
}

test "interpretSource returns nonzero on failure" {
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 0), interpretSource("1 + 1"));
    try testing.expectEqual(@as(i32, 1), interpretSource("1 +"));
}

test "eval rejects a length past the disc" {
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 1), eval(disc.len + 1));
    try testing.expectEqualStrings("source too large\n", io.captured());
}
