# Implementation Plan: dolet-parallel

## Overview

هاد المستند بيحوّل الـ design تبع `dolet-parallel` لسلسلة tasks تدريجية لـ code-generation. كل task بيبني فوق اللي قبله و بينتهي بدمج (wiring) عشان ما يضل في كود معلّق غير مربوط. الترتيب: من تحت لفوق حسب الاعتماديات — أولًا الـ platform FFI و `cpu_info`، بعدها الـ `Work_Stealing_Deque` في الـ core، بعدها الـ `ThreadPool` و الـ lifecycle، بعدها `parallel_for` و الـ serial fallback، بعدها `spawn_task`/`TaskHandle`، و أخيرًا دمج الـ Frog engine. الـ property tests و الـ unit tests sub-tasks اختيارية (بـ `*`) موضوعة قريبة من الكود اللي بتتحقّق منه عشان نلقط الأخطاء بدري.

اللغة: Dolet (`.dlt`). كل الـ code examples و الـ API identifiers بالإنجليزي. البناء عبر `build.bat` (3-stage byte-stable)، و الاختبارات عبر `run_tests.bat`.

كل property test مكتوب كـ deterministic randomized stress harness (LCG seed ثابت، >= 100 iteration، watchdog/timeout بيحوّل الـ deadlock لـ fail واضح)، و بـ tag بالشكل: `# Feature: dolet-parallel, Property N: <text>`.

## Tasks

- [x] 1. ربط الـ CPU core-count FFI و الـ Cpu_Info_Provider (platform tier)
  - [x] 1.1 ضيف الـ extern bindings لـ `kernel32.dlt`
    - ضيف `fun GetSystemInfo(lpSystemInfo: i64)` و `fun GetActiveProcessorCount(GroupNumber: i32) -> i32` داخل الـ `extern lib "kernel32"` block الموجود
    - استخدم صياغة `extern` موجودة بلا keyword جديد (عشان ما نحتاج two-step bootstrap dance)
    - _Requirements: 12.1_

  - [x] 1.2 أنشئ `library/platform/windows/cpu_info.dlt` مع `struct CpuInfo` و `static fun cpu_count() -> i32`
    - جرّب `GetActiveProcessorCount(65535)` (ALL_PROCESSOR_GROUPS) كـ primary path
    - fallback: `Memory.malloc_zeroed(48)` ثم `GetSystemInfo(buf)` ثم `Memory.read_i32(buf + 32)` ثم `Memory.free(buf)`
    - رجّع 1 لو النتيجة < 1 (graceful degradation، بلا OS threads → Core_Count = 1)
    - _Requirements: 2.1, 12.2, 2.4, 1.2, 1.6_

  - [x] 1.3 سجّل `cpu_info` في `library/platform/windows/mod.dlt`
    - ضيف `load platform/windows/cpu_info` بعد `load platform/windows/info`
    - ضيف `export GetSystemInfo`, `export GetActiveProcessorCount`, `export CpuInfo`
    - _Requirements: 1.2, 12.3_

  - [x] 1.4 اكتب unit test لـ `cpu_count()`
    - assert إن `CpuInfo.cpu_count() >= 1` على الجهاز
    - _Requirements: 2.1, 12.2_

- [x] 2. تنفيذ الـ Work_Stealing_Deque (core tier — خوارزمية نقية بلا OS/FFI)
  - [x] 2.1 أنشئ `library/core/parallel_deque.dlt` مع `@heap struct Work_Stealing_Deque` و methods
    - fields: `buffer: i64` (ring buffer من `Memory.malloc(capacity*8)`), `capacity: i64` (power-of-two, `mask = capacity-1`), `top: AtomicI64`, `bottom: AtomicI64`
    - `static fun new(capacity: i64)`, `fun push(self, item)` (owner, bottom end), `fun pop(self) -> i64` (owner, يحلّ آخر-عنصر race بـ CAS على top), `fun steal(self) -> i64` (thief, CAS على top), `fun is_empty(self) -> bool`, `fun destroy(self)`
    - `EMPTY = -1`, `ABORT = -2`؛ كل الـ handles >= 0؛ slot k في `buffer + (k & mask)*8`
    - بلا أي OS call — atomics SeqCst بس
    - _Requirements: 4.2, 4.3, 1.1_

  - [x] 2.2 سجّل الـ deque في `library/core/mod.dlt`
    - ضيف `load core/parallel_deque` بعد `load core/atomic` (يعتمد على AtomicI64)
    - ضيف `export Work_Stealing_Deque`
    - _Requirements: 1.1_

  - [x] 2.3 اكتب unit tests للـ deque على thread واحد
    - push/pop LIFO من الـ owner end، steal FIFO من الـ top end، حالات EMPTY و ABORT، و wrap-around عبر الـ mask
    - _Requirements: 4.2, 4.3_

