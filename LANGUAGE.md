# NokaScript Language Reference

Complete specification of the NokaScript language.
Designed for a 24-column (but still allowing lines to extend beyond) fantasy console with mobile-first input. See [CONSOLE.md](CONSOLE.md) for the machine itself.

## Design Principles

- **Expression-oriented:** loops, `case`, `fn`, `do` blocks, and assignments all produce values. A small set of constructs (declarations, destructuring, `stop`, `next`) are statements for scoping / control-flow reasons. See [Grammar](#grammar).
- **Newline-delimited:** no semicolons, no statement terminators
- **Keyword-closed blocks:** `end` closes all blocks
- **No implicit truthiness:** no type coercion to boolean; `and`/`or`/`not` require booleans
- **Minimal special characters:** keywords are plain alpha, reducing keyboard-layer switches
- **Flat built-in namespace:** standard library functions are globals, no prefixes
- **Errors are values:** recoverable failures are ordinary `error` values threaded explicitly; unrecoverable bugs `panic`. See [Error Handling](#error-handling).
- **Terse by default:** every token earns its place on a 24-column screen

## Values and Types

There are eight value types:

| Type       | Examples                     | Notes                                |
|------------|------------------------------|--------------------------------------|
| `number`   | `42`, `3.14`, `0xFF`, `0b101`| IEEE 754 double (JS `number`)        |
| `string`   | `"hello"`, `'world'`         | Bytes in the Noka charset; a value, never shared (see [Strings](#strings)) |
| `boolean`  | `true`, `false`              |                                      |
| `nil`      | `nil`                        | Represents absence of a value        |
| `array`    | `[1, 2, 3]`                  | Ordered, 1-indexed                   |
| `object`   | `{name: "noka", ver: 2}`     | String-keyed map                     |
| `function` | `fn f() end`                 | User-defined or native built-in      |
| `error`    | `error("eof", "io")`         | Recoverable failure; see [Error Handling](#error-handling) |

There is no implicit type coercion. Arithmetic operators require numbers. The `+` operator doubles as string concatenation when both operands are strings. Mixed-type `+` (e.g., `"score: " + 10`) is a runtime error; use `f""` or `tostr()`.

### Equality

`==` uses **deep equality** for numbers, strings, booleans, nil, arrays, and objects. Two arrays or objects with the same contents are equal. Functions use **reference equality:** two functions are equal only if they are the same reference.

Numbers compare by IEEE 754 rules, including inside arrays and objects and in `in`: `nan == nan` is `false` and `-0 == 0` is `true`.

Deep equality returns `true` at once for the same reference and otherwise recurses up to 64 levels deep. Past that it panics with "value too deeply nested or cyclic".

```
[1, 2] == [1, 2]    // true (deep)
{a: 1} == {a: 1}    // true (deep)
f : fn() 1
g : fn() 1
f == g              // false (different references)
f == f              // true
```

### Nil Checking

The `?` postfix operator returns `true` if a value is not `nil`, `false` otherwise.

```
x?            // true if x is not nil
items[5]?     // true if index exists
info.name?    // true if key exists
```

The `??` operator returns the left side if not `nil`, otherwise the right side.

```
name : get_name() ?? "default"
```

### Optional Chaining

`?.`, `?[`, and `?(` are optional-chain access operators. If the value on the left is `nil`, the whole chain short-circuits to `nil` without evaluating the rest. If the value is non-nil, the access proceeds normally.

```
user?.address?.city    // nil if user or address is nil
items?[1]              // nil if items is nil
handler?(event)        // nil if handler is nil
```

A chain mixes regular and optional access freely. Once a `?.` / `?[` /
`?(` short-circuits, everything further right is skipped:

```
user?.profile.name    // if user is nil -> nil
                      // if user exists but profile is nil -> runtime error on .name
                      // if both exist -> name
```

Use optional chaining when the intermediate step is legitimately optional. Use regular access when you expect the field to exist; you will get a clearer error if it is missing.

Regular field access on `nil`, or on any other non-object, panics. Reading a key an object doesn't have returns `nil`. See [Objects](#objects).

Long chains can wrap across lines: a line starting with `.`, `?.`, `?[`, or `?(` continues the previous line. See [Line Continuation](#line-continuation).

```
user
  ?.address
  ?.city
```

## Lexical Structure

### Identifiers

Start with a letter (`a`-`z`, `A`-`Z`) or underscore (`_`), followed by zero or more letters, digits, or underscores. The identifier `_` is reserved as the universal discard/wildcard/capture symbol (see [Pipes](#pipes), [Captures](#function-captures), [Destructuring](#destructuring), and [Case](#case-expressions)).

```
foo
_bar
baz123
myVar_2
```

Identifiers are case-sensitive. `foo` and `Foo` are different variables.

### Reserved Keywords

```
case    end     while   for     in
stop    next    fn      do      this
and     or      not     band    bor
bnot    bxor    true    false   nil
if      ret     err     catch
```

`if` is reserved solely for use as a guard in `case` branches (`pat if cond -> body`); it has no standalone statement form.

`ret`, `err`, and `catch` belong to the error-handling system; see [Error Handling](#error-handling).

`init`, `tick`, and `draw` are not keywords. They are ordinary names the engine calls each frame; see [Lifecycle Functions](#lifecycle-functions-host-convention).

Any keyword may be used as a field name after `.` and `?.` and as a key in an object literal (`obj.end`, `{next: 1}`). Shorthand (`{end}`) and unrenamed destructuring (`{next} : obj`) stay illegal; write `{next: n} : obj`.

### Number Literals

Integers, decimals, hexadecimal, and binary.

```
42
3.14
0xFF
0b1010
```

### String Literals

Delimited by double quotes (`"`) or single quotes (`'`). Both behave identically. Must be on a single line unless prefixed with `m`.

```
"hello world"
'she said "hi"'
"it's fine"
```

#### String Prefixes

| Prefix | Escapes | Interpolation | Multi-line |
|--------|---------|---------------|------------|
| (none) | yes     | no            | no         |
| `f`    | yes     | yes           | no         |
| `m`    | no      | no            | yes        |
| `mf`/`fm` | no  | yes           | yes        |

```
// Plain
"hello world"
"tab\there"

// Formatted (interpolation via {expr})
f"score: {score}"
f'hp: {hp}/{max_hp}'

// Multi-line (literal newlines, no escapes)
m"
first line
second line
"

// Multi-line formatted
fm"
name: {name}
score: {score}
"
```

Any expression is allowed inside `{}` in f-strings. The parser tracks brace depth, so strings and nested braces inside interpolations work correctly:

```
f"status: {case hp > 50 -> "ok"}"
f"pos: {{x: 10, y: 20}.x}"
```

Interpolation is a suppressed-newline context, but a multi-line `case`, `do`, etc. opened inside it re-enables newlines within its own body, so multi-line forms can appear inside interpolation when needed.

#### Escape Sequences

Available in plain and `f` strings only.

| Escape | Produces         |
|--------|------------------|
| `\n`   | newline          |
| `\t`   | tab              |
| `\\`   | literal `\`      |
| `\"`   | literal `"`      |
| `\'`   | literal `'`      |
| `\{`   | literal `{` (in `f` strings) |
| `\}`   | literal `}` (in `f` strings) |

### Comments

Line comments start with `//` and extend to the end of the line.

```
// this is a comment
x : 10  // inline comment
```

#### Type Hint Comments

A comment starting with `///` provides optional type hints for the following function. These are **editor-only** soft warnings, not runtime enforcement. They help catch type mismatches before running.

Hints come in two forms. The **single-line** form lists the parameter types in order, with the return type prefixed by `->`. Names are **optional** here, write bare types (`num, num`) for a clean layout, or name them (`x: num, y: num`) when it aids clarity. The **multi-line** form splits across consecutive `///` lines, one entry per line, and names are **mandatory** (`name: type`) so each line is self-describing; the return type goes on its own line, prefixed with `->`:

```
// Single line: bare positional types
/// num, num -> num
fn add(x, y)
  x + y
end

// Single line: names are optional
/// x: num, y: num -> num
fn add(x, y)
  x + y
end

// Multi-line: one named entry per /// line, return on its own line
/// x: num
/// y: num
/// -> num
fn add(x, y)
  x + y
end

/// num|str -> str
fn show(v)
  ...
end

/// num, num, num? -> nil
fn plot(x, y, color)
  ...
end

/// num, *num -> num
fn sum(first, *rest)
  ...
end
```

Short type names: `num`, `str`, `bool`, `nil`, `arr`, `obj`, `fn`, `err`. These are the same names `type()` returns and runtime errors use. Unions: `num|str`. Optional/nullable: `num?` (shorthand for `num|nil`). Variadic: `*num`, or `*rest: num` when named. Omit the `->` entry to leave the return type unspecified.

A multi-line hint must be a run of consecutive `///` lines immediately above the function, a plain `//` line or a blank line ends the block. In the multi-line form, every entry must be named and the names should match the function's parameters; an unnamed or mismatched entry is an editor warning.

Type hints apply to named and anonymous functions only.

### Block Expressions

`do ... end` creates a block expression. Inside a block:
- Newlines are statement separators
- Multiple statements execute sequentially
- The last expression is the return value
- A block that ends in a statement (a declaration, for example) evaluates to `nil`, so `do x : 1 end` is `nil`
- Bindings introduced inside the block are scoped to it and do not leak out
- An empty block (`do end`) evaluates to `nil`

```
// Block expression (multiple statements, last value returned)
result : do
  dmg : roll_damage()
  apply(target, dmg)
  dmg
end
```

A `do ... end` block is a first-class expression: it can appear anywhere an expression is expected (right-hand side of a binding, inside a call argument, as a `case` branch body, etc.).

Parentheses `()` are for grouping and function calls. Newlines are suppressed inside `()`, `[]`, and `{}`.

```
// Grouping (line continuation)
x = (
  long_name +
  other_name
)

// Multi-line function call
foo(
  arg1,
  arg2
)

// Multi-line array
items : [
  1, 2, 3,
  4, 5, 6
]

// Multi-line object
info : {
  name: "noka",
  ver: 2
}
```

### Newline Handling

Expressions are separated by newlines. Newline significance follows a stack rule: newlines are suppressed inside bracketed contexts (`(`, `[`, `{`) and re-enabled inside block constructs opened within them (`do`, multi-line `fn`, multi-line `case`, etc.). See [Newline Significance (Stack Rule)](#newline-significance-stack-rule) for the full table and rules.

### Trailing Commas

Trailing commas are allowed in arrays, objects, function calls, and function parameters.

```
items : [
  1, 2, 3,
]

info : {
  name: "noka",
  ver: 2,
}

foo(
  arg1,
  arg2,
)
```

### Operators and Punctuation

Single-character:

| Token | Meaning                        |
|-------|--------------------------------|
| `+`   | addition / string concat       |
| `-`   | subtraction / unary negation   |
| `*`   | multiplication / rest/spread   |
| `/`   | division                       |
| `%`   | modulo                         |
| `=`   | assignment (existing binding)  |
| `:`   | declaration / key-value        |
| `#`   | constant declaration           |
| `<`   | less than                      |
| `>`   | greater than                   |
| `(`   | grouping / call open           |
| `)`   | grouping / call close          |
| `[`   | array literal / index open     |
| `]`   | array close / index close      |
| `{`   | object literal open            |
| `}`   | object literal close           |
| `,`   | separator                      |
| `.`   | field access                   |
| `?`   | nil-check postfix              |

Two-character:

| Token | Meaning              |
|-------|----------------------|
| `==`  | equality             |
| `!=`  | not-equal            |
| `<=`  | less-or-equal        |
| `>=`  | greater-or-equal     |
| `+=`  | compound add         |
| `-=`  | compound subtract    |
| `*=`  | compound multiply    |
| `/=`  | compound divide      |
| `%=`  | compound modulo      |
| `++`  | increment            |
| `--`  | decrement            |
| `**`  | exponentiation       |
| `<<`  | left shift           |
| `>>`  | right shift          |
| `??`  | nil-coalescing       |
| `//`  | comment start        |
| `->`  | case branch arrow    |
| `\|>` | pipe                 |
| `?.`  | optional field       |
| `?[`  | optional index open  |
| `?(`  | optional call open   |
| `?:`  | result/error split   |

Three-character:

| Token | Meaning              |
|-------|----------------------|
| `**=` | compound exponent    |
| `<<=` | compound left shift  |
| `>>=` | compound right shift |

`%` is floored: the result takes the divisor's sign, so `-7 % 3` is `2`, and for fractions `a % b` is `a - floor(a / b) * b`. `% 0` panics like division by zero. Floored modulo makes wrapping such as `x = (x - 1) % 192` correct.

Bitwise operators (`band`, `bor`, `bxor`, `bnot`, `<<`, `>>`) work on signed 32-bit integers. Operands must be whole numbers in signed 32-bit range and shift counts must be 0 to 31, or the operation panics. `>>` preserves the sign, and results are ordinary numbers. A full 32-bit mask such as `0xFFFFFFFF` is out of range.

`<`, `>`, `<=` and `>=` compare two numbers, or two strings byte by byte. Byte order puts uppercase before lowercase (`"Zed" < "abe"`). Mixed types panic.

## Bindings

NokaScript has two declaration operators and one assignment operator:

| Syntax   | Meaning                                     |
|----------|---------------------------------------------|
| `x : 5`  | declare new mutable local                  |
| `x # 5`  | declare new constant local (frozen snapshot) |
| `x = 5`  | assign to existing binding (error if none) |
| `v, e ?: f()` | declare value + error from a fallible call (see [Error Handling](#error-handling)) |

Declarations (`:` and `#`) are **statements**, they introduce a new name into the enclosing scope and do not produce a value. Destructuring forms (`[x, y] : expr`, `{a, b} # expr`) are also statements.

Assignment (`=`), compound assignment (`+=`, `-=`, ...), and `++` / `--` are **expressions**. They mutate an existing binding and produce the new value, so they can appear anywhere an expression can.

Every variable must be explicitly declared with `:` or `#` before use. Assignment (`=`) walks the scope chain looking for an existing binding. If none is found, it is a **runtime error**.

Re-declaring a variable in the **same scope** is an error (runtime error at the top level, compile error inside blocks). Shadowing a variable from an **outer scope** is allowed.

Constants (`#`) can never be reassigned (runtime error at the top level, compile error inside blocks). A constant holds a **frozen snapshot**: everything reachable from it is frozen, and nothing outside it changes.

- Arrays and objects written as literals in the declaration are frozen in place.
- An array or object reached through a name or a call is copied, then frozen. The original stays mutable, so after `b # a`, `push(a, 4)` still works and `push(b, 4)` panics. After `ui # {target: player}`, `ui.target` is a frozen copy of `player` at that moment, and `player` stays live.
- Copying goes depth-first, up to 64 levels deep. A deeper or cyclic value panics with "value too deeply nested or cyclic". A part reached twice is copied twice.
- Strings are values, so `name # "noka"` simply makes the binding constant, and `name[1] = "N"` panics. Errors are already immutable and are shared. Functions are shared and not frozen: a closure inside a constant can still change the variables it captured.

Reassigning a constant, or pushing to, setting fields on, or index-assigning a frozen value, panics with kind `"frozen"`. A frozen value stays frozen wherever it is passed: after `t : ui.target`, `t.hp = 0` panics. Spreading a frozen value (`[*b]`, `{*b}`) gives an unfrozen copy.

Field and index assignment always use `=`:

```
t.name = "noka"   // field assignment
t[1] = "first"    // index assignment
```

### Examples

```
x : 10            // declare mutable
x = 20            // reassign existing x

PI # 3.14         // constant, locked forever
PI = 0            // RUNTIME ERROR

y = 5             // RUNTIME ERROR (y not declared)

x : 10
x : 20            // RUNTIME ERROR (already declared in this scope)

items # [1, 2, 3]
items[1] = 99     // RUNTIME ERROR (frozen)
push(items, 4)    // RUNTIME ERROR (frozen)

x : 10
fn foo()
  x = 20          // mutates outer x
end

x : 10
fn foo()
  x : 5           // new local x, shadows outer (allowed)
end
```

## Grammar

NokaScript is mostly expression-oriented: loops, `case`, `fn`, `do` blocks, and assignments all produce values. A small set of constructs are **statements** rather than expressions, because they carry scoping or control-flow effects that would be surprising as subexpressions:

- `x : expr` and `x # expr` (declarations introduce a name into scope)
- `v, e ?: expr` (result/error split declaration)
- Destructuring bindings
- `stop [expr]` and `next` (loop control)
- `ret [expr]` and `err expr` (function return / error return)

Assignment (`=`), compound assignment, and `++` / `--` stay as expressions. They mutate an existing binding and produce the new value, without introducing names.

### Program Structure

```
program   = { NEWLINE } { statement NEWLINE } EOF
block     = { NEWLINE } { statement NEWLINE }

statement = binding
          | func_decl
          | destructuring
          | result_bind
          | stop_stmt
          | next_stmt
          | ret_stmt
          | err_stmt
          | expression
```

### Statements

```
binding       = IDENTIFIER ":" expression
              | IDENTIFIER "#" expression

func_decl     = "fn" IDENTIFIER "(" [ params ] ")" expression
              | "fn" IDENTIFIER "(" [ params ] ")" NEWLINE block "end"

destructuring = pattern ( ":" | "#" | "=" ) expression

result_bind   = bind_target "," bind_target "?:" expression
bind_target   = IDENTIFIER | "_"

stop_stmt     = "stop" [ expression ]
next_stmt     = "next"
ret_stmt      = "ret" [ expression ]
err_stmt      = "err" expression
```

A `func_decl` is a named function declaration at statement position. It binds the name into the enclosing scope as a mutable local (equivalent to `name : fn(...) ... end`) and is **hoisted** within its block. Anonymous and named-but-not-statement-position functions use `func_expr` in the expression grammar instead.

`stop_stmt` and `next_stmt` are parse errors unless they appear inside the body of an enclosing loop (`while` or `for`) within the same function. Function boundaries block the check: a `stop` inside a helper function called from a loop does not stop that loop.

`stop_stmt` and `next_stmt` are also legal as the body of a case branch (`-> stop i`, `-> next`), subject to the same enclosing-loop rule.

### Patterns (Destructuring)

```
pattern        = array_pattern | object_pattern

array_pattern  = "[" [ pat_elem { "," pat_elem } [ "," ] ] "]"
pat_elem       = IDENTIFIER [ "??" expression ]
               | "_"
               | "*" IDENTIFIER
               | pattern [ "??" expression ]

object_pattern = "{" [ obj_pat { "," obj_pat } [ "," ] ] "}"
obj_pat        = IDENTIFIER [ ":" ( IDENTIFIER | pattern ) ] [ "??" expression ]
               | "*" IDENTIFIER
```

Patterns nest freely. The same pattern syntax is reused in function parameters (`fn foo({x, y})`) and for-in loops (`for {name} in people`).

A `*rest` element collects whatever slots are not bound by the other elements. It may appear in any position within an `array_pattern`, `object_pattern`, or `params` list (at most one per pattern). Elements before `*rest` bind positionally from the start; elements after it bind positionally from the end (for arrays) or by name (for objects).

### Expression Grammar (Precedence: lowest to highest)

```
expression     = assignment | pipe
assignment     = assignable ( "=" | compound_op ) expression
               | assignable ( "++" | "--" )

compound_op    = "+=" | "-=" | "*=" | "/=" | "%="
               | "**=" | "<<=" | ">>="

assignable     = IDENTIFIER
               | "this"
               | assignable "." field_name
               | assignable "[" expression "]"

pipe           = logic_or { "|>" logic_or }
logic_or       = logic_and { "or" logic_and }
logic_and      = nil_coalesce { "and" nil_coalesce }
nil_coalesce   = bit_or { "??" bit_or }
bit_or         = bit_xor { "bor" bit_xor }
bit_xor        = bit_and { "bxor" bit_and }
bit_and        = equality { "band" equality }
equality       = comparison { ( "==" | "!=" ) comparison }
comparison     = shift { ( "<" | ">" | "<=" | ">=" | "in" | "not" "in" ) shift }
shift          = addition { ( "<<" | ">>" ) addition }
addition       = multiplication { ( "+" | "-" ) multiplication }
multiplication = exponent { ( "*" | "/" | "%" ) exponent }
exponent       = unary { "**" unary }
unary          = ( "not" | "-" | "bnot" ) unary | postfix
postfix        = chain [ "?" ]
chain          = primary { chain_op }
chain_op       = "." field_name          // field access
               | "[" expression "]"      // index access
               | "(" args ")"            // call
               | "?." field_name         // optional field
               | "?[" expression "]"     // optional index
               | "?(" args ")"           // optional call
field_name     = IDENTIFIER | keyword
args           = [ arg { "," arg } [ "," ] ]
arg            = expression | IDENTIFIER ":" expression | <empty>
primary        = NUMBER | STRING | "true" | "false" | "nil" | "_"
               | "this" | IDENTIFIER | "(" expression ")"
               | block_expr | array_literal
               | object_literal | func_expr | case_expr
               | while_expr | for_expr | catch_expr
```

The trailing `?` on `postfix` is the boolean nil-check. The `?.`/`?[`/`?(` chain operators are optional-chain accesses: if the LHS is nil, the whole chain short-circuits to nil.

The pipe (`|>`) is parsed uniformly as `logic_or |> logic_or`. Its **semantics** depend on the shape of the parsed RHS node: if the RHS is syntactically a call (its top-level form is a `chain` ending in `(...)` or `?(...)`), the piped value is inserted into that call's argument list (filling every `_` if any are present, otherwise prepended as the first argument). For any other RHS, the RHS is evaluated and the resulting value must be callable; the piped value is then applied to it.

### Compound Expressions

```
block_expr      = "do" NEWLINE block "end"
                | "do" "end"

catch_expr      = "catch" block_expr

while_expr      = "while" expression NEWLINE block "end"
for_expr        = for_num | for_in
for_num         = "for" IDENTIFIER ":" expression "," expression
                  [ "," expression ] NEWLINE block "end"
for_in          = "for" for_var { "," for_var } "in" expression NEWLINE
                  block "end"
for_var         = IDENTIFIER | "_" | pattern

func_expr       = "fn" [ IDENTIFIER ] "(" [ params ] ")" expression
                | "fn" [ IDENTIFIER ] "(" [ params ] ")" NEWLINE block "end"
params          = param { "," param } [ "," ]
param           = IDENTIFIER
                | IDENTIFIER ":" expression
                | IDENTIFIER "?"
                | "*" IDENTIFIER
                | pattern
                | pattern ":" expression

case_expr       = "case" expression "->" branch_body
                | "case" [ expression ] NEWLINE
                  { case_branch NEWLINE }
                  [ "_" "->" branch_body NEWLINE ]
                  "end"
case_branch     = case_pattern { "," case_pattern } [ "if" expression ]
                  "->" branch_body
case_pattern    = expression | comparison_op expression
comparison_op   = ">" | "<" | ">=" | "<=" | "==" | "!="
branch_body     = expression | stop_stmt | next_stmt | ret_stmt | err_stmt

array_literal   = "[" [ arr_elem { "," arr_elem } [ "," ] ] "]"
arr_elem        = expression | "*" expression

object_literal  = "{" [ object_body ] "}"
object_body     = obj_spread
                | obj_spread "," obj_field { "," obj_field } [ "," ]
                | obj_field { "," obj_field } [ "," ]
obj_spread      = "*" expression
obj_field       = field_name ":" expression    // keywords allowed as keys
                | STRING ":" expression
                | IDENTIFIER                    // shorthand, not a keyword
```

Objects allow at most one spread, which must appear first. The `_` catch-all in `case_expr` must be the last branch; mid-position `_` is a parse error.

### Expression Return Values

Every expression produces a value:

| Expression           | Returns                                          |
|----------------------|--------------------------------------------------|
| `x = 5`             | the assigned value (`5`)                         |
| `x++` / `x--`       | the value after increment/decrement              |
| `x += 1`            | the assigned value                               |
| `while ... end`      | last completed iteration's value, or `nil` (an iteration ended by `next` leaves it unchanged) |
| `for ... end`        | last completed iteration's value, or `nil` (an iteration ended by `next` leaves it unchanged) |
| `case ... end`       | matched branch's value, or `nil` if no match     |
| `fn ... end`       | the function value                               |
| `do ... end`         | last expression in the block, or `nil` if empty or ending in a statement |
| `catch do ... end`   | the block's value, or the error if it panicked   |

Statements (`:`, `#`, `?:`, destructuring, `stop`, `next`, `ret`, `err`) don't appear as values, they execute for their effects. `stop <expr>` causes the enclosing loop to return `<expr>`; bare `stop` returns `nil`. `ret <expr>` returns `<expr>` from the enclosing function (bare `ret` returns `nil`); `err <expr>` returns early with an error.

### Notes

Single-line `case` is always a bare condition (no match expression). Match expressions always use multi-line form with `end`.

Functions return the value of their last expression. Prefer `case` to structure conditional returns; reserve an explicit `ret` for genuine early-exit guards, and use `stop <expr>` for early exit from loops.

### Lexical Grammar

```
token         = literal | identifier | keyword | operator | delimiter
              | COMMENT | NEWLINE

literal       = NUMBER | STRING

NUMBER        = decimal | hex | binary
decimal       = DIGIT { DIGIT } [ "." DIGIT { DIGIT } ]
hex           = "0" ( "x" | "X" ) HEX_DIGIT { HEX_DIGIT }
binary        = "0" ( "b" | "B" ) BIN_DIGIT { BIN_DIGIT }

STRING        = [ string_prefix ] ( '"' { string_char } '"' )
              | [ string_prefix ] ( "'" { string_char } "'" )
string_prefix = "f" | "m" | "fm" | "mf"
string_char   = ESCAPE | INTERP | <any char except quote, or newline unless m-prefixed>
ESCAPE        = "\n" | "\t" | "\\" | '\"' | "\'" | "\{" | "\}"
INTERP        = "{" expression "}"     // f-prefixed strings only

identifier    = ALPHA { ALPHA | DIGIT }
ALPHA         = "a".."z" | "A".."Z" | "_"
DIGIT         = "0".."9"
HEX_DIGIT     = DIGIT | "a".."f" | "A".."F"
BIN_DIGIT     = "0" | "1"

keyword       = "case" | "end" | "while" | "for" | "in"
              | "stop" | "next" | "fn" | "do" | "this"
              | "and" | "or"
              | "not" | "band" | "bor" | "bnot" | "bxor"
              | "true" | "false" | "nil" | "if"
              | "ret" | "err" | "catch"

operator      = "+" | "-" | "*" | "/" | "%" | "=" | ":"
              | "#" | "<" | ">" | "." | "?"
              | "++" | "--" | "+=" | "-=" | "*=" | "/=" | "%="
              | "==" | "!=" | "<=" | ">=" | "->" | "|>"
              | "**" | "<<" | ">>" | "??"
              | "?." | "?[" | "?(" | "?:"
              | "**=" | "<<=" | ">>="

delimiter     = "(" | ")" | "[" | "]" | "{" | "}" | ","

COMMENT       = "//" <any char except newline>*
NEWLINE       = "\n"
```

Whitespace (spaces, tabs, carriage returns) is ignored between tokens. Consecutive newlines are collapsed into a single `NEWLINE` token. EOF acts as an implicit final `NEWLINE`, so a source file without a trailing newline is still valid.

### Newline Significance (Stack Rule)

Newline significance is tracked by a stack of frames. Each frame is either "suppress" (newlines treated as whitespace) or "significant" (newlines delimit statements). The default state at program top level is "significant."

Pushing and popping:

| Construct                                              | Frame         |
|--------------------------------------------------------|---------------|
| `(` `[` `{` ... matching `)` `]` `}`                   | suppress      |
| `do` ... `end`                                         | significant   |
| `while` ... `end`                                      | significant   |
| `for` ... `end`                                        | significant   |
| `fn(...)` NEWLINE ... `end` (multi-line form)        | significant   |
| `case [expr]` NEWLINE ... `end` (multi-line form)      | significant   |

`fn` and `case` only push a frame in their multi-line form. The parser determines this by peeking past the `)` (fn) or past the optional match expression (case): if the next token is NEWLINE, the construct is multi-line and pushes a "significant" frame. Otherwise it is single-line and does not push.

A multi-line construct opened inside a suppressed context therefore re-enables newlines within its body, so this parses cleanly:

```
foo(do
  x : compute()
  x * 2
end)

result : each(items, fn(x)
  case x > 0 -> x * 2
  _ -> 0
  end
end)
```

### Line Continuation

A line that *starts* with one of the following tokens continues the previous line (the intervening newline is treated as whitespace):

- `|>` (pipe)
- `.` (field access)
- `?.`, `?[`, `?(` (optional-chain access)

These tokens are unambiguously postfix (they cannot start a new statement), so they safely continue the preceding expression:

```
name
  |> trim()
  |> upper()

user
  ?.address
  ?.city
```

For arithmetic and other infix continuation, place the trailing binary operator at the end of the current line. The newline immediately after any binary or n-ary operator that requires a right-hand operand is suppressed. This covers:

- arithmetic: `+`, `-`, `*`, `/`, `%`, `**`
- bit shift: `<<`, `>>`
- comparison: `<`, `>`, `<=`, `>=`, `==`, `!=`, `in`, `not in`
- bitwise: `band`, `bor`, `bxor`
- logical: `and`, `or`
- nil-coalescing: `??`
- assignment: `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `**=`, `<<=`, `>>=`
- case branch arrow: `->`

```
total : a +
  b +
  c

ok : alive and
  ready

label : case status
  "alive" ->
    "keep going"
  _ -> "unknown"
end
```

Trailing `,` does not need this rule because commas only appear inside bracketed contexts, where newlines are already suppressed. The four non-bracketed uses of `,`: `for i : a, b, c`, `for k, v in …`, multi-value case patterns `"a", "b" -> …`, and the result/error split (`v, e ?: f()`) must stay on a single line.

### Disambiguation: Destructuring vs. Literals

Destructuring is its own statement production (`destructuring = pattern ( ":" | "#" | "=" ) expression`), syntactically distinct from object and array literals. When `{` or `[` appears at the start of a statement, the parser needs one-token lookahead after the matching close-bracket: if `:`, `#`, or `=` follows, parse as `destructuring`; otherwise, parse as an expression statement (object or array literal). The patterns and literal grammars are disjoint, so no reinterpretation is required.

### Operator Precedence Table

| Precedence  | Operators                  | Associativity | Description           |
|-------------|----------------------------|---------------|-----------------------|
| 0 (lowest)  | `=` `+=` `-=` `*=` `/=` `%=` `**=` `<<=` `>>=` `++` `--` | right | assignment / in-place mutation |
| 1           | `\|>`                      | left          | pipe                  |
| 2           | `or`                       | left          | logical or            |
| 3           | `and`                      | left          | logical and           |
| 4           | `??`                       | left          | nil-coalescing        |
| 5           | `bor`                      | left          | bitwise or            |
| 6           | `bxor`                     | left          | bitwise xor           |
| 7           | `band`                     | left          | bitwise and           |
| 8           | `==`  `!=`                 | left          | equality              |
| 9           | `<`  `>`  `<=`  `>=` `in` `not in` | left  | comparison/membership |
| 10          | `<<`  `>>`                 | left          | bit shift             |
| 11          | `+`  `-`                   | left          | addition/subtraction  |
| 12          | `*`  `/`  `%`              | left          | multiplication        |
| 13          | `**`                       | right         | exponentiation        |
| 14          | `not`  `-`  `bnot`         | right         | unary                 |
| 15          | `?`                        | postfix       | boolean nil-check     |
| 16 (highest)| `()` `[]` `.` `?.` `?[` `?(` | left        | chain / access (optional variants short-circuit on nil) |

Assignment sits below pipe, so `x = 5 |> f()` parses as `x = (5 |> f())`. The LHS of `=`, compound assignment, and `++` / `--` must be an `assignable`: an identifier or a chain of `.` / `[]` accesses. Optional chains (`?.`, `?[`, `?(`) and function calls are **not** assignable.

## Common Expressions

### Declaration and Assignment

```
x : 10    // declare mutable
x # 10    // declare constant (frozen snapshot)
x = 20    // assign to existing (error if undeclared)
```

Declarations (`:`, `#`) are statements and produce no value. Assignment (`=`) is an expression and produces the assigned value, so it may appear anywhere an expression is expected.

### Compound Assignment

```
x += 1
x -= 2
x *= 3
x /= 4
x %= 5
x **= 2
x <<= 1
x >>= 1
```

Compound assignment is syntactic sugar: `x += 1` is equivalent to `x = x + 1`. Requires an existing binding.

### Increment / Decrement

```
x++            // equivalent to x += 1
x--            // equivalent to x -= 1

player.hp++    // works on field access
items[i]++     // works on index access
```

`++` and `--` apply to any assignable target: identifiers, dot access, and index access. Returns the value after increment/decrement.

### Field Assignment

```
t.name = "noka"    // dot access
t[1] = "first"     // index access
```

Field and index assignment always use `=`.

### `while` / `end`

```
i : 0
while i < 5
  print(i)
  i++
end
```

Returns the last completed iteration's value, or `nil` if zero iterations. Supports `stop` and `next`.

### `for` (Numeric)

```
for i : 1, 9
  print(i)
end

for i : 9, 1, -1    // with step
  print(i)
end
```

The range is **inclusive** on both ends. `for i : 1, 9` iterates 1 through 9. The loop variable is declared as a constant binding and scoped to the for block: assigning it is a compile error ("cannot assign to loop variable `i`"). A fresh binding is created each iteration, so captures taken inside the loop see the value of `i` at that iteration.

Start, end, and step must be **integers**, non-integer values are a runtime error. The default step is `1`. A step of `0` is a runtime error.

If the step sign does not match the direction from start to end, the loop runs **zero iterations** (no error):

```
for i : 1, 9, -1    // zero iterations (would go the wrong way)
for i : 9, 1        // zero iterations (default step is +1, goes wrong way)
```

If the step overshoots the end, the loop stops at the last value that stayed within range:

```
for i : 1, 10, 3    // i takes 1, 4, 7, 10 (next would be 13, out of range)
for i : 1, 9, 3     // i takes 1, 4, 7  (next would be 10, out of range)
```

Returns the last completed iteration's value, or `nil` if zero iterations.

### `for` (Generic / Iterator)

Iterates over arrays, objects, or strings.

```
items : [10, 20, 30]

// Array: values only
for v in items
  print(v)              // 10, 20, 30
end

// Array: index-value pairs
for i, v in items
  print(f"{i}: {v}")    // 1: 10, 2: 20, 3: 30
end
```

Array indices are 1-based. Object iteration order is insertion order.

**Objects always require key-value form:**

```
info : {name: "noka", ver: 2}

for k, v in info
  print(f"{k}: {v}")
end

// Discard keys with _
for _, v in info
  print(v)
end
```

`for v in` (single variable) is only valid for arrays and strings, not objects.

Strings iterate by character: `for c in s` yields one-character strings, and `for i, c in s` adds the 1-based index.

Loop variables are constant bindings, as in numeric `for`: assigning one is a compile error. The value isn't frozen, so `for e in enemies` still allows `e.hp -= 1`.

**Changing a collection while iterating it:**

- Arrays are walked live by index, checking the current length each step. Pushed elements are visited, and removals shift later elements.
- Objects panic with kind `"iteration"` if a key is added or removed during the loop. Changing a value is allowed.

To remove items while iterating, walk the array backwards by index:

```
for i : len(enemies), 1, -1
  case enemies[i].hp <= 0 -> remove(enemies, i)
end
```

### `stop`

Exits the innermost enclosing `while` or `for` loop within the current function.

`stop` with no value causes the loop to return `nil`. `stop <expr>` causes the loop to return that value. Nothing is allowed to the **left** of `stop`; it must start its own statement. Everything to the **right** is parsed as the return expression.

```
// Find first match, loop returns the index
fn index_of(arr, val)
  for i, v in arr
    case v == val -> stop i
  end
end
```

`stop` outside of an enclosing loop is a **parse error**. A function boundary blocks the lookup: `stop` inside a helper called from a loop does not stop that loop. Legal positions are the loop body itself or the body of a `case` branch inside the loop.

### `next`

Skips to the next iteration of the innermost enclosing loop. An iteration ended by `next` leaves the loop's value unchanged, while an iteration whose body ends in a statement contributes `nil`. `next` takes no value.

```
for i : 1, 9
  case i % 2 == 0 -> next
  print(i)    // odd numbers only
end
```

Like `stop`, `next` outside of an enclosing loop is a parse error, and function boundaries block the lookup.

## Case Expressions

`case` is the sole conditional construct. It replaces `if/elif/else` entirely. All forms are expressions and return the value of the matched branch.

### Single-Line

A single branch on one line needs no `end`. Single-line case is always a bare condition (no match expression).

```
case x > 5 -> print("big")
case alive? -> tick()
```

### Condition Chain (No Match Expression)

Without a match expression, each branch is a boolean condition. This is how you replace `if/elif/else`.

```
case
  hp > 50 -> status = "healthy"
  hp > 20 -> status = "hurt"
  _ -> status = "critical"
end

case
  key("left") -> x -= speed * dt
  key("right") -> x += speed * dt
end
```

### Value Matching

With a match expression, branches compare against it using equality. Always multi-line with `end`.

```
label : case status
  "alive" -> "keep going"
  "dead" -> "game over"
  _ -> "unknown"
end
```

### Comparison Matching

Branches starting with a comparison operator compare against the case value.

```
label : case hp
  > 50 -> "healthy"
  > 20 -> "hurt"
  _ -> "critical"
end
```

### Multiple Values Per Branch

```
msg : case dir
  "up", "north" -> go_north()
  "down", "south" -> go_south()
  _ -> nil
end
```

### Multi-line Branches

Use a `do ... end` block for multi-line branches.

```
result : case action
  "attack" -> do
    dmg : roll_damage()
    apply(target, dmg)
    dmg
  end
  "heal" -> heal(player)
  _ -> nil
end
```

### Guards

Branches can have an `if` guard for additional conditions. `if` is a reserved keyword used exclusively in this context. It has no standalone statement form.

```
case score
  > 100 if combo > 3 -> "epic"
  > 100 -> "great"
  > 50 -> "ok"
  _ -> "meh"
end
```

Guards must be boolean expressions.

### Nil on Miss

If no branch matches and there is no `_` catch-all, the case expression
returns `nil`.

### Rules

- `case` may optionally take a match expression: `case <expr>` or bare `case`
- Single-line `case` is always bare (no match expression)
- Match expressions always use multi-line form with `end`
- `_` is the catch-all branch (optional)
- If no branch matches and there is no `_`, the case expression returns `nil`
- With a match expression: value patterns use equality, comparison patterns use the specified operator
- Without a match expression: each branch is a boolean condition. A `comparison_op` pattern (e.g., `> 5 ->`) in a bare `case` is a parse error (there is no LHS to compare against)
- Branches may include an `if` guard after the pattern for additional filtering
- Multiple branches: `end` required
- Patterns are evaluated top to bottom; first match wins

## Membership Operators

The `in` operator tests membership. Returns `true` or `false`.

```
// Array: checks if some element == the value (deep equality)
"sword" in items

// Object: checks if key exists
"name" in info

// String: checks if substring exists
"ok" in message
```

The `not in` compound operator is the negation:

```
case "sword" not in items -> flee()
```

`in` and `not in` are at comparison precedence level.

## Pipes

The pipe operator `|>` threads the value on the left into the expression on the right. The RHS form determines how the value is consumed:

- **Call form** (`value |> f(args)`): the piped value is inserted into the
  call as its first argument, or fills every `_` placeholder if any are
  present. This is the common case.
- **Expression form** (`value |> expr`): if the RHS is not syntactically a
  call, `expr` is evaluated and the result is applied to the piped value.
  The RHS must evaluate to a function.

```
// Without pipe
upper(trim(sub(name, 1, 5)))

// With pipe (vertical)
name
  |> sub(1, 5)
  |> trim()
  |> upper()
```

### Placeholder `_`

If `_` appears in the right-hand call, the piped value fills every `_` instead of being inserted as the first argument.

```
player |> damage(10, _)    // damage(10, player)
5 |> clamp(_, 0, _)        // clamp(5, 0, 5)
```

If no `_` is present, the piped value is inserted as the first argument (default behavior).

### Non-call RHS

When the RHS is any expression other than a call, the pipe evaluates it and applies the result to the piped value. This lets a `do ... end` block produce a function on the fly:

```
value |> do
  factor : compute_factor()
  fn(x) x * factor
end
// Equivalent to: (do ... end)(value)
```

A bare identifier on the RHS works the same way: `x |> transform` is `transform(x)`. It is a runtime error if the RHS does not produce a callable.

Pipes sit just above assignment in the precedence table, lower than any other operator, so a pipe chain reads left-to-right without parentheses. They are especially useful with NokaScript's free-function standard library.

```
items
  |> sort(fn(a, b) a < b)
  |> concat(", ")
  |> print()
```

A line starting with `|>` continues the previous line (see [Line Continuation](#line-continuation)), so long chains wrap cleanly without parentheses.

## Function Captures

Any function call containing `_` as an argument becomes a **capture**, a single-argument closure where every `_` is filled with the same value.

```
add(1, _)         // fn(x) add(1, x)
clamp(_, 0, _)    // fn(x) clamp(x, 0, x)
```

`_` captures the **nearest enclosing call**. A fully-formed capture is just a value, parent calls see a function, not a `_`.

```
each(items, add(1, _))  // each(items, fn(x) add(1, x))
                        // _ is inside add(), so add() is the capture
                        // each() receives items and a function
```

Only a bare `_` passed as a whole argument makes a capture. `f(_ + 1)` is a compile error that suggests `fn(x) f(x + 1)`, and reading `_` anywhere else is a compile error.

Captures and pipe placeholders use the same `_` symbol and the same semantics (all `_` filled with one value). Pipes feed the value immediately; captures produce a closure for later use.

```
// These are equivalent:
items |> sort(less(_, _))
items |> sort(fn(x) less(x, x))

// Common use with higher-order functions:
nums |> filter(greater(_, 0))
sorted : sort(items, less(_, _))
doubled : each(nums, mul(2, _))
```

## Functions

### Named Functions

```
fn greet(name)
  print(f"hello {name}")
end

greet("noka")
```

Named function declarations are **hoisted**: they can be called before their declaration in the source. This applies at all scope levels. Named functions create mutable bindings (equivalent to `:`). A hoisted function that reads a local whose declaration hasn't run yet panics with "`x` used before its declaration".

### Return Values

Functions return the value of their **last expression**. Prefer `case` to structure conditional returns; reserve an explicit `ret` for genuine early-exit guards.

```
fn double(x)
  x * 2
end

fn magnitude(x)
  case
    x < 0 -> -x
    _ -> x
  end
end

fn classify(hp)
  case
    hp > 50 -> "healthy"
    hp > 20 -> "hurt"
    _ -> "critical"
  end
end
```

### Parameters

All parameters are **optional by default** and default to `nil` if not provided. Use `:` to specify an explicit default value. Use `?` to mark a parameter as explicitly optional (defaults to `nil`, same as no annotation, useful for documentation).

```
fn box(x, y, w: 8, h: 8)
  rectf(x, y, w, h)
end

box(10, 20)            // x=10, y=20, w=8, h=8
box(10, 20, 16, 16)    // x=10, y=20, w=16, h=16
```

Extra arguments are ignored unless a rest parameter collects them. So a callback that declares fewer parameters than it's called with simply doesn't receive the rest: `each` and `filter` always pass `(v, i)`, and `fn(v) v * 2` works.

Default expressions are evaluated on every call, and may refer to earlier parameters: `fn f(a, b: a * 2)`.

### Labelled Arguments

Arguments can be passed by name using `name: value` syntax at the call site. Unlabelled arguments must come **before** labelled arguments.

```
fn box(x, y, w: 8, h: 8)
  rectf(x, y, w, h)
end

box(10, 20, w: 16)    // x=10, y=20, w=16, h=8
box(10, 20, h: 16)    // x=10, y=20, w=8, h=16
```

Providing the same argument both positionally and by label panics with kind `"args"`, and so does a label that names no parameter ("unknown parameter `wdth`"). Built-ins accept labels using their documented parameter names: `rectf(x, y, h: 16)`.

### Skipping Positional Arguments

Use an empty slot (adjacent commas) to skip a positional argument, which receives its default value (`nil` or the declared default).

```
fn foo(a, b, c, d: 10)
  ...
end

foo(1, , 3)       // a=1, b=nil, c=3, d=10
foo(1, , , 4)     // a=1, b=nil, c=nil, d=4
foo(1, , c: 3)    // a=1, b=nil, c=3, d=10
```

Skips are only for interior gaps. To omit trailing arguments, just don't pass them.

### Rest Parameters

A `*` prefix on a parameter collects remaining arguments into an array. Rest may appear in any position, at most one per parameter list. Parameters before `*rest` bind positionally from the start; parameters after it bind positionally from the end.

```
fn sum(first, *rest)
  total : first
  for v in rest
    total += v
  end
  total
end

sum(1, 2, 3, 4)    // 10
```

### Closures

Functions capture their enclosing scope.

```
fn makeCounter()
  count : 0
  fn inc()
    count += 1
    count
  end
  inc
end

c : makeCounter()
print(c())    // 1
print(c())    // 2
```

### Single-Expression Functions

Both named and anonymous functions support a single-expression form: if the body is a single expression on the same line as the closing `)`, it is the return value and no `end` is required.

```
// Named single-expression
fn add(x, y) x + y
fn neg(x) -x

// Anonymous single-expression
sort(items, fn(a, b) a < b)
doubled : each(nums, fn(x) x * 2)
```

Multi-line form always requires `end`:

```
handler : fn(x)
  print(x)
  x * 2
end
```

The parser picks the form by looking at the token after `)`: a NEWLINE means multi-line, anything else means single-expression.

### Anonymous Functions

Anonymous functions use the `fn` keyword without a name. Both multi-line and single-expression forms are supported (see above).

```
handler : fn(x)
  print(x)
  x * 2
end

cmp : fn(a, b) a < b
```

### Constant Functions

To make a function immutable, use `#` with an anonymous function. Note: `#` bindings are not hoisted.

```
greet # fn(name)
  print(f"hello {name}")
end
```

## `this` and Methods

Objects can store functions as values. When a function is accessed via dot syntax, `this` is automatically bound to the object.

```
player : {
  hp: 100,
  heal: fn()
    this.hp += 10
  end
}

player.heal()    // this = player, hp becomes 110
```

### Auto-Binding on Dot Access

Accessing a method via dot returns a **bound function** with `this` permanently set to the object. This means methods can be detached and still work:

```
h : player.heal    // h is bound to player
h()                // this = player, works correctly
```

### Rules

- `this` is available inside any function stored on an object
- `obj.method()` binds `this` to `obj`
- `h : obj.method` returns a bound function (auto-binding)
- Every read of a function out of an object field binds `this`: `obj.heal`, `obj["heal"]`, `{heal} : obj`, and `v` in `for k, v in obj`
- A function never reached through a field inherits the `this` of the call that created it, so `each(buffs, fn(b) this.hp += b)` inside a method sees the method's `this`
- `this` outside of a bound context is a runtime error

### Bound Function Equality

Equality of bound functions uses **structural** comparison: two bound functions are equal if they wrap the same underlying function **and** the same bound `this`.

```
a : player.heal
b : player.heal
a == b    // true: same function, same `this`

c : enemy.heal
a == c    // false: different `this`
```

Unbound functions still use reference equality. A bound function and the raw function it wraps are not equal.

## Lifecycle Functions (Host Convention)

Lifecycle functions are a **Noka console convention**, not a core language feature. `init`, `tick`, and `draw` are ordinary functions, PICO-8 style. The engine looks up the program's top-level names `init`, `tick`, and `draw` and calls them if they exist: `init()` once at start, then `tick()` and `draw()` every frame at 60 Hz. Another host could ignore these names entirely.

```
x : 0
speed # 120    // pixels per second

fn init()
  x = 10
end

fn tick()
  x += speed * dt
end

fn draw()
  cls()
  rectf(x, 10, 8, 8)
end
```

| Function | Called                          | Typical use      |
|----------|---------------------------------|------------------|
| `init()` | Once, after top-level code runs | Setup state      |
| `tick()` | Every frame, 60 times a second  | Update logic     |
| `draw()` | Every frame, after `tick`       | Render to screen |

`dt` is a built-in constant equal to 1/60, so programs can work in seconds (`speed` in pixels per second). It never varies: every device steps a program identically. Neither `tick` nor `draw` takes arguments, and animation inside `draw` uses `time()`.

Top-level code runs once at load, then the engine checks top-level must-use (see [Must-Use](#must-use)) and calls `init()`. Put setup that can fail in `init()`, not at top level.

The lookup is by name each time, so reassigning `draw` swaps the handler, and `player.draw()` or `{draw: fn() ... end}` are ordinary methods. If a function doesn't exist, nothing happens for that phase. A program with only `draw` renders a static frame. A program with only `tick` runs logic without display. A program with neither runs top-level code once and exits.

When a frame runs long, the engine runs extra `tick`s and skips `draw` to catch up, at most two ticks per screen refresh, and drops any backlog beyond that. A slow program runs in slow motion, never with wrong physics. `cpu()` reports how much of the frame the last `tick` and `draw` used.

## Error Handling

NokaScript separates two kinds of failure:

- **Panics** are for *bugs*: programming errors that should never
  happen in correct code (type errors, calling `nil`, out-of-range
  mutation, division by zero, must-use violations). A panic unwinds the
  call stack to the nearest `catch`. If nothing catches it, the engine
  stops the program and shows the crash screen (reporting the real
  runtime type, not a type hint).
- **Errors** are ordinary *values* for *recoverable* failure: a save
  that didn't write, input that didn't parse, a lookup that legitimately
  failed. Errors are threaded explicitly, and the language makes it hard
  to drop one by accident.

A third kind of stop is neither: the **hang guard**. A single call into a program (top-level code, `init`, `tick` or `draw`) that runs past 2^28 instructions, about a second of work, is stopped. It bypasses every `catch`, so a runaway loop can't swallow it, and the crash screen shows "stopped responding".

### The `error` Type

`error` is a distinct value type (`type(e) == "err"`). Every error has:

| Field      | Type   | Notes                              |
|------------|--------|------------------------------------|
| `.message` | string | always present                     |
| `.kind`    | string | always present; a free-form tag    |
| `.data`    | any    | optional payload, `nil` if unset   |

Errors are immutable: reassigning `.message`, `.kind` or `.data` panics with kind `"frozen"`. The value stored in `.data` is not frozen.

Construct one with the `error` built-in:

```
e : error("file not found")              // kind defaults to "error"
e : error("bad input", "parse")          // explicit kind
e : error("overflow", "math", {n: x}).   // with data payload
```

"No error" is represented by `nil`. An error-typed binding is therefore always *error-or-nil*, and the presence operator `?` is how you test it:

```
e?    // true if e holds an error, false if nil
```

### Panic Kinds

A caught panic is an `error` whose `.data` is `{line: n}` and whose `.kind` is one of:

| Kind | Raised by |
|---|---|
| `"type"` | wrong operand types, calling a non-function, a non-boolean in `and`/`or`/`not` or a condition, a non-string object key |
| `"undefined"` | undefined name, local used before its declaration |
| `"index"` | index 0, fractional index, write past `len + 1`, multi-character string write, a color outside 1 to 32 |
| `"frozen"` | mutating a frozen value, assigning a constant or built-in at runtime, reassigning an error's fields |
| `"math"` | division or modulo by zero, bitwise operand or shift out of range, non-integer `for` bounds, `for` step 0, bad `rnd` bounds |
| `"args"` | unknown label, same argument by position and by label, unknown key name |
| `"iteration"` | object keys added or removed during `for ... in` |
| `"must_use"` | armed error dropped at scope end, or overwritten |
| `"oom"` | heap exhausted |
| `"stack_overflow"` | more than 4096 value stack slots or 256 nested calls |

Messages use the type names `num`, `str`, `bool`, `nil`, `arr`, `obj`, `fn` and `err`, as in "expected num, got str".

### Returning Values and Errors

A function returns a value the usual way: its last expression, or an explicit `ret`:

```
fn double(x) x * 2            // last expression

fn clamp_lo(x, lo)            // case expression directs the return value
  case
    x < lo -> lo
    _ -> x
  end
end

fn update(e)
  case not e.alive? -> ret    // explicit ret: guard that skips the rest
  e.x += e.vx
  e.y += e.vy
end
```

A function signals failure with `err`, which returns early with an error:

```
fn parse_pos(s)
  n : tonum(s)
  case
    not n? -> err "not a number"    // string is wrapped into an error
    n < 0  -> err error("negative", "range")
    _ -> n
  end
end
```

`err <expr>` accepts either a string (wrapped into an `error` of kind `"error"`) or an existing `error` value. Passing an existing error is how you **forward** a failure you received:

```
fn load(slot)
  v, e ?: read(slot)
  case e? -> err e    // forward read's error unchanged
  parse(v)
end
```

`ret` and `err` are statements, like `stop` and `next`. They may appear as `case` branch bodies (`cond -> err "nope"`). Bare `ret` returns `nil`.

### Consuming a Fallible Call

Four ways to consume a call that might fail, from most to least careful:

**1. Split with `?:`:** the workhorse. Declares two new locals: the value (or `nil` on failure) and the error (or `nil` on success).

```
v, e ?: parse_pos(input)
// v = the number, or nil if it failed
// e = the error,  or nil if it succeeded
case e? -> show(e.message)
draw_at(v)
```

Because the channels are separated, `v` is never secretly an error. It is always value-or-nil, so `v ?? 0` and `v?` mean exactly what they look like. Discard the error explicitly with `_`:

```
v, _ ?: parse_pos(input)    // I genuinely don't care if it failed
```

**2. Dispatch on kind:** after splitting, match `e?.kind` to branch on different failures. On success `e` is `nil`, so `e?.kind` short-circuits to `nil`; reading it also satisfies must-use:

```
v, e ?: load(slot)
case e?.kind
  nil     -> draw(v)    // success
  "io"    -> retry()
  "parse" -> use_default()
  _       -> err e      // unknown kind: forward it
end
```

**3. Plain bind:** `x : f()` binds the raw result. On success `x` is the value; on failure `x` *is* the error value. This arms must-use (below). Use it for forwarding, or when a function returns an error as ordinary data.

**4. Ignore:** a bare call statement drops the error. This is sanctioned; it is the one deliberate hole in must-use.

```
save(state)    // fire and forget
```

### Must-Use

An error must not be silently forgotten *after you have committed to handling it*. Only **variables** are ever armed. A variable is **armed** when an error is stored into it:

- by declaration: `x : f()`, `v, e ?: f()`, a destructured variable, or a loop variable (`for e in errors` arms `e` on each iteration)
- by assignment: `x = f()`

Parameters are never armed, and neither are array elements or object fields. An armed variable must be **handled before the end of its enclosing block's scope** (including a function return, `stop` or `next` leaving the scope), or the program panics with kind `"must_use"`.

Handling means any **read** of the variable:
- using it (`e.message`, passing it to a function, storing it in an array or object, copying it to another variable),
- **presence-testing** it (`e?`),
- **forwarding** it (`err e`).

So `x : e` handles `e` and arms `x`, and `log(e)` handles `e` without arming the parameter inside `log`. Discarding with `_` (`v, _ ?: f()`) never binds the error at all.

```
do
  v, e ?: risky()
  draw(v)
end    // PANIC: e was armed and never handled
```

```
do
  v, e ?: risky()
  case e? -> recover(e)    // handled
  draw(v)
end                        // ok
```

The deliberate hole: never *binding* the error in the first place (mode 4, the bare call) is fine. Must-use catches *forgetting after committing*, not *never committing*.

Armed top-level variables are checked once, when top-level code finishes and before the engine calls `init()`. The REPL skips this check, so `x : load("slot1")` can be inspected on the next line.

### Clobber

Assigning anything (another error, `nil`, `5`) to a variable that still holds an **armed, unhandled** error panics with kind `"must_use"` at that line, as you would be discarding the first error unnoticed:

```
v, e ?: first()
e = second()    // PANIC if e from first() was never handled
```

Handle the first error before reusing the variable. To discard one deliberately, read it first (`case e? -> ...`). Redeclaring `v, e ?:` in the same block is a compile error like any redeclaration, so clobbering only happens through assignment.

### `catch`

`catch` is the rare escape hatch that turns a **panic** back into a value, so you can recover from a bug at a boundary. It evaluates a block; if the block completes, `catch` yields its value; if the block panics, `catch` yields the error instead. The result is consumed like any other fallible call:

```
v, e ?: catch do
  risky_subsystem()
end
case e? -> log(e)
```

`catch` is the same machinery the engine applies around each `tick` and `draw`: an implicit outermost `catch` that drives the crash screen. Reach for an explicit `catch` only at real boundaries (a plugin, a subsystem, a frame); routine failure should use error values, not panics.

`catch do ... end` is a control-flow boundary: a `stop`, `next` or `ret` that would jump out of it is a parse error. Compute a value inside and act on it afterwards. The hang guard is not a panic and can't be caught.

## Strings

Strings are **1-indexed** sequences of bytes in the **Noka charset**: byte 10 is the newline, bytes 32 to 126 are ASCII, and the remaining values are the console font's icon glyphs (see CONSOLE.md). Every byte is one character and one glyph, so `len`, `s[i]`, `ord` and `char` work on bytes. Source files are UTF-8: the compiler converts each string literal's characters to charset bytes, and a character with no charset equivalent (an emoji, for example) is a compile error, "character not in the Noka charset".

```
s : "hello"
print(s[1])     // "h"
print(s[-1])    // "o" (negative indexing)
s[1] = "H"      // "Hello"
```

**Strings are values.** Each binding holds its own string: after `t : s` and `s[1] = "H"`, `t` is unchanged, and passing a string to a function never lets the callee change the caller's string. Arrays and objects are shared; strings are values.

Indexing returns a one-character string. Assigning to an index replaces that character, which behaves exactly like rebinding `s` to a changed copy, including through fields and indices (`player.name[1] = "N"` gives `player.name` a new string).

- The right-hand side must be exactly one character, so `s[1] = "HE"` and `s[1] = ""` panic. Use `sub` and `+` to splice.
- Positions follow the array rules: `s[len + 1] = c` appends, and `s[0]`, fractional indices and writes further out panic.
- A literal always evaluates to the same unchanging string, so `fn f() "abc" end` always returns `"abc"`.

A string declared with `#` is a constant binding, so its characters can't be assigned:

```
name # "noka"
name[1] = "N"    // PANIC (frozen)
```

## Arrays

Ordered, **1-indexed** collections.

### Creating Arrays

```
nums : [10, 20, 30]
empty : []
```

Arrays and objects are separate types and use different literal syntax (`[]` for arrays, `{}` for objects).

### Accessing Values

```
nums : [10, 20, 30]
print(nums[1])    // 10 (1-indexed)
print(nums[3])    // 30
```

Reading past either end returns `nil`. `nums[0]` panics ("arrays are 1-based, index 0 is invalid"), and so does a fractional index. Both panic with kind `"index"`.

### Negative Indexing

Negative indices count from the end of the array.

```
nums : [10, 20, 30]
print(nums[-1])    // 30 (last element)
print(nums[-2])    // 20
```

### Setting Values

```
items : []
items[1] = "sword"
push(items, "shield")
```

Writing at `len + 1` appends. Any write further out panics: `a[len + 2]`, `a[0]`, a fractional index, or a negative index past the start. Arrays never grow from an out-of-range write, so a mistyped index can't silently allocate.

### Length

```
items : [10, 20, 30]
print(len(items))    // 3
```

`nil` is an ordinary element, and arrays store their length, so `len([1, nil, 3])` is 3.

### Array Spread

The `*` operator spreads an array into a new array literal. Spreads may appear anywhere in the literal, any number of times:

```
a : [1, 2]
b : [*a, 3, 4]        // [1, 2, 3, 4]
c : [0, *a, *a, 5]    // [0, 1, 2, 1, 2, 5]
d : [0, *a]           // [0, 1, 2]
```

### Arrays Are Passed by Reference

```
fn addItem(inv, item)
  push(inv, item)
end

items : ["sword"]
addItem(items, "shield")
print(len(items))    // 2
```

Arrays and objects are shared by reference. Strings are not: they are values, so a function can never change a caller's string (see [Strings](#strings)).

## Objects

String-keyed maps.

### Creating Objects

```
// Explicit keys
point : {x: 1, y: 2}

// Shorthand (variable name becomes key)
name : "noka"
ver : 2
info : {name, ver}    // equivalent to {name: "noka", ver: 2}

// String-literal keys (for keys with spaces or punctuation)
config : {"max-hp": 100, "save path": "disc0"}
print(config["max-hp"])

// Empty object
empty : {}
```

Keys may be identifiers, keywords (`{next: 1}`), or string literals. Identifier and keyword keys become string keys of the same name. Shorthand (`{name}`) needs an identifier, not a keyword. Computed keys (`[expr]: value`) are not supported. A key given `nil` isn't stored: `{a: nil}` has no key `a`.

### Accessing Values

```
info : {name: "noka", ver: 2}
print(info.name)       // noka
print(info["name"])    // noka (equivalent)
```

Missing keys return `nil`. Wrong-type access panics:

- field access on a non-object (`5.x`, `nil.x`, `true.x`)
- named fields on an array (`arr.x`)
- non-string keys on an object (`obj[1]`)

### Setting Values

```
info : {}
info.name = "noka"
info["ver"] = 2
```

Assigning `nil` deletes the key: after `info.name = nil`, `"name" in info` is `false` and `len(info)` doesn't count it. This is the only way to remove a key.

### Object Spread

Create a new object from an existing one with overridden fields. The spread `*` must be first and only one is allowed per object literal. A spread by itself (no other fields) is legal and produces a shallow copy.

```
player : {name: "noka", hp: 100, mp: 50}
hurt : {*player, hp: 50}
// {name: "noka", hp: 50, mp: 50}

copy : {*player}    // shallow copy
```

## Destructuring

Destructuring unpacks arrays and objects into individual bindings. It is a statement, not an expression.

When `{` or `[` appears at statement position, the parser checks if `:`, `#`, or `=` follows the closing bracket. If so, the content is parsed as a destructuring pattern. Otherwise, it is an expression (array or object literal).

### Array Destructuring

```
pos : [10, 20]
[x, y] : pos

// With rest
nums : [1, 2, 3, 4, 5]
[first, *rest] : nums    // first = 1, rest = [2, 3, 4, 5]

// Discard with _
[_, y] : pos             // ignore first element
```

Extra values in the source are ignored. Too few values is a runtime error unless the missing elements have `??` defaults.

### Object Destructuring

```
info : {name: "noka", ver: 2, id: 5}
{name, ver} : info           // name = "noka", ver = 2 (id ignored)

// With rename
{name: playerName} : info    // playerName = "noka"

// With rest
{name, *rest} : info         // name = "noka", rest = {ver: 2, id: 5}
```

Variable names must match key names (unless renamed with `:`). Destructuring a missing key without a default is a runtime error.

### Defaults

Use `??` to provide default values for missing elements:

```
[a, b, c ?? 0] : [1, 2]              // c = 0
{name, age ?? 0} : {name: "noka"}    // age = 0
```

With a `??` default, missing values use the default instead of erroring.

### Rename Plus Default

Object patterns combine rename and default by placing `??` on the renamed binding:

```
{name: playerName ?? "anon"} : info
// playerName = info.name, or "anon" if missing
```

### Nested Patterns

Patterns nest, a destructuring slot can itself be a pattern:

```
data : {pos: [10, 20], stats: {hp: 100}}
{pos: [x, y], stats: {hp}} : data
// x = 10, y = 20, hp = 100

// With defaults on a nested pattern
{pos: [x, y] ?? [0, 0]} : data
```

### In Function Parameters

Patterns are also legal as function parameters:

```
fn distance({x: x1, y: y1}, {x: x2, y: y2})
  sqrt((x2 - x1)**2 + (y2 - y1)**2)
end

fn first([head, *tail])
  head
end
```

A pattern parameter destructures its argument on call. Defaults work:

```
fn box([x, y], opts: {w: 8, h: 8})
  rectf(x, y, opts.w, opts.h)
end
```

Note: labelled-argument syntax at the call site (`foo(x: 5)`) is not applied through a pattern parameter. A pattern parameter is a single positional slot. The argument passed in is destructured, not labelled.

### In `for ... in`

Patterns work as `for-in` loop variables:

```
pairs : [[1, "a"], [2, "b"]]
for [i, label] in pairs
  print(f"{i}: {label}")
end

people : [{name: "noka", hp: 100}, {name: "zed", hp: 50}]
for {name, hp} in people
  print(f"{name} has {hp}")
end
```

### Destructuring with All Binding Operators

```
[x, y] : pos          // declare mutable
[x, y] # pos          // declare constant
[x, y] = pos          // assign to existing

{name, ver} : info    // declare mutable
{name, ver} # info    // declare constant
```


## Built-in Functions

All built-ins are flat globals, highlighted in azure in the editor. They are constant globals declared before the program starts, so the ordinary scope rules apply:

- Redeclaring one at top level is an error: "`len` is a built-in".
- Assigning to one is an error: "cannot assign to built-in `len`".
- Shadowing one inside a function or block is allowed.

Names like `map`, `time` and `color` are therefore unavailable as top-level variables. Built-ins don't count toward a program's 1024 top-level names. Built-ins accept labelled arguments using the parameter names shown below (`rectf(x, y, h: 16)`).

### Core

| Function       | Description                                      |
|---------------|--------------------------------------------------|
| `print(v)`    | Write a value as a line to the console terminal (the shell's transcript). Never draws on the screen; use `text` for that. |
| `type(v)`     | Returns type as string: `"num"`, `"str"`, `"bool"`, `"nil"`, `"arr"`, `"obj"`, `"fn"`, `"err"` |
| `tostr(v)`    | Converts any value to string (see String Representations) |
| `tonum(v)`    | Converts a string to a number using the number-literal grammar (decimal, `0x`, `0b`) with an optional leading `-`, ignoring surrounding whitespace: `tonum("0xFF")` is `255`. Exponents (`"1e3"`) and `""` give `nil`. A number passes through; any other type gives `nil`. |
| `len(v)`      | Length of string (bytes), array, or object (key count) |
| `error(msg, kind, data)` | Construct an `error` (`kind` defaults to `"error"`, `data` optional) |

### Math

| Function          | Description                              |
|------------------|------------------------------------------|
| `floor(n)`       | Round down to integer                    |
| `ceil(n)`        | Round up to integer                      |
| `round(n)`       | Round to nearest integer                 |
| `abs(n)`         | Absolute value                           |
| `sign(n)`        | Returns -1, 0, or 1                     |
| `max(a, b)`      | Larger of two numbers                    |
| `min(a, b)`      | Smaller of two numbers                   |
| `clamp(v, lo, hi)` | Constrain value to range               |
| `lerp(a, b, t)`  | Linear interpolation                     |
| `sqrt(n)`        | Square root                              |
| `rnd(n)`         | Random integer from 1 to `n`, so `rnd(6)` is a die roll |
| `rnd(lo, hi)`    | Random integer from `lo` to `hi` (inclusive) |
| `rnd()`          | Random float in [0, 1)                   |
| `seed(n)`        | Fix the random sequence (same seed, same sequence) |
| `sin(n)`         | Sine (radians)                           |
| `cos(n)`         | Cosine (radians)                         |
| `tan(n)`         | Tangent (radians)                        |
| `asin(n)`        | Inverse sine                             |
| `acos(n)`        | Inverse cosine                           |
| `atan2(y, x)`    | Angle from origin to point               |

Each program has its own deterministic random generator, seeded randomly when the program starts. Non-integer bounds, or `lo > hi`, panic with kind `"math"`.

### String

| Function            | Description                                        |
|--------------------|----------------------------------------------------|
| `sub(v, i, j)`     | Substring or subarray from `i` to `j` (1-indexed, inclusive). `j` is optional and defaults to the end. Negative indices count from the end. Out-of-range bounds clamp (`sub("abc", 2, 99)` is `"bc"`), and `i > j` after clamping gives an empty result. A bound of 0 or a fractional bound panics with `"index"`. |
| `upper(s)`         | Uppercase (ASCII letters only)                     |
| `lower(s)`         | Lowercase (ASCII letters only)                     |
| `find(v, pat)`     | Find first occurrence in string or array, returns index (1-based) or nil |
| `split(s, sep)`    | Split string into array                            |
| `trim(s)`          | Remove leading/trailing whitespace                 |
| `replace(s, old, new)` | Replace all occurrences of old with new        |
| `char(n)`          | Character for code `n` (0 to 255; outside panics with `"index"`) |
| `ord(s)`           | Code of the first character (`ord("A")` is 65)     |

Character codes are encoding values in the Noka charset (ASCII for 32 to 126), not names, so they start at 0.

### Array

| Function              | Description                                  |
|-----------------------|----------------------------------------------|
| `push(arr, v)`        | Append value, returns `arr`                  |
| `pop(arr)`            | Remove and return last value                 |
| `shift(arr)`          | Remove and return first value                |
| `insert(arr, i, v)`   | Insert value at index, returns `arr`         |
| `remove(arr, i)`      | Remove value at index, returns `arr`         |
| `sort(arr, cmp)`      | Return a **new** stably sorted array. Without `cmp`, numbers sort ascending and strings bytewise (uppercase first); a mix of types or any other type panics with `"type"`. `cmp(a, b)` returns `true` when `a` goes before `b`. |
| `reverse(arr)`        | Return **new** reversed array                |
| `each(arr, fn)`       | Return new array of `fn(v, i)` for each element |
| `filter(arr, fn)`     | Return new array of the elements where `fn(v, i)` is true |
| `pick(arr)`           | Return a random element, or `nil` for an empty array |
| `keys(obj)`           | Return array of object keys                  |
| `vals(obj)`           | Return array of object values                |
| `concat(arr, sep)`    | Join elements into a string, passing each through `tostr`. `sep` defaults to `""`: `concat([1, true, "a"], ",")` is `"1,true,a"`. |

`each` and `filter` always pass `(v, i)`; a callback that declares only `v` ignores `i`. For case-insensitive sorting, compare lowercased strings:

```
sort(names, fn(a, b) lower(a) < lower(b))
```

### System

| Name              | Description                              |
|------------------|------------------------------------------|
| `exit()`         | Exit current program                     |
| `get_arg(n)`     | Get launch argument by index (1-based)   |
| `mem()`          | Bytes in use in the program's 131072-byte heap |
| `time()`         | Seconds since the program started, counted in frames (0 during top-level code and `init`, +1/60 per `tick`). Never reads the device clock. |
| `cpu()`          | Last frame's `tick` + `draw` time as a fraction of 1/60 s (above 1 means frames are dropping into slow motion). Wall-clock time, so it varies by device and run: **for display only**, since using it in game logic breaks replays. |
| `dt`             | Constant: 1/60, the seconds per `tick`   |

### Display

Display functions draw into the program's 192×224 screen.

| Function                      | Description                        |
|------------------------------|------------------------------------|
| `cls(c)`                      | Clear screen                       |
| `color(c)`                    | Set the current draw color         |
| `text(s, x, y, c)`            | Draw a string with the console font. `\n` moves down 8 px to the starting `x`. Returns the `x` after the last character. |
| `rect(x, y, w, h, c)`         | Draw rectangle outline             |
| `rectf(x, y, w, h, c)`        | Draw filled rectangle              |
| `circ(x, y, r, c)`            | Draw circle outline                |
| `circf(x, y, r, c)`           | Draw filled circle                 |
| `line(x1, y1, x2, y2, c)`     | Draw line                          |
| `pset(x, y, c)`               | Set pixel                          |
| `pget(x, y)`                  | Get pixel color, or `nil` off-screen |
| `spr(n, x, y, w: 1, h: 1, fx: false, fy: false)` | Draw sprite `n` (1 to 256). `w` and `h` are in sprites; `fx`/`fy` flip. |
| `map(cx: 1, cy: 1, x: 0, y: 0, w: 24, h: 28)` | Draw `w`×`h` tilemap cells starting at map cell (`cx`, `cy`), with the top-left at pixel (`x`, `y`). Empty tiles are skipped. |
| `mget(cx, cy)`                | Sprite number at a map cell, or `nil` for an empty tile or a cell off the 128×64 map |
| `mset(cx, cy, n)`             | Set a map cell's sprite; `nil` clears it. Off the map panics with `"index"`. |
| `sget(x, y)`                  | Color of a sprite-sheet pixel (128×128), or `nil` off the sheet |
| `sset(x, y, c)`               | Set a sprite-sheet pixel (off the sheet is ignored) |
| `pal(c, rgb)`                 | Set color `c` to `0xRRGGBB`, snapped to the 15-bit ladder. `pal(c)` resets one color to DHARM32 and `pal()` resets all. |
| `palt(c, on)`                 | Set or clear color `c`'s transparent bit |
| `gget(code, x, y)`            | Whether a font glyph pixel is on (`code` 0 to 255, `x` and `y` 0 to 7) |
| `gset(code, x, y, on)`        | Set a font glyph pixel; letters and digits can be redrawn like any glyph |
| `camera(x, y)`                | Offset all draw calls; `camera()` resets it |
| `clip(x, y, w, h)`            | Set the clipping rectangle; `clip()` resets it to the full screen |

Display rules:

- **Numbering:** numbers that name a thing start at 1 (colors 1 to 32, sprites 1 to 256, map cells), while pixel coordinates start at 0: `pset(0, 0)` is the top-left pixel, and the screen spans x 0 to 191 and y 0 to 223.
- **Colors:** the trailing `c` is optional and defaults to the current draw color without changing it. A color is floored; a non-number panics with `"type"`, and anything outside 1 to 32 panics with `"index"`. A program starts with draw color 7 (cyan), and color 1 is transparent by default.
- **Coordinates:** every coordinate and size argument is floored, and `camera` values are floored when set.
- **Clipping:** drawing outside the screen or the clip rectangle is clipped silently. A rectangle with `w` or `h` of 0 or less, or a circle with `r` below 0, draws nothing.
- **Transparency:** `spr` and `map` skip pixels whose color has the transparent bit set (see `palt`).
- **Palette:** a `pal` change recolors the whole screen, including pixels drawn earlier in the frame, because the screen stores color numbers.

### Input

| Function         | Description                              |
|-----------------|------------------------------------------|
| `key(k)`        | Is button `k` currently held?            |
| `keyp(k)`       | Was button `k` pressed this frame? (first frame only, no repeat) |
| `typed()`       | Next entry from the text keyboard, or `nil` |
| `keyboard(mode)` | Show the gamepad (`"pad"`) or the text keyboard (`"text"`) |
| `touch()`       | `{x, y}` in screen pixels while a finger is on the screen, otherwise `nil` |
| `touchp()`      | Like `touch()`, but only on the first frame of a touch |

Buttons are `"up"`, `"down"`, `"left"`, `"right"`, `"a"`, `"b"`, `"x"`, `"y"`, and `"start"`. Any other name panics with kind `"args"`, so a typo can't silently read `false`. The console's menu button suspends the running disc and can't be read by discs.

`typed()` returns characters as one-character strings in the Noka charset, and editing keys as names: `"backspace"`, `"enter"`, `"tab"`, `"left"`, `"right"`, `"up"`, `"down"`, `"select"`, `"copy"`, `"cut"`, `"paste"`. Discs start with the gamepad showing.

## Runtime Behavior

### Variable Scoping

Variables use lexical scoping with a scope chain. Each function call creates a new scope. Declaration (`:` / `#`) creates in the current scope. Assignment (`=`) walks the chain; error if no binding found.

```
x : 10
fn f()
  x : 20      // shadows outer x
  print(x)    // 20
end
f()
print(x)      // 10 (unchanged)
```

### Function Hoisting

Named function declarations (`fn name() ... end`) are hoisted, collected before execution so they can be called before their source position. Hoisting is **block-scoped**: a named function is visible only within the block that contains its declaration, not in enclosing blocks.

```
greet("noka")    // works, greet is hoisted to top of this scope

fn greet(name)
  print(f"hello {name}")
end
```

A function declared inside a `do`, `while`, `for`, `case` branch, or function body is scoped to that block:

```
do
  fn helper(x) x * 2 end
  helper(5)    // works: scoped to this block
end
helper(1)      // RUNTIME ERROR: not visible out here
```

Functions declared inside a loop body are re-declared on every iteration, producing fresh closures each time:

```
for i : 1, 3
  fn f() i end
  push(results, f)    // each f captures its iteration's i
end
```

Only named declarations are hoisted; `:` / `#` bindings holding anonymous functions are not. Functions return the value of their last expression. An empty body returns `nil`.

### String Representations

`print()` and `tostr()` produce display-friendly output:

| Value                  | Output              |
|------------------------|---------------------|
| `42`                   | `42`                |
| `0.1 + 0.2`            | `0.3`               |
| `1e21`                 | `1e+21`             |
| `-0`                   | `0`                 |
| `"hello"`              | `hello`             |
| `true`                 | `true`              |
| `nil`                  | `nil`               |
| `[1, 2, 3]`           | `[1, 2, 3]`         |
| `{name: "noka"}`      | `{name: "noka"}`    |
| `{"max-hp": 100}`     | `{"max-hp": 100}`   |
| `fn greet() ... end`  | `<fn greet>`        |
| `fn() ... end`        | `<fn>`              |
| `error("eof", "io")`  | `<error io: eof>`   |

- **Numbers:** whole numbers below 2^53 print as plain digits. Anything else prints with up to 14 significant digits, switching to exponent form when needed (Lua's `%.14g`). `nan`, `inf` and `-inf` print as written. `tonum(tostr(x))` may differ from `x` in the last bits.
- **Strings** print unquoted at the top level. Inside arrays and objects they are double-quoted, with `"`, `\` and newlines escaped as in literals.
- **Object keys** print bare when they could be written bare in source (identifiers and keywords) and quoted otherwise. Separators are `, ` and `: `, so the output is valid literal syntax.
- **Functions** print `<fn name>` when named and `<fn>` when anonymous, bound methods the same way. **Errors** print `<error kind: message>`.
- A value that contains itself prints the inner occurrence as `[...]` or `{...}`.

### REPL

The shell's REPL keeps its top-level names from line to line, and a top-level redeclaration stays an error, as in any program. `reset` clears them. The REPL also resets automatically when it runs out of heap or out of top-level names, and the shell says so. A line that panics leaves the REPL alive and keeps everything earlier lines defined. The top-level must-use check doesn't run in the REPL.

While a disc is suspended (menu button), REPL lines run inside the disc, so `print(player.hp)` and `player.hp = 99` act on its live state. Nothing typed there changes the disc's source, and stopping the disc discards it all.

### Error Reporting

Errors include a 1-based line number in the format `[line N] message`.

Scan and parse errors are reported before the program runs:
- **ScanError:** invalid character or unterminated string
- **ParseError:** unexpected token, missing `end`, etc.
- **BindingError:** redeclaring or reassigning a local constant

At runtime there are two distinct failure channels (see
[Error Handling](#error-handling)):
- **Panic:** unrecoverable bugs (type errors, undefined variables, division by zero, must-use violations). A panic unwinds to the nearest `catch`; if none, the engine stops the program and the crash screen shows it, with the real runtime type.
- **error values:** recoverable failures, threaded explicitly through `ret` / `err` and the `?:` split.

## Syntax Highlighting

The in-console editor colors source with DHARM32 colors (numbers as in CONSOLE.md), the same theme as the tour's dark mode:

| Token Category | Color |
|----------------|-------|
| Background     | 11 spruce |
| Keyword        | 28 coral |
| Atom (`true`, `false`, `nil`) | 17 amber |
| Number         | 14 grass |
| String         | 16 lemon |
| Comment        | 3 slate |
| Operator       | 7 cyan |
| Built-in       | 8 azure |
| Identifier     | 5 ice |

## Example Programs

### Hello World
```
print("hello world")
```

### FizzBuzz
```
for i : 1, 30
  print(case
    i % 15 == 0 -> "fizzbuzz"
    i % 3 == 0 -> "fizz"
    i % 5 == 0 -> "buzz"
    _ -> tostr(i)
  end)
end
```

### Fibonacci (Recursive)
```
fn fib(n)
  case
    n <= 1 -> n
    _ -> fib(n - 1) + fib(n - 2)
  end
end

for i : 1, 11
  print(fib(i))
end
```

### Closures
```
fn makeCounter()
  count : 0
  fn inc()
    count += 1
    count
  end
  inc
end

c : makeCounter()
print(c())    // 1
print(c())    // 2
print(c())    // 3
```

### Game Loop
```
x : 0
y : 0
speed # 60    // pixels per second

fn init()
  x = 100
  y = 100
end

fn tick()
  case key("left") -> x -= speed * dt
  case key("right") -> x += speed * dt
end

fn draw()
  cls()
  rectf(x, y, 8, 8)
end
```

### Destructuring
```
fn getPlayer()
  {
    name: "noka",
    hp: 100,
    pos: [10, 20]
  }
end

{name, hp, pos} : getPlayer()
[x, y] : pos
print(f"{name} at {x}, {y}")
```

### Pipes
```
result : "  HELLO WORLD  "
  |> trim()
  |> sub(1, 5)
  |> upper()

items : [3, 1, 4, 1, 5]
  |> sort()
  |> filter(fn(x) x > 2)
  |> concat(", ")
```

### Methods and `this`
```
fn newPlayer(name, hp)
  {
    name: name,
    hp: hp,
    heal: fn()
      this.hp += 10
    end,
    info: fn()
      f"{this.name}: {this.hp}hp"
    end
  }
end

p : newPlayer("noka", 100)
p.heal()
print(p.info())    // noka: 110hp

show : p.info      // auto-bound
print(show())      // noka: 110hp
```

### Function Captures
```
nums : [1, 2, 3, 4, 5]

// Without captures
doubled : each(nums, fn(x) x * 2)
positive : filter(nums, fn(x) x > 0)

// With captures
doubled : each(nums, mul(2, _))
positive : filter(nums, greater(_, 0))

// Capture in sort
sorted : sort(items, less(_, _))
```

### Labelled Arguments
```
fn box(x, y, w: 8, h: 8)
  rectf(x, y, w, h)
end

box(10, 20)              // defaults
box(10, 20, w: 16)       // override w
box(10, 20, h: 16)       // override h
box(10, , w: 4, h: 4)    // skip y
```

### Loop Return Values
```
// Find first match
fn index_of(arr, val)
  for i, v in arr
    case v == val -> stop i
  end
end

idx : index_of([10, 20, 30], 20)
print(idx)    // 2
```

### Membership
```
inv : ["sword", "shield", "potion"]

case "sword" in inv -> print("armed!")

case "bow" not in inv -> print("need range")

info : {name: "noka", role: "knight"}
case "role" in info -> print(info.role)
```

### Error Handling
```
fn parse_score(s)
  n : tonum(s)
  case
    not n? -> err "not a number"
    n < 0  -> err error("negative score", "range", {got: n})
    _ -> n
  end
end

// split with ?: and handle the error before block end
score, e ?: parse_score(get_arg(1))
case e? -> print(f"bad score: {e.message}")
print(f"score: {score ?? 0}")

// or dispatch on the error kind
v, e ?: parse_score("42")
case e?.kind
  nil     -> print(f"ok: {v}")
  "range" -> print("out of range")
  _       -> print(e.message)
end

// recover from a panic at a boundary
_, crash ?: catch do
  risky_subsystem()
end
case crash? -> print(f"subsystem down: {crash.kind}")
```
