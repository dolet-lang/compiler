# DEFERRED.md — intentionally postponed features

> Companion to `ROADMAP.md`. The roadmap is the **active plan** — what
> we commit to building. This file is the **backlog** — features that
> are real and wanted but deliberately *not* scheduled yet, with the
> reasoning for the deferral and enough detail to pick them up later.
>
> Nothing here is "rejected" (that lives in ROADMAP.md → Out-of-roadmap).
> Everything here is "yes, eventually — just not now."

---

## D1. Dynamic dispatch / trait objects

**What:** Heterogeneous collections + runtime polymorphism —
`list<dyn Drawable>` holding mixed concrete types, with `.draw()`
dispatching to the right implementation at runtime.

```dolet
trait Drawable:
    fun draw(self)

# NOT possible today — would need this:
shapes: list<dyn Drawable> = []
shapes.append(circle)        # Circle
shapes.append(rect)          # Rect
for s in shapes:
    s.draw()                 # dynamic dispatch via vtable
```

**Why deferred:**
- `kobic` (the in-house engine) is **ECS-based**. ECS stores components
  in per-type arrays and each system operates on one concrete component
  type — it sidesteps trait objects entirely by design. No engine
  pressure for this feature.
- Static generics with trait bounds (`fun render<T: Drawable>(x: T)`)
  already cover the single-type-per-call case at zero runtime cost.
- `attach Trait for Type:` already ships the *contract-checking* half
  of traits (compile-time verification that a type implements every
  trait method). That's the higher-value half — it catches bugs.
- Real cost: ~1 week of codegen work (vtables, type tags, fat pointers).

**When it becomes important:**
- A UI widget tree with mixed widget types in one child list.
- A plugin system loading behavior at runtime.
- Any genuinely heterogeneous collection that ECS can't model.

**Implementation sketch:**
- `dyn Trait` is a **fat pointer**: `(data_ptr, vtable_ptr)` — 16 bytes.
- Per `(Type, Trait)` pair, emit a vtable: a static array of function
  pointers in trait-method-declaration order.
- `shapes.append(circle)` coerces `Circle` → `dyn Drawable` by pairing
  the Circle pointer with the `Circle×Drawable` vtable.
- `s.draw()` on a `dyn` value: load `vtable_ptr`, index to `draw`'s
  slot, indirect-call with `data_ptr` as self.
- Parser: `dyn Trait` as a type expression. Codegen: vtable emission +
  fat-pointer ABI + indirect call lowering.

**Estimate:** 1 focused multi-session arc (~5 sessions).

---

## D2. Static-field factory initializer — codegen bug

