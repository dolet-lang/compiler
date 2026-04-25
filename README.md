# Dolet Compiler

<div align="center">

```

    ██████╗  ██████╗ ██╗     ███████╗████████╗
    ██╔══██╗██╔═══██╗██║     ██╔════╝╚══██╔══╝
    ██║  ██║██║   ██║██║     █████╗     ██║
    ██║  ██║██║   ██║██║     ██╔══╝     ██║
    ██████╔╝╚██████╔╝███████╗███████╗   ██║
    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝   ╚═╝

```

**A self-hosting systems programming language that compiles to native code via MLIR/LLVM.**

[![Version](https://img.shields.io/badge/version-v1.4.0--beta-green)]()
[![Written in Dolet](https://img.shields.io/badge/written%20in-Dolet-blue)]()
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey)]()

</div>

---

## Overview

The Dolet compiler (`doletc`) is **written in Dolet itself** — it's a self-hosting compiler. It reads `.dlt` source files and produces native executables through the following pipeline:

```
.dlt → Tokenize → Parse → Generate MLIR → LLVM IR → Object → Executable
```

The compiler is **platform-neutral** — it reads all toolchain and linker configuration from `platform.conf` files at `library/platform/<os>/`. No platform-specific knowledge is hardcoded in the compiler itself.

The runtime uses **no C runtime** — all runtime functions (memory, I/O, strings, process management) are implemented in pure Dolet using the OS API directly (Windows API / Linux raw syscalls).

## Quick Start

### Option 1: Download Pre-built Release

Download the latest release from [Releases](https://github.com/dolet-lang/dolet-compiler/releases), extract, and run:

```batch
doletc hello.dlt -o hello --target windows
```

### Option 2: Build from Source

See [Building from Source](#building-from-source) below.

## Usage

```
doletc <input.dlt> [-o output] [--target <os>] [--release] [--keep-mlir] [--keep-llvm]
```

| Option | Description |
|--------|-------------|
| `-o <path>` | Output executable path (extension added from platform config) |
| `--target <os>` | Target platform — loads `library/platform/<os>/platform.conf` |
| `--release` | Build as GUI app (no console window, Windows only) |
| `--keep-mlir` | Keep intermediate `.mlir` file |
| `--keep-llvm` | Keep intermediate `.ll` file |

## Idioms

- **String concatenation:** use `a + b` or `a.concat(b)`. Both are
  compiler-dispatched to an arena-backed builtin inside a bracketed
  scope, so the intermediate string is freed automatically when the
  scope exits. Never use `Str.concat()` (the static form) in user
  code — it always heap-allocates and the caller must remember to
  `Memory.free`. It exists for compiler internals and rare cases
  where a long-lived heap string is genuinely wanted.

## Language Features

- **Static typing** with type inference
- **Primitive types**: `i8`, `i16`, `i32`, `i64`, `i128`, `u8`-`u128`, `f32`, `f64`, `bool`, `str`, `char`
- **Structs** with static and instance methods
- **Enums** with variants
- **Pattern matching** (`match`/`case`)
- **Generic collections**: `list<T>`, `array<T>`, `map<K, V>`
- **Custom annotations**: `@inline`, `@hot`, `@deprecated`, composable user-defined annotations
- **Async/Await** with event loop
- **FFI** — `extern` blocks for C / OS API interop
- **Module system** — `import`, `from X import Y`, `use`, access control
- **Cross-platform** — Windows x64 and Linux x64 (no libc)

## Example

```dolet
fun factorial(n: i32) -> i32:
    if n <= 1:
        return 1
    return n * factorial(n - 1)

result: i32 = factorial(10)
print(result)
```

```dolet
struct Point:
    x: f64
    y: f64

    fun distance(self, other: Point) -> f64:
        dx: f64 = self.x - other.x
        dy: f64 = self.y - other.y
        return Math.sqrt(dx * dx + dy * dy)

a: Point = Point(x=0.0, y=0.0)
b: Point = Point(x=3.0, y=4.0)
print(a.distance(b))
```

## Project Structure

```
dolet-compiler/
├── lexer/                 # Tokenizer
│   └── tokenizer.dlt
├── parser/                # Recursive descent parser + AST
│   ├── ast_nodes.dlt
│   ├── parser_core.dlt
│   ├── parser_expr.dlt
│   ├── parser_stmt.dlt
│   ├── parser_decl.dlt
│   └── parser_main.dlt
├── codegen/               # MLIR code generation
│   ├── codegen_core.dlt
│   ├── codegen_types.dlt
│   ├── codegen_expr.dlt
│   ├── codegen_stmt.dlt
│   ├── codegen_decl.dlt
│   ├── codegen_access.dlt
│   └── codegen_main.dlt
├── driver/                # CLI driver
│   ├── pipeline_init.dlt
│   └── doletc_driver.dlt
├── library/               # Standard library & runtime (separate repo)
│   ├── core/              # Memory, types (zero OS dependency)
│   ├── std/               # Standard IO
│   ├── extra/             # Math, random
│   └── platform/          # OS-specific layers
│       ├── windows/       # Windows API bindings, .lib files, platform.conf
│       └── linux/         # Raw syscall wrappers, platform.conf
├── build/                 # Single-file amalgamation (pipeline_build.dlt)
├── tests/                 # 48 feature + e2e tests
└── build.bat              # Bootstrap build script
```

## Building from Source

The compiler is self-hosting, so you need the [bootstrap compiler](https://github.com/dolet-lang/dolet-bootstrap) (written in Python) for the first build.

### Prerequisites

- **Python 3.8+**
- **LLVM 17+ Tools**: `clang`, `lld-link` / `ld.lld`, `mlir-translate`

### 1. Clone the Compiler

```batch
git clone https://github.com/dolet-lang/dolet-compiler.git
cd dolet-compiler
```

### 2. Clone Dependencies (inside dolet-compiler)

```batch
git clone https://github.com/dolet-lang/dolet-bootstrap.git bootstrap
git clone https://github.com/dolet-lang/library.git library
git clone https://github.com/dolet-lang/tools.git tools
```

### 3. Build the Compiler

```batch
build.bat
```

Or manually:

```batch
python bootstrap\doletc.py build\pipeline_build.dlt -o bin\doletc.exe --target windows
```

### 4. Verify (Self-Hosting)

```batch
bin\doletc.exe build\pipeline_build.dlt -o bin\doletc2.exe --target windows
```

If `doletc2.exe` compiles successfully, the compiler can compile itself.

### 5. Run Tests

```batch
run_tests.bat
```

All 48 tests should pass.

## Self-Hosting Flow

```
┌──────────────────────────────────────────────────────────────────┐
│  Stage 1 — Bootstrap                                             │
│  Python bootstrap ──compiles──> bin/doletc.exe                   │
│                                                                  │
│  Stage 2 — Self-Hosting                                          │
│  doletc.exe ──compiles──> bin/doletc2.exe                        │
│                                                                  │
│  Stage 3 — Verification                                          │
│  doletc2.exe ──compiles──> bin/doletc3.exe                       │
└──────────────────────────────────────────────────────────────────┘
```

## Platform Configuration

The compiler reads all platform-specific settings from `library/platform/<os>/platform.conf`:

```ini
[toolchain]
translate = mlir-translate.exe
compile = clang.exe
linker = lld-link.exe
obj_ext = .obj
exe_ext = .exe

[link]
default_libs = kernel32, ws2_32, msvcrt-math
runtime_helpers = runtime_helpers.obj
entry = main

[link.flags]
output = -out:{path}
flag_entry = -entry:{name}
stack = -stack:{size}
```

To add a new platform, create `library/platform/<name>/platform.conf` and use `--target <name>`.

## Related Repositories

| Repository | Description |
|------------|-------------|
| [dolet-compiler](https://github.com/dolet-lang/dolet-compiler) | The Dolet compiler (this repo) |
| [dolet-bootstrap](https://github.com/dolet-lang/dolet-bootstrap) | Python bootstrap compiler |
| [library](https://github.com/dolet-lang/library) | Standard library, runtime & platform layers |
| [tools](https://github.com/dolet-lang/tools) | LLVM toolchain for Windows x64 |

## License

Dolet Programming Language — [dolet-lang](https://github.com/dolet-lang)
