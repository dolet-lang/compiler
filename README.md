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

The compiler is **platform-neutral**: it reads the operating-system contract,
architecture, ABI facts, toolchain roles, link order, and target-owned
resources from `library/platform/<os>/targets/<arch>/platform.toml`. Backend
triples are private LLVM-adapter details and never appear in application
manifests. No operating system or C runtime is selected by hardcoded compiler
branches.

The canonical `windows/x86_64` and `linux/x86_64` targets use the Pure Dolet
runtime. Windows reaches Win32 directly; Linux reaches the kernel through a
small target-owned syscall/entry object. Ordinary Linux applications are
static and libc-free, and Windows can cross-build their ELF executables.
When resolved source uses the native window bridge or Vulkan, the same Linux
target automatically selects its internal loader-compatible desktop SDK. The
bridge prefers Wayland and falls back to X11/XWayland at runtime. This keeps
one public target ID while isolating unavoidable system-library ABI
dependencies from the Pure Dolet runtime.

## Quick Start

### Option 1: Download Pre-built Release

Download the latest release from [Releases](https://github.com/dolet-lang/dolet-compiler/releases), extract, and run:

```batch
doletc hello.dlt -o hello.exe --target windows/x86_64
doletc hello.dlt -o hello --target linux/x86_64
```

### Option 2: Build from Source

See [Building from Source](#building-from-source) below.

## Usage

```
doletc <input.dlt> [-o output] [--target <os/arch>] [--package-path <path>] [--release] [--keep-mlir] [--keep-llvm]
```

| Option | Description |
|--------|-------------|
| `-o <path>` | Output executable path (extension added from platform config) |
| `--target <os/arch>` | Canonical target ID, such as `windows/x86_64` or `linux/x86_64` |
| `--package-path <path>` | Add a project-local package root; may be repeated |
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
- **Custom annotations**: `@inline`, `@hot`, `@deprecated`, `@noarena`, composable user-defined annotations
- **Async/Await** with event loop
- **FFI** — `extern` blocks for C / OS API interop
- **Module system** — `import`, `from X import Y`, `use`, access control
- **Cross-platform** — Windows x64 and Linux x64; Pure Dolet core programs are libc-free, while Linux desktop programs use the target-owned X11/Vulkan system ABI profile

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

The compiler is self-hosting. Each checked-in native host seed has an
independent version and SHA-256 pin in `bootstrap.seed.toml`; `build.bat`
refuses to use a changed or mislabeled seed, regenerates the amalgamated
source, builds two self-hosted stages, and promotes the result only when both
stages are byte-identical. A trusted older seed may build the next source
version; the promoted host record advances only after the fixed point passes.
The historical Python compiler is archived for language archaeology and is
not a second source of truth.

### Prerequisites

- **Python 3.8+**
- **LLVM 17+ Tools**: `clang`, `lld-link` / `ld.lld`, `mlir-translate`

### 1. Clone the Compiler

```batch
git clone https://github.com/dolet-lang/dolet-compiler.git
cd dolet-compiler
```

### 2. Clone the nested source repositories (inside dolet-compiler)

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
obin build --profile release --target windows
obin build --profile release --target linux
obin package --profile release --target windows
obin package --profile release --target linux
```

This produces `doletc.exe` for `windows/x86_64` and a static Pure Dolet ELF
for `linux/x86_64`. SDK packages place the compiler under `bin/`
and stage the Dolet library, platform packs, backend target adapters, toolchain
manifest, and matching host-tool pack. Both release packages are complete:
`obin package --target linux` runs the target-specific preparation hook, stages
native Linux `mlir-translate`, Clang, and LLD executables, follows their
non-glibc shared-library closure, and wraps them with SDK-relative library
lookup. The resulting compiler therefore works from `./bin/doletc` without a
system LLVM installation or a configured `PATH`. `DOLET_TOOLCHAIN_PATH`, host
discovery, and `tools/setup_tools.sh` remain developer overrides rather than
requirements for release users.
The package manifest declares both shared and target-specific required paths,
so Obin rejects an incomplete SDK instead of printing a misleading success.
Host-local links are never included in `dist`; the Linux package contains real
files plus `bundle.toml` hashes and its exact minimum GLIBC symbol version.
Packaging fails if any required host tool is absent, so a release cannot
silently degrade into an unusable thin SDK. Official builders can choose the
baseline WSL distribution with `DOLET_LINUX_WSL_DISTRO` and enforce a maximum
with `DOLET_LINUX_MAX_GLIBC` (for example `2.35` for Ubuntu 22.04).
The Linux compiler executable is cross-built from Windows and runs without a
dynamic loader or libc. `build.bat` remains the independent byte-stable bootstrap trust
path and must still be used after compiler changes.

To verify without replacing the checked-in seed:

```batch
python scripts\bootstrap.py --no-promote
```

### 4. Run Tests

```batch
run_tests.bat
```

The suite executes generated programs through hard time and working-set limits.
The known heavy stress case is opt-in with `DOLET_RUN_STRESS=1`.

## Self-Hosting Flow

```text
trusted native seed --builds--> stage 1 --builds--> stage 2
                                 |                 |
                                 +-- SHA-256 equal-+
                                            |
                                            +--> promote
```

## Target Packs

Each canonical target is a self-contained manifest under
`library/platform/<os>/targets/<arch>/platform.toml`:

```toml
schema = 3
id = "linux/x86_64"
os = "linux"
arch = "x86_64"
abi = "sysv"
runtime = "dolet"
object_format = "elf"
executable_format = "elf"
module_root = "platform/linux"
registry = "platform/linux/registry.dlt"
resource_root = "platform/linux/targets/x86_64/resources"

[toolchain]
toolchain_id = "llvm"
toolchain_version = "1"
translate_role = "translate"
compile_role = "compile"
link_role = "link_elf"

[link]
provided_libs = "dolet-runtime"
default_libs = ""
runtime_helpers = "runtime_helpers.o"
link_options = "-static -m elf_x86_64"
entry = "_start"

[link.dynamic]
dynamic_for_libs = "dolet_window_linux,wayland-client,wayland-cursor,xkbcommon,X11,vulkan"
dynamic_resource_root = "platform/linux/targets/x86_64/resources/desktop"
dynamic_default_libs = "pthread,c"
dynamic_runtime_helpers = "runtime_helpers.o"
dynamic_pre_objects = "entry_helpers.o"
dynamic_link_options = "-m elf_x86_64 --allow-shlib-undefined -dynamic-linker /lib64/ld-linux-x86-64.so.2"
dynamic_entry = "_start"
```

Host executables are selected separately by logical tool roles in
`toolchains/<id>/<version>/hosts/<host>/host.toml`. Adding another target does
not require adding OS-specific conditions to the compiler driver. Dynamic
profiles are target-owned policy selected from resolved external-library
requirements; they are not separate public targets.

## Related Repositories

| Repository | Description |
|------------|-------------|
| [dolet-compiler](https://github.com/dolet-lang/dolet-compiler) | The Dolet compiler (this repo) |
| [dolet-bootstrap](https://github.com/dolet-lang/dolet-bootstrap) | Historical Python stage-0 archive and compatibility entry point |
| [library](https://github.com/dolet-lang/library) | Standard library, runtime & platform layers |
| [tools](https://github.com/dolet-lang/tools) | LLVM toolchain for Windows x64 |

## License

Dolet Programming Language — [dolet-lang](https://github.com/dolet-lang)
