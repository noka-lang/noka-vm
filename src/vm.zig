const std = @import("std");
const io = @import("io.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const Compiler = @import("compiler.zig").Compiler;
const debug = @import("debug.zig");
const Value = @import("value.zig").Value;
const disc_mod = @import("disc.zig");
const memory = @import("memory.zig");
const builtins = @import("builtins.zig");
const globals = @import("globals.zig");
const report_mod = @import("report.zig");
const Reason = report_mod.Reason;

const debug_print_bytecode = false;
const debug_trace_execution = false;

// ---- machine -----------------------------------------------------------------------------------

pub const Report = report_mod.Report;

pub const Status = enum(i32) {
    /// The program is calling `noka_tick` and `noka_draw`.
    running = 0,
    /// The program has no `tick` or `draw`, it ran once and is done.
    finished = 1,
    /// The program has halted due to a compile/runtime error or a bad disc.
    /// `noka_reset` clears this status.
    failed = 2,
};

const Machine = struct {
    // Do not give fields defaults, or `m.* = .{}` will copy the 512 KiB block on every create.
    block: [memory.size]u8 align(16) = undefined,
    chunk: Chunk = undefined,
    heap: *memory.Heap = undefined,
    globals: *[memory.globals_slots]Value = undefined,
    failed: bool = undefined,
    report: Report = undefined,

    fn create() ?*Machine {
        const m = std.heap.page_allocator.create(Machine) catch return null;
        m.* = .{};
        m.globals = m.slots(memory.globals, Value);
        m.heap = &m.slots(memory.heap, memory.Heap)[0];
        m.heap.* = .{};
        m.failed = false;
        m.report.len = 0;

        return m;
    }

    fn destroy(self: *Machine) void {
        std.heap.page_allocator.destroy(self);
    }

    /// Returns one memory map region of this machine's block.
    fn region(self: *Machine, comptime r: memory.Region) *[r.size]u8 {
        return self.block[r.offset..][0..r.size];
    }

    /// Returns a slice of slots of type T in the given region.
    fn slots(self: *Machine, comptime r: memory.Region, comptime T: type) *[r.size / @sizeOf(T)]T {
        return @ptrCast(@alignCast(self.region(r)));
    }

    fn reset(self: *Machine) void {
        self.heap.reset();
        self.failed = false;
        self.report.len = 0;
    }

    fn fail(self: *Machine) Status {
        self.failed = true;
        return .failed;
    }

    fn eval(self: *Machine, len: usize) Status {
        if (self.failed) return .failed;
        const disc = self.region(memory.disc);

        if (len > disc.len) {
            self.report.write(.disc, "source too large", .{});
            return self.fail();
        }

        return self.compileAndRun(disc[0..len]);
    }

    fn loadDisc(self: *Machine, len: usize) Status {
        if (self.failed) return .failed;
        const disc = self.region(memory.disc);

        if (len > disc.len) {
            self.report.write(.disc, "disc too large", .{});
            return self.fail();
        }

        const image = disc[0..len];
        const header = disc_mod.parse(image) catch |e| {
            self.report.write(.disc, "{s}", .{disc_mod.describe(e)});
            return self.fail();
        };

        const src = header.section(image, .src) orelse {
            self.report.write(.disc, "disc has no source", .{});
            return self.fail();
        };

        // TODO: handle the rest of the disc sections

        return self.compileAndRun(src);
    }

    fn compileAndRun(self: *Machine, source: []const u8) Status {
        self.chunk = .{ .code = self.region(memory.code), .constants = self.slots(memory.constants, Value) };

        if (!Compiler.compile(source, &self.chunk, self.heap, &self.report)) return self.fail();
        if (debug_print_bytecode) debug.disassembleChunk(self, &self.chunk, "compiled code");

        var vm = VM{ .machine = self, .chunk = &self.chunk, .stack = self.slots(memory.stack, Value) };

        if (!vm.run()) return self.fail();
        if (!self.callIfDeclared("init")) return self.fail();

        return self.lifecycleStatus();
    }

    fn tick(self: *Machine) Status {
        if (self.failed) return .failed;
        if (!self.callIfDeclared("tick")) return self.fail();

        return self.lifecycleStatus();
    }

    fn draw(self: *Machine) Status {
        if (self.failed) return .failed;
        if (!self.callIfDeclared("draw")) return self.fail();
        // TODO: collect garbage after draw

        return self.lifecycleStatus();
    }

    fn lifecycleStatus(self: *Machine) Status {
        if (self.declaredSlot("tick") != null or self.declaredSlot("draw") != null) return .running;

        return .finished;
    }

    /// Calls the program-scope function `name` if the program declared it.
    /// If the call fails, return false and write the crash report.
    fn callIfDeclared(self: *Machine, comptime name: []const u8) bool {
        const slot = self.declaredSlot(name) orelse return true;
        const value = self.globals[slot];

        // TODO: call `value` once function exist
        self.report.write(.type, "'" ++ name ++ "' expected function, got {s}", .{value.typeName()});
        return false;
    }

    /// Returns the GLOBALS slot of the program-scope `name`, or null if it isn't declared.
    /// Built-ins are not checked.
    fn declaredSlot(self: *Machine, name: []const u8) ?u16 {
        const string = self.heap.strings.lookup(name) orelse return null;
        const slot = self.heap.names.find(string) orelse return null;
        if (!self.heap.names.pool[slot].declared) return null;

        return slot;
    }
};

// ---- exports -----------------------------------------------------------------------------------

export fn noka_machine_new() ?*Machine {
    return Machine.create();
}

export fn noka_machine_free(m: *Machine) void {
    m.destroy();
}

/// Clear a machine's globals and strings, and revive a failed machine.
export fn noka_reset(m: *Machine) void {
    m.reset();
}

export fn noka_memory(m: *Machine) [*]u8 {
    return &m.block;
}

/// Returns the crash report after a `failed` status, empty otherwise.
export fn noka_report(m: *Machine) [*]const u8 {
    return &m.report.bytes;
}

export fn noka_report_len(m: *Machine) usize {
    return m.report.len;
}

export fn noka_eval(m: *Machine, len: usize) Status {
    return m.eval(len);
}

export fn noka_load(m: *Machine, len: usize) Status {
    return m.loadDisc(len);
}

export fn noka_tick(m: *Machine) Status {
    return m.tick();
}

export fn noka_draw(m: *Machine) Status {
    return m.draw();
}

/// Run `source` in a fresh machine, `report` is given the crash report on failure.
pub fn interpretSource(source: []const u8, report: *Report) Status {
    const m = Machine.create() orelse {
        report.write(.oom, "out of memory", .{});
        return .failed;
    };
    defer m.destroy();

    const status = m.compileAndRun(source);
    if (status == .failed) report.* = m.report;

    return status;
}

pub fn interpretDisc(image: []const u8, report: *Report) Status {
    const m = Machine.create() orelse {
        report.write(.oom, "out of memory", .{});
        return .failed;
    };
    defer m.destroy();

    if (image.len > memory.disc.size) {
        report.write(.disc, "disc too large", .{});
        return .failed;
    }
    @memcpy(m.region(memory.disc)[0..image.len], image);

    const status = m.loadDisc(image.len);
    if (status == .failed) report.* = m.report;

    return status;
}

// ---- VM ----------------------------------------------------------------------------------------

const VM = struct {
    machine: *Machine,
    chunk: *const Chunk,
    ip: usize = 0,
    stack: *[memory.stack_slots]Value,
    sp: usize = 0,

    comptime {
        if (Chunk.stack_max > memory.stack_slots) @compileError("STACK must hold the largest chunk the compiler allows");
    }

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
            _ = self.runtimeError(.math, "bitwise expected whole number, got {d}", .{n});
            return null;
        }

        if (n < std.math.minInt(i32) or n > std.math.maxInt(i32)) {
            _ = self.runtimeError(.math, "bitwise expected 32-bit number, got {d}", .{n});
            return null;
        }

        return @intFromFloat(n);
    }

    fn run(self: *VM) bool {
        while (true) {
            if (debug_trace_execution) {
                _ = debug.disassembleInstruction(self.machine, self.chunk, self.ip);
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
                        return self.runtimeError(.type, "compare expected two numbers, got {s} and {s}", .{ a.typeName(), b.typeName() });
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
                        var builder = self.machine.heap.strings.build();
                        builder.pushSlice(a.string.bytes);
                        builder.pushSlice(b.string.bytes);

                        const joined = builder.finish() orelse {
                            return self.runtimeError(.oom, "out of string memory", .{});
                        };

                        self.push(.{ .string = joined });
                        continue;
                    }

                    if (a != .number or b != .number) {
                        return self.runtimeError(.type, "'add' expected two numbers or strings, got {s} and {s}", .{ a.typeName(), b.typeName() });
                    }

                    self.push(.{ .number = a.number + b.number });
                },
                .subtract, .multiply, .divide, .modulo, .exponent => {
                    const b = self.pop();
                    const a = self.pop();

                    if (a != .number or b != .number) {
                        return self.runtimeError(.type, "'{s}' expected two numbers, got {s} and {s}", .{ @tagName(op), a.typeName(), b.typeName() });
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
                        return self.runtimeError(.type, "'{s}' expected two numbers, got {s} and {s}", .{ @tagName(op), a.typeName(), b.typeName() });
                    }

                    const ai = self.toInt32(a.number) orelse return false;
                    const bi = self.toInt32(b.number) orelse return false;

                    const sh: u5 = switch (op) {
                        .shift_left, .shift_right => blk: {
                            if (bi < 0 or bi > 31) {
                                return self.runtimeError(.math, "'{s}' expected shift of 0-31, got {d}", .{ @tagName(op), bi });
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
                        return self.runtimeError(.type, "negate expected number, got {s}", .{v.typeName()});
                    }

                    self.push(.{ .number = -v.number });
                },
                .not => {
                    const v = self.pop();

                    if (v != .boolean) {
                        return self.runtimeError(.type, "'not' expected boolean, got {s}", .{v.typeName()});
                    }

                    self.push(.{ .boolean = !v.boolean });
                },
                .in => {
                    const haystack = self.pop();
                    const needle = self.pop();

                    // TODO: arrays and objects
                    if (needle != .string or haystack != .string) {
                        return self.runtimeError(.type, "'in' expected two strings, got {s} and {s}", .{ needle.typeName(), haystack.typeName() });
                    }

                    self.push(.{ .boolean = std.mem.indexOf(u8, haystack.string.bytes, needle.string.bytes) != null });
                },
                .bnot => {
                    const v = self.pop();

                    if (v != .number) {
                        return self.runtimeError(.type, "'bnot' expected number, got {s}", .{v.typeName()});
                    }

                    const vi = self.toInt32(v.number) orelse return false;
                    self.push(.{ .number = @floatFromInt(~vi) });
                },
                .print => {
                    self.pop().print(self.machine);
                    io.print(self.machine, "\n");
                },
                .jump => {
                    const offset = self.readShort();
                    self.ip += offset;
                },
                .jump_if_false => {
                    const offset = self.readShort();
                    const cond = self.peek(0);
                    if (cond != .boolean) {
                        return self.runtimeError(.type, "condition expected boolean, got {s}", .{cond.typeName()});
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
                        return self.runtimeError(.type, "condition expected boolean, got {s}", .{cond.typeName()});
                    }
                    if (cond.boolean) self.ip += offset;
                },
                .get_builtin => self.push(builtins.common[self.readByte()].value),
                .define_global, .define_const => {
                    const slot = self.readShort();
                    const mutability: globals.Mutability = switch (op) {
                        .define_const => .constant,
                        .define_global => .mutable,
                        else => unreachable,
                    };

                    self.machine.heap.names.declare(slot, mutability) catch {
                        const name = self.machine.heap.names.pool[slot].name;
                        return self.runtimeError(.undefined, "'{s}' has already been declared", .{name.bytes});
                    };
                    self.machine.globals[slot] = self.pop();
                },
                .get_global => {
                    const slot = self.readShort();
                    _ = self.declaredGlobal(slot) orelse return false;

                    self.push(self.machine.globals[slot]);
                },
                .set_global => {
                    const slot = self.readShort();
                    const global = self.declaredGlobal(slot) orelse return false;

                    if (global.mutability == .constant) {
                        return self.runtimeError(.frozen, "'{s}' is constant and cannot be reassigned", .{global.name.bytes});
                    }

                    self.machine.globals[slot] = self.peek(0);
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
                        self.pop().print(self.machine);
                        io.print(self.machine, "\n");
                    }
                    return true;
                },
                _ => unreachable,
            }
        }
    }

    /// Returns the global in `slot`, or null.
    inline fn declaredGlobal(self: *VM, slot: u16) ?*globals.Global {
        const global = &self.machine.heap.names.pool[slot];
        if (!global.declared) {
            _ = self.runtimeError(.undefined, "undefined variable '{s}'", .{global.name.bytes});
            return null;
        }

        return global;
    }

    fn runtimeError(self: *VM, reason: Reason, comptime message: []const u8, args: anytype) bool {
        self.machine.report.write(reason, message, args);

        return false;
    }
};

