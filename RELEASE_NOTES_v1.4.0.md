# 🛠️ Dolet Compiler v1.4.0-beta

By the grace of Allah — the biggest leap yet. Scope arena, `+` and `.concat()` for strings, self-managing memory, `imm`/`mut`, and a full struct-stomp fix in the self-hosted backend. ✨

## 🆕 What's New (since v1.2.0-beta)

### 🧠 Scope Arena Allocator

Every bracketed scope (the `while` body, an `if` body, any function body that doesn't return `str`) opens a bump-pointer arena frame and pops it at exit. Transient strings, formatter results, and intermediate concatenations all live there — the next pop reclaims every byte automatically. Zero ceremony, zero free calls in user code.

- 16 MiB reserve per arena, HeapAlloc-backed on Windows 📦
- `push` / `pop` are single-pointer bumps — O(1), no fragmentation ⚡
- Global exempt list for arena-allocating builtins so they don't self-recurse 🛡️
- Lives in `library/core/arena.dlt` — pure Dolet, no C runtime 🌐

### ✨ `+` and `.concat()` on `str`

String concatenation is now a safe, arena-managed operation. Both forms below produce the same MLIR — a direct call to `_str_plus` inside any bracketed scope:

```dolet
greeting: str = "hello, " + name
label:    str = "level: ".concat(Convert.i32_to_str(volume))
```

The call-site dispatcher in codegen rewrites `Convert.*_to_str`, `str_concat`, and the `+` operator to their arena-backed variants when `g_arena_emit == 1`. Outside a bracket (e.g. a function that returns `str`) the same code falls back to the heap path — so escaping the scope still works if you really need it.

- **Policy**: `Str.concat()` (static form on the `Str` struct) is now reserved for compiler internals — never call it from user code. The new `extend str` method `a.concat(b)` and the `+` operator are the only forms apps should use. 📜
- `_str_plus`, `_str_dupe`, `_str_heap_dupe`, `_arena_i32_to_str`, `_arena_i64_to_str`, `_arena_bool_to_str` live in `library/core/str_ops.dlt` — all pure Dolet. 🔧

### 🔒 `imm` and `mut` keywords

Variables can now be explicitly typed as `imm` (immutable) or `mut` (mutable) at the declaration site. Default stays as it was; the keywords let you tell readers which values the compiler can assume never re-bind, and eventually they'll feed escape analysis for stricter arena routing.

```dolet
imm title: str = "Eqoi Framework"   # compiler knows this won't re-bind
mut counter: i32 = 0
counter = counter + 1                # allowed
```

### 🐞 Struct-stomp crash fixed

Self-hosted builds that used structs with more than ~20 fields were hitting a silent stack overwrite when a child struct returned by value (sret ABI). The fix:

- **Entry-block alloca hoisting**: every sret-temporary now lives in the caller's entry block, not at its use site, so the callee's dead stack can't stomp it. See `gen_main_body` + `gen_fun_def` + `gen_method_def` in `codegen/`. 🧱
- **Buffer overflow fix**: bumped `mk_node_list(64)` to `mk_node_list(512)` at three sites so big structs (EqoiApp has 84 fields) don't overflow the AST node list. 📋

### 📈 Transitive import resolution

`import a.b.c` now pulls in `a.b`'s dependencies too, recursively. No more "missing struct X" errors when package A depends on package B which depends on core module C. 🔗

### 🧩 Platform-driven runtime loading

The runtime now loads in a strict order: `core` → `platform` → `std`. The core module has zero OS knowledge, the platform layer wraps the OS, and std builds on both — bare-metal targets can just drop the platform layer. 🌐

### 📦 Pure-Dolet UI + Eqoi framework

- **`packages/ui` v0.6.1** — framebuffer cache (allocated once, re-used across frames), bitmap text, mouse state, draw-command recording. Pure software, zero Win32 in the package itself. 🖼️
- **`packages/eqoi` v0.4.0** — widget framework on top of `ui` + `window`: title, label, button, checkbox, toggle, slider, progress_bar, text_input, tooltip, panel, modal, scrollbar_vertical, scrollable, tab_bar, dropdown, drag_source, drop_target. All state slots managed by `EqoiApp` — no manual `Memory.malloc` / `Memory.free` pairs in user code. 🎛️

### 🐞 Other fixes

- Static-field codegen segfault + late string emission (v1.2.1) 🛠️
- Heap corruption on structs with >64 fields (v1.3.1) 🛠️
- Framebuffer not freed on window resize — now re-cached in place, no per-frame heap growth 🛠️
- `Str.concat()` leaks in `simple-app-eqoi` (per-frame label leak) and `FileManager` (click + format_size + filtered-entry leaks) — all fixed at the call site by migrating to `+` / `.concat()` 🛠️
- `--version` flag now prints version and exits cleanly 📟

## 📊 Compiler Stats

- **Current binary**: `bin/doletc.exe` — 292 KB ⚡
- **Pipeline**: 14,072 lines (single-file amalgamation) 📄
- **Core library**: 932 lines (arena + math + memory + str_ops + mod) 📚
- **Test suite**: 22 feature tests + 18 comprehensive tests = 40 passing ✅
- **Stage 3 self-host**: binary-stable — `doletc2.exe == doletc3.exe` 💎
- **Delta since v1.2.0-beta**: 22 files changed, +2,542 / −3,852 lines (net shrink — a lot of the churn was replacing hardcoded paths and removing dead C-runtime shims) 📊

## 🌍 Supported Platforms

- **Windows x64**: fully supported (GUI and console) 🔵
- **Linux x64**: platform layer ready (no libc — raw syscalls) 🟢
- **Bare-metal**: core + str_ops + arena compile cleanly; just add a minimal platform layer 🟡

## 📝 Notes

- This is a pre-release (beta) 🧪
- Requirements: LLVM/MLIR tools (`clang`, `lld-link`, `mlir-translate`) must be in `PATH` ⚙️
- Full changelog: `git log v1.2.0-beta..v1.4.0-beta` in this repo 📜
- Related repos: [library](https://github.com/dolet-lang/library), [eqoi-core](https://github.com/Eqoi/eqoi-core), [ui](https://github.com/dolet-lang/ui), [tools](https://github.com/dolet-lang/tools) 🔗
