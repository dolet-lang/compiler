# Dolet Module System — Handoff Document
> For a fresh AI session with no prior context.
> Project: `c:\Users\xRo0t\Desktop\xMine\dolet work spaces\dolet-compiler`
> Branch: `main`
> Build command: `python bootstrap/doletc.py build/pipeline_build.dlt -o bin/doletc.exe`
> Test suite: `./run_tests.bat` — expect **41/41 PASS**

---

## 1. What is Dolet?

Dolet is a **self-hosted, statically-typed compiled language** targeting x86-64 via MLIR/LLVM.
The compiler is written in Dolet itself. Compilation pipeline:

```
Source (.dlt)
  → bootstrap/doletc.py  (Python bootstrap, only used to rebuild the compiler itself)
  → bin/doletc.exe       (the self-hosted compiler)
  → MLIR → LLVM IR → .exe
```

**Critical facts:**
- `build/pipeline_build.dlt` is a **single-file amalgamation** of the entire compiler. Every change to `codegen/`, `parser/`, `lexer/`, `driver/` files **must also be mirrored** in `pipeline_build.dlt`. This is what the Python bootstrap compiles to produce a new `bin/doletc.exe`.
- `bin/doletc.exe` **is compiled from `pipeline_build.dlt`**, not from the individual `.dlt` files in subdirectories.
- The individual `.dlt` files in subdirectories (`codegen/`, `parser/`, etc.) are what `bin/doletc.exe` uses to compile user programs. They are the **compiler source** AND the **library** simultaneously.
- Tests live in `tests/features/` and are run via `./run_tests.bat`.
- The standard library is in `library/` and is loaded at runtime via `import std`.

---

## 2. Module System — Goal

The goal is a module/package system **stronger than Java's**, suitable for kernel/embedded use. The user showed these examples:

```dolet
# Struct field access control
struct Account:
    public name: str
    private password: str
    protect age: i32

# Namespace disambiguation
import std.collections     # std.collections.List
import extra.collections   # extra.collections.List — no collision

# Export control in mod.dlt
module mymod
export io
private internal
```

---

## 3. Phase Overview

| Phase | Description | Status |
|-------|-------------|--------|
| 0+1 | Foundation + `mod.dlt` processing | ✅ Done (41/41 tests pass) |
| 2 | Access control enforcement (`public`/`private`/`protect`) | ✅ Done |
| 3 | Namespace isolation + qualified access (`ns.func()`, `ns.Struct.method()`) | 🔄 **In Progress — see §5** |
| 4 | Export control in `mod.dlt` | ⏳ Pending |
| 5–7 | `use` statement, `from X import Y`, function visibility | ⏳ Pending |

---

## 4. Phase 2 — What Was Done (Access Control)

### Token + AST additions

**`lexer/tokenizer.dlt`** — new keywords after `TK_ARRAY=114`:
```dolet
TK_MODULE: i32 = 116
TK_EXPORT: i32 = 117
TK_REQUIRES: i32 = 118
```
Also added `"module"`, `"export"`, `"requires"` to `resolve_keyword()` after `"extend"`.

**`parser/ast_nodes.dlt`** — new node constants before `NODE_PARAM` block:
```dolet
NODE_MODULE_DECL: i32 = 160
NODE_EXPORT: i32 = 161
NODE_REQUIRES: i32 = 162
NODE_USE_MODULE: i32 = 163
```

**`parser/parser_main.dlt`** — skip `module`/`export`/`requires` lines:
```dolet
if k == TK_MODULE or k == TK_EXPORT or k == TK_REQUIRES:
    advance()
    while cur_kind() != TK_NEWLINE and cur_kind() != TK_EOF:
        advance()
    return 0
```

### Access modifier storage

Struct field AST nodes store access modifiers at **offset +40** as a string (`"public"`, `"private"`, `"protected"`).

The function `get_field_access(struct_name, field_name) -> str` in `codegen/codegen_types.dlt` reads this:
```dolet
fun get_field_access(struct_name: str, field_name: str) -> str:
    fields: i64 = get_struct_fields(struct_name)
    if fields == 0:
        return "public"
    fc: i32 = nl_count(fields)
    i: i32 = 0
    while i < fc:
        fnode: i64 = nl_get(fields, i)
        fname: str = Memory.read_i64(fnode + 8) as str
        if str_eq(fname, field_name) == 1:
            acc_val: i64 = Memory.read_i64(fnode + 40)
            if acc_val != 0:
                acc: str = acc_val as str
                if Memory.strlen(acc) > 0:
                    return acc
            return "public"
        i = i + 1
    return "public"
```

