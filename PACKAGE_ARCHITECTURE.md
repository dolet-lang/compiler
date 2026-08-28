# Dolet Package Architecture

Every Dolet package declares which layer it belongs to. The layer determines
what the package is allowed to depend on and whether it may touch the operating
system. This document is the contract; `scripts/check_package_layers.py`
enforces it.

## The law

**Dependencies point down. Never up, never sideways into a lower-privilege
layer.**

```
composition   eqoi   web   kobic   frog          frameworks and applications
                  ▲
pure          fonts   ui   image   json          Dolet only, zero OS calls
                  ▲
os            window   input   net               OS syscalls and own native code
                  ▲
binding       glfw   vulkan   mysql              FFI wrappers around third-party
                                                 native libraries
```

A package may depend on its own layer and on layers below it, with one
exception: `pure` may depend only on `pure`. That exception is the whole point
of the layer — a pure package must stay testable and portable with no window,
no display server, and no libc beyond what the Dolet runtime already provides.

## The four layers

### `pure`

Written entirely in Dolet. No `extern lib`, no native sources, no
`[link.*]` flags, no OS calls. Depends only on other `pure` packages.

A pure package must be fully testable without opening a window. This is not a
style preference — it is what makes the package cross-compilable to any target,
including bare metal, and what makes its test suite run in CI without a display
server.

Current: `fonts`, `ui`, `image`, `json`.

### `os`

Talks to the operating system directly: syscalls, platform APIs, and native
sources compiled from this repository. May declare `[link.*]` flags and ship a
static library built from its own `native/` sources.

An `os` package must present a target-neutral public API. Callers must not be
able to tell which backend is live. `window` is the reference implementation:
the same API runs on Win32, Wayland, and X11, and `window_backend()` reports
which one was selected at runtime.

Current: `window`, `input`, `net`.

### `binding`

An FFI wrapper around a third-party native library the project did not write.
The library is a build and runtime prerequisite for anyone using the package.

Current: `glfw`, `vulkan`, `mysql`.

### `composition`

Frameworks and applications assembled from the layers below. A composition
package is the only kind allowed to combine `pure` and `os` in one dependency
set. It should contain no `extern lib` of its own — if it needs the OS, that
belongs in an `os` package it depends on.

Current: `eqoi`, `web`, `kobic`, `frog`.

## From-scratch guarantee

A package may declare that its entire transitive dependency tree is built from
scratch, with no third-party native library anywhere in it:

```ini
[info]
no-bindings = true
```

The checker walks the full tree and fails if it reaches a `binding` package.

`eqoi` carries this guarantee. Anything Eqoi needs is either pure Dolet or an
`os` package whose native sources live in this project. This is deliberate: an
Eqoi application must build from a Dolet toolchain and a system C compiler
alone, with nothing to install first.

`kobic` and `frog` do not carry the guarantee — they depend on `vulkan`, which
is correct for a GPU engine and out of scope for this rule.

## `module.meta` schema

Every package ships a `module.meta` at its root. Two spellings existed
historically (`[info]` and `[package]`); `[info]` is canonical.

```ini
# Short description of what this package is and what it must never become.

[info]
name = ui
version = 0.9.0
layer = pure
description = One line, present tense, describing what the package provides.
author = xRo0t
license = MIT

# Optional. Present only when the from-scratch tree is a guarantee.
no-bindings = true

[dependencies]
fonts = "*"

# Import libraries to link. Forbidden for `pure`.
[libs]
linux = libdolet_window_linux.a

# Runtime libraries to copy next to the executable. Forbidden for `pure`.
[dlls]

# Per-platform native linking. Forbidden for `pure`.
[link.windows]
system_libs = user32, gdi32, kernel32

[link.linux]
flags = -ldolet_window_linux -lwayland-client

[link.macos]
```

`layer` is required. The checker reports a missing `layer` as an error, so a new
package cannot silently join the tree without declaring what it is.

## What the checker enforces

`python scripts/check_package_layers.py [--packages <dir>]`

| Rule | Applies to |
| --- | --- |
| `layer` is declared and is one of the four values | every package |
| No `extern lib` in any `.dlt` source | `pure`, `composition` |
| No `[libs]`, `[dlls]`, or `[link.*]` entries | `pure` |
| No `native/` sources | `pure` |
| Dependencies are `pure` only | `pure` |
| Dependencies are not `binding` | `os` |
| Transitive tree contains no `binding` | `no-bindings = true` |

The checker exits non-zero on any violation, so it can gate CI.

## Adding a package

1. Decide the layer first. If it needs the OS, it is `os` and its public API
   must be target-neutral. If it wraps someone else's `.so`/`.dll`, it is
   `binding`. Otherwise it is `pure`.
2. Create `mod.dlt` with `module <name>`, the `load` lines, and the `export`
   list. Note that `export` is documentation only — the compiler does not gate
   visibility on it (`AGENTS.md`), so the export list is a contract maintained
   by convention and by review, not by the toolchain.
3. Create `module.meta` using the schema above.
4. Add `README.md` and `tests/smoke.dlt`.
5. Run `python scripts/check_package_layers.py` before the first commit.

## Why the layers are drawn here

The split already existed in the code before it was written down. `fonts`
carried the comment "zero OS calls", `ui` carried "No platform libraries", and
`image` carried "no system libs" — three packages independently asserting the
same property with no shared name for it and nothing checking it.

Naming it costs one field per manifest. Not naming it costs the property: the
first time a pure package reaches for a platform API to solve something quickly,
the whole layer stops being cross-compilable, and nothing reports it until a
target that lacks the API fails to build.
