# Dolet Compiler Roadmap

> Living document. Each item below is a self-contained work package.
> Pick one per session, follow the detailed plan, ship it, tick it off.
> Designed so a future session can resume cold from this file alone.

## Status Legend

- ⬜ **TODO** — not started
- 🟡 **IN PROGRESS** — partially done, see notes
- ✅ **DONE** — shipped, verified, in main
- ⏸️ **BLOCKED** — waits on another item; arrow points to blocker
- ❌ **WONTDO** — explicitly rejected with reason

## Quality Bar (applies to every item)

1. **No temporary solutions** — if it can't be done right, defer it.
2. **Self-host stable** — `./build.bat` stage 1 → 2 → 3 must produce
   byte-identical binaries before declaring an item DONE.
3. **No regressions** — `system_smoke.exe`, `output_smoke.exe`, and
   all four user apps (simple-app-eqoi, FileManager, DisplayManager,
   DesktopShell) rebuild cleanly after each item.
4. **Strong tests** — every new feature ships with at least one
   focused test in `tests/` that exercises the happy path AND one
   error path.
5. **Clear error messages** — failures must point at file:line and
   say what's wrong, not just `Error: codegen failed`.

## Tier-Order Index

| Tier | Items | Total Estimate | When |
|---|---|---|---|
| **1. Foundation** | A1 panic · A2 visibility · A3 validation · A4 error-tests | 1 session | Next session |
| **2. Type System** | B1 Result/Option · B2 `?` · B3 user-generics | 4-7 sessions | After Tier 1 |
| **3. Major Features** | C1 closures · C2 DWARF · C3 threading · C4 incremental | 20+ sessions | Long-term |
| **4. Platform Parity** | D1 Linux pipes | 1-2 sessions | When Linux box available |

---

# Tier 1 — Foundation

These four items have small surface area, high long-term ROI, and
unblock subsequent work. Tackle in order.

---

## A1. `panic` keyword ✅

**Shipped.** `panic "msg"` parses, lowers to `dolet_panic(msg)` which
prints `[panic] msg` and exits 101. Function-call form `panic(...)`
left intact for compiler internals (parser/codegen `fun panic`).

**Why now:** Today the convention is `print("...") + Process.exit(1)`
which is verbose, has no source location, and is easy to forget.
A real `panic` keyword is the foundation for `?` operator
desugaring (Tier 2) and the validation layer's failure path (A3).

**Estimate:** 1 short session (~45 min including bootstrap iterations).

**Dependencies:** none.

### Files to modify

| File | Change |
|---|---|
| `lexer/tokenizer.dlt` | Add `TK_PANIC` constant + add `panic` to `resolve_keyword` |
| `parser/ast_nodes.dlt` | Add `NODE_PANIC` constant + builder `mk_panic(msg, line)` + accessor |
| `parser/parser_stmt.dlt` | Parse `panic "message"` statement (consume TK_PANIC + TK_STRING) |
| `codegen/codegen_stmt.dlt` | Emit `print(formatted_msg)` + `Process.exit(101)` |
| `codegen/codegen_main.dlt` | If gen_stmt sees NODE_PANIC, dispatch to handler |
| `library/std/mod.dlt` | (No change — `Process` already exported) |
| `tests/panic_basic.dlt` | New test |
| `README.md` | Document under "Error model" section |

### Detailed implementation

#### 1. Token (lexer/tokenizer.dlt)

Find `TK_RETURN: i32 = 78` block. Add:

```dolet
TK_PANIC: i32 = NN   # pick next free number, check existing TK_* constants
```

In `resolve_keyword` (line 371), add (alphabetical with the rest):

```dolet
if str_eq(name, "panic") == 1:
    return TK_PANIC
```

#### 2. AST node (parser/ast_nodes.dlt)

Add the node type constant (find existing `NODE_*` constants, pick next free number):

```dolet
NODE_PANIC: i32 = NN
```

Builder + accessors:

```dolet
fun mk_panic(msg: str, line: i32) -> i64:
    n: i64 = alloc_node(NODE_PANIC)
    Memory.write_i64(n + 8, msg as i64)    # message (str literal)
    Memory.write_i32(n + 16, line)          # source line for error msg
    return n

fun panic_msg(n: i64) -> str:
    return Memory.read_i64(n + 8) as str

fun panic_line(n: i64) -> i32:
    return Memory.read_i32(n + 16)
```

#### 3. Parser (parser/parser_stmt.dlt)

In the statement dispatch (find where `TK_RETURN` is handled). Add:

```dolet
if cur_kind() == TK_PANIC:
    saved_line: i32 = cur_line()
    advance()                              # consume 'panic'
    if cur_kind() != TK_STRING:
        parse_error("panic requires a string literal")
    msg: str = cur_val()
    advance()                              # consume the string
    return mk_panic(msg, saved_line)
```

Don't accept arbitrary expressions — keep it simple, `panic "msg"` only
for v1. Format-string panic (`panic "value was {x}"`) is a follow-up.

#### 4. Codegen (codegen/codegen_stmt.dlt)

In the statement dispatcher, add a branch on NODE_PANIC. Look at how
NODE_RETURN is emitted for the pattern. Generate:

```mlir
; Emit a global string constant for the formatted panic message
@.panic_msg_NN = private constant [...] = "[panic at FILE:LINE] MESSAGE\n\00"

; In the statement body:
%addr = llvm.mlir.addressof @.panic_msg_NN : !llvm.ptr
llvm.call @print(%addr) : (!llvm.ptr) -> ()
llvm.call @Process_exit(%c101) : (i32) -> ()
llvm.unreachable
```

Use the existing string-literal emission helper (find how `print("...")`
literals are emitted today — there's a global-string allocator in
codegen_core.dlt).

The `[panic at FILE:LINE]` prefix is built at codegen time using:
- `g_current_file` (track file path during compilation — already
  recorded somewhere in driver)
- `panic_line(node)` from the AST

If `g_current_file` doesn't exist, add it now: a global str set in
the driver at compilation start. Cheap and useful for many future
features.

#### 5. Test (tests/panic_basic.dlt)

```dolet
import std

# This should print the panic message and exit with code 101
panic "this is a test panic"
print("UNREACHABLE — should not print")
```

Verification (in `run_tests.bat` or by hand):

```bash
./bin/doletc.exe tests/panic_basic.dlt -o /tmp/p.exe --target windows
./tmp/p.exe ; echo "exit=$?"
# Expected output:
# [panic at tests/panic_basic.dlt:5] this is a test panic
# exit=101
```

#### 6. README

Add a short section under "Language Features":

```markdown
## Error Model

- Recoverable errors: return `Result<T, E>` (see Tier 2).
- Unrecoverable errors: `panic "message"` — prints `[panic at FILE:LINE] message`
  to stdout and exits with code 101 (matches Rust convention).
```

### Edge cases

- `panic` inside a function with non-`void` return type: codegen
  emits `llvm.unreachable` after the exit call so MLIR doesn't
  complain about missing return.
