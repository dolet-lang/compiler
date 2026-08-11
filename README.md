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

[![Version](https://img.shields.io/badge/version-v2.0.0--beta-green)]()
[![Written in Dolet](https://img.shields.io/badge/written%20in-Dolet-blue)]()
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey)]()

</div>

---

## Overview

The Dolet compiler (`doletc`) is **written in Dolet itself** — it's a self-hosting compiler. It reads `.dlt` source files and produces native executables through the following pipeline:

```
.dlt → Tokenize → Parse → Generate MLIR → LLVM IR → Object → Executable
```

The compiler is **platform-neutral**: it reads target ABI, toolchain roles,
link order, native libraries, and target-owned resources from
`library/platform/<os>/targets/<arch>-<abi>/platform.toml`. No operating
system or libc is selected by hardcoded compiler branches.

Runtime policy belongs to the target pack. For example,
`windows/x86_64-msvc` uses the Windows platform resources, while the
self-contained `linux/x86_64-musl` pack owns musl, its CRT objects, and the
Dolet runtime helpers required for cross-building from Windows.

## Quick Start

### Option 1: Download Pre-built Release

Download the latest release from [Releases](https://github.com/dolet-lang/dolet-compiler/releases), extract, and run:

```batch
doletc hello.dlt -o hello.exe --target windows/x86_64-msvc
doletc hello.dlt -o hello --target linux/x86_64-gnu
doletc hello.dlt -o hello-static --target linux/x86_64-musl
```

### Option 2: Build from Source

See [Building from Source](#building-from-source) below.

## Usage

```
doletc <input.dlt> [-o output] [--target <os/arch-abi>] [--release] [--keep-mlir] [--keep-llvm]
```

| Option | Description |
|--------|-------------|
| `-o <path>` | Output executable path (extension added from platform config) |
| `--target <os/arch-abi>` | Canonical target ID, such as `windows/x86_64-msvc`, `linux/x86_64-gnu`, or `linux/x86_64-musl` |
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

## Error Model

- **Recoverable errors** (planned): return `Result<T, E>`.
- **Unrecoverable errors**: `panic "message"` — prints `[panic] message`
  to stdout and exits with code `101` (matches the Rust convention).
  ```dolet
  if denominator == 0:
      panic "division by zero"
  ```

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
│       ├── windows/       # Windows modules and ABI target packs
│       └── linux/         # Linux modules and ABI target packs
├── build/                 # Single-file amalgamation (pipeline_build.dlt)
├── tests/                 # Feature, regression, and e2e tests
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

For normal multi-target development, Obin uses the already trusted
`bin/doletc.exe`, regenerates the amalgamated source only when its contents
change, and isolates every artifact by target:

```batch
obin build --profile release --all-targets
obin package --profile release --all-targets
```

This produces `doletc.exe` for `windows/x86_64-msvc`, a GNU Linux `doletc`,
and a static musl Linux `doletc`. SDK packages place the compiler under `bin/`
and stage the Dolet library, target packs, toolchain manifest, and matching
host-tool slot. The Windows package is full because its LLVM/MLIR host pack is
present locally. Linux packages are thin until the Linux host pack is populated;
run `tools/setup_tools.sh <llvm-directory>` on Linux before compiling programs
with them. The setup script links to the native LLVM installation instead of
copying isolated executables, preserving LLVM/MLIR shared-library resolution.
The GNU and static-musl compiler executables themselves are already cross-built
and runnable. `build.bat` remains the independent byte-stable bootstrap trust
path and must still be used after compiler changes.

Or manually:

```batch
python scripts\generate_pipeline.py
python bootstrap\doletc.py build\pipeline_build.dlt -o bin\doletc.exe --target windows
```

### 4. Verify (Self-Hosting)

```batch
bin\doletc.exe build\pipeline_build.dlt -o bin\doletc2.exe --target windows/x86_64-msvc
```

If `doletc2.exe` compiles successfully, the compiler can compile itself.

### 5. Run Tests

```batch
run_tests.bat
```

The selected test suites should pass.

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

## Target Packs

Each canonical target is a self-contained manifest under
`library/platform/<os>/targets/<arch>-<abi>/platform.toml`:

```toml
schema = 2
id = "linux/x86_64-musl"
os = "linux"
arch = "x86_64"
abi = "musl"
module_root = "platform/linux"
registry = "platform/linux/registry.dlt"
resource_root = "platform/linux/targets/x86_64-musl/resources"

[toolchain]
toolchain_id = "llvm"
toolchain_version = "1"
translate_role = "translate"
compile_role = "compile"
link_role = "link_elf"
target_triple = "x86_64-unknown-linux-musl"

[link]
default_libs = "c"
runtime_helpers = "runtime_helpers.o"
pre_objects = "crt1.o, crti.o"
post_objects = "crtn.o"
link_options = "-static -m elf_x86_64"
```

Host executables are selected separately by logical tool roles in
`toolchains/<id>/<version>/hosts/<host>/host.toml`. Adding another target does
not require adding OS-specific conditions to the compiler driver.

## Related Repositories

| Repository | Description |
|------------|-------------|
| [dolet-compiler](https://github.com/dolet-lang/dolet-compiler) | The Dolet compiler (this repo) |
| [dolet-bootstrap](https://github.com/dolet-lang/dolet-bootstrap) | Python bootstrap compiler |
| [library](https://github.com/dolet-lang/library) | Standard library, runtime & platform layers |
| [tools](https://github.com/dolet-lang/tools) | LLVM toolchain for Windows x64 |

## License

Dolet Programming Language — [dolet-lang](https://github.com/dolet-lang)
