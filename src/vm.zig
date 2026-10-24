const std = @import("std");
const io = @import("io.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Compiler = @import("compiler.zig").Compiler;
const debug = @import("debug.zig");
const Value = @import("value.zig").Value;
const disc_mod = @import("disc.zig");
const strings = @import("strings.zig");
const Mutability = @import("compiler.zig").Mutability;
const memory = @import("memory.zig");

const debug_print_bytecode = false;
const debug_trace_execution = false;

// ---- machine -----------------------------------------------------------------------------------

const globals_max = 256;

const Global = struct {
    name: *const strings.String,
    value: Value,
    mutability: Mutability,
};

const Machine = struct {
    block: [memory.size]u8 align(16) = undefined,
    chunk: Chunk = undefined,
    strings: strings.Strings = .{},
    globals: [globals_max]Global = undefined,
    globals_count: usize = 0,

    fn create() ?*Machine {
        const m = std.heap.page_allocator.create(Machine) catch return null;
        m.* = .{};

        return m;
    }

    fn destroy(self: *Machine) void {
        std.heap.page_allocator.destroy(self);
    }

    /// Returns one memory map region of this machine's block
    fn region(self: *Machine, comptime r: memory.Region) *[r.size]u8 {
        return self.block[r.offset..][0..r.size];
    }

    fn slots(self: *Machine, comptime r: memory.Region, comptime T: type) *[r.size / @sizeOf(T)]T {
        return @ptrCast(@alignCast(self.region(r)));
    }

    fn reset(self: *Machine) void {
        self.strings.reset();
        self.globals_count = 0;
    }

    fn eval(self: *Machine, len: usize) i32 {
        const disc = self.region(memory.disc);

        if (len > disc.len) {
            io.print("disc error: source too large.\n");
            return 1;
        }

        return self.compileAndRun(disc[0..len]);
    }

    fn loadDisc(self: *Machine, len: usize) i32 {
        const disc = self.region(memory.disc);

        if (len > disc.len) {
            io.print("disc error: disc too large.\n");
            return 1;
        }

        const image = disc[0..len];
        const header = disc_mod.parse(image) catch |e| {
            io.printf("disc error: {s}.\n", .{disc_mod.describe(e)});
            return 1;
        };

        const src = header.section(image, .src) orelse {
            io.print("disc error: disc has no source.\n");
            return 1;
        };

        // TODO: handle the rest of the disc sections

        return self.compileAndRun(src);
    }

    fn compileAndRun(self: *Machine, source: []const u8) i32 {
        self.chunk = .{ .code = self.region(memory.code), .constants = self.slots(memory.constants, Value) };

        if (!Compiler.compile(source, &self.chunk, &self.strings)) return 1;
        if (debug_print_bytecode) debug.disassembleChunk(&self.chunk, "compiled code");

        var vm = VM{ .machine = self, .chunk = &self.chunk };

        return if (vm.run()) 0 else 1;
    }

    fn defineGlobal(self: *Machine, name: *const strings.String, value: Value, mutability: Mutability) error{ AlreadyDeclared, TooManyGlobals }!void {
        if (self.findGlobal(name) != null) return error.AlreadyDeclared;
        if (self.globals_count >= globals_max) return error.TooManyGlobals;

        self.globals[self.globals_count] = .{ .name = name, .value = value, .mutability = mutability };
        self.globals_count += 1;
    }

    fn findGlobal(self: *Machine, name: *const strings.String) ?*Global {
        for (self.globals[0..self.globals_count]) |*global| {
            if (global.name == name) return global;
        }

        return null;
    }
};

// ---- exports -----------------------------------------------------------------------------------

export fn noka_new() ?*Machine {
    return Machine.create();
}

export fn noka_free(m: *Machine) void {
    m.destroy();
}

export fn noka_reset(m: *Machine) void {
    m.reset();
}

export fn noka_memory(m: *Machine) [*]u8 {
    return &m.block;
}

/// Returns 0 on success, non-zero on error.
export fn noka_eval(m: *Machine, len: usize) i32 {
    return m.eval(len);
}

/// Returns 0 on success, non-zero on error.
export fn noka_load_disc(m: *Machine, len: usize) i32 {
    return m.loadDisc(len);
}

pub fn interpretSource(source: []const u8) i32 {
    const m = Machine.create() orelse {
        io.print("out of memory.\n");
        return 1;
    };
    defer m.destroy();

    return m.compileAndRun(source);
}

pub fn interpretDisc(image: []const u8) i32 {
    const m = Machine.create() orelse {
        io.print("out of memory.\n");
        return 1;
    };
    defer m.destroy();
    if (image.len > memory.disc.size) {
        io.print("disc error: disc too large.\n");
        return 1;
    }
    @memcpy(m.region(memory.disc)[0..image.len], image);

    return m.loadDisc(image.len);
}

// ---- VM ----------------------------------------------------------------------------------------

const VM = struct {
    machine: *Machine,
    chunk: *const Chunk,
    ip: usize = 0,
    stack: [Chunk.stack_max]Value = undefined,
    sp: usize = 0,

    fn push(self: *VM, value: Value) void {
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    fn pop(self: *VM) Value {
        self.sp -= 1;
        return self.stack[self.sp];
    }

    fn peek(self: *VM, distance: usize) Value {
        return self.stack[self.sp - 1 - distance];
    }

    fn readByte(self: *VM) u8 {
        const byte = self.chunk.code[self.ip];
        self.ip += 1;
        return byte;
    }

    fn readShort(self: *VM) u16 {
        const hi: u16 = self.readByte();
        const lo: u16 = self.readByte();

        return (hi << 8) | lo;
    }

    fn readConstant(self: *VM) Value {
        return self.chunk.constants[self.readShort()];
    }

    fn toInt32(self: *VM, n: f64) ?i32 {
        if (@trunc(n) != n) {
            _ = self.runtimeError("bitwise expected whole number, got {d}", .{n});
            return null;
        }

        if (n < std.math.minInt(i32) or n > std.math.maxInt(i32)) {
            _ = self.runtimeError("bitwise expected 32-bit number, got {d}", .{n});
            return null;
        }

        return @intFromFloat(n);
    }

    fn run(self: *VM) bool {
        while (true) {
            if (debug_trace_execution) {
                _ = debug.disassembleInstruction(self.chunk, self.ip);
            }

            const op: OpCode = @enumFromInt(self.readByte());
            switch (op) {
                .constant => self.push(self.readConstant()),
                .nil => self.push(.nil),
                .true => self.push(Value{ .boolean = true }),
                .false => self.push(Value{ .boolean = false }),
                .pop => {
                    _ = self.pop();
                },
                .equal => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(.{ .boolean = a.equals(b) });
                },
                .greater, .less => {
                    const b = self.pop();
                    const a = self.pop();

                    if (a != .number or b != .number) {
                        return self.runtimeError("compare expected two numbers, got {s} and {s}", .{ a.typeName(), b.typeName() });
                    }

                    self.push(.{ .boolean = switch (op) {
                        .greater => a.number > b.number,
                        .less => a.number < b.number,
                        else => unreachable,
                    } });
                },
                .add => {
                    const b = self.pop();
                    const a = self.pop();

                    if (a == .string and b == .string) {
                        var builder = self.machine.strings.build();
                        builder.pushSlice(a.string.bytes);
                        builder.pushSlice(b.string.bytes);

                        const joined = builder.finish() orelse {
                            return self.runtimeError("out of string memory", .{});
                        };

                        self.push(.{ .string = joined });
                        continue;
                    }

                    if (a != .number or b != .number) {
                        return self.runtimeError("'add' expected two numbers or strings, got {s} and {s}", .{ a.typeName(), b.typeName() });
                    }

                    self.push(.{ .number = a.number + b.number });
                },
                .subtract, .multiply, .divide, .modulo, .exponent => {
                    const b = self.pop();
                    const a = self.pop();

                    if (a != .number or b != .number) {
                        return self.runtimeError("'{s}' expected two numbers, got {s} and {s}", .{ @tagName(op), a.typeName(), b.typeName() });
                    }

                    self.push(.{ .number = switch (op) {
                        .add => a.number + b.number,
                        .subtract => a.number - b.number,
                        .multiply => a.number * b.number,
                        .divide => a.number / b.number,
                        .modulo => @rem(a.number, b.number),
                        .exponent => std.math.pow(f64, a.number, b.number),
                        else => unreachable,
                    } });
                },
                .band, .bor, .bxor, .shift_left, .shift_right => {
                    const b = self.pop();
                    const a = self.pop();

                    if (a != .number or b != .number) {
                        return self.runtimeError("'{s}' expected two numbers, got {s} and {s}", .{ @tagName(op), a.typeName(), b.typeName() });
                    }

                    const ai = self.toInt32(a.number) orelse return false;
                    const bi = self.toInt32(b.number) orelse return false;

                    const sh: u5 = switch (op) {
                        .shift_left, .shift_right => blk: {
                            if (bi < 0 or bi > 31) {
                                return self.runtimeError("'{s}' expected shift of 0-31, got {d}", .{ @tagName(op), bi });
                            }
                            break :blk @intCast(bi);
                        },
                        else => 0,
                    };

                    self.push(.{ .number = @floatFromInt(switch (op) {
                        .band => ai & bi,
                        .bor => ai | bi,
                        .bxor => ai ^ bi,
                        .shift_left => ai << sh,
                        .shift_right => ai >> sh,
                        else => unreachable,
                    }) });
                },
                .negate => {
                    const v = self.pop();

                    if (v != .number) {
                        return self.runtimeError("negate expected number, got {s}", .{v.typeName()});
                    }

                    self.push(.{ .number = -v.number });
                },
                .not => {
                    const v = self.pop();

                    if (v != .boolean) {
                        return self.runtimeError("'not' expected boolean, got {s}", .{v.typeName()});
                    }

                    self.push(.{ .boolean = !v.boolean });
                },
                .in => {
                    const haystack = self.pop();
                    const needle = self.pop();

                    // TODO: arrays and objects
                    if (needle != .string or haystack != .string) {
                        return self.runtimeError("'in' expected two strings, got {s} and {s}", .{ needle.typeName(), haystack.typeName() });
                    }

                    self.push(.{ .boolean = std.mem.indexOf(u8, haystack.string.bytes, needle.string.bytes) != null });
                },
                .bnot => {
                    const v = self.pop();

                    if (v != .number) {
                        return self.runtimeError("'bnot' expected number, got {s}", .{v.typeName()});
                    }

                    const vi = self.toInt32(v.number) orelse return false;
                    self.push(.{ .number = @floatFromInt(~vi) });
                },
                .print => {
                    self.pop().print();
                    io.print("\n");
                },
                .jump => {
                    const offset = self.readShort();
                    self.ip += offset;
                },
                .jump_if_false => {
                    const offset = self.readShort();
                    const cond = self.peek(0);
                    if (cond != .boolean) {
                        return self.runtimeError("condition expected boolean, got {s}", .{cond.typeName()});
                    }

                    if (cond.boolean == false) self.ip += offset;
                },
                .jump_if_not_nil => {
                    const offset = self.readShort();
                    if (self.peek(0) != .nil) self.ip += offset;
                },
                .jump_if_true => {
                    const offset = self.readShort();
                    const cond = self.peek(0);
                    if (cond != .boolean) {
                        return self.runtimeError("condition expected boolean, got {s}", .{cond.typeName()});
                    }
                    if (cond.boolean) self.ip += offset;
                },
                .define_global, .define_const => {
                    const name = self.readConstant().string;
                    const mutability: Mutability = switch (op) {
                        .define_const => .constant,
                        .define_global => .mutable,
                        else => unreachable,
                    };

                    self.machine.defineGlobal(name, self.pop(), mutability) catch |e| return switch (e) {
                        error.AlreadyDeclared => self.runtimeError("'{s}' has already been declared", .{name.bytes}),
                        error.TooManyGlobals => self.runtimeError("globals limit exceeded", .{}),
                    };
                },
                .get_global => {
                    const name = self.readConstant().string;
                    const global = self.machine.findGlobal(name) orelse {
                        return self.runtimeError("undefined variable '{s}'", .{name.bytes});
                    };

                    self.push(global.value);
                },
                .set_global => {
                    const name = self.readConstant().string;
                    const global = self.machine.findGlobal(name) orelse {
                        return self.runtimeError("undefined variable '{s}'", .{name.bytes});
                    };

                    if (global.mutability == .constant) {
                        return self.runtimeError("'{s}' is constant and cannot be reassigned", .{name.bytes});
                    }

                    global.value = self.peek(0);
                },
                // TODO: replace absolute indices with frame-relative ones
                .get_local => {
                    const slot = self.readByte();
                    self.push(self.stack[slot]);
                },
                .set_local => {
                    const slot = self.readByte();
                    self.stack[slot] = self.peek(0);
                },
                .loop => {
                    const offset = self.readShort();
                    self.ip -= offset;
                },
                .collapse => {
                    const n = self.readByte();
                    self.stack[self.sp - 1 - n] = self.stack[self.sp - 1];
                    self.sp -= n;
                },
                .@"return" => {
                    // Temporary: print the result of the top-level expression.
                    // TODO: real `return` belongs to function calls; a top-level program should
                    // print via an explicit print statement/op instead of leaning on OP_RETURN.
                    if (self.sp > 0) {
                        self.pop().print();
                        io.print("\n");
                    }
                    return true;
                },
                _ => {
                    io.printf("runtime error: unknown opcode {d}.\n", .{@intFromEnum(op)});
                    return false;
                },
            }
        }
    }

    fn runtimeError(self: *VM, comptime message: []const u8, args: anytype) bool {
        // TODO: print line number
        _ = self;
        io.printf("runtime error: " ++ message ++ ".\n", args);

        return false;
    }
};

// ---- TESTS -------------------------------------------------------------------------------------

const testing = @import("std").testing;

fn expectOutput(source: []const u8, expected: []const u8) !void {
    io.beginCapture();
    defer io.endCapture();
    const code = interpretSource(source);

    try testing.expectEqualStrings(expected, std.mem.trimEnd(u8, io.captured(), "\n"));
    try testing.expectEqual(@as(i32, 0), code);
}

fn expectFailure(source: []const u8, expected: []const u8) !void {
    io.beginCapture();
    defer io.endCapture();
    const code = interpretSource(source);

    try testing.expectEqualStrings(expected, std.mem.trimEnd(u8, io.captured(), "\n"));
    try testing.expectEqual(@as(i32, 1), code);
}

fn evalIn(m: *Machine, source: []const u8) i32 {
    @memcpy(m.region(memory.disc)[0..source.len], source);
    return noka_eval(m, source.len);
}

test "ignore spaces" {
    try expectOutput("2<3", "true");
    try expectOutput("2 < 3", "true");
}

test "literals" {
    try expectOutput("true", "true");
    try expectOutput("false", "false");
    try expectOutput("nil", "nil");
    try expectOutput("42", "42");
    try expectOutput("3.14", "3.14");
}

test "arithmetic" {
    try expectOutput("1 + 2", "3");
    try expectOutput("7 - 9", "-2");
    try expectOutput("6 * 7", "42");
    try expectOutput("10 / 4", "2.5");
}

test "equality" {
    try expectOutput("1 == 1", "true");
    try expectOutput("1 != 2", "true");
    try expectOutput("true == true", "true");
    try expectOutput("nil == nil", "true");
    try expectOutput("nil == false", "false");
    try expectOutput("1 == true", "false");
}

test "comparison" {
    try expectOutput("1 < 2", "true");
    try expectOutput("2 > 1", "true");
    try expectOutput("3 <= 4", "true");
    try expectOutput("4 >= 3", "true");
    try expectOutput("5 <= 5", "true");
    try expectOutput("6 >= 6", "true");
    try expectFailure("1 < true", "runtime error: compare expected two numbers, got number and boolean.");
}

test "boolean logical operators" {
    try expectOutput("not true", "false");
    try expectOutput("not false", "true");
    try expectOutput("true and true", "true");
    try expectOutput("true and false", "false");
    try expectOutput("false and true", "false");
    try expectOutput("false and false", "false");
    try expectOutput("true or true", "true");
    try expectOutput("true or false", "true");
    try expectOutput("false or true", "true");
    try expectOutput("false or false", "false");
    try expectFailure("not 1", "runtime error: 'not' expected boolean, got number.");
    try expectFailure("1 and 2", "runtime error: condition expected boolean, got number.");
    try expectFailure("true band 1", "runtime error: 'band' expected two numbers, got boolean and number.");
    try expectFailure("1.5 band 2", "runtime error: bitwise expected whole number, got 1.5.");
    try expectFailure("5000000000 bor 1", "runtime error: bitwise expected 32-bit number, got 5000000000.");
    try expectFailure("!true", "compile error at end: '!' is not an operator, use 'not' for logical negation.");
}

test "bitwise logical operators" {
    try expectOutput("12 band 10", "8");
    try expectOutput("12 bor 10", "14");
    try expectOutput("12 bxor 10", "6");
    try expectOutput("bnot -3", "2");
    try expectOutput("bnot 0", "-1");
    try expectOutput("1 bor 2 band 3", "3");
}

test "short-circuiting operators" {
    try expectOutput("false and (1 + true)", "false");
    try expectFailure("true and (1 + true)", "runtime error: 'add' expected two numbers or strings, got number and boolean.");
    try expectOutput("true or (1 + true)", "true");
    try expectFailure("false or (1 + true)", "runtime error: 'add' expected two numbers or strings, got number and boolean.");
    try expectOutput("3 ?? (1 + true)", "3");
}

test "arithmetic on non-numbers is a runtime error" {
    try expectFailure("1 + true", "runtime error: 'add' expected two numbers or strings, got number and boolean.");
    try expectFailure("nil - false", "runtime error: 'subtract' expected two numbers, got nil and boolean.");
    try expectFailure("3 * true", "runtime error: 'multiply' expected two numbers, got number and boolean.");
    try expectFailure("false / 4", "runtime error: 'divide' expected two numbers, got boolean and number.");
}

test "negating a non-number is a runtime error" {
    try expectFailure("-true", "runtime error: negate expected number, got boolean.");
    try expectFailure("-nil", "runtime error: negate expected number, got nil.");
}

test "precedence and grouping" {
    try expectOutput("1 - 2 - 3", "-4");
    try expectOutput("1 + 2 * 3", "7");
    try expectOutput("(1 + 2) * 3", "9");
    try expectOutput("8 / 4 / 2", "1");
    try expectOutput("2 < 3 == true", "true");
    try expectOutput("not true == false", "true");
    try expectOutput("1 << 2 + 1", "8");
    try expectOutput("2 * 3 ** 2", "18");
    //TODO: one case per bitwise level against equality, mirroring LANGUAGE.md's table
}

test "right-associativity" {
    try expectOutput("2 ** 3 ** 2", "512");
}

test "modulo" {
    try expectOutput("8 % 3", "2");
    try expectOutput("-7 % 3", "-1");
}

test "shift" {
    try expectOutput("2 << 3", "16");
    try expectOutput("-8 >> 1", "-4");
}

test "unary minus" {
    try expectOutput("-5", "-5");
    try expectOutput("--5", "5");
    try expectOutput("-2 * 3", "-6");
}

test "blocks and locals" {
    try expectOutput("do\n  a : 2\n a * 3\nend", "6");
    try expectOutput("x : do\n  a : 2\n  b : 3\n  a + b\nend\nx", "5");
    try expectOutput("do end", "nil");
    try expectOutput("a : 1\ndo\n  a : 2\n  a\nend", "2"); // shadowing
    try expectOutput("a : 1\ndo\n  a : 2\nend\na", "1");
    try expectOutput("1 + do\n  a : 2\n  a\nend", "3");
    try expectOutput("do\n  a : 1\n  a = 2\n  a\nend", "2");
    try expectFailure("do\n  a : 1\n  a : 2\nend", "compile error at 'a': 'a' has already been declared.");
}

test "strings" {
    try expectOutput("\"hello\"", "hello");
    try expectOutput("'hello'", "hello");
    try expectOutput("\"\"", "");
    try expectOutput("'Noka says \"hi\"'", "Noka says \"hi\"");
    try expectOutput("\"it's fine\"", "it's fine");
}

test "string escapes" {
    try expectOutput("\"a\\tb\"", "a\tb");
    try expectOutput("\"a\\nb\"", "a\nb");
    try expectOutput("\"a\\\\b\"", "a\\b");
    try expectOutput("\"a\\\"b\"", "a\"b");
    try expectOutput("'a\\'b'", "a'b");
    try expectFailure("\"a\\qb\"", "compile error at '\"a\\qb\"': unknown escape '\\q'.");
}

test "string concatenation" {
    try expectOutput("\"foo\" + \"bar\"", "foobar");
    try expectOutput("\"a\" + \"b\" + \"c\"", "abc");
    try expectFailure("\"score: \" + 10", "runtime error: 'add' expected two numbers or strings, got string and number.");
    try expectFailure("\"a\" - \"b\"", "runtime error: 'subtract' expected two numbers, got string and string.");
}

test "string equality" {
    try expectOutput("\"a\" == \"a\"", "true");
    try expectOutput("\"a\" == \"b\"", "false");
    try expectOutput("\"a\" != \"b\"", "true");
    try expectOutput("\"ab\" == \"a\" + \"b\"", "true");
    try expectOutput("\"a\" == 1", "false");
    try expectOutput("\"\" == nil", "false");
}

test "string 'in' operator" {
    try expectOutput("\"ok\" in \"it is ok\"", "true");
    try expectOutput("\"no\" in \"it is ok\"", "false");
    try expectOutput("\"ok\" not in \"it is ok\"", "false");
    try expectFailure("1 in \"abc\"", "runtime error: 'in' expected two strings, got number and string.");
}

test "unterminated/unsupported strings" {
    try expectFailure("\"abc", "compile error at '\"abc': unterminated string.");
    try expectFailure("\"abc\nx\"", "compile error at '\"abc': unterminated string.");
    try expectFailure("f\"hi\"", "compile error at 'f': string prefixes are not supported (yet).");
    try expectFailure("m'hi'", "compile error at 'm': string prefixes are not supported (yet).");
}

test "global declarations" {
    try expectOutput("x : 10\nx", "10");
    try expectOutput("x : 10\nx + 5", "15");
    try expectOutput("greeting : \"hi\"\ngreeting + \" there\"", "hi there");
    try expectOutput("a : 1\nb : 2\na + b", "3");
}

test "assignment is an expression" {
    try expectOutput("x : 10\nx = 20\nx", "20");
    try expectOutput("x : 10\nx = 20", "20");
    try expectOutput("x : 10\ny : x = 5\ny + x", "10");
}

test "constants cannot be reassigned" {
    try expectOutput("PI # 3.14\nPI", "3.14");
    try expectFailure("PI # 3.14\nPI = 0", "runtime error: 'PI' is constant and cannot be reassigned.");
}

test "undeclared and redeclared are runtime errors" {
    try expectFailure("y", "runtime error: undefined variable 'y'.");
    try expectFailure("y = 5", "runtime error: undefined variable 'y'.");
    try expectFailure("x : 10\nx : 20", "runtime error: 'x' has already been declared.");
    try expectFailure("x : 10\nx # 20", "runtime error: 'x' has already been declared.");
}

test "declarations require an initializer" {
    try expectFailure("x :", "compile error at end: expected expression.");
    try expectFailure("a : 1\nb : 2\nc : 3\na * b = c", "compile error at '=': invalid assignment target.");
}

test "globals reset between runs" {
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 0), interpretSource("x : 1\nx"));
    try testing.expectEqual(@as(i32, 0), interpretSource("x : 2\nx"));
}

