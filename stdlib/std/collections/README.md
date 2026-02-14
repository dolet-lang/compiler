# Dolet Collections Library

## Overview
This directory contains Dolet's standard collection types that are automatically loaded at compile time (Tier 1).

## Available Collections

### `Vec<T>` - Dynamic Array
**File**: `vec.dlt`

A growable array type similar to Rust's `Vec` or C++'s `std::vector`.

#### Features:
- ✅ Generic over any type `T`
- ✅ Zero-cost abstraction (monomorphization at compile time)
- ✅ Automatic memory management
- ✅ Bounds checking
- ✅ Dynamic resizing

#### Methods:
```dolet
// Constructor
fun new() -> Vec<T>

// Query methods
fun len(self) -> i32
fun is_empty(self) -> bool
fun get_capacity(self) -> i32

// Modification methods
fun push(self, value: T)
fun pop(self) -> T
fun get(self, index: i32) -> T
fun set(self, index: i32, value: T)
fun clear(self)
fun reserve(self, new_cap: i32)

// Cleanup
fun drop(self)
```

#### Example Usage:
```dolet
# Create a vector of integers
numbers: Vec<i32> = Vec<i32>.new()

# Add elements
numbers.push(10)
numbers.push(20)
numbers.push(30)

# Get size
size: i32 = numbers.len()
print(size)  # Output: 3

# Access elements
first: i32 = numbers.get(0)
print(first)  # Output: 10

# Modify elements
numbers.set(1, 25)

# Pop last element
last: i32 = numbers.pop()
print(last)  # Output: 30

# Cleanup (optional - can use 'use' statement for RAII)
numbers.drop()
```

#### With RAII (Recommended):
```dolet
use Vec<i32>.new() as numbers:
    numbers.push(10)
    numbers.push(20)
    numbers.push(30)
    
    for i in 0 to numbers.len():
        value: i32 = numbers.get(i)
        print(value)
# Auto cleanup here!
```

---

## Implementation Details

### Monomorphization
All generic collections use **compile-time monomorphization** for zero-cost abstraction:

```dolet
# This code:
vec_i32: Vec<i32> = Vec<i32>.new()
vec_str: Vec<str> = Vec<str>.new()

# Generates specialized versions:
# - Vec_i32 with i32-specific operations
# - Vec_str with str-specific operations
# - No runtime overhead!
```

### Memory Layout
```
Vec<T> struct:
┌─────────────┬──────┬──────────┐
│ data (i64)  │ size │ capacity │
│  pointer    │(i32) │  (i32)   │
└─────────────┴──────┴──────────┘
       ↓
    Heap:
    ┌───┬───┬───┬───┬───┬───┐
    │ T │ T │ T │...│   │   │
    └───┴───┴───┴───┴───┴───┘
    Used elements │ Reserved
```

### Growth Strategy
- Initial capacity: **8 elements**
- Growth factor: **2x** (doubles when full)
- Allocation: C `malloc`/`realloc`

---

## Future Collections

### Planned for Tier 1:
- `Map<K, V>` - HashMap implementation
- `Set<T>` - HashSet implementation
- `String` - Dynamic string type

### Planned for Tier 2 (importable):
- `LinkedList<T>` - Doubly-linked list
- `Queue<T>` - FIFO queue
- `Stack<T>` - LIFO stack
- `Deque<T>` - Double-ended queue
- `BTreeMap<K, V>` - Sorted map
- `BTreeSet<T>` - Sorted set

---

## Performance

All collection types are designed for **zero-cost abstraction**:

```
Operation       | Vec<T>  | C array | Overhead
----------------|---------|---------|----------
Access (get)    | O(1)    | O(1)    | 0%
Push (append)   | O(1)*   | N/A     | ~5%**
Pop             | O(1)    | N/A     | 0%
Iteration       | O(n)    | O(n)    | 0%

* Amortized
** Due to growth/reallocation
```

---

## See Also
- `core/traits/` - Core traits like `Clone`, `Display`
- `std/io.dlt` - I/O functions
- `sys/c-std.dlt` - C standard library bindings