### Access enforcement — CRITICAL BUG FIX

**The bug:** `g_cur_method_struct` is initialized to `""` but in the self-hosted compiler runtime, `""` may be stored as a null pointer (`0x0`). Calling `Memory.strlen(0)` or `str_eq(0, anything)` segfaults.

**The fix:** Always guard with `(g_cur_method_struct as i64) != 0` BEFORE calling `Memory.strlen(g_cur_method_struct)`.

The correct pattern (used in `codegen/codegen_access.dlt`, `codegen/codegen_stmt.dlt`, and mirrored in `build/pipeline_build.dlt`):

```dolet
acc: str = get_field_access(obj_type, field_name)
if str_eq(acc, "private") == 1:
    in_struct: i32 = 0
    if (g_cur_method_struct as i64) != 0:
        if Memory.strlen(g_cur_method_struct) > 0:
            if str_eq(g_cur_method_struct, obj_type) == 1:
                in_struct = 1
    if in_struct == 0:
        IOOps.io_println(Str.concat("[error] Cannot access private field: ", field_name))
elif str_eq(acc, "protected") == 1:
    allowed: i32 = 0
    if (g_cur_method_struct as i64) != 0:
        if Memory.strlen(g_cur_method_struct) > 0:
            if str_eq(g_cur_method_struct, obj_type) == 1:
                allowed = 1
            if allowed == 0:
                par: str = get_parent_struct(g_cur_method_struct)
                if (par as i64) != 0:
                    if Memory.strlen(par) > 0:
                        if str_eq(par, obj_type) == 1:
                            allowed = 1
    if allowed == 0:
        IOOps.io_println(Str.concat("[error] Cannot access protected field: ", field_name))
```

This same pattern is in:
- `codegen/codegen_access.dlt` (field read enforcement, lines ~22–40)
- `codegen/codegen_stmt.dlt` (field assignment enforcement, lines ~89–113)
- `build/pipeline_build.dlt` — gen_field_access (~line 8506) and gen_field_assignment (~line 7348)

---

## 5. Phase 3 — What Was Done and What Remains

### What exists (already wired)

#### NS Node types (already defined in `parser/ast_nodes.dlt` and `build/pipeline_build.dlt`)

```
NODE_NS_ACCESS        = 121   # ns.symbol (variable/field access)
NODE_NS_STRUCT_INST   = 122   # ns.Struct(fields...)
NODE_NS_STATIC_METHOD = 123   # ns.Struct.method(args)
NODE_NS_FUN_CALL      = 124   # ns.func(args)
```

Node layouts (all use alloc_node, offsets in bytes):
```
NODE_NS_FUN_CALL    : +8=ns(str), +16=fname(str), +24=args(nodelist), +32=type_args(nodelist)
NODE_NS_STATIC_METHOD: +8=ns(str), +16=sname(str), +24=method(str),  +32=args(nodelist)
NODE_NS_ACCESS      : +8=ns(str), +16=symbol(str)
NODE_NS_STRUCT_INST : +8=ns(str), +16=sname(str), +24=field_vals(nodelist), +32=type_args(nodelist)
```

Constructors in `parser/ast_nodes.dlt` line ~1288:
- `mk_ns_access(ns, symbol) -> i64`
- `mk_ns_struct_inst(ns, sname, field_vals, type_args) -> i64`
- `mk_ns_static_method(ns, sname, method, args) -> i64`
- `mk_ns_fun_call(ns, fname, args, type_args) -> i64`

#### Module symbol registry (already added to `codegen/codegen_core.dlt` lines ~1160–1217)

```dolet
g_mod_sym_module: i64 = 0    # array of str ptrs
g_mod_sym_name: i64 = 0      # array of str ptrs
g_mod_sym_kind: i64 = 0      # array of i32 (0=fun, 1=struct, 2=var)
g_mod_sym_count: i32 = 0

fun init_module_registry(): ...
fun register_module_symbol(mod_name: str, sym_name: str, kind: i32): ...
fun lookup_module_symbol(mod_name: str, sym_name: str) -> i32: ...
```

`init_module_registry()` is called from `init_all_registries()`.

#### Codegen handlers (already added to `codegen/codegen_access.dlt` lines ~479–503)

