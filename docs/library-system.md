# Dolet Library System

## Overview

The Dolet library system provides a structured, modular way to organize and load code. It is designed for systems-level programming with explicit control over what gets loaded and when.

The system has two layers:
- **Internal** (`load`, `requires`, `expose`, `private`) — used inside library `mod.dlt` files
- **External** (`import`, `from...import`) — used in user programs

---

## Directory Structure

```
library/
├── mod.dlt                    # Root registry — maps module names to paths
├── core/
│   ├── mod.dlt                # Core runtime manifest
│   ├── memory.dlt             # Memory struct (malloc, read, write, etc.)
│   └── types/
│       ├── integers.dlt       # I8..I128, U8..U128
│       ├── floats.dlt         # F32, F64
│       ├── primitives.dlt     # Bool, Char, Pointer, StrType
│       └── collections.dlt    # List, Array, Map
├── platform/
│   ├── mod.dlt                # Platform abstraction manifest
│   ├── alloc.dlt              # Memory allocation (Convert struct)
│   ├── format.dlt             # Number-to-string conversion
│   ├── str.dlt                # Str struct (string operations)
│   └── io.dlt                 # IOOps struct (console I/O)
├── std/
│   ├── mod.dlt                # Standard library manifest
│   └── io.dlt                 # High-level print/println functions
├── sys/
│   └── windows/
│       ├── mod.dlt            # Windows OS layer manifest
│       └── kernel32.dlt       # Win32 API extern declarations
└── extra/
    ├── math/
    │   └── mod.dlt            # Math utilities
    ├── net/
    │   └── mod.dlt            # Networking utilities
    └── random/
        └── mod.dlt            # Random number generation
```

---

## Root Registry: `library/mod.dlt`

The root registry is the entry point for the compiler. It maps logical module names to their `mod.dlt` paths:

```dlt
# Syntax: module <path> as <name>
module core/mod as core
module std/mod as std
module platform/mod as platform
module sys/windows/mod as sys.windows
module extra/math/mod as extra.math
module extra/net/mod as extra.net
module extra/random/mod as extra.random
```

When a user writes `import std`, the compiler:
1. Reads `library/mod.dlt`
2. Finds `module std/mod as std`
3. Loads `library/std/mod.dlt`
4. Processes all `load` directives inside it

---

## mod.dlt Directives

### `module <name>`
Declares the namespace for this module.

```dlt
module std
```

### `load <path>`
Includes a file's source code into the module. This is a raw text concatenation that happens before tokenization — similar to C's `#include`. Paths are relative to the `library/` root.

```dlt
load sys/windows/kernel32
load platform/alloc
load platform/str
```

### `export <symbol>`
Declares a symbol as part of the module's public API. Used for documentation and future access control.

```dlt
export Memory
export Convert
export Str
export print
export println
```

### `expose <path> as <name>`
Maps a sub-module name to a file path for selective imports. When a user writes `import std.string`, the compiler looks for `expose platform/str as string` in `std/mod.dlt`.

```dlt
expose platform/str as string
expose std/io as io
expose platform/format as format
expose core/types/collections as collections
expose platform/alloc as alloc
expose sys/windows/kernel32 as kernel
```

### `private <name>`
Excludes a sub-module from being loaded when the parent module is imported. The sub-module's code is skipped during `load`.

```dlt
private internal_debug
```

### `requires <path>`
Declares a dependency on another file. Used in individual `.dlt` files (not `mod.dlt`). The dependency resolver reads these to build the correct load order.

```dlt
# In platform/alloc.dlt:
requires sys/windows/kernel32

# In platform/str.dlt:
requires platform/alloc

# In std/io.dlt:
requires platform/io
requires platform/format
```

---

## Import Syntax (User-Facing)

### Full module import
Loads the entire module and all its sub-modules:
```dlt
import std
```

### Selective import (single)
Loads only the specified sub-module and its dependency chain:
```dlt
import std.io
import std.string
import std.collections
```

### Selective import (bracket syntax)
Loads multiple sub-modules in a single statement:
```dlt
import std.[io, string]
import std.[collections, format, alloc]
```

### From-import (symbol selection)
Import specific symbols from a module:
```dlt
from std import IOOps, Convert
from std import print, println
```

---

## Dependency Resolution

### Full `import std` Flow

1. Compiler loads `library/std/mod.dlt`
2. Processes each `load` directive in order
3. For each `load`, reads the file and concatenates its source
4. All loaded code is prepended to the user's source before tokenization

### Selective `import std.io` Flow

1. Compiler scans user source for `import std.<name>` patterns
2. Reads `library/std/mod.dlt` and finds `expose io = std/io`
3. Reads `library/std/io.dlt`, finds `requires platform/io` and `requires platform/format`
4. Recursively loads each dependency:
   - `platform/io` → requires `sys/windows/kernel32` → loads kernel32, then io
   - `platform/format` → requires `platform/alloc` → requires `sys/windows/kernel32` → already loaded (skipped), then alloc, then format
5. Returns dependency source + file source concatenated
6. Duplicate-load tracking prevents any file from being loaded twice

### Dependency Tree

```
core (always auto-loaded)
├── core/memory
└── core/types/
    ├── integers
    ├── floats
    └── primitives

sys/windows/kernel32 (no deps — extern declarations)

platform/alloc → kernel32
platform/format → alloc → kernel32
platform/str → alloc → kernel32
platform/io → kernel32

std/io → platform/io + platform/format
core/types/collections → platform/alloc → kernel32
```

---

## Core vs Standard Library

| | Core (`core`) | Standard Library (`std`) |
|---|---|---|
| **Loading** | Auto-loaded for every program | Loaded on `import std` or `import std.*` |
| **Contains** | Memory, numeric types, primitives | I/O, strings, formatting, collections |
| **Dependencies** | None (foundation layer) | Depends on core + platform + sys |
| **Size** | ~8KB of source | ~52KB of source (all sub-modules) |

### Why separate?

Every Dolet program needs memory management and basic types — these are in `core` and always available. The standard library adds I/O, string manipulation, and collections, but a minimal program (e.g., an embedded kernel) might not need or want these.

Selective imports (`import std.io`) let you load only what you need, keeping binary size minimal.

---

## Available Selective Imports

| Name | Path | Provides | Dependencies |
|------|------|----------|--------------|
| `std.io` | `std/io` | `print`, `println`, `print_no_newline`, `flush` | platform/io, platform/format |
| `std.string` | `platform/str` | `Str` struct | platform/alloc |
| `std.format` | `platform/format` | `Convert` struct | platform/alloc |
| `std.collections` | `core/types/collections` | `List`, `Array`, `Map` | platform/alloc |
| `std.alloc` | `platform/alloc` | `Memory.malloc`, `Memory.realloc` | sys/windows/kernel32 |
| `std.kernel` | `sys/windows/kernel32` | Win32 FFI externs | (none) |

---

## Examples

### Minimal print program
```dlt
import std.io

fun main():
    print("Hello, world!")
```

### Using strings and I/O
```dlt
import std.[io, string]

fun main():
    greeting: str = Str.concat("Hello, ", "Dolet!")
    print(greeting)
```

### Full standard library
```dlt
import std

fun main():
    items: List = List.new()
    items.push("first")
    items.push("second")
    print(Str.concat("Count: ", Convert.i64_to_str(items.len())))
```

### Importing specific symbols
```dlt
from std import IOOps, Convert

fun main():
    IOOps.io_println("Direct I/O access")
```