// TODO: when arrays are added test deep-freeze

test "bare case expression" {
    try expectOutput("case 1 < 2 -> \"yes\"", "yes");
    try expectOutput("case 1 > 2 -> \"yes\"", "nil");
    try expectOutput("case\n  1 > 2 -> \"a\"\n  2 > 1 -> \"b\"\nend", "b");
    try expectOutput("case\n  false -> \"a\"\n  _ -> \"fallback\"\nend", "fallback");
    try expectOutput("x : case\n  true -> 10\nend\nx", "10");
    try expectOutput("case true -> do\n  a : 2\n  a * 3\nend", "6");
    try expectFailure("case 1 -> \"x\"", "runtime error: condition expected boolean, got number.");
}

test "single-pattern case expression" {
    try expectOutput("case \"b\"\n  \"a\" -> 1\n  \"b\" -> 2\nend", "2");
    try expectOutput("case 3\n  1 -> \"one\"\n  _ -> \"other\"\nend", "other");
    try expectOutput("case 75\n  > 50 -> \"healthy\"\n  > 20 -> \"hurt\"\n  _ -> \"critical\"\nend", "healthy");
    try expectOutput("case 5\n  >= 5 -> \"ok\"\nend", "ok");
    try expectOutput("case 9\n  1 -> \"one\"\nend", "nil");
    try expectOutput("x : case \"b\"\n  \"b\" -> 2\nend\nx", "2");
    try expectOutput("1 + case 1\n  1 -> 2\nend", "3");
    try expectFailure("case\n  > 5 -> \"x\"\nend", "compile error at '>': no left-hand side to compare against.");
}