- [x] 3. تنفيذ الـ ThreadPool struct و الـ lifecycle (std tier)
  - [x] 3.1 أنشئ `library/std/thread_pool.dlt` مع `@heap struct ThreadPool` و الـ constructors
    - fields: `num_workers: i32`, `deques: i64`, `threads: i64`, `state: AtomicI32`, `shutdown: AtomicI32`, `pending: AtomicI64`, `epoch: AtomicI64`, `sleep_mtx: Mutex`
    - `static fun new()` يشتق الـ workers من `CpuInfo.cpu_count()` بـ `max(0, cpu_count()-1)`؛ لو <= 1 → `num_workers = 0` (serial mode، pool ناجح بلا workers)
    - `static fun new_with_workers(n: i32)` يخلق بالضبط n workers (n==0 → serial-mode valid)
    - error handling: لو `Memory.malloc` فشل أو كل الـ `CreateThread` فشلوا → تراجع لـ serial mode (workers=0) بلا crash
    - `fun worker_count(self) -> i32`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 5.1_

  - [x] 3.2 نفّذ الـ worker loop و الـ work-finding و الـ park/wake
    - `_pool_worker_loop(pool_addr, worker_index)`: لف لحد ما `shutdown.load()==1`؛ لاقي work (`_pool_find_work`) → نفّذ (`_pool_execute_item`) → `pending.fetch_sub(1)`؛ غير هيك park
    - `_pool_find_work`: `pop()` من deque المالك، غير هيك لف على باقي الـ deques و `steal()` (تجاهل ABORT و كمّل) — R4.1, R4.3
    - `_pool_park` + `signal_work`: epoch/generation counter + double-check تحت `sleep_mtx` لتجنّب lost-wakeup؛ bounded backoff (yield ثم `Thread.sleep(1)`)
    - اربط الـ worker spawn داخل constructor: `body: @heap fun() = fun() _pool_worker_loop(pool_addr, idx)` ثم `Thread.spawn(body)` و خزّن الـ handle
    - _Requirements: 4.1, 5.3, 5.4, 7.1, 7.3_

  - [x] 3.3 نفّذ `shutdown()` الـ idempotent و الـ init idempotence
    - init: CAS `state` UNINIT(0)→RUNNING(1)؛ بس الفائز يخلق الـ workers، الباقي يستنى `state==RUNNING` (R5.7, R7.5)
    - shutdown: CAS RUNNING(1)→SHUTTING_DOWN(2)؛ الفائز يـ set `shutdown=1`، يصحّي الكل (epoch bump)، يعمل `join` لكل worker، يحرّر الـ deques و الـ thread handles بلا leak؛ نداء تاني يرجع بلا error (R5.8, R7.6)
    - _Requirements: 5.5, 5.6, 5.7, 5.8, 7.5, 7.6_

  - [x] 3.4 سجّل `thread_pool` في `library/std/mod.dlt`
    - ضيف `load std/thread_pool` بعد `load platform/{platform}/mutex`
    - ضيف `export ThreadPool`
    - _Requirements: 1.3_

  - [x] 3.5 اكتب property test لـ init idempotence
    - **Property 7: Init idempotence**
    - **Validates: Requirements 5.7, 7.5**

  - [x] 3.6 اكتب property test لـ shutdown idempotence
    - **Property 8: Shutdown idempotence**
    - **Validates: Requirements 5.8, 7.6**