// ---- TESTS -------------------------------------------------------------------------------------

const testing = @import("std").testing;

fn expectOutput(source: []const u8, expected: []const u8) !void {
    io.beginCapture();
    defer io.endCapture();
    var report: Report = .{};
    const code = interpretSource(source, &report);

    try testing.expectEqualStrings(expected, std.mem.trimEnd(u8, io.captured(), "\n"));
    try testing.expectEqual(Status.finished, code);
}

fn expectFailure(source: []const u8, reason: []const u8, message: []const u8) !void {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.failed, evalIn(m, source));
    try expectReport(m, reason, message);
    try testing.expectEqualStrings("", io.captured());
}

fn expectReport(m: *Machine, reason: []const u8, message: []const u8) !void {
    var buf: [1024]u8 = undefined;
    const expected = try std.fmt.bufPrint(&buf, "{s}\n0\n0\n{s}", .{ reason, message });
    try testing.expectEqualStrings(expected, noka_report(m)[0..noka_report_len(m)]);
}

fn evalIn(m: *Machine, source: []const u8) Status {
    @memcpy(noka_memory(m)[0x00000..][0..source.len], source);
    return noka_eval(m, source.len);
}

/// Writes a noka program that declares `count` globals, followed by `tail`.
fn declareGlobals(buf: []u8, count: usize, tail: []const u8) ![]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    for (0..count) |i| try w.print("g{d} : {d}\n", .{ i, i });
    try w.writeAll(tail);

    return w.buffered();
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
    try expectFailure("1 < true", "type", "compare expected two numbers, got number and boolean");
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
    try expectFailure("not 1", "type", "'not' expected boolean, got number");
    try expectFailure("1 and 2", "type", "condition expected boolean, got number");
    try expectFailure("true band 1", "type", "'band' expected two numbers, got boolean and number");
    try expectFailure("1.5 band 2", "math", "bitwise expected whole number, got 1.5");
    try expectFailure("5000000000 bor 1", "math", "bitwise expected 32-bit number, got 5000000000");
    try expectFailure("!true", "compile", "at end: '!' is not an operator, use 'not' for logical negation");
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
    try expectFailure("true and (1 + true)", "type", "'add' expected two numbers or strings, got number and boolean");
    try expectOutput("true or (1 + true)", "true");
    try expectFailure("false or (1 + true)", "type", "'add' expected two numbers or strings, got number and boolean");
    try expectOutput("3 ?? (1 + true)", "3");
}

