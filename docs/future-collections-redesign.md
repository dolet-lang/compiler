# Future: Collections Syntax Redesign

## Overview
Redesign collection types to use pattern-based syntax instead of generic struct syntax.

## New User Syntax
```dlt
# Fixed Array — stack allocated, size known at compile time
mut arr: i32[4] = [1, 2, 3, 4]
imm colors: i32[3] = [255, 128, 0]

# Dynamic List — heap allocated, growable (requires import std)
mut scores: i32[..] = [100, 85, 90]
scores.append(75)
scores.pop()
scores[0] = 999

# Map — heap allocated (requires import std)
mut user: {str: i32} = {
    "age": 25,
    "score": 100
}
user["age"] = 26

# Immutable — everything frozen
imm days: i32[7] = [1, 2, 3, 4, 5, 6, 7]
days[0] = 999        # compile error: immutable
```

## Library Definition (collections.dlt)

Structs use standard generic syntax. Type aliases provide syntax sugar.

```dlt
# ─── Struct definitions (the real types) ───

@transparent
struct Array<T, N>:
    _data: __buf<T, N>       # compiler intrinsic: N elements of T on stack

@transparent
@heap
struct List<T>:
    _data: ptr<T>            # typed pointer to heap-allocated elements
    _len:  i64
    _cap:  i64

@transparent
@heap
struct Map<K, V>:
    _buckets: ptr
    _count:   i64
    _cap:     i64

# ─── Syntax sugar aliases ───

type T[N]    = Array<T, N>      # i32[4]      → Array<i32, 4>
type T[..]   = List<T>          # i32[..]     → List<i32>
type {K: V}  = Map<K, V>        # {str: i32}  → Map<str, i32>
```

## Compiler Intrinsics

| Intrinsic | Meaning |
|---|---|
| `__buf<T, N>` | N contiguous elements of T inline on stack |
| `ptr<T>` | Typed pointer to T data on heap |

## Memory Rules

| Syntax | Allocation | Requires |
|---|---|---|
| `i32[3]` | stack (3 * 4 = 12 bytes) | core only |
| `i32[..]` | heap (data) + stack (header) | `import std` |
| `{str: i32}` | heap | `import std` |

## Methods

Methods defined via `extend` blocks:

```dlt
extend Array<T, N>:     # or: extend T[N]:
    fun len(self) -> i64
    fun get(self, index: i64) -> T
    fun set(self, index: i64, value: T)

extend List<T>:          # or: extend T[..]:
    fun len(self) -> i64
    fun cap(self) -> i64
    fun append(self, val: T)
    fun pop(self) -> T
    fun get(self, index: i64) -> T
    fun set(self, index: i64, val: T)
    fun remove(self, index: i64)
    fun contains(self, val: T) -> bool
    fun reverse(self)
    fun clear(self)

extend Map<K, V>:        # or: extend {K: V}:
    fun len(self) -> i64
    fun has(self, key: K) -> i32
    fun get(self, key: K) -> V
    fun set(self, key: K, val: V)
    fun remove(self, key: K)
    fun keys(self) -> K[..]
    fun values(self) -> V[..]
```

## Indexing Sugar

```
x[0]       →  T_get(x, 0)
x[0] = 5   →  T_set(x, 0, 5)
m["key"]   →  Map_get(m, "key")
```

## Interaction with mut/imm

| Declaration | Append | Set element | Reassign |
|---|---|---|---|
| `mut x: i32[..]` | yes | yes | yes |
| `imm x: i32[..]` | no | no | no |
| `mut x: i32[3]` | no (fixed) | yes | yes |
| `imm x: i32[3]` | no | no | no |