- `panic` at top-level: same handling, `unreachable` after exit.
- Empty string `panic ""`: allowed, prints just the location prefix.
- Multi-line message: not supported in v1 — keep it as a single
  string literal.

### Verification checklist

- [ ] `panic "x"` parses without error
- [ ] `panic` outside a string literal gives a clear parse error
- [ ] Generated MLIR has the global string + call + exit + unreachable
- [ ] Bootstrap stage 1 → 2 → 3 byte-stable
- [ ] `system_smoke.exe` and `output_smoke.exe` unchanged
- [ ] `tests/panic_basic.dlt` exits 101 with expected message
- [ ] All four user apps rebuild

---

## A2. Visibility enforcement at codegen ✅

**Shipped.** Private/protected access is now a hard compile-time error
for fields AND methods. The parser writes the access modifier at the
new offset +88 of NODE_FUN_DEF (NODE_SIZE bumped from 88 to 96).
Codegen reads via `Memory.read_i64(node + 88)` with null-guard.

**Why now:** Parser already parses `public` / `private` / `protected`
and stores access on `NODE_STRUCT_FIELD` at offset +40. Codegen
ignores it. Anyone can read a "private" field via `Memory.read_i64`
or even via `obj.private_field`. This guts the usefulness of access
modifiers entirely.

**Estimate:** 1 short session (~1 hour). Mostly tracking
`g_current_struct` and a check at field-access sites.

**Dependencies:** none. (A1 not required, but A1 first lets us use
`panic "..."` for the access-violation error message.)

### Files to modify

| File | Change |
|---|---|
| `codegen/codegen_core.dlt` | Add global `g_current_struct: str` (init "") |
| `codegen/codegen_decl.dlt` | In `gen_method_def`: save → set `g_current_struct` to the impl's struct → restore on exit. Same for `gen_fun_def` if needed. |
| `codegen/codegen_access.dlt` | In `gen_field_access`, `gen_nested_field`, `gen_inst_method_call`, `gen_static_method_call`, `gen_nested_method_call`: read `sfield_access` / method's access; if `private`, fail unless `g_current_struct == owning_struct` |
| `codegen/codegen_types.dlt` | Mirror the check in `infer_expr_type` for field access (so type errors also respect privacy) |
| `parser/ast_nodes.dlt` | Add `mfield_access(method_node)` accessor if not present (for method-level visibility) |
| `tests/visibility.dlt` | New test exercising both allowed and rejected access |

### Detailed implementation

#### 1. Track current struct context

In `codegen/codegen_core.dlt`:

```dolet
g_current_struct: str = ""
```

In `codegen/codegen_decl.dlt`, find `gen_method_def` (around line 200).
At the top of the function:

```dolet
fun gen_method_def(method_node: i64, owning_struct: str):
    saved_struct: str = g_current_struct
    g_current_struct = owning_struct
    # ... existing body ...
    g_current_struct = saved_struct       # restore on exit (any return path)
```

For `static fun` methods, the same applies — they belong to a struct.

For top-level (`fun foo(...)` not inside a struct), `g_current_struct`
stays "" — meaning "outside any struct".

#### 2. Field access check

In `codegen/codegen_access.dlt`, find `gen_field_access` (NODE_FIELD_ACCESS
handler). Get the field's owning struct + the access modifier:

```dolet
# obj_name comes from node + 8, field_name from node + 16 (existing logic)
obj_type: str = get_var_type(obj_name)            # struct name
field_node: i64 = lookup_field(obj_type, field_name)
field_acc: str = sfield_access(field_node)         # "public" / "private" / "protected"

if str_eq(field_acc, "private") == 1:
    if str_eq(g_current_struct, obj_type) == 0:
        msg: str = "private field '" + field_name + "' of struct '" + obj_type
        msg = msg + "' cannot be accessed from outside (current scope: '"
        if str_eq(g_current_struct, "") == 1:
            msg = msg + "<top-level>"
        else:
            msg = msg + g_current_struct
        msg = msg + "')"
        # Use panic if A1 done, otherwise print + exit
        print(msg)
        Process.exit(1)
```

Repeat the same check in:
- `gen_nested_field_ptr` for `a.b.c` chains (check each hop)
- `gen_inst_method_call` for instance method visibility
- `gen_static_method_call` for static method visibility
- `gen_nested_method_call` (already has dispatch logic; add check)

#### 3. `protected` semantics