test "arithmetic on non-numbers is a runtime error" {
    try expectFailure("1 + true", "type", "'add' expected two numbers or strings, got number and boolean");
    try expectFailure("nil - false", "type", "'subtract' expected two numbers, got nil and boolean");
    try expectFailure("3 * true", "type", "'multiply' expected two numbers, got number and boolean");
    try expectFailure("false / 4", "type", "'divide' expected two numbers, got boolean and number");
}

test "negating a non-number is a runtime error" {
    try expectFailure("-true", "type", "negate expected number, got boolean");
    try expectFailure("-nil", "type", "negate expected number, got nil");
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
    try expectFailure("do\n  a : 1\n  a : 2\nend", "compile", "at 'a': 'a' has already been declared");
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
    try expectFailure("\"a\\qb\"", "compile", "at '\"a\\qb\"': unknown escape '\\q'");
}

test "string concatenation" {
    try expectOutput("\"foo\" + \"bar\"", "foobar");
    try expectOutput("\"a\" + \"b\" + \"c\"", "abc");
    try expectFailure("\"score: \" + 10", "type", "'add' expected two numbers or strings, got string and number");
    try expectFailure("\"a\" - \"b\"", "type", "'subtract' expected two numbers, got string and string");
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
    try expectFailure("1 in \"abc\"", "type", "'in' expected two strings, got number and string");
}