test "multi-pattern case expression" {
    try expectOutput("case \"north\"\n  \"up\", \"north\" -> \"go north\"\n  _ -> \"?\"\nend", "go north");
    try expectOutput("case 3\n  1, 2 -> \"low\"\n  3, 4 -> \"high\"\nend", "high");
}

test "guarded case expression" {
    try expectOutput("case 150\n  > 100 if true -> \"epic\"\n  > 100 -> \"great\"\nend", "epic");
    try expectOutput("case 150\n  > 100 if false -> \"epic\"\n  > 100 -> \"great\"\nend", "great");
    try expectFailure("case 1\n  1 if 2 -> \"x\"\nend", "runtime error: condition expected boolean, got number.");
}

test "case bodies can assign" {
    try expectOutput("status : \"\"\ncase\n  true -> status = \"healthy\"\nend\nstatus", "healthy");
    try expectOutput("x : 0\ncase true -> x = 5\nx", "5");
    try expectOutput("x : 0\ncase\n  false -> 1\n  _ -> x = 9\nend\nx", "9");
    try expectOutput("x : 0\ncase 2\n  2 -> x = 7\nend\nx", "7");
}

test "a broken case subject is a compile error" {
    try expectFailure("case )\n  1 -> 2\nend", "compile error at ')': expected expression.");
}

