const std = @import("std");

// TODO: this is the most spec-heavy file. LANGUAGE.md's "Lexical Structure"
// and "Lexical Grammar" sections define identifiers, keywords, string
// literals, comments, and (the tricky one) *newline significance* (the stack
// rule) and line continuation. Right now whitespace including newlines is just
// skipped. Need to emit newline tokens where they matter and track line
// numbers for diagnostics.
pub const TokenType = enum {
    // single-character tokens
    left_paren,
    right_paren,
    plus,
    minus,
    star,
    slash,
    // literals
    number,
    true,
    false,
    nil,
    // bookkeeping
    @"error",
    eof,
    // TODO: identifiers, strings, keywords, comparison ops, newline, etc.
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    // TODO: add `line: u32` for error reporting.
};

pub const Scanner = struct {
    src: []const u8,
    start: usize = 0,
    current: usize = 0,

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
            '(' => self.make(.left_paren),
            ')' => self.make(.right_paren),
            '+' => self.make(.plus),
            '-' => self.make(.minus),
            '*' => self.make(.star),
            '/' => self.make(.slash),
            else => self.errorToken("unexpected character"),
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
        switch (self.src[self.start]) {
            'f' => return self.checkKeyword(1, 4, "alse", .false),
            'n' => return self.checkKeyword(1, 2, "il", .nil),
            't' => return self.checkKeyword(1, 3, "rue", .true),
            else => return .@"error",
        }
    }

    fn checkKeyword(self: Scanner, start: usize, length: usize, rest: []const u8, @"type": TokenType) TokenType {
        if (self.current - self.start == start + length and std.mem.eql(u8, self.src[self.start + start .. self.start + start + length], rest)) {
            return @"type";
        }

        return .@"error";
    }

    fn make(self: Scanner, t: TokenType) Token {
        return .{ .type = t, .lexeme = self.src[self.start..self.current] };
    }

    fn errorToken(self: Scanner, msg: []const u8) Token {
        _ = self;
        return .{ .type = .@"error", .lexeme = msg };
    }

    fn advance(self: *Scanner) u8 {
        self.current += 1;
        return self.src[self.current - 1];
    }

    fn peek(self: Scanner) u8 {
        if (self.isAtEnd()) return 0;
        return self.src[self.current];
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