test "unterminated/unsupported strings" {
    try expectFailure("\"abc", "compile", "at '\"abc': unterminated string");
    try expectFailure("\"abc\nx\"", "compile", "at '\"abc': unterminated string");
    try expectFailure("f\"hi\"", "compile", "at 'f': string prefixes are not supported (yet)");
    try expectFailure("m'hi'", "compile", "at 'm': string prefixes are not supported (yet)");
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
    try expectFailure("PI # 3.14\nPI = 0", "frozen", "'PI' is constant and cannot be reassigned");
}

test "undeclared and redeclared are runtime errors" {
    try expectFailure("y", "undefined", "undefined variable 'y'");
    try expectFailure("y = 5", "undefined", "undefined variable 'y'");
    try expectFailure("x : 10\nx : 20", "undefined", "'x' has already been declared");
    try expectFailure("x : 10\nx # 20", "undefined", "'x' has already been declared");
}

test "declarations require an initializer" {
    try expectFailure("x :", "compile", "at end: expected expression");
    try expectFailure("a : 1\nb : 2\nc : 3\na * b = c", "compile", "at '=': invalid assignment target");
}

test "globals reset between runs" {
    io.beginCapture();
    defer io.endCapture();
    var report: Report = .{};
    try testing.expectEqual(Status.finished, interpretSource("x : 1\nx", &report));
    try testing.expectEqual(Status.finished, interpretSource("x : 2\nx", &report));
}