```dolet
fun gen_ns_fun_call(node: i64) -> str:
    fname: str = Memory.read_i64(node + 16) as str
    args_list: i64 = Memory.read_i64(node + 24)
    proxy: i64 = Memory.malloc_zeroed(64)
    Memory.write_i32(proxy, 61)   # NODE_FUN_CALL
    Memory.write_i64(proxy + 8, fname as i64)
    Memory.write_i64(proxy + 16, args_list)
    return gen_fun_call(proxy)

fun gen_ns_static_method(node: i64) -> str:
    sname: str = Memory.read_i64(node + 16) as str
    mname: str = Memory.read_i64(node + 24) as str
    args_list: i64 = Memory.read_i64(node + 32)
    proxy: i64 = Memory.malloc_zeroed(64)
    Memory.write_i32(proxy, 85)   # NODE_STATIC_METHOD
    Memory.write_i64(proxy + 8, sname as i64)
    Memory.write_i64(proxy + 16, mname as i64)
    Memory.write_i64(proxy + 24, args_list)
    return gen_static_method_call(proxy)
```

#### Dispatch wired in `codegen/codegen_expr.dlt` (lines ~92–98) and `codegen/codegen_stmt.dlt` (lines ~785–788)

```dolet
# In gen_expr:
if nt == NODE_NS_FUN_CALL:
    return gen_ns_fun_call(node)
if nt == NODE_NS_STATIC_METHOD:
    return gen_ns_static_method(node)

# In gen_statement:
elif nt == NODE_NS_FUN_CALL:
    gen_ns_fun_call(node)
elif nt == NODE_NS_STATIC_METHOD:
    gen_ns_static_method(node)
```

---

### What STILL NEEDS TO BE DONE for Phase 3

#### TASK A — Parser: Produce NS nodes for dotted qualified calls

**File: `parser/parser_expr.dlt`**
**Function: `parse_dot_access(first: str)` (~line 230)**
**Function: `parse_chained_dot(base: i64)` (~line 285)**

Currently, when parsing `std.io.print("hello")`:
1. Parser sees `std` → `parse_ident_expr()` → detects `.` → calls `parse_dot_access("std")`
2. `parse_dot_access("std")` sees `io`, then another `.` → builds `mk_field_access("std", "io")` as base → calls `parse_chained_dot(base)`
3. `parse_chained_dot` sees `.print(args)` → produces `mk_nested_method(base, "print", args)` = `NODE_NESTED_METHOD` (95)
4. **`NODE_NESTED_METHOD` has NO codegen** — it produces nothing

**The fix needed:**
In `parse_dot_access`, detect when `first` is a module name (lowercase, no active variable) and produce NS nodes instead of field/method nodes.

Here is how `parse_dot_access` should be modified:

```dolet
fun parse_dot_access(first: str) -> i64:
    eat(TK_DOT)
    member: str = cur_val()
    eat(TK_IDENT)

    # Check for namespace-qualified call: ns.func(...) or ns.Struct.method(...)
    # A name is a "namespace candidate" if it's not a known variable
    if is_known_var(first) == 0:
        # ns.func(args) — two-part, function call with ns prefix
        if cur_kind() == TK_LPAREN:
            nargs: i64 = parse_arg_list()
            fc: i8 = Memory.read_i8(member as i64)
            if fc >= 65 and fc <= 90:
                # ns.Struct(fields) — namespaced struct instantiation
                return mk_ns_struct_inst(first, member, nargs, 0)
            return mk_ns_fun_call(first, member, nargs, 0)

        # ns.Struct.method(args) — three-part with dot chain
        if cur_kind() == TK_DOT:
            eat(TK_DOT)
            method: str = cur_val()
            eat(TK_IDENT)
            if cur_kind() == TK_LPAREN:
                margs: i64 = parse_arg_list()
                fc2: i8 = Memory.read_i8(member as i64)
                if fc2 >= 65 and fc2 <= 90:
                    return mk_ns_static_method(first, member, method, margs)
                return mk_ns_fun_call(first, Str.concat(Str.concat(member, "."), method), margs, 0)
            # ns.symbol — simple access
            return mk_ns_access(first, Str.concat(Str.concat(member, "."), method))

        # ns.symbol — simple two-part access
        return mk_ns_access(first, member)

    # ... rest of existing parse_dot_access logic unchanged (for regular obj.field, Struct.method) ...
```

**Note:** `is_known_var(name)` already exists — check `codegen/codegen_core.dlt` for `get_var_type` or `find_var` to see the signature; in the parser context you may need `is_var_declared(name)` from the parser's own scope tracking. Check `parser/parser_main.dlt` or `parser/parser_expr.dlt` for existing scope/var lookup functions.

