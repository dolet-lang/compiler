# Porting Guide: Adding Your Own Platform to Dolet

This guide explains how to add support for a new operating system or hardware platform to Dolet.

## Required Functions

Your `runtime.c` must implement these core functions:

### 1. Memory Management
```c
void* dsl_malloc(size_t size);
void dsl_free(void* ptr);
void* dsl_realloc(void* ptr, size_t size);
```

### 2. String Operations
```c
size_t dsl_strlen(const char* str);
char* dsl_strcpy(char* dest, const char* src);
char* dsl_strcat(char* dest, const char* src);
```

### 3. Type Conversions
```c
char* dsl_i8_to_string(int8_t value);
char* dsl_i16_to_string(int16_t value);
char* dsl_i32_to_string(int32_t value);
char* dsl_i64_to_string(int64_t value);
char* dsl_u8_to_string(uint8_t value);
char* dsl_u16_to_string(uint16_t value);
char* dsl_u32_to_string(uint32_t value);
char* dsl_u64_to_string(uint64_t value);
char* dsl_f32_to_string(float value);
char* dsl_f64_to_string(double value);
char* dsl_bool_to_string(int32_t value);
char* dsl_char_to_string(char value);
```

### 4. I/O Operations
```c
void dcl_print(const char* str);
void dcl_println(const char* str);
char* dcl_input(const char* prompt);
```

### 5. File Operations (optional if no filesystem)
```c
void* dsl_file_open(const char* path, const char* mode);
void dsl_file_close(void* file);
int64_t dsl_file_read(void* file, void* buffer, int64_t size);
int64_t dsl_file_write(void* file, const void* buffer, int64_t size);
```

## Step-by-Step Guide

### Step 1: Create Platform Directory
```bash
cd tools/dolet/lib/system-abi-manager
mkdir myplatform
cd myplatform
```

### Step 2: Implement `runtime.c`
Create `runtime.c` with all required functions. See `embedded/runtime.c` for a minimal example.

### Step 3: Create `syscalls.dlt`
Define Dolet extern declarations:
```dolet
extern "myplatform" {
    fun malloc(size: i64) -> i64
    fun free(ptr: i64) -> i64
    // ... other functions
}
```

### Step 4: Create Build Script
Create `build.sh` (Linux/macOS) or `build.bat` (Windows):
```bash
#!/bin/bash
clang -c runtime.c -o runtime.o -O2
ar rcs libdolet_myplatform.a runtime.o
```

### Step 5: Build the Library
```bash
chmod +x build.sh
./build.sh
```

### Step 6: Test
Create a test Dolet program:
```dolet
fun main():
    println("Hello from my platform!")
```

Compile with:
```bash
doletc test.dlt -L path/to/myplatform -l dolet_myplatform
```

## Platform-Specific Considerations

### Bare-Metal / Embedded Systems
- Implement custom memory allocator (bump allocator is simplest)
- UART/serial output for `dcl_print`
- No file operations needed
- Consider startup code (_start, stack setup)

### New Operating System
- Use OS-specific system calls
- Link with OS libraries if available
- Implement threading if OS supports it
- Handle platform-specific ABIs

### Custom Hardware
- Memory-mapped I/O for peripherals
- Direct hardware register access
- Interrupt handlers if needed
- DMA support for performance

## Example: Minimal Embedded Port

```c
// runtime.c for microcontroller
#include <stdint.h>

// Heap management
static uint8_t heap[8192];
static size_t heap_pos = 0;

void* dsl_malloc(size_t size) {
    if (heap_pos + size > sizeof(heap)) return NULL;
    void* ptr = &heap[heap_pos];
    heap_pos += size;
    return ptr;
}

void dsl_free(void* ptr) { /* no-op */ }

// UART output
#define UART ((volatile uint32_t*)0x40001000)

void dcl_print(const char* str) {
    while (*str) {
        while (!(*UART & 0x80)); // Wait TX ready
        *UART = *str++;
    }
}

void dcl_println(const char* str) {
    dcl_print(str);
    dcl_print("\n");
}
```

## Testing Checklist

- [ ] Memory allocation works
- [ ] String operations correct
- [ ] Print output appears
- [ ] File I/O (if applicable)
- [ ] Platform-specific features work
- [ ] No crashes on startup
- [ ] Clean shutdown/exit

## Getting Help

- Check existing platform implementations (windows/, linux/, embedded/)
- Open an issue on GitHub with [Port] tag
- Join the community Discord for porting help

## Contributing

Once your port is working:
1. Add documentation to this directory
2. Include example programs
3. Submit PR to main Dolet repository
4. Add to supported platforms list

## License

Your port must be compatible with Dolet's license (MIT/Apache 2.0).