test "program scope holds 1024 globals (built-ins don't count)" {
    var buf: [16 * 1024]u8 = undefined;

    try expectOutput(try declareGlobals(&buf, 1024, "g1023 + dt * 60"), "1024");
    try expectFailure(try declareGlobals(&buf, 1025, ""), "compile", "at 'g1024': too many globals");
}

test "a name from an earlier eval can still be declared later" {
    const m = noka_machine_new().?;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.finished, evalIn(m, "while false\n  y\nend")); // nil
    try testing.expectEqual(Status.finished, evalIn(m, "y : 2")); // nil
    try testing.expectEqual(Status.finished, evalIn(m, "y")); // 2
    try testing.expectEqualStrings("nil\nnil\n2\n", io.captured());
}

test "init, tick, and draw are ordinary names" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.running, evalIn(m, "draw : 1\ndraw"));
    try testing.expectEqual(Status.running, evalIn(m, "tick : draw + 1\ntick"));
    try testing.expectEqualStrings("1\n2\n", io.captured());
    try expectFailure("init + 1", "undefined", "undefined variable 'init'");
}

// TODO: when arrays are added test deep-freeze

test "bare case expression" {
    try expectOutput("case 1 < 2 -> \"yes\"", "yes");
    try expectOutput("case 1 > 2 -> \"yes\"", "nil");
    try expectOutput("case\n  1 > 2 -> \"a\"\n  2 > 1 -> \"b\"\nend", "b");
    try expectOutput("case\n  false -> \"a\"\n  _ -> \"fallback\"\nend", "fallback");
    try expectOutput("x : case\n  true -> 10\nend\nx", "10");
    try expectOutput("case true -> do\n  a : 2\n  a * 3\nend", "6");
    try expectFailure("case 1 -> \"x\"", "type", "condition expected boolean, got number");
}

test "single-pattern case expression" {
    try expectOutput("case \"b\"\n  \"a\" -> 1\n  \"b\" -> 2\nend", "2");
    try expectOutput("case 3\n  1 -> \"one\"\n  _ -> \"other\"\nend", "other");
    try expectOutput("case 75\n  > 50 -> \"healthy\"\n  > 20 -> \"hurt\"\n  _ -> \"critical\"\nend", "healthy");
    try expectOutput("case 5\n  >= 5 -> \"ok\"\nend", "ok");
    try expectOutput("case 9\n  1 -> \"one\"\nend", "nil");
    try expectOutput("x : case \"b\"\n  \"b\" -> 2\nend\nx", "2");
    try expectOutput("1 + case 1\n  1 -> 2\nend", "3");
    try expectFailure("case\n  > 5 -> \"x\"\nend", "compile", "at '>': no left-hand side to compare against");
}

test "multi-pattern case expression" {
    try expectOutput("case \"north\"\n  \"up\", \"north\" -> \"go north\"\n  _ -> \"?\"\nend", "go north");
    try expectOutput("case 3\n  1, 2 -> \"low\"\n  3, 4 -> \"high\"\nend", "high");
}

test "guarded case expression" {
    try expectOutput("case 150\n  > 100 if true -> \"epic\"\n  > 100 -> \"great\"\nend", "epic");
    try expectOutput("case 150\n  > 100 if false -> \"epic\"\n  > 100 -> \"great\"\nend", "great");
    try expectFailure("case 1\n  1 if 2 -> \"x\"\nend", "type", "condition expected boolean, got number");
}

test "case bodies can assign" {
    try expectOutput("status : \"\"\ncase\n  true -> status = \"healthy\"\nend\nstatus", "healthy");
    try expectOutput("x : 0\ncase true -> x = 5\nx", "5");
    try expectOutput("x : 0\ncase\n  false -> 1\n  _ -> x = 9\nend\nx", "9");
    try expectOutput("x : 0\ncase 2\n  2 -> x = 7\nend\nx", "7");
}

test "a broken case subject is a compile error" {
    try expectFailure("case )\n  1 -> 2\nend", "compile", "at ')': expected expression");
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
    try expectFailure("1 2", "compile", "at '2': expected end of statement");
}

