# Dolet System ABI Manager

## Overview
The System ABI Manager provides platform-specific runtime support for Dolet programs. This allows Dolet to run on any operating system or bare-metal hardware by implementing the appropriate ABI layer.

## Architecture

```
Dolet Program
     ↓
System ABI Manager (Platform-specific)
     ↓
Operating System / Hardware
```

## Supported Platforms

### 1. **Windows** (`windows/`)
- Win32 API integration
- MSVC runtime compatibility
- Windows system calls

### 2. **Linux** (`linux/`)
- POSIX system calls
- GNU C Library (glibc) compatibility
- Linux-specific features

### 3. **macOS** (`macos/`)
- Darwin/XNU kernel calls
- Cocoa framework support
- Apple Silicon (ARM64) support

### 4. **Embedded Systems** (`embedded/`)
- Bare-metal support (no OS)
- Minimal runtime for microcontrollers
- Custom hardware support

### 5. **Custom Platforms** (`custom/`)
- Template for implementing new platforms
- Guide for adding your own OS/hardware support

## Components

Each platform directory contains:

1. **`runtime.c`** - C implementation of core runtime functions
   - Memory allocation (malloc/free)
   - String operations
   - Type conversions
   - I/O operations

2. **`syscalls.dlt`** - Dolet definitions for system calls
   - Platform-specific system call wrappers
   - Error handling
   - ABI compatibility layer

3. **`abi.dlt`** - ABI definitions and conventions
   - Calling conventions
   - Data layout
   - Type mappings

4. **`build.sh` / `build.bat`** - Build scripts
   - Compile runtime.c to static library
   - Platform-specific build flags

## How It Works

1. **Compile Time:**
   - Dolet compiler detects target platform
   - Loads appropriate ABI manager files
   - Links with platform-specific runtime library

2. **Runtime:**
   - Dolet calls go through ABI layer
   - ABI layer translates to platform-specific calls
   - Platform executes native operations

## Adding a New Platform

See `custom/PORTING_GUIDE.md` for detailed instructions on:
- Implementing required runtime functions
- Defining system call wrappers
- Building and testing your ABI layer

## Benefits

✅ **True Portability** - Write once, run anywhere
✅ **Bare Metal Support** - No OS required
✅ **Custom Hardware** - Easy to port to new platforms
✅ **Minimal Dependencies** - Each platform only needs what it uses
✅ **Extensible** - Community can add new platforms

## Current Status

- [x] Windows support (in progress)
- [ ] Linux support (planned)
- [ ] macOS support (planned)
- [ ] Embedded bare-metal (planned)