test "newlines around a lone expression are dropped" {
    try expectOutput("1 + 2\n", "3");
    try expectOutput("\n\n1 + 2", "3");
    try expectOutput("\n  \n1 + 2\n  \n\n", "3");
}

test "newline between expressions separates" {
    try expectOutput("1\n2", "2");
    try expectOutput("1\n  \n2", "2");
    try expectOutput("1 + 1\n2 * 3", "6");
    try expectFailure("1 2", "compile error at '2': expected end of statement.");
}

test "compile errors are reported, not executed" {
    try expectFailure("(1 + 2", "compile error at end: expected ')' after expression.");
    try expectFailure("1 +", "compile error at end: expected expression.");
    try expectFailure("$", "compile error at '$': unexpected character.");
}

test "interpretSource returns nonzero on failure" {
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 0), interpretSource("1 + 1"));
    try testing.expectEqual(@as(i32, 1), interpretSource("1 +"));
}

test "exceeding local and stack limits are compile errors" {
    var buf: [8192]u8 = undefined;

    // 255 locals: ok
    var w: std.Io.Writer = .fixed(&buf);
    try w.writeAll("do\n");
    for (0..255) |i| try w.print("  v{d} : {d}\n", .{ i, i });
    try w.writeAll("  v254\nend");
    try expectOutput(w.buffered(), "254");

    w = .fixed(&buf);
    try w.writeAll("do\n");
    for (0..256) |i| try w.print("  v{d} : {d}\n", .{ i, i });
    try w.writeAll("end");
    try expectFailure(w.buffered(), "compile error at 'v255': too many locals in scope.");

    w = .fixed(&buf);
    for (0..300) |_| try w.writeAll("1 + (");
    try w.writeAll("1");
    for (0..300) |_| try w.writeAll(")");
    try expectFailure(w.buffered(), "compile error at '1': expression too deep.");
}

