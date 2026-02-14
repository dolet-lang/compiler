# LLVM Tools

The Dolet compiler requires the following LLVM tools in this directory:

| Tool | Purpose |
|------|---------|
| `mlir-translate.exe` | Converts MLIR to LLVM IR (.mlir → .ll) |
| `clang.exe` | Compiles LLVM IR to object files (.ll → .obj) |
| `lld-link.exe` | Links object files into executables (.obj → .exe) |

## Setup

Run the setup script to copy tools from an existing LLVM installation:

```batch
setup_tools.bat
```

Or manually copy the three executables listed above into this directory.

## Download

These tools are part of the LLVM project. You can build them from source or download pre-built binaries from:
- https://github.com/llvm/llvm-project/releases
