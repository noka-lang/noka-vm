const std = @import("std");
const io = @import("io.zig");
const scanner_mod = @import("scanner.zig");
const Scanner = scanner_mod.Scanner;
const Token = scanner_mod.Token;
const TokenType = scanner_mod.TokenType;
const chunk_mod = @import("chunk.zig");
const Chunk = chunk_mod.Chunk;
const OpCode = chunk_mod.OpCode;
const value_mod = @import("value.zig");

// TODO: Wire each of these up as operators are added.
const Precedence = enum(u8) {
    PREC_NONE,
    PREC_ASSIGNMENT,
    PREC_OR,
    PREC_AND,
    PREC_EQUALITY,
    PREC_COMPARISON,
    PREC_TERM,
    PREC_FACTOR,
    PREC_UNARY,
    PREC_CALL,
    PREC_PRIMARY,
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
        precedence: Precedence = .PREC_NONE,
    };

    /// Compile `source` into `chunk`. Returns false if there were errors.
    pub fn compile(source: []const u8, chunk: *Chunk) bool {
        var self = Compiler{ .scanner = Scanner.init(source), .chunk = chunk };
        self.advance();
        self.expression();
        self.consume(.TOKEN_EOF, "expected end of expression");
        self.emitOp(.OP_RETURN);

        if (chunk.overflow) {
            io.print("compile error: program too large\n");
            return false;
        }

        return !self.had_error;
    }

    fn expression(self: *Compiler) void {
        self.parsePrecedence(.PREC_ASSIGNMENT);
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
        const v = std.fmt.parseFloat(f64, self.previous.lexeme) catch {
            self.errorAtPrevious("invalid number");
            return;
        };

        self.emitConstant(v);
    }

    fn grouping(self: *Compiler) void {
        self.expression();
        self.consume(.TOKEN_RIGHT_PAREN, "expected ')' after expression");
    }

    fn unary(self: *Compiler) void {
        const op = self.previous.type;

        self.parsePrecedence(.PREC_UNARY);

        switch (op) {
            .TOKEN_MINUS => self.emitOp(.OP_NEGATE),
            else => unreachable,
        }
    }

    fn binary(self: *Compiler) void {
        const op = self.previous.type;
        const rule = getRule(op);

        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (op) {
            .TOKEN_PLUS => self.emitOp(.OP_ADD),
            .TOKEN_MINUS => self.emitOp(.OP_SUBTRACT),
            .TOKEN_STAR => self.emitOp(.OP_MULTIPLY),
            .TOKEN_SLASH => self.emitOp(.OP_DIVIDE),
            else => unreachable,
        }
    }

    // TODO: add an entry for every new token type that can start or join an
    // expression.
    fn getRule(t: TokenType) ParseRule {
        return switch (t) {
            .TOKEN_LEFT_PAREN => .{ .prefix = &grouping },
            .TOKEN_MINUS => .{ .prefix = &unary, .infix = &binary, .precedence = .PREC_TERM },
            .TOKEN_PLUS => .{ .infix = &binary, .precedence = .PREC_TERM },
            .TOKEN_STAR, .TOKEN_SLASH => .{ .infix = &binary, .precedence = .PREC_FACTOR },
            .TOKEN_NUMBER => .{ .prefix = &number },
            else => .{},
        };
    }

    // --- token plumbing -----------------------------------------------------

    fn advance(self: *Compiler) void {
        self.previous = self.current;

        while (true) {
            self.current = self.scanner.next();
            if (self.current.type != .TOKEN_ERROR) break;
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

    fn emitByte(self: *Compiler, byte: u8) void {
        self.chunk.writeByte(byte);
    }

    fn emitOp(self: *Compiler, op: OpCode) void {
        self.chunk.writeOp(op);
    }

    fn emitConstant(self: *Compiler, value: value_mod.Value) void {
        self.emitOp(.OP_CONSTANT);
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

        if (token.type == .TOKEN_EOF) {
            io.printf("compile error at end: {s}\n", .{msg});
        } else {
            io.printf("compile error at '{s}': {s}\n", .{ token.lexeme, msg });
        }
    }
};