For now: same as `private`. (Real `protected` needs subtype checks,
which Dolet doesn't have — defer until traits get runtime dispatch.)

#### 4. Test (tests/visibility.dlt)

```dolet
import std

struct Account:
    public name: str
    private balance: i64

    fun deposit(self, amt: i64):
        self.balance = self.balance + amt   # OK — same struct's method

    fun get_balance(self) -> i64:
        return self.balance                 # OK — same struct

a: Account = Account(name="alice", balance=100 as i64)
print(a.name)                                # OK — public
print(Convert.i64_to_str(a.get_balance()))   # OK — via method
# print(Convert.i64_to_str(a.balance))       # ERROR — private from outside
```

Two test files: `tests/visibility_ok.dlt` (commented-out the bad line,
should compile) and `tests/visibility_fail.dlt` (with the bad line,
should FAIL to compile with a clear error). The build script wraps
the failing case in expected-failure handling.

### Edge cases

- `self.private_field` inside a method of the same struct → allowed
  (because `g_current_struct == obj_type`).
- Field access via interim variable: `x = a; x.balance` — the type
  check uses `obj_type = get_var_type("x")` which still resolves to
  `Account`, so the rule still fires correctly.
- Method calls via instance: same logic, just check `mfield_access`
  on the method node.
- Library code reading its own private fields: works (the check
  passes when inside the owning struct's method).

### Verification checklist

- [ ] `tests/visibility_ok.dlt` compiles cleanly
- [ ] `tests/visibility_fail.dlt` FAILS with a clear, file:line error
- [ ] Self-host: bootstrap stage 1 → 2 → 3 byte-stable. If the compiler's
      own structs use private fields cross-struct anywhere (likely some
      do!), fix those too — those are real privacy violations the
      original code got away with by accident.
- [ ] `system_smoke`, `output_smoke`, all 4 user apps rebuild

### Subtle hazards

- The compiler itself probably accesses private fields cross-struct
  in 5-20 places (because the rule was never enforced). Each
  violation will produce a clean error. Fix them by either
  (a) marking the field public if it really should be (most cases),
  or (b) adding a public accessor method.
- Don't break by leaving `g_current_struct` set after a method ends.
  The save/restore pattern is essential.

---

## A3. Codegen validation layer ✅

**Shipped (v1).** Two checks live in `gen_return`: (a) bare `return`
in non-void function panics; (b) empty value computed for non-void
return type panics with hint about chained-method bug. Wired through
new global `g_validate_enabled` (default ON via driver init) plus
`--validate` / `--no-validate` flags. Future sessions can extend
with sret/alloca/call-arg checks.

**Why now:** In 6 months we shipped 4 ABI / codegen bugs that
crashed at runtime or produced bad MLIR:

1. struct-stomp from missing entry-block alloca hoist
2. `mk_node_list(64)` overflow on >64-field structs
3. `Outer.Inner.say()` miscompiled to `i64_say(...)` (wrong return type)
4. `Process.run_capture(cmd).trim()` miscompiled to `() -> ()` void

Each of these would be caught by a 5-line assertion at codegen time.
We can add the assertion layer once and prevent the next bug from
ever reaching runtime.

**Estimate:** 1 medium session (~2 hours). New module + ~6 hook
points + driver flag.

**Dependencies:** A1 (panic) is helpful for clean failure messages
but not required.

### Files to modify

| File | Change |
|---|---|
| `codegen/codegen_validate.dlt` | NEW — all assertion functions |
| `codegen/codegen_main.dlt` | Hook validators in pre/post-codegen and per-function |
| `codegen/codegen_decl.dlt` | Call `validate_sret_struct_return` after `gen_fun_def` |
| `codegen/codegen_access.dlt` | Call `validate_call_arg_types` in every call-emit path |
| `codegen/codegen_stmt.dlt` | Call `validate_method_return_consistency` in `gen_return` |
| `codegen/codegen_expr.dlt` | Call `validate_entry_active_for_alloca` before any alloca emission |
| `driver/doletc_driver.dlt` | `--validate` / `--no-validate` flag (default on, off in --release) |
| `tests/validate_*.dlt` | Tests that intentionally violate ABI to confirm they're caught |

### Detailed implementation

#### Validators to add

```dolet
# codegen/codegen_validate.dlt
fun validate_entry_active_for_alloca(node: i64):
    if g_validate_enabled == 0:
        return
    if g_entry_active == 0:
        report_codegen_error("alloca emitted outside entry-block context",
                             node, "Use flush_entry_allocas pattern.")

fun validate_sret_struct_return(fn_node: i64, ret_type: str):
    if g_validate_enabled == 0:
        return
    if is_struct_type(ret_type) == 0:
        return                          # not an sret case
    # Check: function has at least one llvm.store to %sret_arg
    # Check: function ends in llvm.return
    # (This is structural — walk emitted MLIR? Or instrument the
    #  emit_ind path with a counter?)
    if g_sret_stores != 1:
        report_codegen_error("sret return must store exactly once", fn_node,
                             "Got " + Convert.i32_to_str(g_sret_stores) + " stores.")

fun validate_call_arg_types(call_name: str, arg_types: str, ret_type: str, node: i64):
    if g_validate_enabled == 0:
        return
    expected_ret: str = get_fun_ret_type(call_name)
    if str_eq(expected_ret, "unknown") == 1:
        return                          # extern, can't validate
    if str_eq(expected_ret, ret_type) == 0:
        msg: str = "call to '" + call_name + "' return type mismatch — "
        msg = msg + "site expects " + ret_type + ", function returns " + expected_ret
        report_codegen_error(msg, node, "")
    # Also check arg count + types if get_fun_param_count(call_name) is known.

fun validate_method_return_consistency(return_node: i64, expected_ret: str):
    if g_validate_enabled == 0:
        return
    inner_expr: i64 = Memory.read_i64(return_node + 8)
    actual_ret: str = infer_expr_type(inner_expr)
    if str_eq(actual_ret, "unknown") == 1:
        return
    if str_eq(actual_ret, expected_ret) == 0:
        # Allow implicit numeric widening (i32 → i64 etc.)
        if implicit_castable(actual_ret, expected_ret) == 0:
            msg: str = "return type mismatch: function returns " + expected_ret
            msg = msg + " but expression has type " + actual_ret
            report_codegen_error(msg, return_node, "")

fun report_codegen_error(msg: str, node: i64, hint: str):
    file: str = g_current_file
    line: str = Convert.i32_to_str(node_line(node))
    full: str = "[codegen error at " + file + ":" + line + "] " + msg
    print(full)
    if str_eq(hint, "") == 0:
        print("  hint: " + hint)
    Process.exit(2)
```

#### Globals to add (codegen_core.dlt)

```dolet
g_validate_enabled: i32 = 1     # set by driver based on --validate flag
g_sret_stores: i32 = 0          # incremented per llvm.store to sret in current fn
                                # reset on each gen_fun_def entry
```

#### Hook points

In `codegen_decl.dlt::gen_fun_def`:

```dolet
fun gen_fun_def(fn_node: i64):
    g_sret_stores = 0           # reset counter for this function
    # ... existing body ...
    validate_sret_struct_return(fn_node, ret_type)
```

In `codegen_access.dlt`, every place we `emit_ind("llvm.call @...")`,
right before the emit, add:

```dolet
validate_call_arg_types(mangled, arg_types_str, ret_type, node)
```

In `codegen_stmt.dlt::gen_return`:

```dolet
validate_method_return_consistency(node, g_current_fn_ret_type)
# ... emit return ...
```

In `codegen_expr.dlt`, before any `llvm.alloca` emission:

```dolet
validate_entry_active_for_alloca(node)
```

#### Driver flag (driver/doletc_driver.dlt)

```dolet
elif str_eq(arg, "--validate") == 1:
    g_validate_enabled = 1
elif str_eq(arg, "--no-validate") == 1:
    g_validate_enabled = 0
```

In `--release` flag handling, also disable validation by default:

```dolet
elif str_eq(arg, "--release") == 1:
    no_console = 1
    g_validate_enabled = 0     # release builds skip validation
```

### Tests (tests/validate_*.dlt)

Each test intentionally creates a known-bad pattern and confirms
the compiler catches it. These tests are EXPECTED TO FAIL compilation
with a specific error message (the test runner inverts the assertion).

- `tests/validate_return_mismatch.dlt`: function returns `i32` but
  body has `return "hello"` — must fail with "return type mismatch".
- `tests/validate_unknown_call.dlt`: call to nonexistent function —
  must fail with "unknown function" (this might already error today).
- `tests/validate_static_field_typo.dlt`: `Outer.Innre.say()`
  (typo in `Inner`) — must fail (today this silently miscompiled).

### Verification checklist

- [ ] All four historical bugs (struct-stomp, mk_node_list overflow,
      `i64_say`, `str_trim → ()`) are reproducible BEFORE the validator
      and caught BY it (synthetic test cases).
- [ ] Self-host bootstrap clean — the compiler doesn't trip its own
      validator. (If it does, it's a real bug we should fix.)
- [ ] `--no-validate` flag bypasses checks (smoke-tested).
- [ ] All 4 user apps rebuild with validation on.

### Subtle hazards

- Validation overhead: probably 1-3% on compile time. Acceptable
  for non-release builds.
- The `g_sret_stores` counter must be reset PER FUNCTION, not
  globally. Easy to forget on early-return paths.
- Some externs have `unknown` return type. Validator must treat
  unknown as "skip" not "fail" — only validate calls to
  Dolet-defined functions.

---

## A4. Error-path tests for std/system ✅

**Shipped.** `tests/error_paths.dlt` covers exists / run / capture /
output / File on missing inputs and non-zero exits, plus a 50× repeat
to confirm no per-call leak. Wired into `run_tests.bat`. Suite now
runs 54 tests, all PASS.

**Why now:** The smoke tests (`system_smoke.dlt`, `output_smoke.dlt`)
exercise happy paths. Failure modes aren't covered. A regression
that silently swallows errors would slip past CI.

**Estimate:** 1 short session (~45 min).

**Dependencies:** none. (Better with A1 done so error tests can use
`panic`-checking, but works without.)

### Files to add

| File | Purpose |
|---|---|
| `tests/error_paths.dlt` | Comprehensive test of every error mode |
| `run_tests.bat` | Wire it in |

### What to test

- `System.exists("not_a_real_path_xyz_123")` → returns 0
- `System.exists("C:\\")` (or `/`) → returns 1
- `System.exists("")` → returns 0 (empty path)
- `System.Command.run("doesnotexist123")` → returns -1
- `System.Command.capture("doesnotexist123")` → returns "" (empty)
- `System.Command.output("doesnotexist123")` → `code == -1`,
  `stdout == ""`, `stderr == ""`
- `System.Command.output("cmd /c exit 5")` → `code == 5`,
  empty out/err
- `System.Command.output("cmd /c echo line1 & echo err1 1>&2 & exit 3")`
  → `code == 3`, out == "line1", err == "err1"
- Stdout overflow: `System.Command.output("cmd /c for /L %i in (1,1,5000) do @echo aaaaaaaaaaaaaaaaaaaaaaaaaaa")`
  — verify buffer limit behavior (currently 1MB cap)
- `File.open("/nope/no/file", "r")` → `is_valid() == 0`
- `File.open` then `read_text` then `close` cycle on a real file
- Multi-call without leak: call `System.Command.capture("cmd /c echo x")`
  100 times, check `Memory.alloc_balance()` doesn't grow without bound

### Detailed test structure (tests/error_paths.dlt)

```dolet
import std

# Test framework: tally pass/fail, print summary, exit non-zero on any fail.
g_pass: i32 = 0
g_fail: i32 = 0

fun assert_i32(label: str, got: i32, expected: i32):
    if got == expected:
        g_pass = g_pass + 1
    else:
        print("FAIL: " + label + " — expected " + Convert.i32_to_str(expected) +
              " got " + Convert.i32_to_str(got))
        g_fail = g_fail + 1

fun assert_str(label: str, got: str, expected: str):
    if str_eq(got, expected) == 1:
        g_pass = g_pass + 1
    else:
        print("FAIL: " + label + " — expected '" + expected + "' got '" + got + "'")
        g_fail = g_fail + 1

# --- exists ---
assert_i32("exists nonexistent", System.exists("X:\\nope_xyz_123"), 0)
assert_i32("exists root",        System.exists("C:\\"),              1)
assert_i32("exists empty",       System.exists(""),                  0)

# --- run ---
assert_i32("run nonexistent",    System.Command.run("doesnotexist123"), -1)
assert_i32("run exit 0",         System.Command.run("cmd /c exit 0"),    0)
assert_i32("run exit 7",         System.Command.run("cmd /c exit 7"),    7)

# --- capture ---
assert_str("capture echo",       System.Command.capture("cmd /c echo hi"), "hi")
assert_str("capture nonexistent", System.Command.capture("doesnotexist123"), "")

# --- output ---
r1: Output = System.Command.output("cmd /c echo hi")
assert_i32("output ok code",     r1.code,   0)
assert_str("output ok stdout",   r1.stdout, "hi")
assert_str("output ok stderr",   r1.stderr, "")

r2: Output = System.Command.output("cmd /c exit 7")
assert_i32("output exit-7 code", r2.code, 7)

r3: Output = System.Command.output("cmd /c echo out & echo err 1>&2 & exit 3")
assert_i32("output mixed code",   r3.code, 3)
assert_str("output mixed stdout", r3.stdout, "out")
assert_str("output mixed stderr", r3.stderr, "err")

r4: Output = System.Command.output("doesnotexist123")
assert_i32("output not-found code", r4.code, -1)

# --- File ---
fbad: File = File.open("/nope/no/file", "r")
assert_i32("file open missing", fbad.is_valid() as i32, 0)

# --- summary ---
print("---")
print("PASS: " + Convert.i32_to_str(g_pass))
print("FAIL: " + Convert.i32_to_str(g_fail))
if g_fail > 0:
    Process.exit(1)
```

### Verification checklist

- [ ] All assertions pass on Windows
- [ ] `run_tests.bat` includes this file and exits non-zero if any fail
- [ ] No memory leak after the suite (compare `Memory.alloc_balance`
      before and after)

---

# Tier 2 — Type System

These are the language-level features that move Dolet from "compiles"
to "expressive." Each is significantly bigger than Tier 1.

---

## B1. `Result<T, E>` and `Option<T>` as compiler built-in generics ⬜

**Why now:** Without `Result`, every Dolet function that can fail
returns `i32 = -1` by convention. There's no way to communicate
"I succeeded with this string" or "I failed with this error code"
in a typed way. Adding `Result<T, E>` as a compiler-known generic
(same status as `list<T>`, `array<T>`, `map<K,V>` today) gives
us proper error types **without waiting for full user-defined
generics** (B3).

This is NOT a temporary solution. Rust shipped `Result` as a
language-level type for years before const generics matured;
Swift has built-in `Optional` separate from user-defined generics.
The pattern is well-established.

**Estimate:** 2-3 medium sessions.

**Dependencies:** A1 (panic) for `unwrap()` failure path.

### Type representation

`Result<T, E>` lowers to a tagged union:

```
struct Result__T__E {
    tag:   i32      // 0 = Ok, 1 = Err
    value: T        // valid iff tag == 0
    error: E        // valid iff tag == 1
}
```

`Option<T>`:

```
struct Option__T {
    tag:   i32      // 0 = Some, 1 = None
    value: T        // valid iff tag == 0
}
```

Layout: tag at offset 0 (4 bytes), then padding to 8, then value/error.
Total size: `8 + sizeof(T) + sizeof(E)` (with E=void → just 8 + sizeof(T)).

### Per-use-site monomorphization

When the type checker sees:

```dolet
r: Result<i32, str> = some_call()
```

…the codegen looks up (or creates) a hidden struct
`Result__i32__str` with the right field layout. Method calls
(`r.is_ok()`, `r.unwrap()`) get rewritten to
`Result__i32__str_is_ok(&r)` etc. The method body templates live
in `library/std/result.dlt` with placeholder type `T`/`E`; the
codegen substitutes per use-site.

This is exactly the monomorphization machinery we'd need for B3
(user-defined generics) but limited to the two types `Result` and
`Option`. Building it on a small surface first is the right
order.

### Files to modify

| File | Change |
|---|---|
| `parser/parser_type.dlt` | Recognize `Result<T,E>` / `Option<T>` as type expressions; build `NODE_GENERIC_TYPE` AST node |
| `parser/parser_expr.dlt` | Recognize `Ok(x)`, `Err(e)`, `Some(x)`, `None` as constructor calls (special-cased atoms, not generic function calls) |
| `parser/parser_stmt.dlt` | Extend `match`/`case` to bind variant payloads: `case Ok(x):` |
| `codegen/codegen_core.dlt` | Globals `g_result_monomorphs` (set of `T__E` keys seen) and `g_option_monomorphs`; helpers to emit hidden structs on demand |
| `codegen/codegen_types.dlt` | When inferring type of a `NODE_GENERIC_TYPE(Result, [T, E])`, return string `"Result<T,E>"` (use as map key) |
| `codegen/codegen_decl.dlt` | When emitting a function or variable that uses `Result<T,E>`, ensure the hidden struct is emitted once |
| `codegen/codegen_expr.dlt` | Emit struct construction for `Ok(x)`, `Err(e)`, `Some(x)`, `None` with right tag value |
| `codegen/codegen_stmt.dlt` | Emit pattern match: load tag, branch, in case bind payload to local |
| `library/std/result.dlt` | NEW — declares the methods (`is_ok`, `is_err`, `unwrap`, `unwrap_or`, `ok`, `err`) using placeholder type names; compiler instantiates per use-site |
| `library/std/option.dlt` | NEW — same for `Option<T>` |
| `library/std/mod.dlt` | `load std/result`, `load std/option`; `export Result, Option, Ok, Err, Some, None` |
| `tests/result_basic.dlt` | NEW |
| `tests/option_basic.dlt` | NEW |

### Implementation order (within this item)

1. **Parser**: recognize `Result<T,E>` in type expressions and
   `Ok(x)` / `Err(e)` in expressions. Build correct AST shapes.
   Don't generate any code yet — just verify the AST roundtrips.
2. **Type system**: type inference returns `"Result<i32, str>"`
   strings. Equality / unification of these types.
3. **Codegen — struct emission**: collect every distinct
   `Result<T,E>` instantiation seen during compilation, emit one
   hidden struct per. Use `T__E` mangling.
4. **Codegen — constructor calls**: `Ok(42)` lowers to
   `Result__i32__E { tag: 0, value: 42 }` (E inferred from context).
5. **Codegen — method calls**: `r.unwrap()` lowers to
   `Result__i32__str_unwrap(&r)`; the body of `_unwrap` is emitted
   from a template in `library/std/result.dlt` with `T`/`E`
   substituted.
6. **Codegen — pattern match**: `case Ok(x):` checks `tag == 0`,
   binds `x` to the `value` field, runs the body. `case Err(e):`
   symmetric.

### Method API (library/std/result.dlt template)

```dolet
# Compiler treats this file as a TEMPLATE — T and E are placeholders
# substituted per use-site. No actual struct Result is defined here;
# the compiler synthesizes Result__T__E structs on demand.

extend Result<T, E>:
    fun is_ok(self) -> bool:
        return self.tag == 0

    fun is_err(self) -> bool:
        return self.tag == 1

    fun unwrap(self) -> T:
        if self.tag != 0:
            panic "unwrap on Err"
        return self.value

    fun unwrap_or(self, default: T) -> T:
        if self.tag == 0:
            return self.value
        return default

    fun ok(self) -> Option<T>:
        if self.tag == 0:
            return Some(self.value)
        return None

    fun err(self) -> Option<E>:
        if self.tag == 1:
            return Some(self.error)
        return None
```

Symmetric `library/std/option.dlt`.

### Test (tests/result_basic.dlt)

```dolet
import std

fun parse_pos(n: i32) -> Result<i32, str>:
    if n < 0:
        return Err("negative")
    return Ok(n * 2)

r1: Result<i32, str> = parse_pos(5)
r2: Result<i32, str> = parse_pos(-1)

print(Convert.i32_to_str(r1.unwrap()))            # 10
print(r2.unwrap_or(99) as str ... )                # actually Convert.i32_to_str
print(r2.is_err() as str ...)                      # true

match r2:
    case Ok(x): print("ok " + Convert.i32_to_str(x))
    case Err(e): print("err " + e)                 # "err negative"
```

### Verification checklist

- [ ] `Result<i32, str>` declared, constructed, matched, unwrapped
- [ ] `Option<str>` similar
- [ ] Two different `Result<T,E>` instantiations in the same program
      produce two different hidden structs (no collision)
- [ ] Self-host: bootstrap stable. (Expected — this is purely
      additive; existing code doesn't use Result yet.)
- [ ] `unwrap()` on `Err` panics with clear message + exit 101

### Hazards

- **Generic-type string equality**: `"Result<i32, str>"` and
  `"Result<i32 , str>"` (extra space) must compare equal. Normalize
  during parser or unification.
- **Recursive instantiation**: `Result<Result<i32, str>, str>` —
  must emit `Result__Result__i32__str__str` (or some flattened key).
  Pick a delimiter that won't collide with type names.
- **Forward references**: if module A returns `Result<B, C>` and
  module B is loaded later, the hidden struct emission must happen
  after type registration is complete. Probably emit at the end of
  the codegen pass, not eagerly per call site.

---

## B2. `?` postfix operator ⬜

**Why now:** `?` is the ergonomic shortcut that makes `Result` worth
using. Without it, every fallible call is a 4-line match. With it,
one character.

**Estimate:** 1 medium session (~2 hours), assuming B1 is done.

**Dependencies:** B1 (Result/Option must exist as types).

### Semantics

```dolet
fun chain(x: i32) -> Result<i32, str>:
    a: i32 = parse_pos(x)?         # if parse_pos returns Err, return Err immediately
    b: i32 = parse_pos(a)?         # otherwise unwrap to i32
    return Ok(b + 1)
```

Desugars to:

```dolet
fun chain(x: i32) -> Result<i32, str>:
    __tmp1: Result<i32, str> = parse_pos(x)
    if __tmp1.tag == 1:
        return Err(__tmp1.error)   # propagate
    a: i32 = __tmp1.value

    __tmp2: Result<i32, str> = parse_pos(a)
    if __tmp2.tag == 1:
        return Err(__tmp2.error)
    b: i32 = __tmp2.value

    return Ok(b + 1)
```

For `Option<T>?`, propagation is `return None` instead of `return Err(...)`.

### Type-check rules

- The `?` operand must be `Result<T, E>` or `Option<T>`.
- The enclosing function must return `Result<_, E_compat>` (any T, but
  the same or a wider E for Result `?`) or `Option<_>` for Option `?`.
- E_compat: for v1, require exact match. Coercion (e.g., from
  `Result<T, ErrA>` to `Result<U, ErrB>` via a `From` trait) is
  follow-up.

### Files to modify

| File | Change |
|---|---|
| `parser/parser_expr.dlt` | Add postfix `?` after primary expressions, same precedence as `.field` |
| `parser/ast_nodes.dlt` | NEW node `NODE_TRY_OP` with `inner: i64` (the wrapped expression) |
| `codegen/codegen_expr.dlt` | Lower `NODE_TRY_OP` per the desugaring above. Use entry-block alloca for `__tmp` to avoid stomp |
| `codegen/codegen_types.dlt` | Type of `expr?` is `T` (the inner type of `Result<T,E>` or `Option<T>`) |
| `tests/try_op_basic.dlt` | NEW |

### Detailed steps

1. **Parser**: in `parser_expr.dlt`, find the postfix loop (the place
   that handles `.field` and `(args)` and `[idx]`). Add:

   ```dolet
   while postfix_loop:
       if cur_kind() == TK_DOT:
           # ... existing field/method handling ...
       elif cur_kind() == TK_LBRACKET:
           # ... existing index handling ...
       elif cur_kind() == TK_LPAREN:
           # ... existing call handling ...
       elif cur_kind() == TK_QUESTION:
           advance()
           lhs = mk_try_op(lhs)
       else:
           break
   ```

2. **Type inference**: `infer_expr_type` for `NODE_TRY_OP`:

   ```dolet
   if ntype == NODE_TRY_OP:
       inner: i64 = Memory.read_i64(node + 8)
       inner_type: str = infer_expr_type(inner)
       # Strip the Result<...> or Option<...> wrapper
       if Str.starts_with(inner_type, "Result<") == 1:
           return extract_first_generic_arg(inner_type)
       if Str.starts_with(inner_type, "Option<") == 1:
           return extract_first_generic_arg(inner_type)
       return "unknown"
   ```

3. **Codegen**: in `codegen_expr.dlt`, lower `NODE_TRY_OP` by:

   - Allocate `__tmpN` in entry block (use existing flush_entry_alloca infra)
   - Evaluate the inner expression, store in __tmpN
   - Load tag: `%tag = llvm.extractvalue %tmp, 0`
   - Compare tag against err-value (1)
   - If err: build the appropriate Err/None propagation value, store
     to current function's `%sret_arg`, return
   - If ok: extract `value` field, that's the result of the `?`
     expression

4. **Verify return type compat**: at codegen time, check
   `g_current_fn_ret_type` is compatible with the propagation. If
   not, emit a clear error: "use of `?` requires the enclosing
   function to return Result/Option."

### Test (tests/try_op_basic.dlt)

```dolet
import std

fun parse_pos(n: i32) -> Result<i32, str>:
    if n < 0:
        return Err("negative")
    return Ok(n * 2)

fun chain(x: i32) -> Result<i32, str>:
    a: i32 = parse_pos(x)?
    b: i32 = parse_pos(a)?
    return Ok(b + 1)

r1: Result<i32, str> = chain(2)         # parse_pos(2)=4, parse_pos(4)=8, +1 = 9
print(Convert.i32_to_str(r1.unwrap()))   # 9

r2: Result<i32, str> = chain(-1)         # first parse_pos returns Err, propagated
match r2:
    case Ok(x):  print("ok " + Convert.i32_to_str(x))
    case Err(e): print("err " + e)       # "err negative"
```

### Verification checklist

- [ ] `?` parses as postfix at same precedence as `.field`
- [ ] Type inference returns `T` for `Result<T,E>?`
- [ ] Codegen emits the desugared early-return correctly
- [ ] Calling `?` in a function whose return type is NOT
      Result/Option fails compilation with a clear error
- [ ] Self-host bootstrap clean

### Hazards

- **Operator precedence**: `?` should bind tighter than `.` so that
  `foo()?.bar()` works as `(foo()?).bar()`, not `foo()?.bar()`.
  Or maybe the same — Rust binds `?` tighter than method calls
  except `?.` is its own thing. Pick a rule and document.
- **Multiple `?`** in one expression: `a()?.b()?` should work.
- **Inside non-Result function**: `print(parse(x)?)` from `main()`
  (which doesn't return Result) — fail compilation cleanly.

---

## B3. User-defined generics with monomorphization ⬜

**Why now:** Once Result/Option work, the next ergonomic gap is
"can I write my own `Stack<T>` or `Pair<A, B>`?" Today no.

**Estimate:** 4-6 medium sessions. The hardest item in Tier 2.

**Dependencies:** B1 (Result/Option work) provides the
monomorphization template. Generalize from there.

### Scope (for v1)

In scope:
- `struct Box<T>: value: T` and `struct Pair<A, B>: a: A; b: B`
- Generic functions: `fun max<T>(a: T, b: T) -> T:` (with `T` as
  a *concrete* type at each call site, no bounds)
- Use sites: `Box<i32>`, `max<str>("a", "b")`
- Per-use-site monomorphization, like Result

Out of scope (for v1):
- Trait bounds (`T: Display`)
- Higher-kinded types (`F<_>`)
- Lifetime/borrow analysis (Dolet doesn't have lifetimes)
- Default type params

### Files to modify (high-level)

- `parser/parser_decl.dlt`: already parses `<T>` — need to verify
  it stores type-params on `NODE_STRUCT_DECL` and `NODE_FUN_DECL`
  consistently.
- `codegen/codegen_decl.dlt`: when emitting a generic struct/fun,
  emit the *template* in some intermediate form, not as a
  monomorphized struct yet.
- `codegen/codegen_types.dlt`: type substitution table
  (`T -> i32`, etc.) when resolving types in a generic body.
- `codegen/codegen_mono.dlt` (NEW): monomorphization cache + on-
  demand emission. Walks the AST after parsing, collects every
  use-site, emits one specialization per `(generic_name, type_args)`
  combination.
- `codegen/codegen_main.dlt`: call the mono pass between parse and
  codegen-emit.

This is multi-session work; future sessions will write the detailed
implementation steps when they pick this up.

### Hazards

- **Cyclic instantiation**: `Box<Box<i32>>` — must terminate.
- **Forward references** across modules: same problem as Result.
- **Naming**: `Pair__i32__str` mangling needs to be unambiguous.
- **Method tables**: `extend Box<T>: fun get(self) -> T` — the
  method body must be re-codegen'd per instantiation with `T`
  substituted.

---

# Tier 3 — Major Features

These are 5-10 session efforts. Don't start any of them inside an
otherwise-busy session — give each its own dedicated focus.

---

## C1. Closures with captures ⬜

**Why now:** Every modern callback API needs them. Event handlers,
async continuations, iterators with predicates — all blocked
without closures.

**Estimate:** 5-7 sessions.

### Approach: closure conversion (lambda lifting)

Source:

```dolet
make_counter: fun() -> i32 = ...
counter: fun() -> i32 = make_counter()
counter()    # returns 1
counter()    # returns 2
```

The compiler:

1. Detects `fun(args) -> ret` types in declarations / parameters /
   returns.
2. Parses anonymous functions: `fun(x: i32) -> i32: x + 1`. Decide
   syntax: prefer explicit `fun(...)` form over `|x|` shorthand
   for clarity (Dolet is verbose-by-design).
3. Free-variable analysis on the closure body: anything referenced
   that isn't a parameter or a global is captured.
4. Closure conversion: lift the body to a top-level fun that takes
   the captures as a hidden first arg (an "environment" struct).
   At the construction site, allocate the env (heap or arena),
   pack captures.
5. The closure value at runtime is `(fn_ptr, env_ptr)` — an 8-byte
   pair (or 16 if both are i64).

### Files (sketch)

- `parser/ast_nodes.dlt`: `NODE_CLOSURE_LIT` (params + body + 
  captured-vars list)
- `parser/parser_expr.dlt`: `fun(args) -> ret: body` as expression
- `parser/parser_type.dlt`: `fun(arg_types) -> ret_type` as type
- `codegen/codegen_closure.dlt` (NEW): lambda lift, env struct
  emission, fn-ptr table
- `codegen/codegen_call.dlt`: distinguish direct call vs closure
  call; closure call extracts fn_ptr from the closure value and
  passes env_ptr as hidden first arg

### Critical hazards

- **Capture lifetime**: a closure that captures a local outlives
  the local's scope → must move-or-copy. Default to copy for v1
  (similar to Go's escape analysis but simpler).
- **Mutable captures**: capturing `mut x` and writing through the
  closure → needs a "by reference" capture form. Defer to v2.
- **Recursive closures**: `let f = fun(n: i32) -> i32: if n == 0: 0 else f(n-1)`.
  The closure can't capture itself — needs a Y-combinator hack or
  a `let rec`-style binding. Defer or punt.
- **First-class fn pointers vs closures**: a regular function name
  used as a value (`map(parse_pos, list)`) should also work. Treat
  it as a closure with empty captures.

---

## C2. DWARF / CodeView debug info ⬜

**Why now:** Today every crash gives a raw address. No backtrace,
no source line. Mandatory for any user beyond the author.

**Estimate:** 5-7 sessions.

### Approach: emit MLIR DI ops, let LLVM lower

LLVM's MLIR has full DWARF + CodeView support via the `llvm.di*`
ops. The work is:

1. Add `--g` / `--debug` driver flag.
2. Track per-token source positions through the pipeline. The
   tokenizer already records `tok_indent` and likely line number;
   wire that into every AST node (currently many nodes drop line
   info).
3. Emit `llvm.dicompileunit` at module top.
4. For every fun: `llvm.disubprogram` attribute attached to
   `llvm.func`.
5. For every variable: `llvm.dilocalvariable` + `llvm.dbg.declare`.
6. For every statement: `loc(...)` location attribute on the
   relevant ops.
7. Pass `--debugify-level=location+variables` to mlir-translate (or
   equivalent).
8. Verify with `llvm-dwarfdump -a hello.exe` (Linux) or
   `cvdump.exe -lines hello.exe` (Windows) that symbols + line
   tables exist.
9. Test breakpoint experience: open a Dolet binary in VS Code with
   the C/C++ extension, set a breakpoint, hit it, inspect locals.

### Hazards

- MLIR DI op ergonomics are not great — easy to emit malformed
  metadata. Plan to spend a session just understanding the existing
  MLIR DI examples (look at `mlir/test/Conversion/LLVMCommon/`).
- Inline functions and templated code (Result monomorphizations)
  need careful DISubprogram handling so the debugger doesn't get
  confused.
- Optimization passes can drop debug info — make sure
  `--debugify-each` is set if running any opt passes.

---

## C3. Real threading + atomics ⬜

**Why now:** Async exists but is single-threaded cooperative. CPU-
bound work blocks the event loop. Real OS threads + atomics enable
parallelism.

**Estimate:** 5-7 sessions.

### Scope (v1)

- `Thread.spawn(fn)` — creates an OS thread, returns a handle
- `Thread.join(handle)` — waits for the thread, returns its result
- `Mutex.new() / Mutex.lock(m) / Mutex.unlock(m)`
- `Atomic<i32>` / `Atomic<i64>` / `Atomic<bool>` with
  `load() / store() / cas(old, new) / fetch_add(delta)`
- Memory ordering: sequentially consistent default. `acq` / `rel` /
  `relaxed` forms as opt-in.

### Files (sketch)

- `library/platform/windows/thread.dlt` (NEW): wraps `CreateThread`,
  `WaitForSingleObject`, `WaitForMultipleObjects`, critical sections
- `library/platform/linux/thread.dlt` (NEW): wraps `clone` syscall
  with the thread CLONE flags, futex syscalls
- `library/platform/windows/atomic.dlt`: `_InterlockedIncrement64`,
  `_InterlockedCompareExchange64` from kernel32
- `library/platform/linux/atomic.dlt`: GCC `__atomic_*` builtins
  via inline asm (or LLVM atomic ops directly in MLIR)
- `library/std/thread.dlt`: cross-platform facade
- `library/std/sync.dlt`: Mutex, Atomic
- `codegen/codegen_atomic.dlt` (NEW): emit `llvm.atomicrmw`,
  `llvm.cmpxchg`, `llvm.fence` ops

### Hazards

- **Memory model**: get this wrong and code "works on my machine"
  but corrupts on other CPUs. Default to seq-cst for safety; expose
  weaker orderings only as explicit opt-in.
- **Thread-local storage**: needed for any decent runtime. Win32
  has `TlsAlloc`/`TlsGetValue`; Linux has `__thread` keyword in C
  but raw syscall route uses `arch_prctl(ARCH_SET_FS)`. Defer
  TLS to v2.
- **Closure capture across threads**: when v1 of C1 (closures)
  ships, decide whether `Thread.spawn(closure)` requires `Send`-
  like marker. For v1, document "captures must be deep-copyable"
  and don't enforce it.

---

## C4. Incremental builds ⬜

**Why now:** Currently every `./build.bat` re-amalgamates 14k LOC
and compiles from scratch. Sub-second on the compiler itself but
will hurt on 100+ file projects.

**Estimate:** 7-10 sessions. Big architectural change.

### Approach: per-module .obj + content-hash cache

1. Refactor compiler to accept multiple input files OR a
   compile-database manifest.
2. Per source file: compute SHA-256 of the file + transitive
   imports' exported signatures. If unchanged from last build,
   reuse the cached `.obj`.
3. Linker step composes all `.obj` files into the final executable.
4. Cache directory: `.dolet_cache/` next to each module.

This requires:
- The compiler currently flattens everything into pipeline_build.dlt
  before parsing. That model has to go — parse per-module, type-
  check per-module with import resolution.
- Cross-module type signatures need to be export-tracked
  (`module.meta` already has package-level metadata; extend to
  per-symbol exports).
- Linker invocation refactor.

### Hazards

- Self-hosting becomes harder — the compiler itself has to support
  the new model OR keep the amalgamation route as a fallback for
  bootstrap.
- Cross-module generic instantiation: where does `Box<MyType>`
  get monomorphized when `Box` is in module A and `MyType` is in
  module B and the use site is in module C? Pick a rule (use-site,
  probably) and document.
- Cache invalidation is "the second hardest problem in CS." Plan
  for at least one session of pure debugging.

---

# Tier 4 — Platform Parity

---

## D1. Linux platform layer (real run_capture / run_output) ⬜

**Why now:** Linux `library/platform/linux/process.dlt` has
`run_capture` stubbed (returns `""`). Linux build is unusable for
any tool that needs to read command output.

**Estimate:** 1-2 sessions IF Linux box is available for testing.
Mostly mechanical (mirror the Windows pipe pattern using
fork/dup2/select).

**Dependencies:** none.

**Blocker:** need a Linux machine for verification. Cannot
meaningfully ship this from a Windows-only session (no way to
test).

### Files to add/modify

- `library/platform/linux/syscalls.dlt`: add externs for
  `dsl_pipe`, `dsl_dup2`, `dsl_select`, `dsl_kill`, `dsl_access`
- `library/platform/linux/runtime_helpers.ll`: implement the LLVM
  IR wrappers around the raw syscalls (numbers: pipe=22, dup2=33,
  select=23, kill=62, access=21)
- `library/platform/linux/path.dlt`: add `PathOps.exists` using
  `dsl_access(path, 0)` (F_OK = 0)
- `library/platform/linux/process.dlt`: add `Process.exit` using
  `dsl_exit`. Implement `run_capture` properly (fork, child does
  pipe redirection via dup2, exec, parent reads from pipe). Add
  `run_output` with two pipes + select() drain (analogous to
  Windows PeekNamedPipe loop).
- `library/platform/linux/info.dlt` (NEW): `PlatformInfo.name() = "linux"`
- `library/platform/linux/mod.dlt`: load info

### Verification

Requires a Linux machine. Smoke test:
```bash
./bin/doletc-linux hello.dlt -o hello --target linux
./hello
```

---

# Cross-cutting: Reuse map

When working any item, reuse these existing patterns rather than
inventing parallel infrastructure:

| Need | Use | Where |
|---|---|---|
| Allocate AST node | `alloc_node(kind)` | `parser/ast_nodes.dlt:144` |
| Read field from node | `Memory.read_i64(node + offset)` | many examples |
| Build static method call | `mk_static_method(struct, method, args)` | `parser/ast_nodes.dlt:913` |
| Detect struct type | `is_struct_type(name)` | `codegen/codegen_core.dlt:545` |
| Function ret type lookup | `get_fun_ret_type(mangled)` | `codegen/codegen_core.dlt` |
| Variable type lookup | `get_var_type(name)` | `codegen/codegen_core.dlt:407` |
| Emit MLIR line | `emit_ind(text)` | many places in codegen_*.dlt |
| Entry-block alloca hoist | `flush_entry_allocas`, `g_entry_active`, `g_entry_insert_pos` | `codegen/codegen_main.dlt:720+` |
| Source location on token | tokenizer records line in token; pass via parser to AST node — partially missing today |
| Struct field access modifier | `sfield_access(field_node)` | `parser/ast_nodes.dlt:778` |

---

# Process notes

- **One item per session.** Never mix two items in one commit/PR
  unless they are structurally inseparable.
- **Bootstrap after every change**, not just at the end of a
  session. If stage 2 ≠ stage 3, halt and bisect immediately —
  miscompilations get harder to find as more changes pile up.
- **Update this ROADMAP** when an item is done: change ⬜ to ✅,
  add a "Shipped: <commit>" line.
- **If an estimate is wrong by >2x**, write a "Reality" subsection
  explaining what was harder than expected — that's documentation
  the future-you (and anyone else) will thank you for.

---

# BUGS — known compiler bugs awaiting dedicated fix sessions

## B-01. Chained extend-str return type loss ⬜

**Symptom:** Calls into `extend str` methods (or any user method
on a primitive type, when chained or used in a non-assignment
context) emit `llvm.call @<method>(...) : (...) -> ()` (void),
losing the actual return type. Downstream code then breaks:
`llvm.return : !llvm.ptr` (no value), or
`llvm.store , %X : T, !llvm.ptr` (empty operand).

**Reproduce:**
```dolet
import std
a: str = "x"
b: str = "x"
ok: bool = a.equals(b)        # FAIL: equals lowered as void
```
or
```dolet
fun f(cmd: str) -> str:
    return Process.run_capture(cmd).trim()    # FAIL: trim void
```

**Impact:** We've worked around this 4+ times by introducing
intermediate variables (`raw: str = ...; return raw.trim()`). Any
new `extend str` method that returns a primitive (bool, i32) is
unusable in chained or expression contexts.

**Specific example shipped today:** `library/std/string.dlt`
intentionally OMITS `equals(self, other)` from the `extend str`
block. Only `Str.equals(a, b)` (static form) is exposed. When
this bug is fixed, add the wrapper back and update tests.

**Trace (from prior investigation):**
- Parser builds `NODE_INST_METHOD(obj=ident, method, args)` for
  `var.method()` and `NODE_NESTED_METHOD(base=node, method, args)`
  for `f().method()`.
- `gen_instance_method_call` mangles to `<base_type>_<method>`
  (e.g. `str_equals`) and calls `get_fun_ret_type(mangled)`.
- For some reason the return type lookup returns
  `unknown` / `""` for `extend str` methods that return
  primitives — the call emits as void.
- Direct static-method calls (`Str.equals(a, b)`) work, so
  the registration during NODE_EXTEND_BLOCK processing in
  `codegen_main.dlt:311+` captures the signature correctly under
  one mangling but lookup uses a different mangling.

**Likely fix:** check what name `register_overload` produces for
extend-str methods (probably `str_equals$` or similar) vs what
`gen_instance_method_call` looks up at line 569 (`base_type + "_" + mname`).
Equalize the mangling rule on both sides.

**Estimate:** 1 medium session. Discrete codegen bug.

**Why deferred today:** session quality bar — we have to choose
between many small fixes or one big feature. This bug is small
but affects a class of user code; B1 (Result/Option) is bigger
but unlocks a whole programming pattern. Each deserves its own
session.

---

# Out-of-roadmap (explicitly NOT planned)

- **Garbage collection.** The arena + heap split is the model.
  Adding a GC would mean keeping both, which doubles complexity.
- **Hot reload / live coding.** Cool but requires a totally
  different runtime model.
- **Self-modifying code / JIT.** Out of scope for a systems
  language with ahead-of-time compilation.
- **Browser / WASM target.** Not on the path. The MLIR backend
  could in principle target WASM, but the runtime (kernel32 / raw
  syscalls) doesn't translate. Would be a separate ecosystem.