test "compile errors are reported, not executed" {
    try expectFailure("(1 + 2", "compile", "at end: expected ')' after expression");
    try expectFailure("1 +", "compile", "at end: expected expression");
    try expectFailure("$", "compile", "at '$': unexpected character");
}

test "interpretSource gives back a crash report on failure" {
    io.beginCapture();
    defer io.endCapture();
    var report: Report = .{};
    try testing.expectEqual(Status.finished, interpretSource("1 + 1", &report));
    try testing.expectEqual(Status.failed, interpretSource("1 +", &report));
    try testing.expectEqualStrings("compile\n0\n0\nat end: expected expression", report.text());
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
    try expectFailure(w.buffered(), "compile", "at 'v255': too many locals in scope");

    w = .fixed(&buf);
    for (0..300) |_| try w.writeAll("1 + (");
    try w.writeAll("1");
    for (0..300) |_| try w.writeAll(")");
    try expectFailure(w.buffered(), "compile", "at '1': expression too deep");
}

test "unimplemented syntax is a compile error" {
    try expectFailure("1 + for", "compile", "at 'for': not supported (yet)");
    try expectFailure("x : fn", "compile", "at 'fn': not supported (yet)");
    try expectFailure("this", "compile", "at 'this': not supported (yet)");
    try expectFailure("x : 1\nx.y", "compile", "at '.': not supported (yet)");
    try expectFailure("x : 1\nx(", "compile", "at '(': not supported (yet)");
}

test "local constants" {
    try expectOutput("do\n  PI # 3\n  PI * 2\nend", "6");
    try expectFailure("do\n  PI # 3\n  PI = 4\nend", "compile", "at 'PI': 'PI' is constant and cannot be reassigned");
    try expectFailure("do\n  PI # 3\n  PI : 4\nend", "compile", "at 'PI': 'PI' has already been declared");
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
    try expectFailure("case 1\n  _ -> 1\n  2 -> 3\nend", "compile", "at '2': '_' must be the last branch");
    try expectFailure("case 1\n  1 -> 2\n", "compile", "at end: expected 'end' to close 'case'");
    try expectFailure("case 1\n  _ -> 2\n", "compile", "at end: expected 'end' to close 'case'");
}

test "while loops" {
    try expectOutput("i : 0\nwhile i < 3\n  i = i + 1\nend", "3");
    try expectOutput("while false\n  1\nend", "nil");
    try expectOutput("x : while false\n  1\nend\nx", "nil");
    try expectOutput("i : 0\nwhile i < 3\n  j : i * 2\n  i = i + 1\n  j\nend", "4");
    try expectFailure("while 1\n  2\nend", "type", "condition expected boolean, got number");
    try expectFailure("while true 1 end", "compile", "at '1': expected newline after 'while' condition");
    try expectFailure("while true\n  1\n", "compile", "at end: expected 'end' to close 'while'");
}

test "stop statement" {
    try expectOutput("i : 0\nwhile true\n  i = i + 1\n  case i == 5 -> stop i * 10\nend", "50");
    try expectOutput("while true\n  stop\nend", "nil");
    try expectOutput("while true\n  do\n    a : 7\n    case a > 5 -> stop a\n  end\nend", "7");
    try expectOutput("i : 0\nwhile true\n  i = i + 1\n  x : 100 + case i\n    3 -> stop i\n    _ -> 0\n  end\nend", "3");
    try expectFailure("stop", "compile", "at 'stop': 'stop' outside of a loop");
    try expectFailure("1 + stop", "compile", "at 'stop': expected expression");
}

test "next statement" {
    try expectOutput("i : 0\ntotal : 0\nwhile i < 6\n  i = i + 1\n  case i % 2 == 0 -> next\n  total = total + i\nend", "9");
    try expectOutput("i : 0\nwhile i < 3\n  i = i + 1\n  a : i\n  case true -> next\nend", "nil");
    try expectFailure("next", "compile", "at 'next': 'next' outside of a loop");
}

test "nested loops" {
    try expectOutput("count : 0\ni : 0\nwhile i < 3\n  i = i + 1\n  j : 0\n  while true\n    j = j + 1\n    count = count + 1\n    case j == 2 -> stop\n  end\nend\ncount", "6");
    try expectOutput("i : 0\nwhile i < 3\n  i = i + 1\n  while true\n    stop i\n  end\nend", "3");
}

