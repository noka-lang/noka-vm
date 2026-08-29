const std = @import("std");

// TODO: need to emit newline tokens where they matter and track line
// numbers for diagnostics.
pub const TokenType = enum {
    // single-character tokens
    bang, // !
    bracket_left, // [
    bracket_right, // ]
    colon, // :
    comma, // ,
    curly_left, // {
    curly_right, // }
    dot, // .
    equal, // =
    greater, // >
    less, // <
    minus, // -
    modulo, // %
    paren_left, // (
    paren_right, // )
    plus, // +
    pound, // #
    question, // ?
    slash, // /
    star, // *
    underscore,
    // two-character tokens
    bang_equal, // !=
    case_arrow, // ->
    equal_equal, // ==
    greater_equal, // >=
    greater_greater, // >>
    less_equal, // <=
    less_less, // <<
    minus_equal, // -=
    modulo_equal, // %=
    pipe_arrow, // |>
    plus_equal, // +=
    question_bracket, // ?[
    question_colon, // ?:
    question_dot, // ?.
    question_paren, // ?(
    question_question, // ??
    slash_equal, // /=
    star_equal, // *=
    star_star, // **
    // three-character tokens
    greater_greater_equal, // >>=
    less_less_equal, // <<=
    star_star_equal, // **=
    // keywords
    @"and",
    band,
    bnot,
    bor,
    bxor,
    case,
    @"catch",
    do,
    draw,
    end,
    err,
    false,
    @"fn",
    @"for",
    @"if",
    in,
    init,
    next,
    nil,
    not,
    @"or",
    ret,
    stop,
    this,
    tick,
    true,
    @"while",
    // literals
    identifier,
    number, // decimal, 0x/0X hex, 0b/0B binary
    string, // optional prefixes f, m, fm, mf
    // bookkeeping
    comment,
    eof,
    @"error",
    newline,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: u32,
};

pub const Scanner = struct {
    src: []const u8,
    start: usize = 0,
    current: usize = 0,
    line: u32 = 0, // TODO: update this placeholder to reflect current line

    pub fn init(src: []const u8) Scanner {
        return .{ .src = src };
    }

    pub fn next(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;

        if (self.isAtEnd()) return self.make(.eof);

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
            else => self.errorToken(self.src[self.start..self.current]),
        };
    }

    fn number(self: *Scanner) Token {
        while (isDigit(self.peek()) or self.peek() == '.') {
            _ = self.advance();
        }
        return self.make(.number);
    }

    fn skipWhitespace(self: *Scanner) void {
        // TODO: newlines are significant in NokaScript, so don't just eat
        // them. Also handle comments here (see spec "Comments").
        while (true) {
            switch (self.peek()) {
                ' ', '\t', '\r', '\n' => _ = self.advance(),
                else => return,
            }
        }
    }

    fn identifier(self: *Scanner) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();

        return self.make(self.identifierType());
    }

    fn identifierType(self: Scanner) TokenType {
        // TODO: all the rest of the keywords
        return switch (self.src[self.start]) {
            'a' => self.checkKeyword(1, 2, "nd", .@"and"),
            'b' => if (self.current - self.start > 1) switch (self.src[self.start + 1]) {
                'a' => self.checkKeyword(2, 2, "nd", .band),
                'n' => self.checkKeyword(2, 2, "ot", .bnot),
                'o' => self.checkKeyword(2, 1, "r", .bor),
                'x' => self.checkKeyword(2, 2, "or", .bxor),
                else => .@"error",
            } else .@"error",
            'f' => self.checkKeyword(1, 4, "alse", .false),
            'n' => if (self.current - self.start > 1) switch (self.src[self.start + 1]) {
                'i' => self.checkKeyword(2, 1, "l", .nil),
                'o' => self.checkKeyword(2, 1, "t", .not),
                else => .@"error",
            } else .@"error",
            'o' => self.checkKeyword(1, 1, "r", .@"or"),
            't' => self.checkKeyword(1, 3, "rue", .true),
            else => .@"error",
        };
    }

    fn checkKeyword(self: Scanner, start: usize, length: usize, rest: []const u8, @"type": TokenType) TokenType {
        if (self.current - self.start == start + length and std.mem.eql(u8, self.src[self.start + start .. self.start + start + length], rest)) {
            return @"type";
        }

        return .@"error";
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
