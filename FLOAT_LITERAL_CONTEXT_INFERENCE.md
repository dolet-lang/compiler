# Float Literal Context Inference

## Summary

Decimal float literals such as `1.75` currently behave as `f64` by default.
That default is acceptable, but the compiler should use the surrounding type
context when the literal is passed to, assigned to, or returned as `f32`.

Current workaround:

```dolet
night_object.set_texture_size(1.75 as f32)
```

Desired code:

```dolet
night_object.set_texture_size(1.75)
```

`set_texture_size` is correctly typed as `f32` because the value is a render
parameter that eventually goes to GPU/shader `float` data. The ergonomics issue
is that the user must cast an obvious literal to `f32`.

## Expected Behavior

Allow decimal literals to be contextually typed as `f32` when the target type is
known and the source expression is a literal.

Examples that should compile:

```dolet
fun takes_f32(v: f32):
    pass

takes_f32(1.75)

x: f32 = 0.5

fun make_scale() -> f32:
    return 1.25
```

Method-call example:

```dolet
obj.set_texture_size(1.75)
```

## Important Constraint

Do not turn this into broad implicit narrowing from `f64` to `f32`.

This should remain rejected unless explicitly cast:

```dolet
v: f64 = 1.75
takes_f32(v)        # should still require: v as f32
```

The safe rule is: contextual conversion applies to numeric literals only, not to
arbitrary `f64` expressions or variables.

## Likely Fix Area

The relevant code is probably in:

- `codegen/codegen_types.dlt` for expression type inference.
- `codegen/codegen_access.dlt` for method-call argument matching and overload
  resolution.
- Any helper that resolves call argument types before emission.

The exact overload matcher currently appears to see `1.75` as `f64`, while the
method parameter expects `f32`, so the user has to write `as f32`.

## Tests To Add

Add focused compiler tests before changing behavior:

1. Function call: `takes_f32(1.75)` compiles.
2. Method call: `obj.set_value(1.75)` where `set_value(value: f32)` compiles.
3. Assignment: `x: f32 = 1.75` compiles.
4. Return: `fun f() -> f32: return 1.75` compiles.
5. Non-literal narrowing still fails: `v: f64 = 1.75; takes_f32(v)`.

After the fix, run the normal test suite:

```bat
run_tests.bat
```
