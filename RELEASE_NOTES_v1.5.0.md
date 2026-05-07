# Dolet Compiler v1.5.0-beta

By the grace of Allah — every "future-feature" we listed for v1.4 is in
the bottle. Generics, pattern matching, panic with stack traces,
closures with mutable captures and self-capture, and a hardened
foundation pass all landed since v1.4.0. Tier 2 of the ROADMAP is
done; Tier 3 is mostly complete (everything except DWARF integration,
threading, and incremental builds).

## What's New (since v1.4.0-beta)

### Tier 1 — Foundation (A1–A4)

A four-item polish pass that makes the rest of the language safer to
build on:

- **`panic("msg")`** — function-call form, lowers to `dolet_panic` and
  exits with code 101 (Rust convention). Codegen embeds a
  `[panic at FILE:LINE]` prefix into every emitted message; the line
  number is the user-source line, computed by tracking newlines in
  the prelude+runtime+imports prefix and subtracting at emit time.
  Tokenizer's `tok_advance` is now the single source of truth for
  line tracking — strings, char-literals, and multiline comments now
  correctly increment the line counter.
- **Visibility enforcement at codegen** — `private` / `protected`
  fields and methods now actually fail compilation when accessed
  cross-struct, with a clear file:line error.
- **Codegen validation layer** — catches the four historical
  miscompile shapes (struct-stomp, mk_node_list overflow, i64_say
  miscompile, str_trim void) at codegen time with file:line errors
  pointing at the offending function. ON by default; `--no-validate`
  bypasses for debugging, `--release` skips it for performance.
- **Error-path tests for std/system** — locks in current behaviour
  of `System.exists`, `Command.run`, `Command.capture`,
  `Command.output`, and `File.open` failure modes.

### Tier 2 — Type System

#### `Option<T>` and `Result<T, E>` (B1)

Both types are first-class, transparent tagged sums baked into the
compiler:

```dolet
opt:  option<i32>      = Some(42)
none: option<i32>      = None()
ok:   result<i32, str> = Ok(99)
err:  result<i32, str> = Err("oops")
```

Includes:

- **Polymorphic constructor sugar (B1.5)** — `option<i64> = Some(42)`
  picks the i64 overload automatically; no explicit `as i64` needed
  on the literal.
- **Pattern matching (B1.6)** — `case Some(x):` / `case None:` /
  `case Ok(x):` / `case Err(e):` work in `match` expressions.
- **Qualified constructors (B1.7)** — `Option.Some(42)`,
  `Option.None()`, `Result.Ok(99)`, `Result.Err("oops")` aligned
  with Dolet's `Module.method` idiom. Bare `Some(...)` / `Ok(...)`
  still work.

#### `?` postfix operator (B2)

Propagates `Err` / `None` from `result` / `option`-returning calls:

```dolet
fun parse_pair(s: str) -> result<i64, str>:
    n: i64 = parse_i64(s)?     # early-return on Err
    return Ok(n * 2)
```

#### User-defined generics (B3, Phases 1–4.5)

- **Generic structs** — `struct Box<T>: item: T`
- **Methods on generic structs** — `extend Box<T>: fun get(self) -> T:`
- **Trait bounds** — `struct Box<T: Display>: ...` validates that T
  implements Display at instantiation; clean error if it doesn't.
- **T-substitution inside method bodies** — `fun copy_value(self) -> T:
  x: T = self.value; return x` now correctly uses the concrete type
  per instantiation.
- **Generic functions** — `fun pack<T>(x: T) -> Box<T>:
  return Box<T>(value=x)` works; the body is cloned with T → concrete
  per instantiation.

Phase 5 (Option/Result migration to use these) is intentionally
deferred — it would degrade `None()` polymorphism for marginal gain.

### Tier 3 — Major Features

#### Closures with captures (C1, all four phases)

Anonymous fns are first-class, with full closure semantics:

```dolet
# Phase 1: lambdas without captures
add_one: fun(i32) -> i32 = |x: i32| -> i32 x + 1

# Phase 2: capture local vars
fun do_it():
    scale: i32 = 10
    f: fun(i32) -> i32 = |x: i32| -> i32 x * scale

# Phase 3: explicit `@heap` for closures that escape
fun make_adder(n: i32) -> @heap fun(i32) -> i32:
    return |x: i32| -> i32 x + n
```

Phase 3 enforces a single rule: stack default everywhere; the user
writes `@heap fun(...)` on the type to opt into heap. Returns
require `@heap` — stack-return-of-closure is provably UAF, so the
compiler refuses with a clear message that points at the fix.

##### C1 Phase 4 (this release)

Four targeted fixes after each was surfaced by a concrete failing
test:

- **Zero-arg lambdas** — `|| -> i32 42`. The lexer can't tell
  `a || b` from `|| -> ...` without context, so the parser now
  disambiguates at primary-expression position. Single-expression
  bodies without an explicit `-> T` are treated as void (no implicit
  return wrap), so `|| print(msg)` compiles cleanly.
- **Mutable captures persist across calls** — old approach prepended
  `n: T = Memory.read_T(env+off)` and treated captures as locals,
  so `n = n + delta; return n` updated only the local copy. Counter
  pattern produced 1, 1, 1. New approach rewrites scalar/str
  captures inline so var_ref(n) becomes a direct env load and
  assign(n=v) becomes a direct env store. The env IS the variable's
  home; mutations persist with no prologue copy or write-back.
- **Closures-of-closures (compose)** — capture analysis missed the
  callee name in `f(g(x))`. Walker now also inspects fn-position.
  Closure-typed captures keep the var-decl prologue (rewriting them
  to raw i64 loses the call-site type info gen_indirect_call needs).
- **Self-capture in method-local lambdas** — direct `self.field`
  reads inside a lambda inside a method now work end-to-end:
  ```dolet
  extend Counter:
      fun bind_inc(self) -> @heap fun(i32) -> i32:
          return |delta: i32| -> i32 self.n + delta
  ```
  The lifter tracks the enclosing struct via `g_lift_method_struct`,
  detects NODE_SELF / NODE_SELF_FIELD in capture analysis and adds
  a synthetic `__self` capture, then rewrites the body so
  NODE_SELF → var_ref(__self) and NODE_SELF_FIELD(f) →
  field_access(__self, f). The factory call passes the enclosing
  method's implicit self as the captured value.

#### Stack traces at panic (C2 Phase 1+2)

Phase 1: every emitted panic carries `[panic at FILE:LINE]` (already
covered above under Tier 1).

Phase 2: the new `--debug` flag wraps every non-exempt function with
`__frame_push` at entry and `__frame_pop` before each return path so
`dolet_panic` can print a multi-frame call chain:

```
$ doletc app.dlt -o app.exe --debug
$ ./app
[panic at app.dlt:5] division by zero

Stack trace (most recent first):
  at divide (app.dlt)
  at compute_avg (app.dlt)
  at process_batch (app.dlt)
```

Default builds compile to identical code as before — instrumentation
only happens with `--debug`. Skip-list (`is_frame_exempt`) keeps the
runtime out of the trace and avoids self-recursion: frame helpers
themselves, Memory.*, Str.*, Convert.*, IOOps.*, Process.*,
FileOps.*, print/println overloads, dolet_panic, and everything
is_arena_exempt already excludes.

### Bug fixes

- Chained extend-str return type loss (B-01)
- Overload-blind `find_impl_method` (B-02)
- Parser dropped trailing siblings after nested else-if (B-03)
- Nested method on struct/str-typed field (`b.item.show()`) was
  passing the field-slot address instead of the loaded pointer
- Static method calls were not resolving overloads — fixed in
  `gen_static_method_call`
- `init_gen_fn_registry` was being called twice and zeroing the
  populated registry — now called once via `init_all_registries`
- `init_ast_constants` was missing `NODE_LAMBDA = 180` — lambda
  nodes were silently created with type=0 and ignored by walkers
- Lambda lifter walker now recurses into NODE_EXTEND_BLOCK and
  NODE_IMPL_BLOCK, so methods get their lambdas lifted at all.
  Without this, ANY lambda inside a method was invisible to the
  lift pass and the method silently compiled to `return null`.

### Library additions

- `Str` library (15 methods: equals, index_of, replace, repeat,
  split, lines, parse_i64, parse_i32, parse_f64, is_int, is_empty,
  starts_with, ends_with, trim, substring, ...)
- `Convert.{i32_to_hex, i64_to_hex}`
- `Memory.compare`
- `Dir.list`
- `String literal method calls` (`"hi".trim()`)

## Verification

- 87 / 87 tests pass
- Bootstrap stage 1 → 2 → 3 byte-stable
- All four user apps (simple-app-eqoi, FileManager, DisplayManager,
  DesktopShell) rebuild with `--target windows --release`

## What's Next

ROADMAP-remaining (each genuinely multi-session):

- **B3 Phase 5** — Option/Result migration to user-generic plumbing
  (deferred deliberately; kept as-is because the migration would
  degrade `None()` polymorphism for marginal gain)
- **C2 DWARF / CodeView** — full debugger integration so a Dolet
  binary can be opened in VS Code with breakpoints + locals + step
- **C3 threading + atomics** — `Thread.spawn`, `Mutex`, `Atomic<T>`
  with proper memory ordering
- **C4 incremental builds** — per-module .obj cache + content-hash
  invalidation
- **D1 Linux platform pipes** — real `pipe()` / `dup2()` / `fork()`
  chain (needs Linux box for verification)