- [x] 4. Checkpoint — تأكّد إن كل الاختبارات ناجحة
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. تنفيذ `parallel_for` و الـ Serial Fallback و الـ global default pool (std tier)
  - [x] 5.1 نفّذ الـ global default pool بـ lazy first-use init
    - `g_default_pool_ptr: i64`, `g_default_pool_state: AtomicI32`؛ `_default_pool()` بـ CAS `0→1` فالفائز يخلق `ThreadPool.new()` و ينشر الـ ptr، الباقي يستنى لحد ما `g_default_pool_ptr != 0`
    - pool واحد على مستوى الـ process، ما منخلق pool لكل نداء
    - _Requirements: 5.1, 5.2, 10.1_

  - [x] 5.2 أنشئ `library/std/parallel.dlt` و نفّذ `parallel_for(count: i32, body: @heap fun(i32))`
    - قسّم `[0,count)` لـ chunks متباينة بلا تداخل، غلّف كل chunk في RANGE work-item record (kind=0, body_ptr, lo, hi, remaining_ptr) في submission arena، وزّع round-robin على الـ deques
    - `remaining: AtomicI64 = AtomicI64.new(num_chunks)`؛ `pool.signal_work()`؛ الـ caller يشارك (`_pool_drain_until`) بدل ما يقعد idle؛ استنى `remaining.load()==0` بـ yield؛ بعدها `remaining.destroy()`
    - استدعاء الـ body عبر heap env pointer: `b: @heap fun(i32) = body_ptr as @heap fun(i32); b(i)` (closure ABI، env valid عبر حدود الـ thread)
    - _Requirements: 3.1, 3.2, 2.5, 11.1, 11.3, 7.3_

  - [x] 5.3 نفّذ الـ Serial_Fallback داخل `parallel_for`
    - `count <= 0` → return فورًا بلا استدعاء body
    - `pool.worker_count() == 0` → loop عادي `i` من 0 لـ count على الـ calling thread، نتيجة مطابقة للـ parallel path
    - _Requirements: 3.3, 3.4, 3.5, 3.6_

  - [x] 5.4 اكتب property test لـ exactly-once index coverage
    - **Property 1: Exactly-once index coverage** (array من atomics، assert كل `hits[i]==1`)
    - **Validates: Requirements 3.1, 7.3, 4.2, 4.3, 2.5**

  - [x] 5.5 اكتب property test لـ parallel == serial pure mapping
    - **Property 2: Parallel equals serial for a pure mapping** (random N، random pure f، random per-index cost لاختبار load imbalance، worker count من 0 لـ 2×Core_Count)
    - **Validates: Requirements 3.6, 7.2, 3.4, 3.5, 4.4, 9.2**

  - [x] 5.6 اكتب property test لـ exact-count invariant
    - **Property 3: Exact-count invariant (with completion before return)** (كل index `fetch_add(1)` على shared AtomicI32، assert counter==N بعد الرجوع)
    - **Validates: Requirements 7.4, 3.2, 9.1**

  - [x] 5.7 اكتب property test لـ empty range
    - **Property 4: Empty range invokes the body zero times** (`parallel_for(c<=0, body)` → صفر استدعاء)
    - **Validates: Requirements 3.3**

  - [x] 5.8 اكتب property test لـ explicit worker count
    - **Property 5: Explicit worker count is honored** (`new_with_workers(n)` → `worker_count()==n`، n==0 → serial-mode valid)
    - **Validates: Requirements 2.3**

  - [x] 5.9 اكتب property test لـ termination/no-deadlock عبر كل core counts
    - **Property 10: Termination without deadlock for any core count** (random worker count 0..2×cpu_count، random N، watchdog timeout يحوّل الـ hang لـ fail)
    - **Validates: Requirements 7.7**

- [x] 6. تنفيذ `spawn_task` و `TaskHandle` (std tier)
  - [x] 6.1 أضف `struct TaskHandle` و `fun wait(self)` لـ `library/std/parallel.dlt`
    - field `done: AtomicI32` (0=pending, 1=completed)؛ stack-allocated
    - `wait`: لف لحد ما `done.load()==1`؛ أثناء الانتظار ساعد بـ draining (`_default_pool_try_run_one`) عشان pool بـ worker واحد ما يعمل deadlock؛ لو خلصت قبل → يرجع فورًا
    - _Requirements: 6.3, 6.4, 7.7_

  - [x] 6.2 نفّذ `spawn_task(work: @heap fun()) -> TaskHandle`
    - `done: AtomicI32 = AtomicI32.new(0)`؛ لو `worker_count()==0` → `work()` inline ثم `done.store(1)` ثم رجّع handle (serial fallback)
    - غير هيك: غلّف TASK work-item (kind=1, work_ptr, done_ptr)، push، `signal_work()`، رجّع handle
    - في `_pool_execute_item`: TASK → استدعاء `work()` عبر heap env pointer ثم `done.store(1)`
    - _Requirements: 6.1, 6.2, 6.5, 11.2, 11.3_

  - [x] 6.3 اكتب property test لـ each task runs exactly once
    - **Property 6: Each spawned task runs exactly once** (k tasks، بعد كل `wait()`، كل task نفّذ مرة وحدة)
    - **Validates: Requirements 6.2**

  - [x] 6.4 اكتب unit tests لـ spawn_task/wait
    - مهمة بتزيد global counter، بعد `wait` القيمة محدّثة؛ و `wait` على مهمة خلصت قبل يرجع فورًا
    - _Requirements: 6.1, 6.3, 6.4_

