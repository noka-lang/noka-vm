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
        while (!self.isAtEnd() and (isDigit(self.peek()) or self.peek() == '.')) {
            _ = self.advance();
        }
        return self.make(.number);
    }

    fn skipWhitespace(self: *Scanner) void {
        // TODO: newlines are significant in NokaScript, so don't just eat
        // them. Also handle comments here (see spec "Comments").
        while (!self.isAtEnd()) {
            switch (self.peek()) {
                ' ', '\t', '\r', '\n' => _ = self.advance(),
                else => return,
            }
        }
    }

    fn make(self: *Scanner, t: TokenType) Token {
        return .{ .type = t, .lexeme = self.src[self.start..self.current] };
    }

    fn errorToken(self: *Scanner, msg: []const u8) Token {
        _ = self;
        return .{ .type = .@"error", .lexeme = msg };
    }

    fn advance(self: *Scanner) u8 {
        const c = self.src[self.current];
        self.current += 1;
        return c;
    }

    fn peek(self: *Scanner) u8 {
        return self.src[self.current];
    }

    fn isAtEnd(self: *Scanner) bool {
        return self.current >= self.src.len;
    }
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
