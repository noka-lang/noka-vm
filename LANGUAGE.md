# NokaScript Language Reference

Complete specification of the NokaScript language.
Designed for a 25-column (but still allowing lines to extend beyond) fantasy console with mobile-first input.

## Design Principles

- **Expression-oriented** -- loops, `case`, `func`, `do` blocks, and
  assignments all produce values. A small set of constructs (declarations,
  destructuring, `stop`, `next`) are statements for scoping / control-flow
  reasons — see [Grammar](#grammar).
- **Newline-delimited** -- no semicolons, no statement terminators
- **Keyword-closed blocks** -- `end` closes all blocks
- **No implicit truthiness** -- no type coercion to boolean; `and`/`or`/`not` require booleans
- **Minimal special characters** -- keywords are plain alpha, reducing keyboard-layer switches
- **Flat built-in namespace** -- standard library functions are globals, no prefixes
- **Terse by default** -- every token earns its place on a 25-column screen


## Values and Types

There are seven value types:

| Type       | Examples                     | Notes                                |
|------------|------------------------------|--------------------------------------|
| `number`   | `42`, `3.14`, `0xFF`, `0b101`| IEEE 754 double (JS `number`)        |
| `string`   | `"hello"`, `'world'`        | Single or double quoted              |
| `boolean`  | `true`, `false`              |                                      |
| `nil`      | `nil`                        | Represents absence of a value        |
| `array`    | `[1, 2, 3]`                 | Ordered, 1-indexed                   |
| `object`   | `{name: "noka", ver: 2}`    | String-keyed map                     |
| `function` | `func f() end`              | User-defined or native built-in      |

There is no implicit type coercion. Arithmetic operators require numbers.
The `+` operator doubles as string concatenation when both operands are strings.
Mixed-type `+` (e.g., `"score: " + 10`) is a runtime error; use `f""` or `tostr()`.

### Equality

`==` uses **deep equality** for numbers, strings, booleans, nil, arrays, and objects.
Two arrays or objects with the same contents are equal. Functions use **reference
equality** -- two functions are equal only if they are the same reference.

```
[1, 2] == [1, 2]         // true (deep)
{a: 1} == {a: 1}         // true (deep)
f : func() 1
g : func() 1
f == g                    // false (different references)
f == f                    // true
```

### Nil Checking

The `?` postfix operator returns `true` if a value is not `nil`, `false` otherwise.

```
x?              // true if x is not nil
items[5]?       // true if index exists
info.name?      // true if key exists
```

The `??` operator returns the left side if not `nil`, otherwise the right side.

```
name : get_name() ?? "default"
```

### Optional Chaining

`?.`, `?[`, and `?(` are optional-chain access operators. If the value
on the left is `nil`, the whole chain short-circuits to `nil` without
evaluating the rest. If the value is non-nil, the access proceeds
normally.

```
user?.address?.city     // nil if user or address is nil
items?[1]                // nil if items is nil
handler?(event)          // nil if handler is nil
```

A chain mixes regular and optional access freely. Once a `?.` / `?[` /
`?(` short-circuits, everything further right is skipped:

```
user?.profile.name       // if user is nil -> nil
                         // if user exists but profile is nil -> runtime error on .name
                         // if both exist -> name
```

Use optional chaining when the intermediate step is legitimately
optional. Use regular access when you expect the field to exist; you
will get a clearer error if it is missing.

Long chains can wrap across lines: a line starting with `.`, `?.`,
`?[`, or `?(` continues the previous line. See
[Line Continuation](#line-continuation).

```
user
  ?.address
  ?.city
```


## Lexical Structure

### Identifiers

Start with a letter (`a`-`z`, `A`-`Z`) or underscore (`_`), followed by zero or
more letters, digits, or underscores. The identifier `_` is reserved as the
universal discard/wildcard/capture symbol (see Pipes, Captures, Destructuring, Case).

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
stop    next    func    do      this
and     or      not     band    bor
bnot    bxor    init    tick    draw
true    false   nil     if
```

`if` is reserved solely for use as a guard in `case` branches
(`pat if cond -> body`); it has no standalone statement form.

### Number Literals

Integers, decimals, hexadecimal, and binary.

```
42
3.14
0xFF
0b1010
```

### String Literals

Delimited by double quotes (`"`) or single quotes (`'`).
Both behave identically. Must be on a single line unless prefixed with `m`.

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

Any expression is allowed inside `{}` in f-strings. The parser tracks brace
depth, so strings and nested braces inside interpolations work correctly:

```
f"status: {case hp > 50 -> "ok"}"
f"pos: {{x: 10, y: 20}.x}"
```

Interpolation is a suppressed-newline context, but a multi-line `case`,
`do`, etc. opened inside it re-enables newlines within its own body —
so multi-line forms can appear inside interpolation when needed.

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

A comment starting with `///` provides optional type hints for the
following function. These are **editor-only** soft warnings, not runtime
enforcement. They help catch type mismatches before running.

Hints come in two forms. The **single-line** form lists the parameter
types in order, with the return type prefixed by `->`. Names are
**optional** here — write bare types (`num, num`) for a clean layout,
or name them (`x: num, y: num`) when it aids clarity. The
**multi-line** form splits across consecutive `///` lines, one entry
per line, and names are **mandatory** (`name: type`) so each line is
self-describing; the return type goes on its own line, prefixed with
`->`:

```
// Single line: bare positional types
/// num, num -> num
func add(x, y)
  x + y
end

// Single line: names are optional
/// x: num, y: num -> num
func add(x, y)
  x + y
end

// Multi-line: one named entry per /// line, return on its own line
/// x: num
/// y: num
/// -> num
func add(x, y)
  x + y
end

/// num|str -> str
func tostr(v)
  ...
end

/// num, num, num? -> nil
func draw(x, y, color)
  ...
end

/// num, *num -> num
func sum(first, *rest)
  ...
end
```

Short type names: `num`, `str`, `bool`, `nil`, `arr`, `obj`, `fn`.
Unions: `num|str`. Optional/nullable: `num?` (shorthand for `num|nil`).
Variadic: `*num`, or `*rest: num` when named. Omit the `->` entry to
leave the return type unspecified.

A multi-line hint must be a run of consecutive `///` lines immediately
above the function — a plain `//` line or a blank line ends the block.
In the multi-line form, every entry must be named and the names should
match the function's parameters; an unnamed or mismatched entry is an
editor warning.

Type hints apply to named and anonymous functions only.

### Block Expressions

`do ... end` creates a block expression. Inside a block:
- Newlines are statement separators
- Multiple statements execute sequentially
- The last expression is the return value
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

A `do ... end` block is a first-class expression: it can appear anywhere
an expression is expected (right-hand side of a binding, inside a call
argument, as a `case` branch body, etc.).

Parentheses `()` are for grouping and function calls. Newlines are
suppressed inside `()`, `[]`, and `{}`.

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

Expressions are separated by newlines. Newline significance follows a
stack rule: newlines are suppressed inside bracketed contexts (`(`, `[`,
`{`) and re-enabled inside block constructs opened within them (`do`,
multi-line `func`, multi-line `case`, etc.). See
[Newline Significance (Stack Rule)](#newline-significance-stack-rule)
for the full table and rules.

### Trailing Commas

Trailing commas are allowed in arrays, objects, function calls,
and function parameters.

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

Three-character:

| Token | Meaning              |
|-------|----------------------|
| `**=` | compound exponent    |
| `<<=` | compound left shift  |
| `>>=` | compound right shift |


## Bindings

NokaScript has two declaration operators and one assignment operator:

| Syntax   | Meaning                                     |
|----------|---------------------------------------------|
| `x : 5`  | declare new mutable local                  |
| `x # 5`  | declare new constant local (deep freeze)   |
| `x = 5`  | assign to existing binding (error if none) |

Declarations (`:` and `#`) are **statements** — they introduce a new
name into the enclosing scope and do not produce a value. Destructuring
forms (`[x, y] : expr`, `{a, b} # expr`) are also statements.

Assignment (`=`), compound assignment (`+=`, `-=`, ...), and `++` /
`--` are **expressions**. They mutate an existing binding and produce
the new value, so they can appear anywhere an expression can.

Every variable must be explicitly declared with `:` or `#` before use.
Assignment (`=`) walks the scope chain looking for an existing binding.
If none is found, it is a **runtime error**.

Re-declaring a variable in the **same scope** is a runtime error.
Shadowing a variable from an **outer scope** is allowed.

Constants (`#`) can never be reassigned. The value is **deep-frozen** --
arrays, objects, and strings declared with `#` cannot be mutated. Attempting to
reassign, push to, set fields on, or index-assign a frozen value is a runtime error.

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
func foo()
  x = 20          // mutates outer x
end

x : 10
func foo()
  x : 5           // new local x, shadows outer (allowed)
end
```


## Grammar

NokaScript is mostly expression-oriented: loops, `case`, `func`, `do`
blocks, and assignments all produce values. A small set of constructs
are **statements** rather than expressions, because they carry scoping
or control-flow effects that would be surprising as subexpressions:

- `x : expr` and `x # expr` (declarations introduce a name into scope)
- Destructuring bindings
- `stop [expr]` and `next` (loop control)
- Lifecycle blocks `init` / `tick` / `draw` (top-level only)

Assignment (`=`), compound assignment, and `++` / `--` stay as
expressions — they mutate an existing binding and produce the new value,
without introducing names.

### Program Structure

```
program         = { NEWLINE } { top_item NEWLINE } EOF
top_item        = statement | lifecycle_block
block           = { NEWLINE } { statement NEWLINE }

statement       = binding
                | func_decl
                | destructuring
                | stop_stmt
                | next_stmt
                | expression
```

Lifecycle blocks are only legal at program top level. At most one each
of `init`, `tick`, `draw` per program; duplicates are a parse error.

### Statements

```
binding         = IDENTIFIER ":" expression
                | IDENTIFIER "#" expression

func_decl       = "func" IDENTIFIER "(" [ params ] ")" expression
                | "func" IDENTIFIER "(" [ params ] ")" NEWLINE block "end"

destructuring   = pattern ( ":" | "#" | "=" ) expression

stop_stmt       = "stop" [ expression ]
next_stmt       = "next"
```

A `func_decl` is a named function declaration at statement position. It
binds the name into the enclosing scope as a mutable local (equivalent
to `name : func(...) ... end`) and is **hoisted** within its block.
Anonymous and named-but-not-statement-position functions use `func_expr`
in the expression grammar instead.

`stop_stmt` and `next_stmt` are parse errors unless they appear inside
the body of an enclosing loop (`while` or `for`) within the same
function. Function boundaries block the check: a `stop` inside a
helper function called from a loop does not stop that loop.

`stop_stmt` and `next_stmt` are also legal as the body of a case
branch (`-> stop i`, `-> next`), subject to the same enclosing-loop
rule.

### Patterns (Destructuring)

```
pattern         = array_pattern | object_pattern

array_pattern   = "[" [ pat_elem { "," pat_elem } [ "," ] ] "]"
pat_elem        = IDENTIFIER [ "??" expression ]
                | "_"
                | "*" IDENTIFIER
                | pattern [ "??" expression ]

object_pattern  = "{" [ obj_pat { "," obj_pat } [ "," ] ] "}"
obj_pat         = IDENTIFIER [ ":" ( IDENTIFIER | pattern ) ] [ "??" expression ]
                | "*" IDENTIFIER
```

Patterns nest freely. The same pattern syntax is reused in function
parameters (`func foo({x, y})`) and for-in loops (`for {name} in people`).

A `*rest` element collects whatever slots are not bound by the other
elements. It may appear in any position within an `array_pattern`,
`object_pattern`, or `params` list — at most one per pattern. Elements
before `*rest` bind positionally from the start; elements after it
bind positionally from the end (for arrays) or by name (for objects).

### Expression Grammar (Precedence: lowest to highest)

```
expression      = assignment | pipe
assignment      = assignable ( "=" | compound_op ) expression
                | assignable ( "++" | "--" )

compound_op     = "+=" | "-=" | "*=" | "/=" | "%="
                | "**=" | "<<=" | ">>="

assignable      = IDENTIFIER
                | "this"
                | assignable "." IDENTIFIER
                | assignable "[" expression "]"

pipe            = logic_or { "|>" logic_or }
logic_or        = logic_and { "or" logic_and }
logic_and       = nil_coalesce { "and" nil_coalesce }
nil_coalesce    = bit_or { "??" bit_or }
bit_or          = bit_xor { "bor" bit_xor }
bit_xor         = bit_and { "bxor" bit_and }
bit_and         = equality { "band" equality }
equality        = comparison { ( "==" | "!=" ) comparison }
comparison      = shift { ( "<" | ">" | "<=" | ">=" | "in" | "not" "in" ) shift }
shift           = addition { ( "<<" | ">>" ) addition }
addition        = multiplication { ( "+" | "-" ) multiplication }
multiplication  = exponent { ( "*" | "/" | "%" ) exponent }
exponent        = unary { "**" unary }
unary           = ( "not" | "-" | "bnot" ) unary | postfix
postfix         = chain [ "?" ]
chain           = primary { chain_op }
chain_op        = "." IDENTIFIER          // field access
                | "[" expression "]"      // index access
                | "(" args ")"            // call
                | "?." IDENTIFIER         // optional field
                | "?[" expression "]"     // optional index
                | "?(" args ")"           // optional call
args            = [ arg { "," arg } [ "," ] ]
arg             = expression | IDENTIFIER ":" expression | <empty>
primary         = NUMBER | STRING | "true" | "false" | "nil" | "_"
                | "this" | IDENTIFIER | "(" expression ")"
                | block_expr | array_literal
                | object_literal | func_expr | case_expr
                | while_expr | for_expr
```

The trailing `?` on `postfix` is the boolean nil-check. The `?.`/`?[`/`?(`
chain operators are optional-chain accesses: if the LHS is nil, the whole
chain short-circuits to nil.

The pipe (`|>`) is parsed uniformly as `logic_or |> logic_or`. Its
**semantics** depend on the shape of the parsed RHS node: if the RHS is
syntactically a call (its top-level form is a `chain` ending in `(...)`
or `?(...)`), the piped value is inserted into that call's argument
list (filling every `_` if any are present, otherwise prepended as the
first argument). For any other RHS, the RHS is evaluated and the
resulting value must be callable; the piped value is then applied to it.

### Compound Expressions

```
block_expr      = "do" NEWLINE block "end"
                | "do" "end"

while_expr      = "while" expression NEWLINE block "end"
for_expr        = for_num | for_in
for_num         = "for" IDENTIFIER ":" expression "," expression
                  [ "," expression ] NEWLINE block "end"
for_in          = "for" for_var { "," for_var } "in" expression NEWLINE
                  block "end"
for_var         = IDENTIFIER | "_" | pattern

func_expr       = "func" [ IDENTIFIER ] "(" [ params ] ")" expression
                | "func" [ IDENTIFIER ] "(" [ params ] ")" NEWLINE block "end"
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
branch_body     = expression | stop_stmt | next_stmt

// Host convention, not core language syntax. The NokaOS runtime
// recognizes `init` / `tick` / `draw` at top level and drives them from
// the game loop. Other hosts may define a different set.
lifecycle_block = ( "init" | "tick" | "draw" ) "(" [ params ] ")" NEWLINE
                  block "end"

array_literal   = "[" [ arr_elem { "," arr_elem } [ "," ] ] "]"
arr_elem        = expression | "*" expression

object_literal  = "{" [ object_body ] "}"
object_body     = obj_spread
                | obj_spread "," obj_field { "," obj_field } [ "," ]
                | obj_field { "," obj_field } [ "," ]
obj_spread      = "*" expression
obj_field       = IDENTIFIER ":" expression
                | STRING ":" expression
                | IDENTIFIER                    // shorthand
```

Objects allow at most one spread, which must appear first. The `_`
catch-all in `case_expr` must be the last branch; mid-position `_`
is a parse error.

### Expression Return Values

Every expression produces a value:

| Expression           | Returns                                          |
|----------------------|--------------------------------------------------|
| `x = 5`             | the assigned value (`5`)                         |
| `x++` / `x--`       | the value after increment/decrement              |
| `x += 1`            | the assigned value                               |
| `while ... end`      | last completed iteration's value, or `nil`       |
| `for ... end`        | last completed iteration's value, or `nil`       |
| `case ... end`       | matched branch's value, or `nil` if no match     |
| `func ... end`       | the function value                               |
| `do ... end`         | last expression in the block, or `nil` if empty  |

Statements (`:`, `#`, destructuring, `stop`, `next`) don't appear as
values — they execute for their effects. `stop <expr>` causes the
enclosing loop to return `<expr>`; bare `stop` causes it to return `nil`.

### Notes

Single-line `case` is always a bare condition (no match expression).
Match expressions always use multi-line form with `end`.

Functions return the value of their last expression. There is no
`ret` keyword. Use `case` to structure conditional returns, and
`stop <expr>` for early exit from loops.

### Lexical Grammar

```
token           = literal | identifier | keyword | operator | delimiter
                | COMMENT | NEWLINE

literal         = NUMBER | STRING

NUMBER          = decimal | hex | binary
decimal         = DIGIT { DIGIT } [ "." DIGIT { DIGIT } ]
hex             = "0" ( "x" | "X" ) HEX_DIGIT { HEX_DIGIT }
binary          = "0" ( "b" | "B" ) BIN_DIGIT { BIN_DIGIT }

STRING          = [ string_prefix ] ( '"' { string_char } '"' )
                | [ string_prefix ] ( "'" { string_char } "'" )
string_prefix   = "f" | "m" | "fm" | "mf"
string_char     = ESCAPE | INTERP | <any char except quote, or newline unless m-prefixed>
ESCAPE          = "\n" | "\t" | "\\" | '\"' | "\'" | "\{" | "\}"
INTERP          = "{" expression "}"     // f-prefixed strings only

identifier      = ALPHA { ALPHA | DIGIT }
ALPHA           = "a".."z" | "A".."Z" | "_"
DIGIT           = "0".."9"
HEX_DIGIT       = DIGIT | "a".."f" | "A".."F"
BIN_DIGIT       = "0" | "1"

keyword         = "case" | "end" | "while" | "for" | "in"
                | "stop" | "next" | "func" | "do" | "this"
                | "init" | "tick" | "draw" | "and" | "or"
                | "not" | "band" | "bor" | "bnot" | "bxor"
                | "true" | "false" | "nil" | "if"

operator        = "+" | "-" | "*" | "/" | "%" | "=" | ":"
                | "#" | "<" | ">" | "." | "?"
                | "++" | "--" | "+=" | "-=" | "*=" | "/=" | "%="
                | "==" | "!=" | "<=" | ">=" | "->" | "|>"
                | "**" | "<<" | ">>" | "??"
                | "?." | "?[" | "?("
                | "**=" | "<<=" | ">>="

delimiter       = "(" | ")" | "[" | "]" | "{" | "}" | ","

COMMENT         = "//" <any char except newline>*
NEWLINE         = "\n"
```

Whitespace (spaces, tabs, carriage returns) is ignored between tokens.
Consecutive newlines are collapsed into a single `NEWLINE` token. EOF
acts as an implicit final `NEWLINE`, so a source file without a
trailing newline is still valid.

### Newline Significance (Stack Rule)

Newline significance is tracked by a stack of frames. Each frame is
either "suppress" (newlines treated as whitespace) or "significant"
(newlines delimit statements). The default state at program top level
is "significant."

Pushing and popping:

| Construct                                              | Frame         |
|--------------------------------------------------------|---------------|
| `(` `[` `{` ... matching `)` `]` `}`                   | suppress      |
| `do` ... `end`                                         | significant   |
| `while` ... `end`                                      | significant   |
| `for` ... `end`                                        | significant   |
| `init` / `tick` / `draw` ... `end`                     | significant   |
| `func(...)` NEWLINE ... `end` (multi-line form)        | significant   |
| `case [expr]` NEWLINE ... `end` (multi-line form)      | significant   |

`func` and `case` only push a frame in their multi-line form. The parser
determines this by peeking past the `)` (func) or past the optional
match expression (case): if the next token is NEWLINE, the construct is
multi-line and pushes a "significant" frame. Otherwise it is single-line
and does not push.

A multi-line construct opened inside a suppressed context therefore
re-enables newlines within its body, so this parses cleanly:

```
foo(do
  x : compute()
  x * 2
end)

result : map(items, func(x)
  case x > 0 -> x * 2
  _ -> 0
  end
end)
```

### Line Continuation

A line that *starts* with one of the following tokens continues the
previous line (the intervening newline is treated as whitespace):

- `|>` (pipe)
- `.` (field access)
- `?.`, `?[`, `?(` (optional-chain access)

These tokens are unambiguously postfix — they cannot start a new
statement — so they safely continue the preceding expression:

```
name
  |> trim()
  |> upper()

user
  ?.address
  ?.city
```

For arithmetic and other infix continuation, place the trailing binary
operator at the end of the current line. The newline immediately after
any binary or n-ary operator that requires a right-hand operand is
suppressed. This covers:

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

(Trailing `,` does not need this rule because commas only appear inside
bracketed contexts, where newlines are already suppressed. The three
non-bracketed uses of `,` — `for i : a, b, c`, `for k, v in …`, and
multi-value case patterns `"a", "b" -> …` — must stay on a single line.)

### Disambiguation: Destructuring vs. Literals

Destructuring is its own statement production (`destructuring = pattern
( ":" | "#" | "=" ) expression`), syntactically distinct from object
and array literals. When `{` or `[` appears at the start of a
statement, the parser needs one-token lookahead after the matching
close-bracket: if `:`, `#`, or `=` follows, parse as `destructuring`;
otherwise, parse as an expression statement (object or array literal).
The patterns and literal grammars are disjoint, so no reinterpretation
is required.

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

Assignment sits below pipe, so `x = 5 |> f()` parses as `x = (5 |> f())`.
The LHS of `=`, compound assignment, and `++` / `--` must be an
`assignable`: an identifier or a chain of `.` / `[]` accesses. Optional
chains (`?.`, `?[`, `?(`) and function calls are **not** assignable.


## Common Expressions

### Declaration and Assignment

```
x : 10            // declare mutable
x # 10            // declare constant (deep freeze)
x = 20            // assign to existing (error if undeclared)
```

Declarations (`:`, `#`) are statements and produce no value. Assignment
(`=`) is an expression and produces the assigned value, so it may appear
anywhere an expression is expected.

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

Compound assignment is syntactic sugar: `x += 1` is equivalent to `x = x + 1`.
Requires an existing binding.

### Increment / Decrement

```
x++               // equivalent to x += 1
x--               // equivalent to x -= 1

player.hp++       // works on field access
items[i]++        // works on index access
```

`++` and `--` apply to any assignable target: identifiers, dot access,
and index access. Returns the value after increment/decrement.

### Field Assignment

```
t.name = "noka"   // dot access
t[1] = "first"    // index access
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

Returns the last completed iteration's value, or `nil` if zero iterations.
Supports `stop` and `next`.

### `for` (Numeric)

```
for i : 1, 9
  print(i)
end

for i : 9, 1, -1      // with step
  print(i)
end
```

The range is **inclusive** on both ends. `for i : 1, 9` iterates 1 through 9.
The loop variable is declared by `:` and scoped to the for block — a fresh
binding is created each iteration, so captures taken inside the loop see
the value of `i` at that iteration.

Start, end, and step must be **integers** — non-integer values are a runtime error.
The default step is `1`. A step of `0` is a runtime error.

If the step sign does not match the direction from start to end, the
loop runs **zero iterations** (no error):

```
for i : 1, 9, -1      // zero iterations (would go the wrong way)
for i : 9, 1          // zero iterations (default step is +1, goes wrong way)
```

If the step overshoots the end, the loop stops at the last value that
stayed within range:

```
for i : 1, 10, 3      // i takes 1, 4, 7, 10 (next would be 13, out of range)
for i : 1, 9, 3       // i takes 1, 4, 7  (next would be 10, out of range)
```

Returns the last completed iteration's value, or `nil` if zero iterations.

### `for` (Generic / Iterator)

Iterates over arrays or objects.

```
items : [10, 20, 30]

// Array: values only
for v in items
  print(v)            // 10, 20, 30
end

// Array: index-value pairs
for i, v in items
  print(f"{i}: {v}")  // 1: 10, 2: 20, 3: 30
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

`for v in` (single variable) is only valid for arrays, not objects.

### `stop`

Exits the innermost enclosing `while` or `for` loop within the current
function.

`stop` with no value causes the loop to return `nil`.
`stop <expr>` causes the loop to return that value. Nothing is allowed
to the **left** of `stop`; it must start its own statement. Everything
to the **right** is parsed as the return expression.

```
// Find first match — loop returns the index
func find(arr, val)
  for i, v in arr
    case v == val -> stop i
  end
end
```

`stop` outside of an enclosing loop is a **parse error**. A function
boundary blocks the lookup — `stop` inside a helper called from a loop
does not stop that loop. Legal positions are the loop body itself or
the body of a `case` branch inside the loop.

### `next`

Skips to the next iteration of the innermost enclosing loop. Does not
affect the loop's return value. `next` takes no value.

```
for i : 1, 9
  case i % 2 == 0 -> next
  print(i)            // odd numbers only
end
```

Like `stop`, `next` outside of an enclosing loop is a parse error, and
function boundaries block the lookup.


## Case Expressions

`case` is the sole conditional construct. It replaces `if/elif/else` entirely.
All forms are expressions and return the value of the matched branch.

### Single-Line

A single branch on one line needs no `end`. Single-line case is always
a bare condition (no match expression).

```
case x > 5 -> print("big")
case alive? -> tick(dt)
```

### Condition Chain (No Match Expression)

Without a match expression, each branch is a boolean condition.
This is how you replace `if/elif/else`.

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

With a match expression, branches compare against it using equality.
Always multi-line with `end`.

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

Branches can have an `if` guard for additional conditions.
`if` is a reserved keyword used exclusively in this context — it has
no standalone statement form.

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
- Without a match expression: each branch is a boolean condition. A `comparison_op` pattern (e.g., `> 5 ->`) in a bare `case` is a parse error -- there is no LHS to compare against
- Branches may include an `if` guard after the pattern for additional filtering
- Multiple branches: `end` required
- Patterns are evaluated top to bottom; first match wins


## Membership Operators

The `in` operator tests membership. Returns `true` or `false`.

```
// Array: checks if value exists
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

The pipe operator `|>` threads the value on the left into the expression
on the right. The RHS form determines how the value is consumed:

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

If `_` appears in the right-hand call, the piped value fills every `_`
instead of being inserted as the first argument.

```
player |> damage(10, _)    // damage(10, player)
5 |> clamp(_, 0, _)        // clamp(5, 0, 5)
```

If no `_` is present, the piped value is inserted as the first argument
(default behavior).

### Non-call RHS

When the RHS is any expression other than a call, the pipe evaluates it
and applies the result to the piped value. This lets a `do ... end` block
produce a function on the fly:

```
value |> do
  factor : compute_factor()
  func(x) x * factor
end
// Equivalent to: (do ... end)(value)
```

A bare identifier on the RHS works the same way -- `x |> transform` is
`transform(x)`. It is a runtime error if the RHS does not produce a
callable.

Pipes sit just above assignment in the precedence table — lower than
any other operator, so a pipe chain reads left-to-right without
parentheses. They are especially useful with NokaScript's free-function
standard library.

```
items
  |> sort(func(a, b) a < b)
  |> concat(", ")
  |> print()
```

A line starting with `|>` continues the previous line (see
[Line Continuation](#line-continuation)), so long chains wrap cleanly
without parentheses.


## Function Captures

Any function call containing `_` as an argument becomes a **capture** --
a single-argument closure where every `_` is filled with the same value.

```
add(1, _)              // func(x) add(1, x)
clamp(_, 0, _)         // func(x) clamp(x, 0, x)
```

`_` captures the **nearest enclosing call**. A fully-formed capture is
just a value — parent calls see a function, not a `_`.

```
map(items, add(1, _))  // map(items, func(x) add(1, x))
                        // _ is inside add(), so add() is the capture
                        // map() receives items and a function
```

Captures and pipe placeholders use the same `_` symbol and the same
semantics (all `_` filled with one value). Pipes feed the value
immediately; captures produce a closure for later use.

```
// These are equivalent:
items |> sort(less(_, _))
items |> sort(func(x) less(x, x))

// Common use with higher-order functions:
nums |> filter(greater(_, 0))
sorted : sort(items, less(_, _))
doubled : map(nums, mul(2, _))
```


## Functions

### Named Functions

```
func greet(name)
  print(f"hello {name}")
end

greet("noka")
```

Named function declarations are **hoisted** -- they can be called before
their declaration in the source. This applies at all scope levels.
Named functions create mutable bindings (equivalent to `:`).

### Return Values

Functions return the value of their **last expression**. There is no
return keyword. Use `case` to structure conditional returns.

```
func double(x)
  x * 2
end

func abs(x)
  case
    x < 0 -> -x
    _ -> x
  end
end

func classify(hp)
  case
    hp > 50 -> "healthy"
    hp > 20 -> "hurt"
    _ -> "critical"
  end
end
```

### Parameters

All parameters are **optional by default** and default to `nil` if not provided.
Use `:` to specify an explicit default value. Use `?` to mark a parameter
as explicitly optional (defaults to `nil`, same as no annotation — useful
for documentation).

```
func draw(x, y, w: 8, h: 8)
  rectf(x, y, w, h)
end

draw(10, 20)              // x=10, y=20, w=8, h=8
draw(10, 20, 16, 16)      // x=10, y=20, w=16, h=16
```

### Labelled Arguments

Arguments can be passed by name using `name: value` syntax at the call site.
Unlabelled arguments must come **before** labelled arguments.

```
func draw(x, y, w: 8, h: 8)
  rectf(x, y, w, h)
end

draw(10, 20, w: 16)       // x=10, y=20, w=16, h=8
draw(10, 20, h: 16)       // x=10, y=20, w=8, h=16
```

Providing the same argument both positionally and by label is a runtime error.

### Skipping Positional Arguments

Use an empty slot (adjacent commas) to skip a positional argument,
which receives its default value (`nil` or the declared default).

```
func foo(a, b, c, d: 10)
  ...
end

foo(1, , 3)               // a=1, b=nil, c=3, d=10
foo(1, , , 4)             // a=1, b=nil, c=nil, d=4
foo(1, , c: 3)            // a=1, b=nil, c=3, d=10
```

Skips are only for interior gaps. To omit trailing arguments, just
don't pass them.

### Rest Parameters

A `*` prefix on a parameter collects remaining arguments into an array.
Rest may appear in any position — at most one per parameter list.
Parameters before `*rest` bind positionally from the start; parameters
after it bind positionally from the end.

```
func sum(first, *rest)
  total : first
  for v in rest
    total += v
  end
  total
end

sum(1, 2, 3, 4)      // 10
```

### Closures

Functions capture their enclosing scope.

```
func makeCounter()
  count : 0
  func inc()
    count += 1
    count
  end
  inc
end

c : makeCounter()
print(c())            // 1
print(c())            // 2
```

### Single-Expression Functions

Both named and anonymous functions support a single-expression form:
if the body is a single expression on the same line as the closing `)`,
it is the return value and no `end` is required.

```
// Named single-expression
func add(x, y) x + y
func neg(x) -x

// Anonymous single-expression
sort(items, func(a, b) a < b)
doubled : map(nums, func(x) x * 2)
```

Multi-line form always requires `end`:

```
handler : func(x)
  print(x)
  x * 2
end
```

The parser picks the form by looking at the token after `)`: a NEWLINE
means multi-line, anything else means single-expression.

### Anonymous Functions

Anonymous functions use the `func` keyword without a name. Both
multi-line and single-expression forms are supported (see above).

```
handler : func(x)
  print(x)
  x * 2
end

cmp : func(a, b) a < b
```

### Constant Functions

To make a function immutable, use `#` with an anonymous function.
Note: `#` bindings are not hoisted.

```
greet # func(name)
  print(f"hello {name}")
end
```


## `this` and Methods

Objects can store functions as values. When a function is accessed via dot
syntax, `this` is automatically bound to the object.

```
player : {
  hp: 100,
  heal: func()
    this.hp += 10
  end
}

player.heal()         // this = player, hp becomes 110
```

### Auto-Binding on Dot Access

Accessing a method via dot returns a **bound function** with `this`
permanently set to the object. This means methods can be detached
and still work:

```
h : player.heal       // h is bound to player
h()                   // this = player, works correctly
```

### Rules

- `this` is available inside any function stored on an object
- `obj.method()` binds `this` to `obj`
- `h : obj.method` returns a bound function (auto-binding)
- `this` outside of a bound context is a runtime error
- `this` used **directly** inside a lifecycle block (`init`/`tick`/`draw`)
  is a runtime error. `this` is fine inside methods called from a
  lifecycle block (e.g., `player.update()` reaches its `this` normally)

### Bound Function Equality

Equality of bound functions uses **structural** comparison: two bound
functions are equal if they wrap the same underlying function **and**
the same bound `this`.

```
a : player.heal
b : player.heal
a == b               // true — same function, same this

c : enemy.heal
a == c               // false — different `this`
```

Unbound functions still use reference equality. A bound function and
the raw function it wraps are not equal.


## Lifecycle Blocks (Host Convention)

Lifecycle blocks are a **NokaOS host convention**, not a core language
feature. The runtime looks for `init`, `tick`, and `draw` at program
top level and drives them from the game loop. Another host could
ignore these names entirely or define its own set.

Programs that run in the game loop define lifecycle blocks.
These are first-class keywords, not function definitions.
Parens are always required. All three are optional and independent.

**Lifecycle blocks are only legal at program top level.** Defining them
inside a function, block, or another lifecycle block is a parse error.
At most one each of `init`, `tick`, and `draw` per program; duplicates
are a parse error.

```
x : 0
speed # 2

init()
  x = 100
end

tick(dt)
  x += speed * dt
end

draw()
  cls()
  rectf(x, 10, 8, 8)
end
```

| Block      | Called                              | Typical use           |
|------------|-------------------------------------|-----------------------|
| `init()`   | Once, when program starts           | Setup state           |
| `tick(dt)` | Every frame, receives delta time    | Update logic          |
| `draw()`   | Every frame, after tick             | Render to screen      |

Code outside lifecycle blocks runs once at load time (top-level initialization).

If a lifecycle block is not defined, nothing happens for that phase.
A program with only `draw` renders a static frame. A program with only
`tick` runs logic without display. A program with no lifecycle blocks
runs top-level code once and exits.

Parameters (`dt` in `tick`) are scoped to the lifecycle block and
shadow any outer bindings with the same name.


## Strings

Strings are **mutable** and **1-indexed**. Individual characters can be read
and written via index access.

```
s : "hello"
print(s[1])           // "h"
print(s[-1])          // "o" (negative indexing)
s[1] = "H"            // "Hello"
```

Indexing returns a single-character string. Assigning to an index replaces
that character. Strings declared with `#` are frozen and cannot be mutated.

```
name # "noka"
name[1] = "N"         // RUNTIME ERROR (frozen)
```


## Arrays

Ordered, **1-indexed** collections.

### Creating Arrays

```
nums : [10, 20, 30]
empty : []
```

Arrays and objects are separate types and use different literal syntax
(`[]` for arrays, `{}` for objects).

### Accessing Values

```
nums : [10, 20, 30]
print(nums[1])        // 10 (1-indexed)
print(nums[3])        // 30
```

Missing indices return `nil`.

### Negative Indexing

Negative indices count from the end of the array.

```
nums : [10, 20, 30]
print(nums[-1])       // 30 (last element)
print(nums[-2])       // 20
```

### Setting Values

```
items : []
items[1] = "sword"
push(items, "shield")
```

### Length

```
items : [10, 20, 30]
print(len(items))     // 3
```

### Array Spread

The `*` operator spreads an array into a new array literal. Spreads
may appear anywhere in the literal, any number of times:

```
a : [1, 2]
b : [*a, 3, 4]        // [1, 2, 3, 4]
c : [0, *a, *a, 5]    // [0, 1, 2, 1, 2, 5]
d : [0, *a]           // [0, 1, 2]
```

### Arrays Are Passed by Reference

```
func addItem(inv, item)
  push(inv, item)
end

items : ["sword"]
addItem(items, "shield")
print(len(items))     // 2
```


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

// String-literal keys (for keys with spaces, punctuation, or reserved words)
config : {"max-hp": 100, "save path": "disc0"}
print(config["max-hp"])

// Empty object
empty : {}
```

Keys may be identifiers or string literals. Identifier keys become
string keys of the same name. Computed keys (`[expr]: value`) are not
supported.

### Accessing Values

```
info : {name: "noka", ver: 2}
print(info.name)      // noka
print(info["name"])   // noka (equivalent)
```

Missing keys return `nil`.

### Setting Values

```
info : {}
info.name = "noka"
info["ver"] = 2
```

### Object Spread

Create a new object from an existing one with overridden fields.
The spread `*` must be first and only one is allowed per object
literal. A spread by itself (no other fields) is legal and produces
a shallow copy.

```
player : {name: "noka", hp: 100, mp: 50}
hurt : {*player, hp: 50}
// {name: "noka", hp: 50, mp: 50}

copy : {*player}       // shallow copy
```


## Destructuring

Destructuring unpacks arrays and objects into individual bindings. It
is a statement, not an expression.

When `{` or `[` appears at statement position, the parser checks if
`:`, `#`, or `=` follows the closing bracket. If so, the content is
parsed as a destructuring pattern. Otherwise, it is an expression
(array or object literal).

### Array Destructuring

```
pos : [10, 20]
[x, y] : pos

// With rest
nums : [1, 2, 3, 4, 5]
[first, *rest] : nums    // first = 1, rest = [2, 3, 4, 5]

// Discard with _
[_, y] : pos              // ignore first element
```

Extra values in the source are ignored. Too few values is a runtime
error unless the missing elements have `??` defaults.

### Object Destructuring

```
info : {name: "noka", ver: 2, id: 5}
{name, ver} : info          // name = "noka", ver = 2 (id ignored)

// With rename
{name: playerName} : info   // playerName = "noka"

// With rest
{name, *rest} : info        // name = "noka", rest = {ver: 2, id: 5}
```

Variable names must match key names (unless renamed with `:`).
Destructuring a missing key without a default is a runtime error.

### Defaults

Use `??` to provide default values for missing elements:

```
[a, b, c ?? 0] : [1, 2]          // c = 0
{name, age ?? 0} : {name: "noka"} // age = 0
```

With a `??` default, missing values use the default instead of erroring.

### Rename Plus Default

Object patterns combine rename and default by placing `??` on the
renamed binding:

```
{name: playerName ?? "anon"} : info
// playerName = info.name, or "anon" if missing
```

### Nested Patterns

Patterns nest — a destructuring slot can itself be a pattern:

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
func distance({x: x1, y: y1}, {x: x2, y: y2})
  sqrt((x2 - x1)**2 + (y2 - y1)**2)
end

func first([head, *tail])
  head
end
```

A pattern parameter destructures its argument on call. Defaults work:

```
func draw([x, y], opts: {w: 8, h: 8})
  rectf(x, y, opts.w, opts.h)
end
```

Note: labelled-argument syntax at the call site (`foo(x: 5)`) is not
applied through a pattern parameter. A pattern parameter is a single
positional slot — the argument passed in is destructured, not labelled.

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
[x, y] : pos         // declare mutable
[x, y] # pos         // declare constant
[x, y] = pos         // assign to existing

{name, ver} : info   // declare mutable
{name, ver} # info   // declare constant
```


## Built-in Functions

All built-ins are flat globals. They are highlighted in frost/cyan in the editor.

### Core

| Function       | Description                                      |
|---------------|--------------------------------------------------|
| `print(v)`    | Output a value                                   |
| `type(v)`     | Returns type as string: `"number"`, `"string"`, `"boolean"`, `"nil"`, `"array"`, `"object"`, `"function"` |
| `tostr(v)`    | Converts any value to string (see String Representations) |
| `tonum(v)`    | Converts string/number to number, or `nil`       |
| `len(v)`      | Length of string, array, or object (key count)   |

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
| `rnd(lo, hi)`    | Random integer from lo to hi (inclusive)  |
| `sin(n)`         | Sine (radians)                           |
| `cos(n)`         | Cosine (radians)                         |
| `tan(n)`         | Tangent (radians)                        |
| `asin(n)`        | Inverse sine                             |
| `acos(n)`        | Inverse cosine                           |
| `atan2(y, x)`    | Angle from origin to point               |

### String

| Function            | Description                                        |
|--------------------|----------------------------------------------------|
| `sub(v, i, j)`     | Substring or subarray from i to j (1-indexed, inclusive) |
| `upper(s)`         | Uppercase                                          |
| `lower(s)`         | Lowercase                                          |
| `find(v, pat)`     | Find first occurrence in string or array, returns index (1-based) or nil |
| `split(s, sep)`    | Split string into array                            |
| `trim(s)`          | Remove leading/trailing whitespace                 |
| `replace(s, old, new)` | Replace all occurrences of old with new        |
| `char(n)`          | Number to character                                |
| `ord(s)`           | First character to number                          |

### Array

| Function              | Description                                  |
|-----------------------|----------------------------------------------|
| `push(arr, v)`        | Append value, returns `arr`                  |
| `pop(arr)`            | Remove and return last value                 |
| `shift(arr)`          | Remove and return first value                |
| `insert(arr, i, v)`   | Insert value at index, returns `arr`         |
| `remove(arr, i)`      | Remove value at index, returns `arr`         |
| `sort(arr [, cmp])`   | Return **new** sorted array, optional comparator |
| `reverse(arr)`        | Return **new** reversed array                |
| `map(arr, fn)`        | Return new array with fn(v) or fn(v, i) applied |
| `filter(arr, fn)`     | Return new array where fn(v) or fn(v, i) is true |
| `pick(arr)`           | Return random element                        |
| `keys(obj)`           | Return array of object keys                  |
| `vals(obj)`           | Return array of object values                |
| `concat(arr, sep)`    | Join array elements into string              |

### System

| Function          | Description                              |
|------------------|------------------------------------------|
| `exit()`         | Exit current program                     |
| `get_arg(n)`     | Get launch argument by index (1-based)   |
| `mem()`          | Current memory usage                     |
| `time()`         | Current time                             |

### Display

| Function                      | Description                        |
|------------------------------|------------------------------------|
| `cls()`                       | Clear screen                       |
| `color(c)`                    | Set draw color                     |
| `print_at(s, x, y)`          | Print string at position           |
| `rect(x, y, w, h)`           | Draw rectangle outline             |
| `rectf(x, y, w, h)`          | Draw filled rectangle              |
| `circ(x, y, r)`              | Draw circle outline                |
| `circf(x, y, r)`             | Draw filled circle                 |
| `line(x1, y1, x2, y2)`       | Draw line                          |
| `pset(x, y)`                 | Set pixel                          |
| `pget(x, y)`                 | Get pixel color                    |
| `spr(n, x, y)`               | Draw sprite                        |
| `camera(x, y)`               | Offset all draw calls              |
| `clip(x, y, w, h)`           | Set clipping region                |

### Input

| Function    | Description                              |
|------------|------------------------------------------|
| `key(k)`   | Is key currently held?                   |
| `keyp(k)`  | Was key just pressed this frame?         |


## Runtime Behavior

### Variable Scoping

Variables use lexical scoping with a scope chain. Each function call creates
a new scope. Declaration (`:` / `#`) creates in the current scope.
Assignment (`=`) walks the chain; error if no binding found.

```
x : 10
func f()
  x : 20            // shadows outer x
  print(x)          // 20
end
f()
print(x)            // 10 (unchanged)
```

### Function Hoisting

Named function declarations (`func name() ... end`) are hoisted --
collected before execution so they can be called before their source
position. Hoisting is **block-scoped**: a named function is visible
only within the block that contains its declaration, not in enclosing
blocks.

```
greet("noka")       // works -- greet is hoisted to top of this scope

func greet(name)
  print(f"hello {name}")
end
```

A function declared inside a `do`, `while`, `for`, `case` branch, or
function body is scoped to that block:

```
do
  func helper(x) x * 2 end
  helper(5)          // works -- scoped to this block
end
helper(1)            // RUNTIME ERROR — not visible out here
```

Functions declared inside a loop body are re-declared on every
iteration, producing fresh closures each time:

```
for i : 1, 3
  func f() i end
  push(results, f)   // each f captures its iteration's i
end
```

Only named declarations are hoisted; `:` / `#` bindings holding
anonymous functions are not. Functions return the value of their last
expression. An empty body returns `nil`.

### String Representations

`print()` and `tostr()` produce display-friendly output:

| Value                  | Output              |
|------------------------|---------------------|
| `42`                   | `42`                |
| `"hello"`              | `hello`             |
| `true`                 | `true`              |
| `nil`                  | `nil`               |
| `[1, 2, 3]`           | `[1, 2, 3]`         |
| `{name: "noka"}`      | `{name: "noka"}`    |
| `func() ... end`      | `<function>`        |

Strings inside arrays/objects are quoted with escaped inner quotes.

### Error Reporting

Errors include a 1-based line number in the format `[line N] message`.

Three error types:
- **ScanError** -- invalid character or unterminated string
- **ParseError** -- unexpected token, missing `end`, etc.
- **RuntimeError** -- type errors, undefined variables, division by zero


## Syntax Highlighting

| Token Category | Color Name | Hex       |
|----------------|------------|-----------|
| Keyword        | amber      | `#CCAA33` |
| Number         | deep blue  | `#4488FF` |
| String         | verdant    | `#44CC66` |
| Boolean        | violet     | `#9944FF` |
| Nil            | ash        | `#6A6A78` |
| Comment        | ash        | `#6A6A78` |
| Operator       | bone       | `#C8C4B8` |
| Built-in       | frost      | `#88DDFF` |
| Identifier     | bone       | `#C8C4B8` |


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
func fib(n)
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
func makeCounter()
  count : 0
  func inc()
    count += 1
    count
  end
  inc
end

c : makeCounter()
print(c())            // 1
print(c())            // 2
print(c())            // 3
```

### Game Loop
```
x : 0
y : 0
speed # 60

init()
  x = 100
  y = 100
end

tick(dt)
  case key("left") -> x -= speed * dt
  case key("right") -> x += speed * dt
end

draw()
  cls()
  rectf(x, y, 8, 8)
end
```

### Destructuring
```
func getPlayer()
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
  |> filter(func(x) x > 2)
  |> concat(", ")
```

### Methods and `this`
```
func newPlayer(name, hp)
  {
    name: name,
    hp: hp,
    heal: func()
      this.hp += 10
    end,
    info: func()
      f"{this.name}: {this.hp}hp"
    end
  }
end

p : newPlayer("noka", 100)
p.heal()
print(p.info())       // noka: 110hp

show : p.info         // auto-bound
print(show())         // noka: 110hp
```

### Function Captures
```
nums : [1, 2, 3, 4, 5]

// Without captures
doubled : map(nums, func(x) x * 2)
positive : filter(nums, func(x) x > 0)

// With captures
doubled : map(nums, mul(2, _))
positive : filter(nums, greater(_, 0))

// Capture in sort
sorted : sort(items, less(_, _))
```

### Labelled Arguments
```
func rect(x, y, w: 8, h: 8)
  rectf(x, y, w, h)
end

rect(10, 20)              // defaults
rect(10, 20, w: 16)       // override w
rect(10, 20, h: 16)       // override h
rect(10, , w: 4, h: 4)   // skip y
```

### Loop Return Values
```
// Find first match
func find(arr, val)
  for i, v in arr
    case v == val -> stop i
  end
end

idx : find([10, 20, 30], 20)
print(idx)                // 2
```

### Membership
```
inv : ["sword", "shield", "potion"]

case "sword" in inv -> print("armed!")

case "bow" not in inv -> print("need range")

info : {name: "noka", role: "knight"}
case "role" in info -> print(info.role)
```
