const std = @import("std");
const io = @import("io.zig");
const scanner_mod = @import("scanner.zig");
const Scanner = scanner_mod.Scanner;
const Token = scanner_mod.Token;
const TokenType = scanner_mod.TokenType;
const chunk_mod = @import("chunk.zig");
const Chunk = chunk_mod.Chunk;
const OpCode = chunk_mod.OpCode;
const Value = @import("value.zig").Value;

// TODO: Wire each of these up as operators are added.
const Precedence = enum(u8) {
    none,
    assignment,
    @"or",
    @"and",
    equality,
    comparison,
    term,
    factor,
    unary,
    call,
    primary,
};

pub const Compiler = struct {
    scanner: Scanner,
    chunk: *Chunk,
    current: Token = undefined,
    previous: Token = undefined,
    had_error: bool = false,
    panic_mode: bool = false,

    const ParseFn = *const fn (*Compiler) void;
    const ParseRule = struct {
        prefix: ?ParseFn = null,
        infix: ?ParseFn = null,
        precedence: Precedence = .none,
    };

    /// Compile `source` into `chunk`. Returns false if there were errors.
    pub fn compile(source: []const u8, chunk: *Chunk) bool {
        var parser = Compiler{ .scanner = Scanner.init(source), .chunk = chunk };
        parser.advance();
        parser.expression();
        parser.consume(.eof, "expected end of expression");
        parser.emitOp(.@"return");

        if (chunk.overflow) {
            io.print("compile error: program too large\n");
            return false;
        }

        return !parser.had_error;
    }

    fn expression(self: *Compiler) void {
        self.parsePrecedence(.assignment);
    }

    fn parsePrecedence(self: *Compiler, prec: Precedence) void {
        self.advance();
        const prefix_rule = getRule(self.previous.type).prefix orelse {
            self.errorAtPrevious("expected an expression");
            return;
        };
        prefix_rule(self);

        while (@intFromEnum(prec) <= @intFromEnum(getRule(self.current.type).precedence)) {
            self.advance();
            const infix_rule = getRule(self.previous.type).infix.?;
            infix_rule(self);
        }
    }

    // --- parse rules --------------------------------------------------------

    fn number(self: *Compiler) void {
        const v: Value = Value{ .number = std.fmt.parseFloat(f64, self.previous.lexeme) catch {
            self.errorAtPrevious("invalid number");
            return;
        } };

        self.emitConstant(v);
    }

    fn grouping(self: *Compiler) void {
        self.expression();
        self.consume(.right_paren, "expected ')' after expression");
    }

    fn literal(self: *Compiler) void {
        switch (self.previous.type) {
            .false => self.emitOp(OpCode.false),
            .nil => self.emitOp(OpCode.nil),
            .true => self.emitOp(OpCode.true),
            else => unreachable,
        }
    }

    fn unary(self: *Compiler) void {
        const op = self.previous.type;

        self.parsePrecedence(.unary);

        switch (op) {
            .bang => self.errorAtCurrent("! is not an operator, use 'not' for logical negation."),
            .minus => self.emitOp(.negate),
            .not => self.emitOp(.not),
            else => unreachable,
        }
    }

    fn binary(self: *Compiler) void {
        const op = self.previous.type;
        const rule = getRule(op);

        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (op) {
            .plus => self.emitOp(.add),
            .minus => self.emitOp(.subtract),
            .star => self.emitOp(.multiply),
            .slash => self.emitOp(.divide),
            else => unreachable,
        }
    }

    // TODO: add an entry for every new token type that can start or join an
    // expression.
    fn getRule(t: TokenType) ParseRule {
        return switch (t) {
            // zig fmt: off
            .left_paren =>      .{ .prefix = &grouping, .infix = null,      .precedence = .none },
            .right_paren =>     .{ .prefix = null,      .infix = null,      .precedence = .none },
            .plus =>            .{ .prefix = null,      .infix = &binary,   .precedence = .term },
            .minus =>           .{ .prefix = &unary,    .infix = &binary,   .precedence = .term },
            .star =>            .{ .prefix = null,      .infix = &binary,   .precedence = .factor },
            .slash =>           .{ .prefix = null,      .infix = &binary,   .precedence = .factor },
            .bang =>            .{ .prefix = &unary,    .infix = null,      .precedence = .none },
            .not =>             .{ .prefix = &unary,    .infix = null,      .precedence = .none},
            .number =>          .{ .prefix = &number,   .infix = null,      .precedence = .none },
            .true =>            .{ .prefix = &literal,  .infix = null,      .precedence = .none },
            .false =>           .{ .prefix = &literal,  .infix = null,      .precedence = .none },
            .nil =>             .{ .prefix = &literal,  .infix = null,      .precedence = .none },
            // zig fmt: on
            else => .{},
        };
    }

    // --- token plumbing -----------------------------------------------------

    fn advance(self: *Compiler) void {
        self.previous = self.current;

        while (true) {
            self.current = self.scanner.next();
            if (self.current.type != .@"error") break;
            self.errorAtCurrent(self.current.lexeme);
        }
    }

    fn consume(self: *Compiler, t: TokenType, msg: []const u8) void {
        if (self.current.type == t) {
            self.advance();
            return;
        }

        self.errorAtCurrent(msg);
    }

    // --- emit helpers -------------------------------------------------------

    fn emitOp(self: *Compiler, op: OpCode) void {
        self.chunk.writeOp(op);
    }

    fn emitByte(self: *Compiler, byte: u8) void {
        self.chunk.writeByte(byte);
    }

    fn emitConstant(self: *Compiler, value: Value) void {
        self.emitOp(.constant);
        self.emitByte(self.chunk.addConstant(value));
    }

    // --- error reporting ----------------------------------------------------
    // TODO: include line numbers (once tokens carry them) and recover at
    // statement boundaries (synchronize) instead of bailing on first error.

    fn errorAtCurrent(self: *Compiler, msg: []const u8) void {
        self.errorAt(self.current, msg);
    }

    fn errorAtPrevious(self: *Compiler, msg: []const u8) void {
        self.errorAt(self.previous, msg);
    }

    fn errorAt(self: *Compiler, token: Token, msg: []const u8) void {
        if (self.panic_mode) return;
        self.panic_mode = true;
        self.had_error = true;

        if (token.type == .eof) {
            io.printf("compile error at end: {s}\n", .{msg});
        } else {
            io.printf("compile error at '{s}': {s}\n", .{ token.lexeme, msg });
        }
    }
};