test "built-ins" {
    try expectOutput("dt * 60", "1");
    try expectOutput("do\n  dt : 5\n  dt\nend", "5");
    try expectOutput("x : dt\nx * 60", "1");
    try expectFailure("dt : 1", "compile", "at 'dt': 'dt' is a built-in");
    try expectFailure("dt # 1", "compile", "at 'dt': 'dt' is a built-in");
    try expectFailure("dt = 1", "compile", "at 'dt': cannot assign to built-in 'dt'");
    try expectFailure("do\n  dt = 1\nend", "compile", "at 'dt': cannot assign to built-in 'dt'");
    try expectFailure("while false\n  dt = 1\nend", "compile", "at 'dt': cannot assign to built-in 'dt'");
}

// ---- Machine tests -----------------------------------------------------------------------------

test "a machine made with create runs a program" {
    const m = Machine.create() orelse return error.OutOfMemory;
    defer m.destroy();

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.finished, m.compileAndRun("x : 6\nx * 7"));
    try testing.expectEqualStrings("42\n", io.captured());
}

test "two machines keep separate globals" {
    const a = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(a);
    const b = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(b);

    io.beginCapture();
    defer io.endCapture();

    // declare `x` in both machines, there should not be any redeclaration error
    try testing.expectEqual(Status.finished, evalIn(a, "x : 1"));
    try testing.expectEqual(Status.finished, evalIn(b, "x : 2"));
    try testing.expectEqual(Status.finished, evalIn(a, "y : \"only a\""));

    io.beginCapture();
    try testing.expectEqual(Status.finished, evalIn(a, "x"));
    try testing.expectEqual(Status.finished, evalIn(b, "x"));
    try testing.expectEqual(Status.finished, evalIn(a, "y"));
    try testing.expectEqualStrings("1\n2\nonly a\n", io.captured());

    io.beginCapture();
    try testing.expectEqual(Status.failed, evalIn(b, "y"));
    try expectReport(b, "undefined", "undefined variable 'y'");
}

test "resetting one machine leaves the other intact" {
    const a = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(a);
    const b = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(b);

    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.finished, evalIn(a, "x : \"from a\""));
    try testing.expectEqual(Status.finished, evalIn(b, "x : \"from b\""));
    noka_reset(a);

    io.beginCapture();
    try testing.expectEqual(Status.failed, evalIn(a, "x"));
    try testing.expectEqual(Status.finished, evalIn(b, "x"));
    try testing.expectEqualStrings("from b\n", io.captured());
    try expectReport(a, "undefined", "undefined variable 'x'");
}

test "each machine has DISC, STACK, and HEAP at correct offsets in their own block" {
    const a = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(a);
    const b = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(b);

    io.beginCapture();
    defer io.endCapture();

    // DISC at 0x00000
    try testing.expectEqual(Status.finished, evalIn(a, "do\n  n : 42\n  s : \"from \" + \"machine a\"\n  n\nend"));
    try testing.expectEqual(Status.finished, evalIn(b, "do\n  n : 7\n  s : \"from \" + \"machine b\"\n  n\nend"));
    try testing.expectEqualStrings("42\n7\n", io.captured());

    // STACK at 0x47000
    const a_slot0 = std.mem.bytesToValue(Value, noka_memory(a)[0x47000..][0..@sizeOf(Value)]);
    const b_slot0 = std.mem.bytesToValue(Value, noka_memory(b)[0x47000..][0..@sizeOf(Value)]);
    try testing.expectEqual(@as(f64, 42), a_slot0.number);
    try testing.expectEqual(@as(f64, 7), b_slot0.number);

    // HEAP at 0x5F000, 128 KiB
    const a_heap = noka_memory(a)[0x5F000..][0 .. 128 * 1024];
    const b_heap = noka_memory(b)[0x5F000..][0 .. 128 * 1024];
    try testing.expect(std.mem.indexOf(u8, a_heap, "from machine a") != null);
    try testing.expect(std.mem.indexOf(u8, a_heap, "from machine b") == null);
    try testing.expect(std.mem.indexOf(u8, b_heap, "from machine b") != null);
    try testing.expect(std.mem.indexOf(u8, b_heap, "from machine a") == null);
}

test "a failed machine refuses later calls" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.failed, evalIn(m, "y"));

    io.beginCapture();
    try testing.expectEqual(Status.failed, evalIn(m, "1"));
    try testing.expectEqual(Status.failed, noka_load(m, 0));
    try testing.expectEqualStrings("", io.captured());
}

test "a crash report is cut off at 1KiB" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.failed, evalIn(m, "\"" ++ @as([2000]u8, @splat('a')) ++ "\\q\""));
    try testing.expectEqual(@as(usize, 1024), noka_report_len(m));
    try testing.expect(std.mem.startsWith(u8, noka_report(m)[0..1024], "compile\n0\n0\nat '\"aaaa"));
}

