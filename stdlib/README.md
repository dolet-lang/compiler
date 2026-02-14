# Built-in Standard Libraries

**Tier 0 & Tier 1**: Auto-loaded libraries - No `import` statement needed

## Libraries in This Category

### core/ - Core Library (Tier 0)
- **File**: `libcore.dlib`
- **Auto-loaded**: Yes (always loaded by compiler)
- **Import needed**: No
- **Provides**:
  - Primitive types: `i8`, `i16`, `i32`, `i64`, `i128`, `u8`, `u16`, `u32`, `u64`, `u128`, `f32`, `f64`, `char`, `bool`, `str`, `ptr`
  - Core types: `Option<T>`, `Result<T, E>`
  - Core traits: `Clone`, `Display`, `Debug`, `Drop`, `Default`

### std/ - Standard Library (Tier 1)
- **File**: `libstd.dlib`
- **Auto-imported**: Yes (automatically available in all programs)
- **Import needed**: No
- **Provides**:
  - Collections: `Vec<T>`, `Map<K, V>`, `String`
  - I/O functions: `print()`, `println()`
  - Math functions: `sqrt()`, `pow()`, `abs()`, `min()`, `max()`
  - Time utilities

## Usage

These libraries are automatically available. No `import` statement is required:

```dolet
fun main():
    // Core types - no import needed
    value: Option<i32> = Some(42)
    result: Result<str, str> = Ok("success")

    // Std collections - no import needed
    numbers: Vec<i32> = Vec()
    numbers.push(10)
    numbers.push(20)

    config: Map<str, i32> = Map()
    config.put("port", 8080)

    // Built-in functions - no import needed
    print("Hello, World!")
    result: f64 = sqrt(16.0)
```

## Compiler Behavior

The Dolet compiler automatically:
1. Loads `libcore.dlib` at startup
2. Imports `libstd.dlib` for every program
3. Makes all symbols from these libraries globally available

---

**Path**: `dolet/lib/built-in-stdLibs/`
**Category**: Built-in (Tier 0 & 1)