**Alternatively (simpler approach):** Instead of checking `is_known_var`, use a **module name registry** at parse time. When the driver loads a module (in `driver/doletc_driver.dlt`), record the module name. In the parser, check if `first` matches a known module name. Add a `g_known_modules` array to the parser globals.

---

#### TASK B — `parse_dot_stmt` in `parser/parser_stmt.dlt` (~line 424)

Same logic as TASK A but for statement context. `parse_dot_stmt(name)` needs the same namespace detection to produce NS nodes when `name` is a module name.

---

#### TASK C — Module name registry in parser

Add globals to `parser/parser_main.dlt` (or wherever parser globals live):
```dolet
g_module_names: i64 = 0      # array of str ptrs — known module names
g_module_count: i32 = 0

fun init_module_names():
    g_module_names = Memory.malloc_zeroed(64 * 8)
    g_module_count = 0

fun register_module_name(name: str):
    off: i64 = (g_module_count as i64) * 8
    Memory.write_i64(g_module_names + off, name as i64)
    g_module_count = g_module_count + 1

fun is_module_name(name: str) -> i32:
    i: i32 = 0
    while i < g_module_count:
        off: i64 = (i as i64) * 8
        m: str = Memory.read_i64(g_module_names + off) as str
        if str_eq(m, name) == 1:
            return 1
        i = i + 1
    return 0
```

Then in `driver/doletc_driver.dlt`, when loading a module that has `module <name>` declaration, call `register_module_name(name)` before parsing the source.

---

#### TASK D — Mirror ALL Phase 3 changes in `build/pipeline_build.dlt`

`pipeline_build.dlt` is a **single-file compiler** that must mirror all changes:

1. Add module symbol registry globals + functions (same as `codegen/codegen_core.dlt` additions)
2. Add `init_module_registry()` call in `init_all_registries()` (search for `init_generic_registry()` in pipeline_build.dlt, add after it)
3. Add `gen_ns_fun_call()` and `gen_ns_static_method()` — find `gen_static_method_call` in pipeline_build.dlt (~line 8650 area) and add these two after it
4. Add NS dispatch in `gen_expr` — find the `NODE_STATIC_METHOD` dispatch in pipeline_build.dlt's gen_expr (~line 6290 area)
5. Add NS dispatch in `gen_statement` — find `NODE_STATIC_METHOD` in gen_statement (~line 8060 area)
6. Add module name registry globals + functions in the parser section of pipeline_build.dlt
7. Update `parse_dot_access` and `parse_dot_stmt` in pipeline_build.dlt (search for `fun parse_dot_access` ~line 4200 area)
8. Update driver's load_module to call `register_module_name` (search for `fun load_module` ~line 3500 area)

---

#### TASK E — Rebuild and test

After all changes:
```bash
python bootstrap/doletc.py build/pipeline_build.dlt -o bin/doletc.exe
./run_tests.bat   # must still be 41/41 PASS
```

Write a test file:
```dolet
# tests/test_ns_qualified.dlt
import std

fun main():
    std.print("hello from qualified call")       # ns.func()
    IOOps.io_println("normal still works")       # original still works
```

---

## 6. Phase 4 — Export Control (Pending)

In `mod.dlt` files, the user wants:
```
module mymod
export io          # visible to importers
private internal   # hidden, internal only
```

**What needs to be done:**
1. Parser for `mod.dlt` must parse `export <name>` and `private <name>` lines
2. Driver's `load_module()` must track which symbols are exported vs private
3. Add an export registry: `g_export_names`, `g_export_module`, `g_export_count`
4. In `resolve_and_load_imports()`, only expose exported symbols to the importing file
5. Mirror all in `pipeline_build.dlt`

---

## 7. Phase 5–7 — Use / From-Import / Function Visibility (Pending)

**`use` statement:**
```dolet
use std.collections.List   # brings List into scope directly
```

**`from X import Y`:**
```dolet
from std.io import print, println
```

**Function visibility:**
```dolet
private fun helper() -> i32:   # not accessible outside module
    return 42
```

These build on top of the export registry from Phase 4.

---

## 8. Existing Driver / Module Loading Architecture