test "unimplemented syntax is a compile error" {
    try expectFailure("1 + for", "compile error at 'for': not supported (yet).");
    try expectFailure("x : fn", "compile error at 'fn': not supported (yet).");
    try expectFailure("this", "compile error at 'this': not supported (yet).");
    try expectFailure("x : 1\nx.y", "compile error at '.': not supported (yet).");
    try expectFailure("x : 1\nx(", "compile error at '(': not supported (yet).");
}

test "local constants" {
    try expectOutput("do\n  PI # 3\n  PI * 2\nend", "6");
    try expectFailure("do\n  PI # 3\n  PI = 4\nend", "compile error at 'PI': 'PI' is constant and cannot be reassigned.");
    try expectFailure("do\n  PI # 3\n  PI : 4\nend", "compile error at 'PI': 'PI' has already been declared.");
}

test "every comparison pattern" {
    try expectOutput("case 3\n  == 3 -> \"eq\"\nend", "eq");
    try expectOutput("case 3\n  != 3 -> \"ne\"\n  _ -> \"not ne\"\nend", "not ne");
    try expectOutput("case 3\n  < 5 -> \"lt\"\nend", "lt");
    try expectOutput("case 5\n  <= 5 -> \"le\"\nend", "le");
    try expectOutput("case 5\n  > 5 -> \"gt\"\n  >= 5 -> \"ge\"\nend", "ge");
}

