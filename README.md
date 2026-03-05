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

[![Written in Dolet](https://img.shields.io/badge/written%20in-Dolet-blue)]()
[![Platform](https://img.shields.io/badge/platform-Windows%20x64-lightgrey)]()

</div>

---

## Overview

The Dolet compiler (`doletc.exe`) is **written in Dolet itself** — it's a self-hosting compiler. It reads `.dlt` source files and produces native Windows executables through the following pipeline:

```
.dlt → Tokenize → Parse → Generate MLIR → LLVM IR → Object → Executable
```

The compiler uses **no C runtime** — all runtime functions (memory, I/O, strings, process management) are implemented in pure Dolet using the Windows API directly.

## Quick Start

### Option 1: Download Pre-built Release

Download the latest release from [Releases](https://github.com/dolet-lang/dolet-compiler/releases), extract, and run:

```batch
bin\doletc.exe hello.dlt -o hello.exe
hello.exe
```

### Option 2: Build from Source

See [Building from Source](#building-from-source) below.

## Usage

```
doletc <input.dlt> [-o output.exe] [--keep-mlir] [--keep-llvm] [--no-runtime]
```

| Option | Description |
|--------|-------------|
| `-o <path>` | Output executable path (default: `<input>.exe`) |
| `--keep-mlir` | Keep intermediate `.mlir` file |
| `--keep-llvm` | Keep intermediate `.ll` file |
| `--no-runtime` | Don't auto-import runtime libraries |

## Language Features

- **Static typing** with type inference
- **Primitive types**: `i8`, `i16`, `i32`, `i64`, `i128`, `u8`–`u128`, `f32`, `f64`, `bool`, `str`, `char`
- **Structs** with static and instance methods
- **Enums** with variants
- **Pattern matching** (`match`/`case`)
- **Generic collections**: `list<T>`, `array<T>`, `map<K, V>`
- **Async/Await** with event loop
- **FFI** — `extern` blocks for C / Windows API interop
- **Module system** — `import` with automatic resolution
- **No C runtime dependency** — pure Windows API

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

a: Point = Point(0.0, 0.0)
b: Point = Point(3.0, 4.0)
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
├── bin/doletc.exe         # Compiled compiler
├── build/                 # Build artifacts
├── tests/                 # Test files
├── dltc.bat               # Batch driver script
└── build_release.bat      # Release builder script
```

## Building from Source

The compiler is self-hosting, so you need the [bootstrap compiler](https://github.com/dolet-lang/dolet-bootstrap) (written in Python) for the first build.

### Prerequisites

- **Python 3.8+**
- **LLVM Tools**: `clang.exe`, `lld-link.exe`, `mlir-translate.exe`

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

Your folder should look like:

```
dolet-compiler/
├── bootstrap/         # Python bootstrap compiler (cloned)
├── library/           # Standard library & runtime (cloned)
│   ├── std/           # Runtime, std, sys, core
│   └── importable/    # Math, net, random
├── tools/             # LLVM toolchain (cloned)
│   ├── clang.exe
│   ├── lld-link.exe
│   └── mlir-translate.exe
├── lexer/             # ← Compiler source (this repo)
├── parser/
├── codegen/
└── driver/
```

### 3. Build the Compiler

```batch
python bootstrap\build.py compile
```

This produces `bin\doletc.exe`.

### 4. Verify

```batch
bin\doletc.exe tests\test_print.dlt -o test.exe
test.exe
```

### 5. Build a Release (optional)

```batch
build_release.bat 0.3
```

This creates `dist\dolet-v0.3-windows-x64.zip` ready for distribution.

## Self-Hosting Flow

```
┌──────────────────────────────────────────────────────────┐
│  First Build (Bootstrap)                                 │
│  Python bootstrap ──compiles──> doletc.exe               │
│                                                          │
│  Self-Hosting (future)                                   │
│  doletc.exe ──compiles──> doletc.exe                     │
└──────────────────────────────────────────────────────────┘
```

## Related Repositories

| Repository | Description |
|------------|-------------|
| [dolet-compiler](https://github.com/dolet-lang/dolet-compiler) | The Dolet compiler (this repo) |
| [dolet-bootstrap](https://github.com/dolet-lang/dolet-bootstrap) | Python bootstrap compiler |
| [library](https://github.com/dolet-lang/library) | Standard library, runtime & importable libs |
| [tools](https://github.com/dolet-lang/tools) | LLVM toolchain for Windows x64 |

## License

Dolet Programming Language — [dolet-lang](https://github.com/dolet-lang)
