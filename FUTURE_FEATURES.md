# Dolet Future Features

This document tracks planned features and improvements for the Dolet programming language.

## Language Features

### 1. Address-of Operator (`&`)
**Priority:** High  
**Status:** Planned

Add support for taking the address of stack-allocated variables.

**Use Case:**
```dolet
fun print_char_optimized(c: char):
    handle: i64 = GetStdHandle(-11)
    WriteFile(handle, &c as i64, 1, 0, 0)  // Zero heap allocation
```

**Benefits:**
- Zero heap allocation for single-char printing
- More efficient memory usage
- Better performance for stack-local operations

**Current Workaround:**
Using `Memory.malloc()` + `Memory.free()` for temporary buffers.

---

## Standard Library Improvements

### 2. Stack-Allocated Buffers
**Priority:** Medium  
**Status:** Planned  
**Depends on:** Address-of operator

Support for fixed-size stack arrays without heap allocation.

**Example:**
```dolet
buf: i8[256]  // Stack-allocated 256-byte buffer
```

---

### 3. `to_string()` Method
**Priority:** Medium  
**Status:** Planned

Add a unified `to_string()` interface instead of relying on F-string interpolation for type conversion.

**Example:**
```dolet
trait ToString:
    fun to_string() -> str

impl ToString for i32:
    fun to_string() -> str:
        return Convert.i32_to_str(self)
```

---

## Compiler Improvements

### 4. Compile-Time Format String Optimization
**Priority:** Low  
**Status:** Planned

Optimize F-strings at compile time when all parts are known.

---

## Notes

- Features are added based on real-world needs and use cases
- Performance improvements are prioritized for hot paths (I/O, memory operations)
- Breaking changes should be avoided when possible