test "case structure" {
    try expectOutput("case 1\nend", "nil");
    try expectOutput("case\nend", "nil");
    try expectOutput("case 2\n  2 -> case 3\n    3 -> \"inner\"\n  end\n  _ -> \"outer\"\nend", "inner");
    try expectOutput("do\n  a : 5\n  b : 7\n  case b\n    > a -> b - a\n    _ -> 0\n  end\nend", "2");
    try expectOutput("do\n  r : case 1\n    1 -> 10\n  end\n  z : 5\n  r + z\nend", "15");
    try expectFailure("case 1\n  _ -> 1\n  2 -> 3\nend", "compile error at '2': '_' must be the last branch.");
    try expectFailure("case 1\n  1 -> 2\n", "compile error at end: expected 'end' to close 'case'.");
    try expectFailure("case 1\n  _ -> 2\n", "compile error at end: expected 'end' to close 'case'.");
}

test "while loops" {
    try expectOutput("i : 0\nwhile i < 3\n  i = i + 1\nend", "3");
    try expectOutput("while false\n  1\nend", "nil");
    try expectOutput("x : while false\n  1\nend\nx", "nil");
    try expectOutput("i : 0\nwhile i < 3\n  j : i * 2\n  i = i + 1\n  j\nend", "4");
    try expectFailure("while 1\n  2\nend", "runtime error: condition expected boolean, got number.");
    try expectFailure("while true 1 end", "compile error at '1': expected newline after 'while' condition.");
    try expectFailure("while true\n  1\n", "compile error at end: expected 'end' to close 'while'.");
}