test "a program without tick or draw is finished" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.finished, evalIn(m, "x : 1"));
    try testing.expectEqual(Status.finished, noka_tick(m));
    try testing.expectEqual(Status.finished, noka_draw(m));
}

test "a program that declares tick or draw is running" {
    const a = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(a);
    const b = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(b);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.running, evalIn(a, "tick : 1"));
    try testing.expectEqual(Status.running, evalIn(b, "draw : 1"));
}

test "a name that is only read is not declared" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.finished, evalIn(m, "while false\n  tick\nend"));
}

test "a tick, draw or init that is not a function fails" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.running, evalIn(m, "tick : 1\ndraw : nil"));
    try testing.expectEqual(Status.failed, noka_tick(m));
    try expectReport(m, "type", "'tick' expected function, got number");

    noka_reset(m);
    try testing.expectEqual(Status.running, evalIn(m, "draw : nil"));
    try testing.expectEqual(Status.failed, noka_draw(m));
    try expectReport(m, "type", "'draw' expected function, got nil");

    noka_reset(m);
    try testing.expectEqual(Status.failed, evalIn(m, "init : true"));
    try expectReport(m, "type", "'init' expected function, got boolean");
}

test "two machines print through one import with their own handles" {
    const a = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(a);
    const b = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(b);

    io.beginCaptureFrom(a);
    defer io.endCapture();
    try testing.expectEqual(Status.finished, evalIn(a, "\"from a\""));
    try testing.expectEqual(Status.finished, evalIn(b, "\"from b\""));
    try testing.expectEqualStrings("from a\n", io.captured());

    io.beginCaptureFrom(b);
    try testing.expectEqual(Status.finished, evalIn(a, "1"));
    try testing.expectEqual(Status.finished, evalIn(b, "2"));
    try testing.expectEqualStrings("2\n", io.captured());
}

test "a failed machine refuses tick and draw" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);
    io.beginCapture();
    defer io.endCapture();

    try testing.expectEqual(Status.failed, evalIn(m, "tick : 1\ny"));
    try testing.expectEqual(Status.failed, noka_tick(m));
    try testing.expectEqual(Status.failed, noka_draw(m));
    try expectReport(m, "undefined", "undefined variable 'y'");
}

test "resetting a failed machine lets it run again" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.failed, evalIn(m, "y"));
    noka_reset(m);

    try testing.expectEqual(@as(usize, 0), noka_report_len(m));

    io.beginCapture();
    try testing.expectEqual(Status.finished, evalIn(m, "1"));
    try testing.expectEqualStrings("1\n", io.captured());
}

// ---- Disc tests --------------------------------------------------------------------------------

test "eval rejects a length past the disc size" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.failed, noka_eval(m, memory.disc.size + 1));
    try expectReport(m, "disc", "source too large");
}

test "load rejects a length past the disc size" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);

    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.failed, noka_load(m, memory.disc.size + 1));
    try expectReport(m, "disc", "disc too large");
}

test "load runs a disc's source" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);

    @memset(m.region(memory.disc), 0);
    const image = disc_mod.forgeDisc(m.region(memory.disc), "1 + 2 * 3");
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.finished, noka_load(m, image.len));
    try testing.expectEqualStrings("7\n", io.captured());
}

test "corrupt disc fails to run" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);

    @memset(m.region(memory.disc), 0);
    const image = disc_mod.forgeDisc(m.region(memory.disc), "1 + 2 * 3");
    @memcpy(image[0..4], "KANO");
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.failed, noka_load(m, image.len));
    try expectReport(m, "disc", "invalid magic header");
}

test "disc with no source fails to run" {
    const m = noka_machine_new() orelse return error.OutOfMemory;
    defer noka_machine_free(m);

    @memset(m.region(memory.disc), 0);
    const image = disc_mod.forgeDisc(m.region(memory.disc), "1 + 2 * 3");
    std.mem.writeInt(u16, image[0x16..0x18], 0, .little);
    io.beginCapture();
    defer io.endCapture();
    try testing.expectEqual(Status.failed, noka_load(m, image.len));
    try expectReport(m, "disc", "disc has no source");
}

test "interpretDisc rejects an image past the disc size" {
    const big: [memory.disc.size + 1]u8 = @splat(0);
    io.beginCapture();
    defer io.endCapture();
    var report: Report = .{};
    try testing.expectEqual(Status.failed, interpretDisc(&big, &report));
    try testing.expectEqualStrings("disc\n0\n0\ndisc too large", report.text());
}
