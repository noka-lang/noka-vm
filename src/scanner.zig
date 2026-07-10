// TODO: this is the most spec-heavy file. LANGUAGE.md's "Lexical Structure"
// and "Lexical Grammar" sections define identifiers, keywords, string
// literals, comments, and (the tricky one) *newline significance* (the stack
// rule) and line continuation. Right now whitespace including newlines is just
// skipped. Need to emit newline tokens where they matter and track line
// numbers for diagnostics.
pub const TokenType = enum {
    // single-character tokens
    TOKEN_LEFT_PAREN,
    TOKEN_RIGHT_PAREN,
    TOKEN_PLUS,
    TOKEN_MINUS,
    TOKEN_STAR,
    TOKEN_SLASH,
    // literals
    TOKEN_NUMBER,
    // bookkeeping
    TOKEN_ERROR,
    TOKEN_EOF,
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

        if (self.isAtEnd()) return self.make(.TOKEN_EOF);

        const c = self.advance();
        if (isDigit(c)) return self.number();

        return switch (c) {
            '(' => self.make(.TOKEN_LEFT_PAREN),
            ')' => self.make(.TOKEN_RIGHT_PAREN),
            '+' => self.make(.TOKEN_PLUS),
            '-' => self.make(.TOKEN_MINUS),
            '*' => self.make(.TOKEN_STAR),
            '/' => self.make(.TOKEN_SLASH),
            else => self.errorToken("unexpected character"),
        };
    }

    fn number(self: *Scanner) Token {
        while (!self.isAtEnd() and (isDigit(self.peek()) or self.peek() == '.')) {
            _ = self.advance();
        }
        return self.make(.TOKEN_NUMBER);
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
        return .{ .type = .TOKEN_ERROR, .lexeme = msg };
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
