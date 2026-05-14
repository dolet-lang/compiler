# AGENTS.md — AI Reference for the Dolet Compiler

> Living spec for AI sessions working on this self-hosted compiler. Read
> this BEFORE grepping the source. Every section was verified against
> the codebase at `dolet-compiler/`. File:line references are real.

**Compiler version:** v1.5.0-beta · **Bootstrap:** stage 1→2→3
byte-stable on Windows · **Test count:** 94 PASS / 0 FAIL.

---

## 0. Table of contents

1. [How to read this file](#1-how-to-read-this-file)
2. [Repo map](#2-repo-map)
3. [Naming conventions (DO NOT VIOLATE)](#3-naming-conventions-do-not-violate)
4. [Primitive types & literals](#4-primitive-types--literals)
5. [Annotations (`@`-prefixed)](#5-annotations--prefixed)
6. [Top-level statements](#6-top-level-statements)
7. [Struct + method declaration forms](#7-struct--method-declaration-forms)
8. [Method dispatch & name mangling](#8-method-dispatch--name-mangling)
9. [Memory model](#9-memory-model-stack--heap--arena)
10. [Strings — primitive `str` vs helper `Str`](#10-strings--primitive-str-vs-helper-str)
11. [Closures (`fun(...) -> ...`)](#11-closures-funargs---ret)
12. [Generics — built-in & user-defined](#12-generics--built-in--user-defined)
13. [Module system](#13-module-system-loadexposeexportrequiresmodule)
14. [Compiler intrinsics (RESERVED NAMES)](#14-compiler-intrinsics-reserved-names)
15. [Threading & atomics](#15-threading--atomics)
16. [Error handling — `Option`, `Result`, `?`, `panic`](#16-error-handling--option-result--panic)
17. [Library layout](#17-library-layout)
18. [Compiler driver & build pipeline](#18-compiler-driver--build-pipeline)
19. [Bootstrap dance — when adding language features](#19-bootstrap-dance--when-adding-language-features)
20. [Common pitfalls (verified from past sessions)](#20-common-pitfalls-verified-from-past-sessions)
21. [Test-runner & verification protocol](#21-test-runner--verification-protocol)

---

## 1. How to read this file

- **Verified facts only.** Every claim was cross-checked against the
  source. File:line references point at the line that proves the
  claim.
- **Pinned to v1.5.0-beta.** When the language changes, update this
  file in the same PR. Stale doc is worse than no doc.
- **Examples come from `tests/`.** They're real, runnable, and the
  test-runner verifies them. If an example here disagrees with a test
  file, the test file wins — fix this doc.
- **AI-first phrasing.** Concise, table-heavy, scan-friendly. Not a
  beginner tutorial.

---

## 2. Repo map

```
dolet-compiler/
├── lexer/tokenizer.dlt              # keyword + token recognition
├── parser/                          # AST construction
│   ├── ast_nodes.dlt                # NODE_* constants + builders
│   ├── parser_core.dlt              # tokens, indent helpers
│   ├── parser_expr.dlt              # expression precedence
│   ├── parser_stmt.dlt              # statements (if/while/for/match)
│   ├── parser_decl.dlt              # struct, fun, impl, extend, group
│   └── parser_main.dlt              # top-level dispatcher
├── codegen/
│   ├── codegen_core.dlt             # registries, type checks
│   ├── codegen_types.dlt            # type inference
│   ├── codegen_expr.dlt             # expression lowering
│   ├── codegen_stmt.dlt             # statement lowering
│   ├── codegen_decl.dlt             # gen_fun_def, gen_method_def
│   ├── codegen_access.dlt           # method dispatch (the big one)
│   ├── codegen_treeshake.dlt        # reachability marking
│   ├── codegen_mono.dlt             # generics monomorphization + lambdas
│   ├── codegen_validate.dlt         # validation layer (--validate flag)
│   └── codegen_main.dlt             # collect_declarations + emit driver
├── driver/
│   ├── pipeline_init.dlt            # init_pipeline()
│   └── doletc_driver.dlt            # main(), CLI args, file I/O
├── library/
│   ├── mod.dlt                      # registry: maps module names → paths
│   ├── core/                        # auto-loaded, platform-independent
│   ├── platform/{windows,linux}/    # OS-specific
│   └── std/                         # opt-in via `import std`
├── bootstrap/                       # Python bootstrap compiler (stage 0)
├── build.bat                        # 3-stage byte-stable bootstrap
├── run_tests.bat                    # 94 tests
├── tests/                           # *.dlt test files
└── bin/doletc.exe                   # the compiled compiler
```

---

## 3. Naming conventions (DO NOT VIOLATE)

| Pattern | Means | Examples |
|---|---|---|
| `lowercase_type` | Primitive type, compiler builtin (lexer keyword) | `str`, `i32`, `i64`, `f64`, `bool`, `ptr`, `list`, `array`, `map`, `option`, `result` |
| `Capitalized` struct | Helper / value type, library code | `Str`, `I32`, `F64`, `Bool`, `Memory`, `Convert`, `Random`, `AtomicI32`, `Thread`, `File` |
| `_lowercase` prefix | **Compiler-internal**. User code MUST NOT redefine these | `_str_plus`, `_str_dupe`, `_arena_i32_to_str`, `_scope_arena_alloc` |
| `__double_underscore` prefix | **Compiler-generated** at codegen time | `__lambda_0`, `__lambda_0_make`, `__lambda_0_env`, `__thread_entry`, `__atomic_*`, `__frame_push`, `__print_stack_trace` |
| `g_lowercase` prefix | Global compiler/runtime state | `g_random_lcg_state`, `g_arena_emit`, `g_validate_enabled`, `g_current_struct` |
| `dolet_X` | Public runtime helper | `dolet_panic` |

**Convention paired primitives ↔ helper structs:**

| Primitive | Helper struct | Lives in |
|---|---|---|
| `str` (compiler builtin, `TK_STR_TYPE`) | `Str` | `library/core/string.dlt` |
| `i32` (`TK_I32`) | `I32` | `library/core/integers.dlt` |
| `i64` (`TK_I64`) | `I64` | `library/core/integers.dlt` |
| `f32` / `f64` | `F32` / `F64` | `library/core/floats.dlt` |
| `bool` | `Bool` | `library/core/primitives.dlt` |
| `char` | `Char` | `library/core/primitives.dlt` |
| `ptr<T>` | `Pointer` | `library/core/primitives.dlt` |

The two are **independent**. There's no implicit alias. `Str.trim(s)` and
`s.trim()` (via `group str:`) both work — `s.trim()` mangles to
`@str_trim`, `Str.trim(s)` mangles to `@Str_trim` — they're separate
symbols. The wrappers in `group str:` literally call `Str.X(self)`.

---

## 4. Primitive types & literals

### Type keywords (recognized in `lexer/tokenizer.dlt:493-500`)

| Keyword | Token | Notes |
|---|---|---|
| `i8` `i16` `i32` `i64` `i128` | `TK_I8` … `TK_I128` | Signed integers |
| `u8` `u16` `u32` `u64` `u128` | `TK_U8` … `TK_U128` | Unsigned integers |
| `f32` `f64` | `TK_F32` / `TK_F64` | IEEE 754 floats |
| `str` | `TK_STR_TYPE` | Null-terminated `ptr<i8>` (compiler builtin) |
| `char` | `TK_CHAR_TYPE` | Single byte |
| `bool` | `TK_TYPE` | `true` / `false` literals → `TK_BOOL` |
| `ptr<T>` | `TK_PTR` | Raw pointer, generic over T |
| `list` `array` `map` | `TK_LIST` / `TK_ARRAY` / `TK_MAP` | Built-in generic containers |
| `int` `float` `double` `string` | `TK_TYPE` | **Reserved aliases** — usable as types but lexed differently. Avoid in names |

### Literals

```dolet
n: i32 = 42                  # decimal
n2: i32 = 0xFF               # hex (TK_HEX)
n3: i32 = 0b1010             # binary (TK_BINARY)
n4: i32 = 0o777              # octal (TK_OCTAL)
big: i64 = 9999999999 as i64
f: f64 = 3.14
b: bool = true
c: char = 'a'
s: str = "hello"
fs: str = @"hello {name}"    # f-string (TK_FSTRING) — interpolates {var}
nothing: ptr = null
```

### Casting

`expr as Type` — explicit conversion. Always required across numeric
widths. `n as i64`, `(s as i64) + 1`, `ptr as str`.

---

## 5. Annotations (`@`-prefixed)

Annotations are stacked top-of-decl. Multiple allowed:
`@inline @hot fun foo():`. Storage: `node + 80` as a node_list.

### Built-in annotations

| Annotation | Targets | Effect | Codegen path |
|---|---|---|---|
| `@stack` | struct decl | Explicit stack allocation (default already) | `parser_main.dlt:344`, `codegen_main.dlt:217` |
| `@heap` | struct decl, fun return type, fun param type, closure type | Force heap allocation; `register_heap_struct(name)` | `parser_main.dlt:346`, `codegen_main.dlt:229` |
| `@transparent` | struct decl | Newtype wrapper around single field; zero-cost | `parser_main.dlt:342`, `codegen_main.dlt:222` |
| `@inline` | fun def | LLVM `alwaysinline` attribute | `codegen_decl.dlt:81` |
| `@noinline` | fun def | LLVM `noinline`. Conflicts with `@inline` | same |
| `@hot` | fun def | LLVM `hot` branch hint | same |
| `@cold` | fun def | LLVM `cold` branch hint. Conflicts with `@hot` | same |
| `@pure` | fun def | LLVM `readnone` (no side effects, no memory reads) | same |
| `@noreturn` | fun def | Function never returns (e.g. `panic` helpers) | same |
| `@deprecated` | fun def, struct decl | Compiler emits warning at use sites | `codegen_decl.dlt:42` |
| `@must_use` | fun def | Compiler errors if return value is discarded | `codegen_decl.dlt:44` |

### `@heap` placement matters

| Position | Meaning | Valid? |
|---|---|---|
| `@heap struct Foo:` | EVERY instance of `Foo` is heap-allocated. The user writes `: Foo` everywhere; constructor calls `Memory.malloc` automatically | ✅ recommended for shared/long-lived structs |
| `fun new() -> @heap T:` | This function returns a heap-allocated T | ✅ |
| `fun take(x: @heap T):` | Param accepts heap T | ✅ |
| `f: @heap fun() = ...` | Closure type is heap-allocated (env on heap) | ✅ required for closures that escape (return, thread spawn) |
| `x: @heap T = ...` (struct var-decl) | **BREAKS METHOD LOOKUP** | ❌ DO NOT use. Codegen searches `@heap T_method` which doesn't exist |
| `x: T = T.new(...)` where `T` is `@heap struct T` | Constructor returns heap, var slot holds the pointer | ✅ correct usage |

### Custom annotations

`annot name = Annot(target=fun, effect="...")` — declares a new
annotation. Defined in `library/core/annotations.dlt`. Parsed at
`parser_decl.dlt:228-385`.

---

## 6. Top-level statements

Dispatched by `parser/parser_main.dlt:34-409` (`parse_statement`).

| Keyword / Token | Form | What it builds |
|---|---|---|
| `const NAME : T = expr` | `parser_main.dlt:43` | NODE_VAR_DECL with const flag |
| `imm NAME : T = expr` | `parser_main.dlt:47` | Same as const (alias) |
| `static NAME : T = expr` | `parser_main.dlt:51` | Module-scope mutable global |
| `static fun NAME(...) ...:` | `parser_main.dlt:53` | Static method outside struct (rare) |
| `mut NAME : T = expr` | `parser_main.dlt:69` | Mutable local |
| `enum Name:` | `parser_main.dlt:84` | Enum decl |
| `trait Name:` | `parser_main.dlt:88` | Abstract method signatures |
| `abstract struct Name:` | `parser_main.dlt:92` | Abstract struct (no instantiation) |
| `struct Name:` | `parser_main.dlt:99` | Struct (with optional dotted name) |
| `impl Name:` | `parser_main.dlt:103` | Method block (Rust style) |
| `extend Name:` / `group Name:` | `parser_main.dlt:107` | Method block (preferred: `group`) |
| `type Alias = T` | `parser_main.dlt:111` | Type alias |
| `fun name(...):` | `parser_main.dlt:121` | Function decl |
| `private fun` / `public fun` / `protect fun` | `parser_main.dlt:125` | Function with visibility |
| `async fun` | `parser_main.dlt:136` | Async function |
| `import std` / `import std.io` / `from std import X` | `parser_main.dlt:183` / `:208` | Module import |
| `use a.b.c` | `parser_main.dlt:196` | Symbol aliasing (no-op currently) |
| `extern "C" fun` | `parser_main.dlt:212` | FFI declaration block |
| `module name` / `export X` / `requires path` | `parser_main.dlt:187` | Skipped at user level (mod.dlt directives) |
| `annot name = Annot(...)` | `parser_main.dlt:261` | Custom annotation decl |
| `@anno1 @anno2 <decl>` | `parser_main.dlt:265` | Annotated declaration |
| `panic("msg")` | parsed as call form | Function-call form (no longer keyword) |

Inside function bodies (statements):
`if`/`elif`/`else`, `while`, `for...in`, `match`/`case`, `break`,
`continue`, `pass`, `return`, plain expressions, assignments.

---

## 7. Struct + method declaration forms

### Struct declaration variants

```dolet
# 1. Plain struct (stack default)
struct Player:
    name: str
    hp: i32

# 2. With methods inside body (since this session)
struct Random:
    _placeholder: i32

    static fun range(min: i32, max: i32) -> i32:
        return ...

    fun method(self):
        ...

# 3. @heap struct — every instance allocated on heap
@heap struct AtomicI32:
    storage: i32

# 4. @transparent struct — newtype wrapper, zero overhead
@transparent struct NodeList:
    ptr: i64

# 5. With type parameters (generics)
struct Box<T>:
    value: T

# 6. With trait bounds
struct Display_Box<T: Display>:
    item: T

# 7. With inheritance
struct Player extends Entity:
    weapon: str

# 8. Composition — namespace nested capabilities through a static field.
# Replaces the removed `struct A.B:` / `extend A.B:` syntax.
struct Secure:
    _placeholder: i32
    static fun range(min: i32, max: i32) -> i32:
        ...

struct Random:
    _placeholder: i32
    static secure: Secure   # type-only; slot never read, just typed
    static fun range(min: i32, max: i32) -> i32:
        ...

# user: Random.secure.range(1, 100) → dispatches to Secure.range(1, 100)
```

### Method block forms (all equivalent in semantics)

```dolet
struct Foo:
    x: i32

# Form A (preferred, new keyword)
group Foo:
    fun method(self) -> i32:
        return self.x

# Form B (legacy alias — same TK_EXTEND token)
extend Foo:
    fun method(self) -> i32:
        return self.x

# Form C (Rust style)
impl Foo:
    fun method(self) -> i32:
        return self.x

# Form D (methods inline in struct body)
struct Foo:
    x: i32

    fun method(self) -> i32:
        return self.x

# Nested namespace
group Outer.Inner:
    static fun greet() -> str:
        return "Outer.Inner.greet"
```

All four forms produce the same MLIR symbol `@Foo_method`. Pick by
style — but `group` is the going-forward keyword.

### Visibility

```dolet
struct Account:
    public name: str            # default
    private balance: i64        # only this struct's methods can read

group Account:
    fun deposit(self, amt: i64):
        self.balance = self.balance + amt   # OK — same struct's method
```

Enforced by `codegen_access.dlt` checking `g_current_struct`. Outside
access compiles to a hard error with file:line.

---

## 8. Method dispatch & name mangling

### Mangling rules

| Form | Mangled name |
|---|---|
| `struct Foo:` `fun bar(self):` | `Foo_bar` |
| `group Foo:` `fun bar(self):` | `Foo_bar` |
| `impl Foo:` `static fun zero():` | `Foo_zero` |
| `Box<T>` after monomorphization with T=i32 | `Box__i32_method` (two underscores between type and arg) |
| `Pair<i32, str>` | `Pair__i32_str` (multiple args joined with `_`) |
| Overload `fun bar(i32)` vs `fun bar(str)` | `Foo_bar__i32` vs `Foo_bar__str` |

**Removed in this version:** `struct A.B:` and `extend/group A.B:` no
longer parse. Use composition (`static b: B` on A) — see Path 3 below.

### Dispatch — `x.method(args)` (instance call)

Resolved in `codegen_access.dlt::gen_inst_method_call` (~line 764):

1. Get `obj_type = get_var_type(obj_name)` — registered var type.
2. Strip generics: `list[i32]` → `list`.
3. **Normalize:** `normalize_type` maps `string` → `str`, `int` → `i32`, etc. (`codegen_core.dlt:1583`).
4. **Pre-pass infer arg types** without emitting MLIR — produces `"i32,str"` style key.
5. `find_impl_method_overload(base_type, mname, pre_arg_types)` picks the right overload.
6. Build `mangled = base_type + "_" + mname`.
7. `resolve_overload(mangled, call_arg_types)` adds suffix if applicable.
8. Emit `llvm.call @<mangled>(%self_ptr, ...args)`.

### Dispatch — `Type.method(args)` (static call)

`codegen_access.dlt::gen_static_method_call` (~line 616):

1. `Type.new(...)` first checks for a user-defined `static fun new`
   on the type via `find_impl_method(Type, "new")`. If found, dispatch
   to it normally. Only if NO custom `new` exists does the codegen
   fall back to the auto-generated struct-instantiation constructor.
   This lets library types do setup (allocate OS state, init fields)
   under the same `.new(...)` ergonomic name.
2. Otherwise: `find_impl_method_overload(Type, mname, ...)` + emit `llvm.call @Type_method(...)` with no implicit self.

### Dispatch — `A.B.method(args)` (3-level / nested)

`codegen_access.dlt::gen_nested_method_call` (~line 158). Three paths
tried in this order:

**Path 1 (legacy formal nested):**
- Build `nested_mangled = A_B_method`.
- If `get_fun_ret_type(nested_mangled) != "unknown"` → call it.
- Dead after the dotted-struct removal but kept for any third-party
  code that still ships an `A_B_method` symbol.

**Path 3 (composition — preferred):**
- A is a struct AND A has a static field `B` of type T (looked up via
  `lookup_static_field_type("A__B")`, validated as a real struct by
  `is_struct_type`).
- AND `T_method` is a registered function.
- Dispatch as `T.method(args)` — a regular static method call on T.
- This is how `Random.secure.range(1, 100)` resolves: Random has
  `static secure: Secure`, and the call lowers to `@Secure_range`.

**Path 2 (legacy leniency):**
- Only when Paths 1 and 3 fail AND both `A` and `B` are top-level
  struct types. Drop `A`, dispatch as `B.method(args)`. Preserved
  for older "decorative qualifier" patterns.

`infer_expr_type` mirrors the same three-path order so the return
type at type-check time matches what gets emitted.

### Overload resolution

`find_impl_method_overload` (`codegen_core.dlt:877-890`):

- Linearly scans the impl-table for methods on `<struct, method-name>`.
- Builds each candidate's param-type signature (sans `self`).
- Picks the one whose signature matches the call's arg types exactly.
- Falls back to `find_impl_method` (first match) if no exact overload.

This is why `list<str>.append(str)` picks the right overload over
`list<i32>.append(i32)` and similar.

### `self` parameter

| Receiver type | `self` MLIR type |
|---|---|
| Struct (`@heap` or stack) | `!llvm.ptr` |
| `i32`/`i64`/`bool`/`char` | value type (`i32`, `i64`, `i1`, `i8`) |
| `str` | `!llvm.ptr` (str is `ptr<i8>`) |

Field access in method body emits
`llvm.getelementptr %self[0, idx]` then `llvm.load`.

---

## 9. Memory model — stack / heap / arena

Three places values can live:

| Mode | Allocator | Lifetime | Default for |
|---|---|---|---|
| **Stack** | LLVM `alloca` | Function frame | Plain `struct`, all local vars |
| **Heap** | `Memory.malloc` (Win32 `HeapAlloc` / Linux `mmap`) | Until explicit `Memory.free` or program exit | `@heap struct`, explicit closures, return-of-string from non-bracketed scope |
| **Arena** | `_scope_arena_alloc` — bump pointer in 16 MiB pool | Until enclosing function returns | String concat results (`+` operator), `Convert.X_to_str` inside bracketed scope |

### Arena bracketing

The codegen "brackets" most user functions:
- On entry: `_scope_arena_push()` saves the cursor.
- On exit: `_scope_arena_pop(handle)` resets cursor to release everything allocated since push.

While bracketed (`g_arena_emit == 1`):
- `a + b` on `str` → `_str_plus(a, b)` — arena allocation
- `Convert.i32_to_str(n)` → `_arena_i32_to_str(n)` — arena allocation
- Returning a `str` from this function → `_str_promote_return(s, parent_handle)` copies the str up to caller's arena before pop

### Function families EXEMPT from arena bracketing

Listed in `codegen_decl.dlt`:

- `Memory_*` — direct memory primitives
- `_scope_arena_*` — arena control itself
- `_str_*`, `_arena_*_to_str` — string runtime
- `Convert_*_to_str` — heap formatters
- `dolet_panic`, `__frame_*`, `__print_stack_trace` — panic infrastructure
- I/O families like `Str_*`, `Convert_*`, `IOOps_*`, `Process_*`

Arena allocation never recurses into these.

### Heap escape rules for strings

| Context | Codegen action |
|---|---|
| `s = a + b` inside bracketed fn | `_str_plus` (arena) |
| `return a + b` inside bracketed fn returning `str` | `_str_promote_return` (arena to caller) |
| Assignment to global `g_x: str = ...` | `_str_heap_dupe` (heap copy, persistent) |
| Assignment to heap struct field | `_str_heap_dupe` |
| `mut str` rebind that previously held a heap-dupe | `_str_heap_free` on the old value |
| `Str.concat(a, b)` (explicit) | Always heap. Caller must `Memory.free`. **NEVER use in user code** |

---

## 10. Strings — primitive `str` vs helper `Str`

### `str` (lowercase) — primitive

- Compiler builtin. `TK_STR_TYPE` keyword. Lowers to `ptr<i8>` (null-terminated bytes).
- Layout: standard C string. `Memory.strlen(s)` for byte length.
- Literal `"hello"` — emitted as a global LLVM string constant in `.rodata`.

### `Str` (uppercase) — helper struct

- Lives in `library/core/string.dlt`.
- Holds static helpers: `Str.to_upper(s)`, `Str.trim(s)`, `Str.parse_i64(s)`, `Str.equals(a, b)`, `Str.concat(a, b)`, etc.
- Each method takes `s: str` as first arg (NOT `self`).

### `group str:` — extension methods

Same file `core/string.dlt`. Wraps every static `Str.X(s)` as `s.X()`:

```dolet
group str:
    fun length(self) -> i64:
        return Memory.strlen(self)
    fun to_upper(self) -> str:
        return Str.to_upper(self)
    # ... ~20 wrappers
```

User syntax:
```dolet
"  hello  ".trim().to_upper()    # "HELLO"
n: i64 = "42".parse_i64()        # 42
```

### The `+` operator

`a + b` on two strs → compiler dispatch to `_str_plus(a, b)`.

### NEVER

| Don't | Why |
|---|---|
| `Str.concat(a, b)` in user code | Always heap-allocates; if you forget `Memory.free`, leaks |
| Define your own `_str_X` function | Reserved compiler intrinsic name |
| Modify a str returned from a function (no mutability for strs) | Strs are immutable arrays of bytes |

---

## 11. Closures (`fun(args) -> ret`)

Status: phases 1, 2, 2.5, 3 shipped. Source: `codegen/codegen_mono.dlt`.

### Syntax forms

```dolet
# Single-expression body (no colon, just expr after type)
add_one: fun(i32) -> i32 = fun(x: i32) -> i32 x + 1

# Multi-arg
mul: fun(i32, i32) -> i32 = fun(a: i32, b: i32) -> i32 a * b

# Type as parameter / return
fun apply(f: fun(i32) -> i32, n: i32) -> i32:
    return f(n)

# Heap closure (escape required)
fun make_adder(n: i32) -> @heap fun(i32) -> i32:
    return fun(x: i32) -> i32 x + n
```

### Capture analysis

A free var inside the lambda body is captured if it is:
- not a lambda param
- not declared inside the lambda body (`g_lift_locals` tracks these)
- not a top-level function name
- not a global var

Otherwise: captured. Captured names are inferred from enclosing fn's
locals.

### Runtime ABI

**Stack closure** (default): generates `__lambda_N_env` struct
- Field 0: `__fn: ptr` (function pointer to lifted `__lambda_N`)
- Field 1+: captures, each as `i64` (smaller types extended)

**Heap closure** (`@heap fun()`): factory `__lambda_N_make(captures...)`
mallocs `[fn_ptr, cap1, cap2, ...]` and returns `ptr`.

**Call**: `f(args)` → load fn_ptr from offset 0 of env, call
`fn_ptr(env_ptr, args)`.

### `@heap` is REQUIRED when

- Returning a closure from a function (compiler error if missing: "closure escapes via return; mark return type with `@heap`")
- Passing a closure to `Thread.spawn(...)` (signature is `fun spawn(f: @heap fun()) -> Thread`)

### `@heap` is OPTIONAL when

- Closure used only within its defining function (stack form is fine, faster)

---

## 12. Generics — built-in & user-defined

### Built-in generics (compiler-known, mostly @transparent in stdlib)

| Type | Form | Notes |
|---|---|---|
| `option<T>` | `Some(x)`, `None()` constructors | Lowercase. **Polymorphic** — `Some(42)` infers T from context |
| `result<T, E>` | `Ok(x)`, `Err(e)` | Lowercase. Same polymorphic dispatch |
| `list<T>` | `[]` literal, `.append`, `.size`, `.get_T(i)` | Heap-allocated dynamic array |
| `array<T>` | `[size]T(...)` | Fixed-size |
| `map<K, V>` | `{}` literal, `.get`, `.set` | Hash map |

### Polymorphic constructors

```dolet
a: option<i64> = Some(42 as i64)     # picks Some__i64
s: option<str> = Some("hello")       # picks Some__str
n: option<i64> = None()              # type-erased; assignable to any option<T>

ok: result<i64, str> = Ok(99 as i64)
err: result<i64, str> = Err("oops")
```

### Type-suffixed unwrap (no implicit unwrap until B3 phase 5)

```dolet
a: option<i64> = Some(42 as i64)
n: i64 = a.unwrap_i64()              # generic methods: unwrap_i64, unwrap_str, unwrap_bool, unwrap_i32, unwrap_f64
fb: i64 = a.unwrap_or_i64(99 as i64)
```

### Pattern match

```dolet
r: result<i64, str> = parse_pos("42")
match r:
    case Ok(v):                  # v binds the i64 payload
        print(v)
    case Err(m):                 # m binds the str
        print(m)
```

### User-defined generics (B3 phase 1-4.5 shipped)

```dolet
struct Box<T>:
    value: T

# Method block on generic struct
group Box:
    fun get(self) -> T:
        return self.value

# Constructor / use site
b: Box<i32> = Box<i32>(value=42)
print(b.get())                       # 42

# Generic function
fun pack<T>(x: T) -> Box<T>:
    return Box<T>(value=x)

a: Box<str> = pack<str>("hello")

# Trait bounds (must implement all methods on bound trait)
struct DisplayBox<T: Display>:
    item: T
```

### Monomorphization key (`canon_if_gen`)

`Box<i32>` → `Box__i32`
`Pair<i32, str>` → `Pair__i32_str`
`Box<Box<i32>>` → `Box__Box__i32` (recursive flatten)

### NOT YET SHIPPED

- B3 Phase 5: migrating Option/Result built-ins into stdlib.
  Deferred — would degrade `None()` polymorphism for marginal gain.

---

## 13. Module system (`load`/`expose`/`export`/`requires`/`module`)

| Directive | Where allowed | Effect | Path style |
|---|---|---|---|
| `module name` | Top of `mod.dlt` only | Registers module name for dispatch (`register_module_name`) | dotted (`sys.windows`) |
| `load path/to/file` | `mod.dlt` only | Triggers parsing/inclusion of that `.dlt` file. Name relative to `library/`, no `.dlt` suffix | **slash** (`core/memory`) |
| `expose path/to/X as alias` | `mod.dlt` | When user writes `import std.alias`, resolves to that path | slash (LHS), bare ident (alias) |
| `export Symbol` | `mod.dlt` | **Documentation only**. Does NOT gate visibility | bare ident |
| `requires path/to/file` | Top of regular `.dlt` files | Forces dependency to load before this file. Recursively resolved | slash |
| `import std` / `import std.io` / `from std import X` / `import std.[a, b]` | User files | Resolves via registry + expose lines | dotted in source, slashes after resolution |

### Boot sequence (executed by `driver/doletc_driver.dlt:1609`)

```
1. init_pipeline() — registries, constants
2. parse CLI args
3. load_platform_config()                  — reads platform/<name>/platform.conf
4. load_library_registry()                  — reads library/mod.dlt
5. load_prelude(exe_dir)                    — library/core/annotations.dlt
6. (unless --no-runtime) load_runtime():
     - library/core/mod.dlt
     - library/platform/<name>/mod.dlt
     - library/std/mod.dlt
     register_module_name("std")
7. resolve_and_load_imports(user_src)       — user `import` statements
8. tokenize → parse → MLIR → LLVM IR → obj → exe
```

### Auto-loaded WITHOUT `import std`

- everything under `library/core/` (via `core/mod.dlt`)
- everything under `library/platform/<host>/` (via platform mod.dlt)

### Requires `import std` to use

- `library/std/io.dlt` (provides `print`, `println`, `flush`)
- `library/std/file.dlt` (`File.open`, `Dir.list`, etc.)
- `library/std/system.dlt` (`Args.get`, `Process.exit`, `System.cwd`)
- `library/std/thread.dlt` (`Thread.spawn`)

### Adding a new file `library/core/foo.dlt`

1. Create the file. Add `requires core/memory` if needed.
2. Edit `library/core/mod.dlt`: add `load core/foo` line.
3. Add `export Foo` if you want it documented.
4. Build twice if a new keyword/syntax was used (see §19 Bootstrap dance).

---

## 14. Compiler intrinsics (RESERVED NAMES)

These names are recognized by the codegen and inserted automatically.
**Do not redefine. Do not rename.**

### Atomic intrinsics — `library/core/atomic.dlt` calls these

| Name | Signature | Lowering |
|---|---|---|
| `__atomic_load_i32` | `(i64) -> i32` | `llvm.load atomic seq_cst` |
| `__atomic_load_i64` | `(i64) -> i64` | same |
| `__atomic_store_i32` | `(i64, i32)` | `llvm.store atomic seq_cst` |
| `__atomic_store_i64` | `(i64, i64)` | same |
| `__atomic_fetch_add_i32` | `(i64, i32) -> i32` | `llvm.atomicrmw add` |
| `__atomic_fetch_add_i64` | `(i64, i64) -> i64` | same |
| `__atomic_fetch_sub_i32` | `(i64, i32) -> i32` | `llvm.atomicrmw sub` |
| `__atomic_fetch_sub_i64` | `(i64, i64) -> i64` | same |
| `__atomic_swap_i32` | `(i64, i32) -> i32` | `llvm.atomicrmw xchg` |
| `__atomic_swap_i64` | `(i64, i64) -> i64` | same |
| `__atomic_cas_i32` | `(i64, i32, i32) -> bool` | `llvm.cmpxchg seq_cst` |
| `__atomic_cas_i64` | `(i64, i64, i64) -> bool` | same |

Lowered in `codegen/codegen_access.dlt::gen_atomic_intrinsic` (~line 379).

### String runtime intrinsics — `library/core/str.dlt`

| Name | Inserted when |
|---|---|
| `_str_plus(a, b) -> str` | `+` operator on str inside bracketed scope |
| `_str_dupe(a) -> str` | Implicit arena copy |
| `_str_heap_dupe(a) -> str` | Assignment to global / heap struct field |
| `_str_heap_free(p) -> ()` | Mut str rebind that frees previous heap-dupe |
| `_str_promote_return(s, handle) -> str` | Returning str from bracketed scope |

### Arena intrinsics — `library/core/arena.dlt`

| Name | When emitted |
|---|---|
| `_scope_arena_init` | Lazy on first arena use |
| `_scope_arena_push() -> i64` | Entry of bracketed function (returns handle) |
| `_scope_arena_pop(handle)` | Exit of bracketed function |
| `_scope_arena_alloc(size) -> i64` | By `_str_plus`, `_arena_*_to_str` |
| `_arena_i32_to_str(n) -> str` | `Convert.i32_to_str(n)` inside bracketed scope |
| `_arena_i64_to_str(n) -> str` | `Convert.i64_to_str(n)` same |
| `_arena_bool_to_str(b) -> str` | `Convert.bool_to_str(b)` same |

### Panic / debug intrinsics — `library/std/panic.dlt`

| Name | Purpose |
|---|---|
| `dolet_panic(msg)` | `panic(...)` lowers to a call to this; prints, exits 101 |
| `__frame_init` | Lazy init of frame stack (1024 slots) |
| `__frame_push(name, file)` | Injected at entry of every non-exempt fn when `--debug` |
| `__frame_pop` | Injected at exit |
| `__print_stack_trace` | Called from `dolet_panic` — walks frames |

### Closure / thread intrinsics

| Name | Purpose |
|---|---|
| `__lambda_N` | Lifted lambda body (top-level fn generated per closure) |
| `__lambda_N_env` | Stack-form env struct |
| `__lambda_N_make(...)` | Factory for heap-form closure |
| `__thread_entry(env: i64) -> i32` | `Thread.spawn`'s shim for Win32 `CreateThread` |

---

## 15. Threading & atomics

### Atomics — `library/core/atomic.dlt`

Currently:
- `AtomicI32`, `AtomicI64` — separate structs (until generics-aware mangling)
- Both are heap-allocated (storage address must stay stable)
- Methods: `.load()`, `.store(v)`, `.fetch_add(d)`, `.fetch_sub(d)`, `.swap(v)`, `.cas(expected, desired)`

Usage:
```dolet
counter: AtomicI32 = AtomicI32.new(0)
counter.fetch_add(1)
counter.cas(0, 1)
counter.load()
```

### Threads — `library/std/thread.dlt`

```dolet
import std

f: @heap fun() = fun() print("worker hello")
t: Thread = Thread.spawn(f)
t.join()                   # block until thread exits
Thread.sleep(100)          # ms
Thread.yield_now()
id: i32 = Thread.current_id()
```

`Thread` is small (just an i64 handle) — stays stack-allocated.

### Mutex — `library/std/mutex.dlt`

```dolet
m: Mutex = Mutex.new()         # allocates 40-byte CRITICAL_SECTION + Initialize
m.lock()
shared = shared + 1            # critical section
m.unlock()

# Or closure form — exception-safe, can't forget unlock:
body: @heap fun() = fun(): shared = shared + 1
m.with(body)

# Non-blocking probe:
if m.try_lock():
    ...
    m.unlock()

m.destroy()                    # release OS state + free buffer
```

`@heap struct Mutex` — the OS handle needs a stable address across
thread spawns. Backed by Win32 `EnterCriticalSection` (uncontended
~10 ns, single CMPXCHG); pthread_mutex on Linux is a future task.

### Pending (not shipped)

- `RwLock`
- `Channel<T>` — message passing
- `Atomic<T>` generic (pending generics-aware mangling)
- Memory ordering (Acquire/Release/Relaxed); currently only SeqCst
- Linux pthread_mutex backing for Mutex

---

## 16. Error handling — `Option`, `Result`, `?`, `panic`

### Option — `library/core/option.dlt`

```dolet
a: option<i64> = Some(42 as i64)
b: option<str> = None()

if a.is_some():
    print(Convert.i64_to_str(a.unwrap_i64()))

# Pattern match
match a:
    case Some(x):  print(x)
    case None:     print("nothing")
```

Methods: `.is_some()`, `.is_none()`, `.unwrap_<T>()`, `.unwrap_or_<T>(default)`.

### Result — `library/core/result.dlt`

```dolet
fun parse_pos(s: str) -> result<i64, str>:
    n: i64 = Str.parse_i64(s)
    if n < 0 as i64:
        return Err("negative")
    return Ok(n)

r: result<i64, str> = parse_pos("42")
if r.is_ok():
    print(Convert.i64_to_str(r.unwrap_i64()))
else:
    print(r.unwrap_err_str())
```

### `?` postfix operator (B2 shipped)

```dolet
fun chain(s: str) -> result<i64, str>:
    n: i64 = parse_pos(s)?       # if Err, propagates immediately
    return Ok(n + 1 as i64)
```

Desugaring: `expr?` → load tag, branch on err, return err early; on
ok, extract payload as the expression's value.

### `panic`

```dolet
panic("unrecoverable: " + reason)
```

- Lowers to `dolet_panic(msg)` (`codegen_stmt.dlt:936`)
- Prints `[panic at FILE:LINE] <msg>` and exits 101 (Rust convention)
- With `--debug`: prints stack trace via `__print_stack_trace`
- Codegen emits `llvm.unreachable` after the call so MLIR is happy

---

## 17. Library layout

```
library/
├── mod.dlt                           # registry: name → path mappings
│
├── core/                             # AUTO-LOADED, platform-independent
│   ├── annotations.dlt               # @heap, @stack, @transparent... declarations
│   ├── memory.dlt                    # Memory struct (read/write helpers)
│   ├── arena.dlt                     # _scope_arena_* helpers
│   ├── str.dlt                       # _str_* compiler runtime
│   ├── string.dlt                    # struct Str + group str (user-facing)
│   ├── atomic.dlt                    # AtomicI32, AtomicI64
│   ├── option.dlt                    # option<T> built-in generic
│   ├── result.dlt                    # result<T, E> built-in generic
│   ├── collections.dlt               # list/array/map operations
│   ├── integers.dlt                  # I8, I16, I32, I64, I128, U8...U128
│   ├── floats.dlt                    # F32, F64
│   ├── primitives.dlt                # Bool, Char, Pointer
│   ├── math.dlt                      # Math functions
│   ├── random/
│   │   ├── random.dlt                # struct Random (LCG default) + static `secure: Secure`
│   │   └── secure.dlt                # struct Secure (SplitMix64); reached via Random.secure
│   └── mod.dlt                       # core load orchestrator
│
├── platform/
│   ├── windows/                      # AUTO-LOADED on Windows targets
│   │   ├── kernel32.dlt              # Win32 FFI (incl. CRITICAL_SECTION for Mutex)
│   │   ├── alloc.dlt                 # Memory.malloc via HeapAlloc
│   │   ├── format.dlt                # number → str via Win32 helpers
│   │   ├── io.dlt                    # console I/O
│   │   ├── file.dlt                  # CreateFileA wrappers
│   │   ├── process.dlt               # CreateProcessA, run_capture
│   │   ├── path.dlt
│   │   ├── args.dlt
│   │   ├── dir.dlt
│   │   ├── time.dlt
│   │   ├── platform.conf             # toolchain config
│   │   ├── resources/                # runtime_helpers.obj, kernel32.def/lib, etc.
│   │   └── mod.dlt
│   └── linux/ (mirror, mostly stubbed)
│
└── std/                              # OPT-IN via `import std`
    ├── io.dlt                        # print, println, IOOps
    ├── file.dlt                      # File, Dir
    ├── system.dlt                    # System, Args, Command, Output
    ├── thread.dlt                    # Thread.spawn / join / sleep
    ├── mutex.dlt                     # Mutex (CRITICAL_SECTION-backed)
    ├── panic.dlt                     # dolet_panic, __frame_*
    ├── time.dlt                      # Time helpers
    ├── async/                        # EventLoop, Task, JoinHandle
    ├── net/                          # TCP/UDP wrappers (WIP)
    └── mod.dlt
```

### Layering rules

- `core/` → no OS calls, no FFI. Pure CPU primitives.
- `platform/<os>/` → only OS-specific stuff. Has `extern` blocks for syscalls/Win32.
- `std/` → can use both. User-facing API.

If string/numeric operation is platform-independent → it goes in
`core/`. Don't duplicate per-platform.

---

## 18. Compiler driver & build pipeline

### CLI flags (`driver/doletc_driver.dlt:1643`)

| Flag | Effect |
|---|---|
| `-o <path>` | Output executable path |
| `--target <name>` | Reads `library/platform/<name>/platform.conf` (default: detected) |
| `--keep-mlir` | Don't delete `.mlir` after build |
| `--keep-llvm` | Don't delete `.ll` after build |
| `--no-runtime` | Skip auto-loading core/platform/std |
| `--no-console` | Build as GUI (no console window) |
| `--debug` | Emit stack-trace instrumentation (`__frame_push`/`pop` per fn) |
| `--validate` | Enable codegen validation layer (default ON) |
| `--no-validate` | Skip validation (faster, less safe) |
| `--release` | (Implies --no-console + --no-validate) |
| `--tree-shake` | Enable dead-code elimination |
| `--version` | Print version and exit |

### Pipeline (`main()` at `doletc_driver.dlt:1609`)

```
1. Read user .dlt file
2. Auto-load runtime (prelude + core/mod + platform/mod + std/mod)
3. Resolve user `import` statements transitively
4. Concatenate everything into single `source` string
5. [1/4] Tokenize  → out_kinds, out_values, out_indents, out_lines
6. [2/4] Parse     → AST (root_ast)
7. [3/4] Codegen   → MLIR text (write to .mlir file)
8. [4/4] Build:
     mlir-translate <input>.mlir → <input>.ll
     clang -c <input>.ll        → <input>.obj
     lld-link <input>.obj      → <output>.exe
9. Cleanup intermediates (unless --keep-mlir / --keep-llvm)
```

### File extensions per platform

| Platform | obj_ext | exe_ext | linker |
|---|---|---|---|
| Windows | `.obj` | `.exe` | `lld-link` |
| Linux | `.o` | (none) | `ld.lld` |

---

## 19. Bootstrap dance — when adding language features

The compiler is self-hosted. `bin/doletc.exe` was built from a
previous version of the source. If a new language feature is added,
the existing `bin/doletc.exe` doesn't know it yet.

### Two-step bootstrap pattern (verified in this session)

When you add NEW SYNTAX (new keyword, new annotation form, etc.):

```
Step 1 — Build with feature in compiler source but NOT used in stdlib:
  - Edit lexer/parser/codegen to teach the new feature.
  - Stdlib stays on OLD syntax.
  - Run build.bat — stage 1 (existing doletc.exe) compiles new compiler source. ✓
  - Stage 2/3 — new doletc compiles itself. ✓
  - Now bin/doletc.exe knows the new feature.

Step 2 — Migrate stdlib to use the new feature:
  - Edit stdlib files to use the new syntax.
  - Run build.bat — stage 1 (new doletc.exe with feature support) compiles. ✓
  - Stage 2/3 byte-stable. ✓
```

**Real example from this session — `extend` → `group` rename:**

1. Lexer added: `if str_eq(name, "group") == 1: return TK_EXTEND`.
2. Built once. Now `bin/doletc.exe` recognizes both `extend` and `group`.
3. Mass-renamed `^extend ` → `^group ` in 25 files.
4. Built again. Stage 1→2→3 byte-stable.

### Bootstrap stages (`build.bat`)

```
[0/3] Generate pipeline_build.dlt by concatenating compiler sources (Python script).
[1/3] bin/doletc.exe   <pipeline_build.dlt>   →  bin/doletc2.exe
[2/3] bin/doletc2.exe  <pipeline_build.dlt>   →  bin/doletc3.exe
[3/3] copy doletc3.exe → bin/doletc.exe (final).
```

`doletc2.exe` and `doletc3.exe` must produce byte-identical output. If
they differ, the new compiler miscompiles itself somewhere — halt and
bisect immediately.

### Python bootstrap (stage 0)

`bootstrap/doletc.py` — Python implementation of Dolet that can compile
the full self-hosted compiler. Used only when:
- bin/doletc.exe doesn't exist
- bin/doletc.exe is broken

Has known limitations (e.g. doesn't implement every recent feature).
The self-hosted `bin/doletc.exe` is the source of truth.

---

## 20. Common pitfalls (verified from past sessions)

### `struct A.B:` and `extend/group A.B:` are REJECTED

```dolet
struct Random.Secure:   # ❌ parser panics with a hint
    ...
extend Random.Secure:   # ❌ same
group Random.Secure:    # ❌ same
```

The dotted-struct syntax conflated "namespace" with "type" and the
compiler had to invent name-mangling rules to make it work. Use
composition instead:

```dolet
struct Secure:                # ✓ regular top-level struct
    static fun range(...): ...

struct Random:
    static secure: Secure     # ✓ static field — type-only, no init
    static fun range(...): ...

# At call sites: Random.secure.range(1, 100) dispatches through
# the codegen's Path 3 to Secure.range(1, 100) — same ergonomics,
# no special parser/mangler magic.
```

### `@heap` on var-decl breaks method lookup

```dolet
counter: @heap AtomicI32 = AtomicI32.new(0)    # ❌ wrong
counter: AtomicI32 = AtomicI32.new(0)          # ✓ right
```

The codegen registers the var's type as the literal annotation string.
`get_var_type("counter")` returns `"@heap AtomicI32"`. Method dispatch
then searches `@heap AtomicI32_method` — never matches anything.

**Workaround:** drop `@heap` from var-decl. Mark the struct itself
`@heap struct AtomicI32:` so the compiler knows to heap-allocate at
constructor time without the user typing `@heap` everywhere.

### `module path/to/x` (slashes) in user code → ERROR

```dolet
module core/random/mod    # ❌ won't parse
module core.random.mod    # ✓ dotted
```

In `mod.dlt` files: slashes in `load`/`expose` paths.
In `module` directives + user `import`s: dots.

### `double` and `string` are reserved type aliases

```dolet
fun double(x: i32) -> i32:    # ❌ TK_TYPE conflict
    return x * 2
```

`int`, `float`, `double`, `string` are tokenized as `TK_TYPE` (aliases
for i32/f32/f64/str). Don't use as identifiers. Pick `times_two`,
`val_str`, etc.

### `@heap fun()` on closure — required when closure escapes

```dolet
fun make_adder(n: i32) -> fun(i32) -> i32:    # ❌ stack closure escapes — UAF
fun make_adder(n: i32) -> @heap fun(i32) -> i32:   # ✓
```

Compiler emits explicit error message pointing at the fix.

### `Str.concat()` heap-allocates — leaks if you forget to free

```dolet
s: str = Str.concat(a, b)    # ❌ s is a heap pointer
                              #    Memory.free(s as i64) required eventually
s: str = a + b               # ✓ arena-allocated, freed automatically on scope exit
s: str = a.concat(b)         # ✓ same as above (group str method delegates to + via _str_plus)
```

### Lambda capture analyzer doesn't see locals declared inside lambda body

If a `var: T = ...` line inside a lambda body is misread as a free var,
add it to `g_lift_locals` BEFORE running the capture analyzer. This was
fixed mid-2026 — verify if reproducing.

### Mass-rename of compiler-source keyword needs 2 builds

See §19 bootstrap dance. Don't try to rename in one step.

### Don't assume `import std` is needed

`core/` is auto-loaded. If you only use `Memory.X`, `Convert.X`,
`Random.X`, `Str.X`, `AtomicI32.X` — no `import std` needed.

You DO need `import std` for: `print`, `println`, `File`, `Args`,
`System`, `Thread`, `Process`.

---

## 21. Test-runner & verification protocol

### Quality bar (from ROADMAP.md §66)

After ANY change to compiler or stdlib:

1. **Bootstrap byte-stable**: `build.bat` produces stage 2 ≡ stage 3.
2. **No test regressions**: `run_tests.bat` reports `94 PASS / 0 FAIL`.
3. **All 4 user apps rebuild**: simple-app-eqoi, FileManager, DisplayManager, DesktopShell.

### Test layout (`run_tests.bat`)

| Dir | Style |
|---|---|
| `tests/features/test_NN_*.dlt` | Feature tests (one per major language feature) |
| `tests/e2e/*.dlt` | End-to-end tests |
| `tests/<name>.dlt` | Top-level tests (panic_basic, str_split, generic_box, closures_*, atomic_counter, thread_basic, random_basic, nested_namespace, etc.) |
| `tests/visibility_fail_*.dlt` etc. | TESTS THAT MUST FAIL TO COMPILE — runner inverts the assertion |

### Manual run

```
cmd.exe /c run_tests.bat
```

Look for `Results: <pass> PASS / <fail> FAIL` at the end.

### When regressions appear

1. Don't commit the breaking change.
2. Bisect by commenting out recent edits.
3. If bootstrap produces stage 2 ≠ stage 3, miscompilation — halt and
   bisect IMMEDIATELY (later commits build on broken state).

---

## Appendix: complete keyword list

From `lexer/tokenizer.dlt:380-501`:

```
if elif else while for break continue
fun return struct enum trait impl extends
self super import from extern use
match case in to step as is
const static mut imm
public private protect abstract
async await pass extend group
module export requires type
true false null
and or not stack annot
int float double string         (type aliases, treated as TK_TYPE)
i8 i16 i32 i64 i128
u8 u16 u32 u64 u128
f32 f64
str char ptr
list array map
```

Legacy alias: `imple` → `TK_IMPL`, `extend` → `TK_EXTEND` (preferred:
`group`).

---

**End of AGENTS.md.** Update this file in any PR that changes:
- a keyword
- an annotation
- a calling convention or ABI
- a stdlib structure (file moved, struct renamed)
- a build step

The doc is only useful while it matches reality. Stale doc costs more
than no doc.