test "stop statement" {
    try expectOutput("i : 0\nwhile true\n  i = i + 1\n  case i == 5 -> stop i * 10\nend", "50");
    try expectOutput("while true\n  stop\nend", "nil");
    try expectOutput("while true\n  do\n    a : 7\n    case a > 5 -> stop a\n  end\nend", "7");
    try expectOutput("i : 0\nwhile true\n  i = i + 1\n  x : 100 + case i\n    3 -> stop i\n    _ -> 0\n  end\nend", "3");
    try expectFailure("stop", "compile error at 'stop': 'stop' outside of a loop.");
    try expectFailure("1 + stop", "compile error at 'stop': expected expression.");
}

test "next statement" {
    try expectOutput("i : 0\ntotal : 0\nwhile i < 6\n  i = i + 1\n  case i % 2 == 0 -> next\n  total = total + i\nend", "9");
    try expectOutput("i : 0\nwhile i < 3\n  i = i + 1\n  a : i\n  case true -> next\nend", "nil");
    try expectFailure("next", "compile error at 'next': 'next' outside of a loop.");
}

test "nested loops" {
    try expectOutput("count : 0\ni : 0\nwhile i < 3\n  i = i + 1\n  j : 0\n  while true\n    j = j + 1\n    count = count + 1\n    case j == 2 -> stop\n  end\nend\ncount", "6");
    try expectOutput("i : 0\nwhile i < 3\n  i = i + 1\n  while true\n    stop i\n  end\nend", "3");
}