**What:** `static x: T = T.new(args)` (a factory call as a static
field's initializer) parses fine but a downstream codegen path
mishandles **chained field access** through such a field.

```dolet
struct Holder:
    static seeded: Inner = Inner.new_seeded()   # parses + dispatches OK

# This WORKS — method dispatch through the static field:
Holder.seeded.some_method()

# This CRASHES — reading a field-of-a-field through the static slot:
Holder.seeded.payload                            # access violation
```

**Why deferred:**
- Method dispatch through a static struct-typed field works (Path 3).
- Only the *field-of-field* read path is broken — a narrow case.
- The composition pattern (`Random.secure.X(...)`) uses method calls,
  not field chains, so the shipped stdlib is unaffected.

**When it becomes important:**
- When a library wants a static config object whose *fields* (not just
  methods) are read: `App.config.timeout`.

**Implementation sketch:**
- Reproduce: `tests/` synthetic — `static x: T` then `Holder.x.field`.
- The bug is in how `gen_static_field_access` (or the nested-field
  pointer path) handles a struct-typed static field — likely returns
  the slot address where it should load the struct pointer first, or
  vice versa. Compare against the working instance-field path.

**Estimate:** ~half a session once reproduced.

---

## D3. Threading — completion beyond Mutex

**What:** The synchronization toolkit past the shipped `Mutex` +
`AtomicI32/I64`:

- **`RwLock`** — multiple readers OR one writer. Win32 `SRWLOCK`
  (`AcquireSRWLockShared` / `...Exclusive`), pthread_rwlock on Linux.
- **`Channel<T>`** — typed message passing between threads. Ring
  buffer + Mutex + condition variable; needs user-defined generics
  to carry `T` (B3 generics already ship — feasible).
- **`Condvar`** — wait/notify on a predicate. Win32
  `SleepConditionVariableCS` / `WakeConditionVariable`.
- **Atomic memory ordering** — `Acquire` / `Release` / `Relaxed`
  variants of the `__atomic_*` intrinsics. Currently SeqCst-only.
- **Linux `pthread_mutex`** backing for `Mutex` (today: Windows
  CRITICAL_SECTION only).

**Why deferred:**
- `Mutex` + atomics already cover the common "protect shared state"
  case. The rest is layered ergonomics / specialized primitives.
- `Channel<T>` is the highest-value next step but wants a careful
  design pass (bounded vs unbounded, blocking vs try-send).

**When it becomes important:**
- Producer/consumer workloads → `Channel<T>`.
- Read-heavy shared caches → `RwLock`.
- Lock-free fast paths that profile as hot → relaxed atomics.

**Estimate:** 3–5 sessions, one primitive per session.

---

## D4. Generic methods (`fun method<T>(...)` inside `attach`)

**What:** Type-parameterised *methods* — a `<T>` on a method declared
in an `attach` block, callable as `obj.method<T>(args)` or
`Type.method<T>(args)`.

```dolet
attach Render:
    static fun draw<T: Drawable>(item: T):    # ← declares fine today
        ...

Render.draw<Circle>(c)        # ← call does NOT parse today
```

**Current state (verified this session):**
- The *declaration* parses — `parse_fun_def` runs `parse_type_param_list`
  whether the fn is free or inside an `attach` block.
- The *call* does NOT parse. `parse_dot_stmt` (statement position) and
  the method-chain path handle `obj.method(args)` but not a `<T>`
  before the `(`. The parser strands on `<`.
- Even with a parser fix, `mk_inst_method` / `mk_static_method` have
  no `type_args` slot (unlike `mk_fun_call`), so codegen
  monomorphization has nowhere to read T from.

**Why deferred:**
- Three layers to touch — parser (`parse_dot_stmt` + expression
  method-chain), AST (`mk_inst_method`/`mk_static_method` need a
  type-args field), codegen (method monomorphization in codegen_mono).
- Generic *free functions* fully work — including statement-position
  calls (`tests/generic_stmt_call.dlt`). They cover the same need:
  `render_draw<Circle>(c)` instead of `Render.draw<Circle>(c)`. The
  struct-namespace prefix is purely cosmetic.

**Recommendation for now:** use a generic free function. Reach for a
generic method only once this is built.

**Estimate:** 1–2 sessions (parser + AST + codegen).

---

## D5. `impl Trait for Type:` — keyword reservation

**What:** Not a feature to build — a **naming note**. The keyword
`impl` is intentionally left unused (the method-block keyword is
`attach`). If Dolet ever wants a Rust-style *distinct* spelling for
trait implementations specifically, `impl Trait for Type:` is free
to claim.

**Current decision:** `attach` covers both inherent methods
(`attach Type:`) and trait impls (`attach Trait for Type:`) — one
keyword, like Rust's `impl`. No plan to split them. This entry just
records that `impl` is a free identifier *and* a free potential
keyword, so the option stays open.

---

## How to promote an item to ROADMAP.md

When one of these gets scheduled:
1. Move the entry into `ROADMAP.md` under the right tier.
2. Expand the implementation sketch into a full work package
   (files to touch, exact signatures, verification checklist).
3. Delete the entry here, or leave a one-line `→ moved to ROADMAP`
   pointer.
