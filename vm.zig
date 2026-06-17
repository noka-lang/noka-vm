const std = @import("std");

extern "env" fn host_print(ptr: [*]const u8, len: usize) void;

var heap_buffer: [1 << 20]u8 = undefined; // 1 MiB
var fba = std.heap.FixedBufferAllocator.init(&heap_buffer);
var scratch: [64 * 1024]u8 = undefined; // 64 Kib

export fn scratch_ptr() [*]u8 {
    return &scratch;
}

export fn scratch_cap() usize {
    return scratch.len;
}

export fn init() void {
    fba.reset();
}

fn print(s: []const u8) void {
    host_print(s.ptr, s.len);
}

const EvalError = error{
    UnexpectedChar,
    ExpectedExpression,
    ExpectedRParen,
    DivideByZero,
};

/// A tiny recursive-descent evaluator for arithmetic expressions.
///
/// Grammar (lowest to highest precedence):
///   expression -> term ( ( "+" | "-" ) term )*
///   term       -> unary ( ( "*" | "/" ) unary )*
///   unary      -> ( "-" )* primary
///   primary    -> NUMBER | "(" expression ")"
const Parser = struct {
    src: []const u8,
    pos: usize = 0,

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.src.len and
            (self.src[self.pos] == ' ' or self.src[self.pos] == '\t' or
                self.src[self.pos] == '\r' or self.src[self.pos] == '\n'))
        {
            self.pos += 1;
        }
    }

    fn peek(self: *Parser) ?u8 {
        self.skipWhitespace();
        if (self.pos >= self.src.len) return null;
        return self.src[self.pos];
    }

    fn match(self: *Parser, c: u8) bool {
        if (self.peek() == c) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn expression(self: *Parser) EvalError!f64 {
        var value = try self.term();
        while (true) {
            if (self.match('+')) {
                value += try self.term();
            } else if (self.match('-')) {
                value -= try self.term();
            } else break;
        }
        return value;
    }

    fn term(self: *Parser) EvalError!f64 {
        var value = try self.unary();
        while (true) {
            if (self.match('*')) {
                value *= try self.unary();
            } else if (self.match('/')) {
                const divisor = try self.unary();
                if (divisor == 0) return EvalError.DivideByZero;
                value /= divisor;
            } else break;
        }
        return value;
    }

    fn unary(self: *Parser) EvalError!f64 {
        if (self.match('-')) {
            return -(try self.unary());
        }
        return self.primary();
    }

    fn primary(self: *Parser) EvalError!f64 {
        if (self.match('(')) {
            const value = try self.expression();
            if (!self.match(')')) return EvalError.ExpectedRParen;
            return value;
        }

        const c = self.peek() orelse return EvalError.ExpectedExpression;
        if (c >= '0' and c <= '9' or c == '.') {
            return self.number();
        }
        return EvalError.UnexpectedChar;
    }

    fn number(self: *Parser) EvalError!f64 {
        const start = self.pos;
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if ((c >= '0' and c <= '9') or c == '.') {
                self.pos += 1;
            } else break;
        }
        return std.fmt.parseFloat(f64, self.src[start..self.pos]) catch
            EvalError.UnexpectedChar;
    }
};

fn errorMessage(err: EvalError) []const u8 {
    return switch (err) {
        EvalError.UnexpectedChar => "unexpected character",
        EvalError.ExpectedExpression => "expected an expression",
        EvalError.ExpectedRParen => "expected ')'",
        EvalError.DivideByZero => "division by zero",
    };
}

/// Compile + run one chunk of source code.
/// Returns 0 on success, non-zero on error.
///
/// Currently evaluates a single arithmetic expression and prints the result.
export fn interpret(len: usize) i32 {
    const source = scratch[0..len];

    var parser = Parser{ .src = source };
    const value = parser.expression() catch |err| {
        print("error: ");
        print(errorMessage(err));
        print("\n");
        return 1;
    };

    // Reject trailing junk, e.g. "1 2" or "3 +".
    if (parser.peek() != null) {
        print("error: unexpected trailing input\n");
        return 1;
    }

    var buf: [64]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "{d}\n", .{value}) catch {
        print("error: could not format result\n");
        return 1;
    };
    print(out);
    return 0;
}