// ---- Machine tests -----------------------------------------------------------------------------

test "a machine made with create runs a program" {
    const m = Machine.create() orelse return error.OutOfMemory;
    defer m.destroy();

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 0), m.compileAndRun("x : 6\nx * 7"));
    try testing.expectEqualStrings("42\n", io.captured());
}

test "two machines keep separate globals" {
    const a = noka_new() orelse return error.OutOfMemory;
    defer noka_free(a);
    const b = noka_new() orelse return error.OutOfMemory;
    defer noka_free(b);

    io.beginCapture();
    defer io.endCapture();

    // declare `x` in both machines, there should not be any redeclaration error
    try testing.expectEqual(@as(i32, 0), evalIn(a, "x : 1"));
    try testing.expectEqual(@as(i32, 0), evalIn(b, "x : 2"));
    try testing.expectEqual(@as(i32, 0), evalIn(a, "y : \"only a\""));

    io.beginCapture();
    try testing.expectEqual(@as(i32, 0), evalIn(a, "x"));
    try testing.expectEqual(@as(i32, 0), evalIn(b, "x"));
    try testing.expectEqual(@as(i32, 0), evalIn(a, "y"));
    try testing.expectEqualStrings("1\n2\nonly a\n", io.captured());

    io.beginCapture();
    try testing.expectEqual(@as(i32, 1), evalIn(b, "y"));
    try testing.expectEqualStrings("runtime error: undefined variable 'y'.\n", io.captured());
}

test "resetting one machine leaves the other intact" {
    const a = noka_new() orelse return error.OutOfMemory;
    defer noka_free(a);
    const b = noka_new() orelse return error.OutOfMemory;
    defer noka_free(b);

    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(@as(i32, 0), evalIn(a, "x : \"from a\""));
    try testing.expectEqual(@as(i32, 0), evalIn(b, "x : \"from b\""));
    noka_reset(a);

    io.beginCapture();
    try testing.expectEqual(@as(i32, 1), evalIn(a, "x"));
    try testing.expectEqual(@as(i32, 0), evalIn(b, "x"));
    try testing.expectEqualStrings("runtime error: undefined variable 'x'.\nfrom b\n", io.captured());
}

// ---- Disc tests --------------------------------------------------------------------------------

test "eval rejects a length past the disc size" {
    const m = noka_new() orelse return error.OutOfMemory;
    defer noka_free(m);

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 1), noka_eval(m, memory.disc.size + 1));
    try testing.expectEqualStrings("disc error: source too large.\n", io.captured());
}

test "load_disc rejects a length past the disc size" {
    const m = noka_new() orelse return error.OutOfMemory;
    defer noka_free(m);

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 1), noka_load_disc(m, memory.disc.size + 1));
    try testing.expectEqualStrings("disc error: disc too large.\n", io.captured());
}

test "load_disc runs a disc's source" {
    const m = noka_new() orelse return error.OutOfMemory;
    defer noka_free(m);

    @memset(m.region(memory.disc), 0);
    const image = disc_mod.forgeDisc(m.region(memory.disc), "1 + 2 * 3");
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 0), noka_load_disc(m, image.len));
    try testing.expectEqualStrings("7\n", io.captured());
}

test "corrupt disc fails to run" {
    const m = noka_new() orelse return error.OutOfMemory;
    defer noka_free(m);

    @memset(m.region(memory.disc), 0);
    const image = disc_mod.forgeDisc(m.region(memory.disc), "1 + 2 * 3");
    @memcpy(image[0..4], "KANO");
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 1), noka_load_disc(m, image.len));
    try testing.expectEqualStrings("disc error: invalid magic header.\n", io.captured());
}

test "disc with no source fails to run" {
    const m = noka_new() orelse return error.OutOfMemory;
    defer noka_free(m);

    @memset(m.region(memory.disc), 0);
    const image = disc_mod.forgeDisc(m.region(memory.disc), "1 + 2 * 3");
    std.mem.writeInt(u16, image[0x16..0x18], 0, .little);
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 1), noka_load_disc(m, image.len));
    try testing.expectEqualStrings("disc error: disc has no source.\n", io.captured());
}

test "interpretDisc rejects an image past the disc size" {
    const big: [memory.disc.size + 1]u8 = @splat(0);
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(@as(i32, 1), interpretDisc(&big));
    try testing.expectEqualStrings("disc error: disc too large.\n", io.captured());
}