- [x] 7. تنفيذ `parallel_shutdown` و الـ leak verification
  - [x] 7.1 أضف `parallel_shutdown()` لتحرير الـ default pool صراحة
    - يستدعي `shutdown()` على الـ default pool و يعيد الـ state لـ UNINIT عشان leak tests تقدر تعمل دورات
    - export في `library/std/mod.dlt` (`export parallel_for`, `export spawn_task`, `export TaskHandle`, `export parallel_shutdown`)
    - _Requirements: 9.3, 1.3_

  - [x] 7.2 اكتب property test لـ init/shutdown leak-freedom
    - **Property 9: Init/shutdown cycles are leak-free and fully joined** (random cycle count 1..100، قارن `Memory.alloc_balance()` قبل/بعد، assert كل worker انعمله join)
    - **Validates: Requirements 5.6, 5.5, 9.3**

- [x] 8. Checkpoint — تأكّد إن كل الاختبارات ناجحة
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. دمج الـ Frog engine (R10)
  - [x] 9.1 أضف الـ wrapper الرفيع `engine_parallel_for` في `packages/frog`
    - `fun engine_parallel_for(count: i32, body: @heap fun(i32)): parallel_for(count, body)` — delegation بحت، بلا scheduler تاني
    - _Requirements: 10.1_

  - [x] 9.2 وازِ الـ CPU frustum culling كـ Pure_Mapping pre-pass في `packages/frog/render/gpu_renderer_core.dlt`
    - أضف array `vb_cull_result` (i32 لكل instance)؛ نفّذ `_frog_cull_one(self_addr, vp, gi, res)` اللي يقرأ bounds الـ instance `gi`، يستدعي `_frog_instance_visible`، و يكتب بس على `Memory.write_i32(res + gi*4, v)` (slot الـ index تبعه فقط — بلا shared write race)
    - استدعِ `engine_parallel_for(vb_count, body)` كـ pre-pass؛ خلّي الـ main render pass serial يقرأ `vb_cull_result[gi]` بدل النداء inline
    - الـ serial-fallback path (بلا OS threads) بينتج نفس الـ visible set تلقائيًا
    - _Requirements: 10.2, 10.3_

  - [x] 9.3 اكتب unit test لتطابق الـ visible set
    - **Property 11: Engine parallel culling produces the same visible set** (مشهد + كاميرا ثابتة، قارن الـ visible set من الـ parallel culling مع الـ serial — لازم متطابقين)
    - **Validates: Requirements 10.2, 10.3**

  - [x] 9.4 اكتب perf smoke test (informational)
    - embarrassingly-parallel workload متوازي مقابل serial، اطبع الزمنين؛ متوقّع المتوازي أسرع على multi-core (مش assertion صارمة)
    - _Requirements: 8.1, 8.2, 8.3_

- [x] 10. Final checkpoint — bootstrap byte-stable و zero regressions
  - شغّل `build.bat` للتأكد إن الـ 3-stage bootstrap byte-stable (stage 2 ≡ stage 3) مع الـ FFI الجديد؛ ما في keyword/ABI جديد فما في two-step dance
  - شغّل `run_tests.bat` و تأكّد إن اختبارات `dolet-parallel` الجديدة ناجحة بلا أي regression على الاختبارات الموجودة
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 12.3, 9.4_

## Notes

- الـ tasks المعلّمة بـ `*` اختيارية (property/unit/perf tests) و ممكن تتخطّى لـ MVP أسرع؛ الـ top-level tasks و الـ core implementation sub-tasks مش اختيارية.
- كل property test مكتوب كـ deterministic randomized stress harness: LCG seed ثابت، >= 100 iteration، watchdog/timeout يحوّل الـ deadlock لـ fail واضح، و tag `# Feature: dolet-parallel, Property N: <text>`.
- الـ 11 correctness property كلها مغطّاة: P1 (5.4)، P2 (5.5)، P3 (5.6)، P4 (5.7)، P5 (5.8)، P6 (6.3)، P7 (3.5)، P8 (3.6)، P9 (7.2)، P10 (5.9)، P11 (9.3).
- الـ properties موضوعة قريبة من الكود اللي بتتحقّق منه عشان نلقط الأخطاء بدري.
- كل task بيبني فوق اللي قبله و بينتهي بدمج — ما في كود معلّق غير مربوط.
- atomics SeqCst بس، و park/wake مبني على الموجود (Mutex + epoch + backoff)؛ الـ event-based wake و الـ lock-free Chase-Lev = future work موثّقة في الـ design.
