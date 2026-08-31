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
const strings = @import("strings.zig");

// Ordered lowest to highest, matching LANGUAGE.md's precedence table.
// TODO: Wire each of these up as operators are added.
const Precedence = enum(u8) {
    none,
    assignment,
    pipe,
    @"or",
    @"and",
    fallback,
    bor,
    bxor,
    band,
    equality,
    comparison,
    shift,
    term,
    factor,
    exponent,
    unary,
    optional,
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

        if (parser.current.type != .eof) parser.expression();

        parser.consume(.eof, "expected end of expression");
        parser.emitOp(.@"return");

        if (chunk.overflow) {
            io.print("compile error: program too large.\n");
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
            self.errorAtPrevious("expected expression");
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

    fn @"and"(self: *Compiler) void {
        const endJump = self.emitJump(.jump_if_false);

        self.emitOp(.pop);
        self.parsePrecedence(.@"and");
        self.patchJump(endJump);
    }

    fn array(self: *Compiler) void {
        _ = self;
    }

    fn assign(self: *Compiler) void {
        _ = self;
    }

    fn binary(self: *Compiler) void {
        const op = self.previous.type;
        const rule = getRule(op);
        const next: Precedence = if (op == .star_star)
            rule.precedence
        else
            @enumFromInt(@intFromEnum(rule.precedence) + 1);

        self.parsePrecedence(next);

        switch (op) {
            .band => self.emitOp(.band),
            .bang_equal => self.emitOps(.equal, .not),
            .bor => self.emitOp(.bor),
            .bxor => self.emitOp(.bxor),
            .equal_equal => self.emitOp(.equal),
            .greater => self.emitOp(.greater),
            .greater_equal => self.emitOps(.less, .not),
            .greater_greater => self.emitOp(.shift_right),
            .less => self.emitOp(.less),
            .less_equal => self.emitOps(.greater, .not),
            .less_less => self.emitOp(.shift_left),
            .minus => self.emitOp(.subtract),
            .modulo => self.emitOp(.modulo),
            .plus => self.emitOp(.add),
            .slash => self.emitOp(.divide),
            .star => self.emitOp(.multiply),
            .star_star => self.emitOp(.exponent),
            else => unreachable,
        }
    }

    fn blockExpr(self: *Compiler) void {
        _ = self;
    }

    fn call(self: *Compiler) void {
        _ = self;
    }

    fn caseExpr(self: *Compiler) void {
        _ = self;
    }

    fn decrement(self: *Compiler) void {
        _ = self;
    }

    fn dot(self: *Compiler) void {
        _ = self;
    }

    fn fallback(self: *Compiler) void {
        const endJump = self.emitJump(.jump_if_not_nil);

        self.emitOp(.pop);
        self.parsePrecedence(.bor);
        self.patchJump(endJump);
    }

    fn forExpr(self: *Compiler) void {
        _ = self;
    }

    fn function(self: *Compiler) void {
        _ = self;
    }
    fn grouping(self: *Compiler) void {
        self.expression();
        self.consume(.paren_right, "expected ')' after expression");
    }

    fn increment(self: *Compiler) void {
        _ = self;
    }

    fn index(self: *Compiler) void {
        _ = self;
    }

    fn literal(self: *Compiler) void {
        switch (self.previous.type) {
            .false => self.emitOp(OpCode.false),
            .nil => self.emitOp(OpCode.nil),
            .true => self.emitOp(OpCode.true),
            else => unreachable,
        }
    }

    fn notIn(self: *Compiler) void {
        self.consume(.in, "expected 'in' after 'not'.");
        self.parsePrecedence(.shift);
        self.emitOps(.in, .not);
    }

    fn number(self: *Compiler) void {
        const v: Value = Value{ .number = std.fmt.parseFloat(f64, self.previous.lexeme) catch {
            self.errorAtPreviousFmt("expected number, got '{s}'", .{self.previous.lexeme});
            return;
        } };

        self.emitConstant(v);
    }

    fn object(self: *Compiler) void {
        _ = self;
    }

    fn optional(self: *Compiler) void {
        self.emitOp(.nil);
        self.emitOps(.equal, .not);
    }

    fn optionalCall(self: *Compiler) void {
        _ = self;
    }

    fn optionalDot(self: *Compiler) void {
        _ = self;
    }

    fn optionalIndex(self: *Compiler) void {
        _ = self;
    }

    fn @"or"(self: *Compiler) void {
        const elseJump = self.emitJump(.jump_if_false);
        const endJump = self.emitJump(.jump);

        self.patchJump(elseJump);
        self.emitOp(.pop);

        self.parsePrecedence(.@"or");
        self.patchJump(endJump);
    }

    fn pipe(self: *Compiler) void {
        _ = self;
    }

    fn string(self: *Compiler) void {
        const body = self.previous.lexeme[1 .. self.previous.lexeme.len - 1];

        var builder = strings.build();
        var i: usize = 0;
        while (i < body.len) : (i += 1) {
            if (body[i] != '\\') {
                builder.push(body[i]);
                continue;
            }

            // scanner cannot end on a literal backslash
            i += 1;
            builder.push(switch (body[i]) {
                'n' => '\n',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                // TODO: '{' and '}'
                else => {
                    builder.discard();
                    self.errorAtPreviousFmt("unknown escape '\\{c}'", .{body[i]});
                    return;
                },
            });
        }

        const s = builder.finish() orelse {
            self.errorAtPrevious("out of string memory");
            return;
        };

        self.emitConstant(.{ .string = s });
    }

    fn this(self: *Compiler) void {
        _ = self;
    }

    fn unary(self: *Compiler) void {
        const op = self.previous.type;

        self.parsePrecedence(.unary);

        switch (op) {
            .bang => self.errorAtCurrent("'!' is not an operator, use 'not' for logical negation"),
            .bnot => self.emitOp(.bnot),
            .minus => self.emitOp(.negate),
            .not => self.emitOp(.not),
            else => unreachable,
        }
    }

    fn variable(self: *Compiler) void {
        _ = self;
    }

    fn whileExpr(self: *Compiler) void {
        _ = self;
    }

    // TODO: add an entry for every new token type that can start or join an
    // expression.
    fn getRule(t: TokenType) ParseRule {
        return switch (t) {
            // zig fmt: off
            .@"and" =>                  .{ .prefix = null,          .infix = &@"and",           .precedence = .@"and" },
            .band =>                    .{ .prefix = null,          .infix = &binary,           .precedence = .band },
            .bang =>                    .{ .prefix = &unary,        .infix = null,              .precedence = .none },
            .bang_equal =>              .{ .prefix = null,          .infix = &binary,           .precedence = .equality },
            .bnot =>                    .{ .prefix = &unary,        .infix = null,              .precedence = .none },
            .bor =>                     .{ .prefix = null,          .infix = &binary,           .precedence = .bor },
            .bracket_left =>            .{ .prefix = &array,        .infix = &index,            .precedence = .call },
            .bxor =>                    .{ .prefix = null,          .infix = &binary,           .precedence = .bxor },
            .case =>                    .{ .prefix = &caseExpr,     .infix = null,              .precedence = .none },
            .curly_left =>              .{ .prefix = &object,       .infix = null,              .precedence = .none },
            .do =>                      .{ .prefix = &blockExpr,    .infix = null,              .precedence = .none },
            .dot =>                     .{ .prefix = null,          .infix = &dot,              .precedence = .call },
            .equal =>                   .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .equal_equal =>             .{ .prefix = null,          .infix = &binary,           .precedence = .equality },
            .false =>                   .{ .prefix = &literal,      .infix = null,              .precedence = .none },
            .@"for" =>                  .{ .prefix = &forExpr,      .infix = null,              .precedence = .none },
            .@"fn" =>                   .{ .prefix = &function,     .infix = null,              .precedence = .none },
            .greater =>                 .{ .prefix = null,          .infix = &binary,           .precedence = .comparison },
            .greater_equal =>           .{ .prefix = null,          .infix = &binary,           .precedence = .comparison },
            .greater_greater =>         .{ .prefix = null,          .infix = &binary,           .precedence = .shift },
            .greater_greater_equal =>   .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .identifier =>              .{ .prefix = &variable,     .infix = null,              .precedence = .none },
            .in =>                      .{ .prefix = null,          .infix = &binary,           .precedence = .comparison },
            .less =>                    .{ .prefix = null,          .infix = &binary,           .precedence = .comparison },
            .less_equal =>              .{ .prefix = null,          .infix = &binary,           .precedence = .comparison },
            .less_less =>               .{ .prefix = null,          .infix = &binary,           .precedence = .shift },
            .less_less_equal =>         .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .minus =>                   .{ .prefix = &unary,        .infix = &binary,           .precedence = .term },
            .minus_equal =>             .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .minus_minus =>             .{ .prefix = null,          .infix = &decrement,        .precedence = .assignment },
            .modulo =>                  .{ .prefix = null,          .infix = &binary,           .precedence = .factor },
            .modulo_equal =>            .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .nil =>                     .{ .prefix = &literal,      .infix = null,              .precedence = .none },
            .not =>                     .{ .prefix = &unary,        .infix = &notIn,            .precedence = .comparison },
            .number =>                  .{ .prefix = &number,       .infix = null,              .precedence = .none },
            .@"or" =>                   .{ .prefix = null,          .infix = &@"or",            .precedence = .@"or" },
            .paren_left =>              .{ .prefix = &grouping,     .infix = &call,             .precedence = .call },
            .pipe_arrow =>              .{ .prefix = null,          .infix = &pipe,             .precedence = .pipe },
            .plus =>                    .{ .prefix = null,          .infix = &binary,           .precedence = .term },
            .plus_equal =>              .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .plus_plus =>               .{ .prefix = null,          .infix = &increment,        .precedence = .assignment },
            .question =>                .{ .prefix = null,          .infix = &optional,         .precedence = .optional },
            .question_bracket =>        .{ .prefix = null,          .infix = &optionalIndex,    .precedence = .call },
            .question_dot =>            .{ .prefix = null,          .infix = &optionalDot,      .precedence = .call },
            .question_paren =>          .{ .prefix = null,          .infix = &optionalCall,     .precedence = .call },
            .question_question =>       .{ .prefix = null,          .infix = &fallback,         .precedence = .fallback },
            .slash =>                   .{ .prefix = null,          .infix = &binary,           .precedence = .factor },
            .slash_equal =>             .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .star =>                    .{ .prefix = null,          .infix = &binary,           .precedence = .factor },
            .star_equal =>              .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .star_star =>               .{ .prefix = null,          .infix = &binary,           .precedence = .exponent },
            .star_star_equal =>         .{ .prefix = null,          .infix = &assign,           .precedence = .assignment },
            .string =>                  .{ .prefix = &string,       .infix = null,              .precedence = .none },
            .this =>                    .{ .prefix = &this,         .infix = null,              .precedence = .none },
            .true =>                    .{ .prefix = &literal,      .infix = null,              .precedence = .none },
            .underscore =>              .{ .prefix = &literal,      .infix = null,              .precedence = .none },
            .@"while" =>                .{ .prefix = &whileExpr,    .infix = null,              .precedence = .none },
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
            self.errorAtCurrent(self.current.message orelse "unexpected character");
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

    fn emitOps(self: *Compiler, op1: OpCode, op2: OpCode) void {
        self.emitOp(op1);
        self.emitOp(op2);
    }

    fn emitConstant(self: *Compiler, value: Value) void {
        const v = self.chunk.addConstant(value) orelse return;
        self.emitOp(.constant);
        self.emitByte(@intCast((v >> 8) & 0xff));
        self.emitByte(@intCast(v & 0xff));
    }

    fn emitJump(self: *Compiler, op: OpCode) usize {
        self.emitOp(op);
        self.emitByte(0xff);
        self.emitByte(0xff);

        return self.chunk.code_count - 2;
    }

    fn patchJump(self: *Compiler, offset: usize) void {
        const jump = self.chunk.code_count - offset - 2;

        if (jump > self.chunk.code.len - 1) {
            self.errorAtCurrentFmt("expected jump under 65535 bytes, got {d}", .{jump});
        }

        self.chunk.code[offset] = @intCast((jump >> 8) & 0xff);
        self.chunk.code[offset + 1] = @intCast(jump & 0xff);
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

    // `++` only concatenates comptime-known values, so messages that interpolate
    // a token or a count have to be formatted into a buffer at runtime.
    fn errorAtCurrentFmt(self: *Compiler, comptime fmt: []const u8, args: anytype) void {
        var buf: [256]u8 = undefined;
        self.errorAt(self.current, std.fmt.bufPrint(&buf, fmt, args) catch fmt);
    }

    fn errorAtPreviousFmt(self: *Compiler, comptime fmt: []const u8, args: anytype) void {
        var buf: [256]u8 = undefined;
        self.errorAt(self.previous, std.fmt.bufPrint(&buf, fmt, args) catch fmt);
    }

    fn errorAt(self: *Compiler, token: Token, msg: []const u8) void {
        if (self.panic_mode) return;
        self.panic_mode = true;
        self.had_error = true;

        if (token.type == .eof) {
            io.printf("compile error at end: {s}.\n", .{msg});
        } else {
            io.printf("compile error at '{s}': {s}.\n", .{ token.lexeme, msg });
        }
    }
};
