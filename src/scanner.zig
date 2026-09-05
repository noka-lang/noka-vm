const std = @import("std");

// TODO: need to emit newline tokens where they matter and track line numbers for diagnostics.
pub const TokenType = enum {
    // zig fmt: off
    // single-character tokens
    bang, bracket_left, bracket_right, colon, comma, curly_left, curly_right, dot, equal, greater,
    less, minus, modulo, paren_left, paren_right, plus, pound, question, slash, star, underscore,
    // two-character tokens
    bang_equal, case_arrow, equal_equal, greater_equal, greater_greater, less_equal, less_less,
    minus_equal, minus_minus, modulo_equal, pipe_arrow, plus_equal, plus_plus, question_bracket,
    question_colon, question_dot, question_paren, question_question, slash_equal, star_equal, star_star,
    // three-character tokens
    greater_greater_equal, less_less_equal, star_star_equal,
    // keywords
    @"and", band, bnot, bor, bxor, case, @"catch", do, draw, end, err, false, @"fn", @"for", @"if",
    in, init, next, nil, not, @"or", ret, stop, this, tick, true, @"while",
    // literals
    identifier, number, string,
    // bookkeeping
    comment, eof, @"error", newline,
    // zig fmt: on
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: u32,
    message: ?[]const u8 = null,
};

const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "and", .@"and" },
    .{ "band", .band },
    .{ "bnot", .bnot },
    .{ "bor", .bor },
    .{ "bxor", .bxor },
    .{ "case", .case },
    .{ "catch", .@"catch" },
    .{ "do", .do },
    .{ "draw", .draw },
    .{ "end", .end },
    .{ "err", .err },
    .{ "false", .false },
    .{ "fn", .@"fn" },
    .{ "for", .@"for" },
    .{ "if", .@"if" },
    .{ "in", .in },
    .{ "init", .init },
    .{ "next", .next },
    .{ "nil", .nil },
    .{ "not", .not },
    .{ "or", .@"or" },
    .{ "ret", .ret },
    .{ "stop", .stop },
    .{ "this", .this },
    .{ "tick", .tick },
    .{ "true", .true },
    .{ "while", .@"while" },
    .{ "_", .underscore },
});

pub const Scanner = struct {
    src: []const u8,
    start: usize = 0,
    current: usize = 0,
    line: u32 = 1,
    emitted_token: bool = false,

    pub fn init(src: []const u8) Scanner {
        return .{ .src = src };
    }

    pub fn next(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;

        if (self.peek() == '\n') {
            while (true) {
                _ = self.advance();
                self.line += 1;

                self.skipWhitespace();
                if (self.peek() != '\n') break;
            }

            if (!self.emitted_token or self.isAtEnd()) return self.next();

            return .{ .type = .newline, .lexeme = "\\n", .line = self.line };
        }

        if (self.isAtEnd()) return self.make(.eof);

        self.emitted_token = true;

        const c = self.advance();
        if (isAlpha(c)) return self.identifier();
        if (isDigit(c)) return self.number();

        return switch (c) {
            '(' => self.make(.paren_left),
            ')' => self.make(.paren_right),
            '+' => self.make(.plus),
            '-' => self.make(.minus),
            '*' => self.make(if (self.match('*')) .star_star else .star),
            '/' => self.make(.slash),
            '%' => self.make(.modulo),
            '?' => self.make(if (self.match('?')) .question_question else .question),
            '!' => self.make(if (self.match('=')) .bang_equal else .bang),
            '=' => self.make(if (self.match('=')) .equal_equal else .equal),
            '>' => self.make(if (self.match('=')) .greater_equal else if (self.match('>')) .greater_greater else .greater),
            '<' => self.make(if (self.match('=')) .less_equal else if (self.match('<')) .less_less else .less),
            ':' => self.make(.colon),
            '#' => self.make(.pound),
            '"', '\'' => self.string(c),
            else => self.errorToken(self.src[self.start..self.current]),
        };
    }

    fn string(self: *Scanner, quote: u8) Token {
        while (true) {
            // TODO: `m` strings may span multiple lines
            // TODO: `f` strings cannot span multiple lines
            if (self.isAtEnd() or self.peek() == '\n') {
                return self.errorTokenMsg("unterminated string");
            }

            const c = self.advance();
            if (c == quote) return self.make(.string);
            if (c == '\\' and !self.isAtEnd() and self.peek() != '\n') _ = self.advance();
        }
    }

    fn number(self: *Scanner) Token {
        while (isDigit(self.peek()) or self.peek() == '.') {
            _ = self.advance();
        }
        return self.make(.number);
    }

    fn skipWhitespace(self: *Scanner) void {
        // TODO: handle comments here (see spec "Comments").
        while (true) {
            switch (self.peek()) {
                ' ', '\t', '\r' => _ = self.advance(),
                else => return,
            }
        }
    }

    fn identifier(self: *Scanner) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();

        const lexeme = self.src[self.start..self.current];

        // TODO: `f` and `m` string prefixes
        if (self.peek() == '"' or self.peek() == '\'') {
            if (isStringPrefix(lexeme)) return self.errorTokenMsg("string prefixes are not supported (yet)");
        }

        return self.make(keywords.get(lexeme) orelse .identifier);
    }

    fn isStringPrefix(lexeme: []const u8) bool {
        for ([_][]const u8{ "f", "m", "fm", "mf" }) |prefix| {
            if (std.mem.eql(u8, lexeme, prefix)) return true;
        }

        return false;
    }

    fn make(self: Scanner, t: TokenType) Token {
        return .{
            .type = t,
            .lexeme = self.src[self.start..self.current],
            .line = self.line,
        };
    }

    fn errorToken(self: Scanner, msg: []const u8) Token {
        return .{
            .type = .@"error",
            .lexeme = msg,
            .line = self.line,
        };
    }

    fn errorTokenMsg(self: Scanner, msg: []const u8) Token {
        return .{
            .type = .@"error",
            .lexeme = self.src[self.start..self.current],
            .line = self.line,
            .message = msg,
        };
    }

    fn advance(self: *Scanner) u8 {
        self.current += 1;
        return self.src[self.current - 1];
    }

    fn peek(self: Scanner) u8 {
        if (self.isAtEnd()) return 0;
        return self.src[self.current];
    }

    fn match(self: *Scanner, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.src[self.current] != expected) return false;
        self.current += 1;

        return true;
    }

    fn isAtEnd(self: Scanner) bool {
        return self.current >= self.src.len;
    }
};

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
