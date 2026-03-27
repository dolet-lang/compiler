# Future: Collections Syntax Redesign

## Goal
Replace generic struct syntax (`List<T>`, `Array<T>`, `Map<K,V>`) with built-in syntax sugar.

## New Syntax

```dlt
# Fixed Array — stack allocated, compile-time size
mut arr: i32[4] = [1, 2, 3, 4]
arr[0] = 99           # mut = writable
imm days: i32[7] = [1,2,3,4,5,6,7]
days[0] = 1           # compile error: immutable

# Dynamic List — heap allocated, growable (requires import std)
mut scores: i32[..] = [100, 80, 60]
scores.append(50)     # grows
scores.pop()          # shrinks
scores[0] = 999       # index write

# Map — heap allocated (requires import std)
mut user: {str: i32} = {
    "age": 25,
    "score": 100
}
user["age"] = 26
user.has("age")       # -> 1
user.remove("score")
```

## Library Definition (collections.dlt)

Struct definitions stay clean and familiar. Type aliases provide the syntax sugar.

```dlt
# Fixed Array — stack, compile-time size
@transparent
struct Array<T, N>:
    _data: __buf<T, N>    # compiler intrinsic: N elements of T inline

# Dynamic List — heap, growable
@transparent
@heap
struct List<T>:
    _data: ptr<T>         # typed pointer to heap data
    _len:  i64
    _cap:  i64

# Map — heap, key-value pairs
@transparent
@heap
struct Map<K, V>:
    _buckets: ptr
    _count:   i64
    _cap:     i64

# ---- Syntax sugar aliases ----
type T[N]    = Array<T, N>     # i32[4]      -> Array<i32, 4>
type T[..]   = List<T>         # i32[..]     -> List<i32>
type {K: V}  = Map<K, V>       # {str: i32}  -> Map<str, i32>
```

## How the Compiler Handles It

The parser translates syntax sugar to internal generic types:

```
User writes           Compiler sees internally
----------------------------------------------
i32[4]           ->   Array<i32, 4>
i32[..]          ->   List<i32>
{str: i32}       ->   Map<str, i32>
x[0]             ->   Array_get(x, 0)  or  List_get(x, 0)
x[0] = 5         ->   Array_set(x, 0, 5)
x.append(5)      ->   List_append(x, 5)
```

## import std Gating

- `T[N]` (fixed array) = stack only, works without `import std`
- `T[..]` (dynamic list) = needs heap = requires `import std`
- `{K: V}` (map) = needs heap = requires `import std`

```dlt
# Embedded/kernel — no import std
mut buf: i8[256] = [0]    # stack only, fine

mut list: i32[..] = []    # compile error: needs import std
```

## Methods via extend

```dlt
extend T[N]:
    fun len(self) -> i64: ...

extend T[..]:
    fun append(self, val: T): ...
    fun pop(self) -> T: ...
    fun len(self) -> i64: ...
    fun cap(self) -> i64: ...

extend {K: V}:
    fun has(self, key: K) -> i32: ...
    fun get(self, key: K) -> V: ...
    fun set(self, key: K, val: V): ...
    fun remove(self, key: K): ...
    fun keys(self) -> K[..]: ...
```

## Compiler Intrinsics Needed

- `__buf<T, N>` — fixed-size inline buffer (N * sizeof(T) bytes on stack)
- `ptr<T>` — typed pointer (for type safety)
- Index operator `[]` desugaring to get/set calls
- Literal syntax `[1, 2, 3]` and `{"k": v}` for initialization