**`driver/doletc_driver.dlt`** key functions:
- `try_resolve_module(mod_name)` — searches `stdlib/std/<path>/mod.dlt`, `stdlib/std/<path>/lib.dlt`, `library/<path>.dlt`
- `load_module(path)` — reads the file, parses `module`, `load`, `requires` directives, recursively loads dependencies
- `resolve_and_load_imports(ast)` — walks the AST, finds `import` statements, calls `load_module`, tracks duplicates via `loaded_names[]`

**`library/` structure:**
```
library/
  platform/
    mod.dlt          # module platform; load platform/alloc; load platform/io; ...
    alloc.dlt
    io.dlt
    str.dlt
  extra/
    math/mod.dlt     # module extra.math; load extra/math/math
    net/mod.dlt      # module extra.net; load extra/net/socket; load extra/net/http
    random/mod.dlt
  sys/windows/
    mod.dlt          # module sys.windows; load sys/windows/kernel32
```

---

## 9. Key Technical Gotchas

1. **Self-hosted compiler** — `bin/doletc.exe` is compiled from `build/pipeline_build.dlt` via Python bootstrap. After ANY change to pipeline_build.dlt, rebuild: `python bootstrap/doletc.py build/pipeline_build.dlt -o bin/doletc.exe`

2. **`g_cur_method_struct` null guard** — Always check `(g_cur_method_struct as i64) != 0` before `Memory.strlen(g_cur_method_struct)`. The empty string `""` is stored as null pointer in the runtime.

3. **Same null guard for any str** — Also check `(somestr as i64) != 0` before calling `Memory.strlen(somestr)` or `str_eq(somestr, ...)` if the string could be an uninitialized global.

4. **Struct instantiation** — Named fields ONLY: `Account(name="Alice", age=30)`. Positional args crash the self-hosted compiler.

5. **Nested Str.concat** — Avoid more than 2–3 nested `Str.concat` calls in error messages; prefer `Str.concat3(a, b, c)` or split into multiple variables.

6. **init_tokenizer_constants()** — In `pipeline_build.dlt`, ALL token constants MUST be re-initialized at runtime in `init_tokenizer_constants()`. If you add new `TK_*` constants, add them both to globals AND to that function.

7. **NODE_NESTED_METHOD (95) has no codegen** — The parser produces this for `a.b.c()` chain patterns but nothing handles it. Don't rely on it.

8. **`or` in if-conditions** — Dolet supports `if a or b:` but watch for precedence. Use parentheses when mixing with function calls.

---

## 10. Quick File Reference

| File | Purpose |
|------|---------|
| `build/pipeline_build.dlt` | **Single-file compiler amalgamation** — must mirror ALL changes |
| `lexer/tokenizer.dlt` | Token constants + keyword resolution |
| `parser/ast_nodes.dlt` | AST node type constants + constructor functions |
| `parser/parser_expr.dlt` | Expression parser — `parse_ident_expr`, `parse_dot_access`, `parse_chained_dot` |
| `parser/parser_stmt.dlt` | Statement parser — `parse_dot_stmt` |
| `parser/parser_main.dlt` | Main parser loop, top-level statement dispatch |
| `codegen/codegen_core.dlt` | All global registries, `init_all_registries()` |
| `codegen/codegen_types.dlt` | Type lookup functions, `get_field_access()` |
| `codegen/codegen_access.dlt` | `gen_fun_call`, `gen_static_method_call`, `gen_field_access`, `gen_ns_fun_call`, `gen_ns_static_method` |
| `codegen/codegen_expr.dlt` | `gen_expr` dispatch |
| `codegen/codegen_stmt.dlt` | `gen_statement` dispatch + field assignment enforcement |
| `driver/doletc_driver.dlt` | Module loading: `load_module`, `try_resolve_module`, `resolve_and_load_imports` |
| `library/` | Standard library `.dlt` files + `mod.dlt` manifests |
| `tests/features/` | 41 test files — all must pass |
| `bootstrap/doletc.py` | Python bootstrap (only for rebuilding `bin/doletc.exe`) |

---

## 11. Immediate Next Step

Start with **TASK C** (module name registry in parser), then **TASK A** (update `parse_dot_access`), then **TASK B** (`parse_dot_stmt`), then **TASK D** (mirror all in `pipeline_build.dlt`), then rebuild and test.

The codegen side (Tasks in §5 marked as "already added") is complete — `gen_ns_fun_call`, `gen_ns_static_method`, dispatch in `gen_expr`/`gen_statement`, and the module symbol registry are all wired in the individual codegen files. **Only `pipeline_build.dlt` still needs these mirrored** (TASK D).
