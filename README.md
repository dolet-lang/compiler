# Dolet Programming Language

A systems programming language that compiles to native code via MLIR/LLVM.

## Project Structure

```
dolet-lang/
├── compiler/              # Self-hosting compiler (written in Dolet)
│   ├── lexer/             # Tokenizer
│   ├── parser/            # Recursive descent parser + AST nodes
│   ├── codegen/           # MLIR code generation
│   └── driver/            # CLI driver + pipeline init
├── bootstrap/             # Python bootstrap compiler (for first build)
│   ├── lexer/
│   ├── parser/
│   ├── sema/
│   ├── codegen/
│   └── doletc.py          # Python compiler entry point
├── stdlib/                # Standard library (auto-imported)
│   ├── runtime/           # Core: Memory, Convert, Str, IOOps, ...
│   ├── std/               # High-level: print(), string extensions, time
│   ├── core/              # Core language support
│   └── sys/windows/       # Platform-specific .lib files
├── packages/              # External modules (qubic, glfw, raylib, web, ...)
├── lib/                   # Additional libraries
│   ├── importable/        # Importable std libs (math, net, random, ...)
│   └── system-abi-manager/# System ABI management
├── tools/                 # LLVM toolchain (clang, lld-link, mlir-translate)
├── tests/e2e/             # End-to-end tests
├── examples/              # Example programs
├── build/                 # Build artifacts (generated)
├── bin/                   # Compiled doletc.exe
└── docs/                  # Documentation
```

## Quick Start

### 1. Setup LLVM Tools

```batch
tools\setup_tools.bat C:\path\to\llvm\bin
```

### 2. Build the Compiler

```batch
python build.py compile
```

This concatenates all `.dlt` source files and compiles them using the Python bootstrap compiler.

### 3. Compile a Program

```batch
dltc examples\hello.dlt -o hello.exe
hello.exe
```

## Compiler Usage

```
dltc <input.dlt> [-o output.exe] [--keep-mlir] [--keep-llvm] [--no-runtime]
```

| Option | Description |
|--------|-------------|
| `-o <path>` | Output executable path (default: `<input>.exe`) |
| `--keep-mlir` | Keep intermediate `.mlir` file |
| `--keep-llvm` | Keep intermediate `.ll` file |
| `--no-runtime` | Don't auto-import runtime libraries |

## Compilation Pipeline

```
.dlt source → doletc → .mlir → mlir-translate → .ll → clang → .obj → lld-link → .exe
```

## Bootstrap Flow

The compiler is **self-hosting** — it's written in Dolet and compiles itself:

```
1. First build:   python bootstrap/doletc.py → bin/doletc.exe  (Python compiles Dolet)
2. Self-hosting:  bin/doletc.exe → bin/doletc.exe               (Dolet compiles itself)
```

## Language Features

- Static typing with type inference
- Manual memory management via `Memory.*` builtins
- Structs with static and instance methods
- Enums with variants
- Pattern matching (`match`/`case`)
- Extern blocks for FFI (C/Windows API)
- String operations via `Str.*`
- I/O via `IOOps.*`

## Example

```dolet
fun factorial(n: i32) -> i32:
    if n <= 1:
        return 1
    return n * factorial(n - 1)

result: i32 = factorial(10)
IOOps.io_println(Str.concat("10! = ", Convert.i64_to_str(result as i64)))
```
