# Requirements Document

## Introduction

هاد المستند بيوصف متطلبات نظام الـ multithreading / data-parallelism الجديد لـ standard library تبع لغة Dolet — اسمه `dolet-parallel`. الفكرة إنه يكون عنا نظام high-performance و cross-platform بيخلي المطوّر يقول "هاد الشغل آمن إنه يتقسّم على threads" من غير ما يحدّد كم thread بيستخدم. الـ runtime هو اللي بيقرر عدد الـ threads وتقسيم الشغل حسب عدد الـ CPU cores الموجودة فعليًا على جهاز اللاعب (player's machine) وقت التشغيل. نفس الـ binary بيشتغل من core واحد لعدد كبير من الـ cores، وبيتكيّف لحاله.

الـ headline API عبارة عن work-stealing thread pool مع `parallel_for` بيتأقلم تلقائيًا. الـ Frog game engine رح يكون أول مستهلك (consumer) عبر إنه يعمل parallelize للـ CPU frustum culling، بس المكتبة نفسها general-purpose — أي برنامج Dolet بيقدر يستخدمها، مش بس الألعاب.

النظام لازم ينبني فوق الـ primitives الموجودة حاليًا: `Thread` (في `library/std/thread.dlt` ← `library/platform/windows/thread.dlt`)، `AtomicI32`/`AtomicI64` (في `library/core/atomic.dlt`)، و `Mutex` (في `library/std/mutex.dlt` ← `library/platform/windows/mutex.dlt`). ما في حاليًا أي thread pool أو scheduler أو job system، فهاد بنبنيه من الصفر بس فوق الموجود.

التقسيم على طبقات Dolet (core / platform / std) لازم يكون مطابق لنمط الـ thread و mutex الموجود: المنطق المستقل عن الـ OS بروح في `core/`، الـ primitives الخاصة بالـ OS بتنحط ورا interface موحّد في `platform/<os>/`، والـ public API بتطلع في `std/`. وعلى المنصّات اللي ما فيها OS threads (baremetal / no-thread)، الـ `parallel_for` لازم يضل يشتغل صح بس بشكل serial على نفس الـ thread اللي نده عليه — هاد متطلب first-class.

### Scope Boundaries

- async I/O (في `library/std/async`) خارج النطاق — هاد concern تاني (I/O concurrency مش CPU data-parallelism)، وبيظل منفصل.
- GPU compute (اللي انشحن عبر `gpu-driven-culling`) خارج النطاق.
- Memory-ordering غير الـ SeqCst خارج نطاق الـ v1 (الـ atomics كلها SeqCst اليوم).
- Linux و baremetal platform implementations ممكن تنعمل stub أو تتأجل، بس الـ architecture لازم تستوعبهم من هلأ.

## Glossary

- **Dolet_Parallel**: النظام الكامل لـ data-parallelism اللي بيوصفه هاد المستند، موزّع عبر طبقات core / platform / std.
- **Thread_Pool**: الـ `ThreadPool` struct في `std/`، بيدير مجموعة ثابتة (persistent) من worker threads اللي بتنخلق مرة وحدة عند الـ startup ويعاد استخدامها.
- **Worker_Thread**: OS thread دائم تابع للـ Thread_Pool، بيدور بشكل مستمر يسحب work items من الـ deque تبعه أو بيسرق من غيره.
- **Work_Stealing_Deque**: الـ double-ended queue اللي بيخزّن فيها كل Worker_Thread شغله؛ المالك بيدفع/بيسحب من طرف، والسارقين بياخدوا من الطرف التاني. المنطق نفسه (الخوارزمية) بقعد في `core/`.
- **Parallel_For**: الـ `parallel_for(count, body)` API اللي بيقسّم المدى `[0, count)` على الـ Worker_Threads وبيستنى لحد ما يخلصوا كلهم.
- **Body_Closure**: الـ closure `fun(i: i32)` اللي بيمرره المطوّر لـ Parallel_For؛ بينعمله استدعاء مرة لكل index ضمن المدى. لازم يكون `@heap` لأنه بيعبر حدود الـ thread.
- **Task_Closure**: الـ closure `fun()` اللي بيمرره المطوّر لـ `spawn_task`؛ بينفّذ مرة وحدة على worker. لازم يكون `@heap`.
- **Task_Handle**: الـ `TaskHandle` المرجوع من `spawn_task`، بيوفّر `wait()` للحجب لحد ما المهمة تخلص.
- **Core_Count**: عدد الـ logical CPU cores المتوفرة على جهاز اللاعب وقت التشغيل، بينقرأ من الـ platform layer.
- **Cpu_Info_Provider**: الـ platform-specific function اللي بترجّع Core_Count (GetSystemInfo على Windows، sysconf على Linux، compile-time constant على baremetal).
- **Os_Thread_Primitive**: الـ platform-specific primitive لخلق وتشغيل OS thread (CreateThread على Windows، pthread_create على Linux).
- **Park_Wake_Primitive**: الـ platform-specific آلية لتنويم worker خامل وإيقاظه (OS events / futex / spin).
- **Serial_Fallback**: تنفيذ الـ Parallel_For بشكل تسلسلي على الـ thread النادي، بينستخدم لما Core_Count = 1 أو لما OS threads مش متوفرة.
- **Pool_Lifecycle**: عمليات init و shutdown للـ Thread_Pool.
- **Engine_Parallel_For**: الـ wrapper الرفيع `Engine.parallel_for(...)` اللي بيستخدمه Frog engine فوق Parallel_For.
- **Cpu_Frustum_Culling**: حساب الـ visible set على الـ CPU في Frog engine عبر اختبار كل object ضد الـ frustum planes؛ أول مستهلك داخلي يتم parallelize-له.
- **Pure_Mapping**: Body_Closure اللي بيكتب بس على بيانات الـ index `i` تبعه وما بيلمس بيانات مشتركة قابلة للكتابة — يعني data-race-free by construction.

## Requirements

### Requirement 1: Layered Cross-Platform Architecture

**User Story:** كـ Dolet library maintainer، بدي نظام الـ parallelism يتوزّع على طبقات core / platform / std بنفس نمط الـ thread و mutex الموجود، عشان المنطق المستقل عن الـ OS ينفصل عن الـ primitives الخاصة بالمنصّة ونقدر نضيف منصّات جديدة من غير ما نعيد كتابة الـ scheduler.

#### Acceptance Criteria

1. THE Dolet_Parallel SHALL place the Work_Stealing_Deque algorithm in the `core/` library tier with no OS calls and no FFI.
2. THE Dolet_Parallel SHALL place the Cpu_Info_Provider, Os_Thread_Primitive, and Park_Wake_Primitive in the `platform/<os>/` library tier behind a uniform interface.
3. THE Dolet_Parallel SHALL place the Thread_Pool and Parallel_For public API in the `std/` library tier.
4. THE Thread_Pool SHALL compose the Os_Thread_Primitive, Cpu_Info_Provider, and Park_Wake_Primitive through the `platform/<os>/` interface without referencing any single OS API directly from the `std/` tier.
5. WHERE a target platform provides OS threads, THE platform tier SHALL expose the Os_Thread_Primitive that creates persistent Worker_Threads.
6. WHERE a target platform does not provide OS threads, THE platform tier SHALL expose a Cpu_Info_Provider that reports a Core_Count of 1.

### Requirement 2: Runtime Adaptation to CPU Core Count

**User Story:** كـ application developer، بدي نفس الـ binary يتأقلم لحاله مع عدد الـ cores على جهاز اللاعب من غير ما أحدّد عدد الـ threads بنفسي، عشان البرنامج يتوسّع من core واحد لعدد كبير من الـ cores من غير إعادة بناء.

#### Acceptance Criteria

1. WHEN the Thread_Pool is initialized, THE Thread_Pool SHALL read the Core_Count from the Cpu_Info_Provider.
2. WHEN no explicit worker count is supplied, THE Thread_Pool SHALL create a number of Worker_Threads derived from the Core_Count.
3. WHERE an explicit worker count is supplied at initialization, THE Thread_Pool SHALL create exactly that number of Worker_Threads.
4. IF the Core_Count reported by the Cpu_Info_Provider is less than 1, THEN THE Thread_Pool SHALL treat the Core_Count as 1.
5. THE Parallel_For SHALL split the range `[0, count)` across the available Worker_Threads without requiring the developer to specify a thread count.

### Requirement 3: Parallel_For Semantics

**User Story:** كـ application developer، بدي `parallel_for(count, body)` تنفّذ الـ body لكل index في المدى `[0, count)` بالتوازي وتحجب لحد ما الكل يخلص، عشان أقدر أوازي الشغل بسطر واحد.

#### Acceptance Criteria

1. WHEN Parallel_For is called with a count N greater than 0, THE Parallel_For SHALL invoke the Body_Closure exactly once for every integer index in the range `[0, N)`.
2. WHEN Parallel_For returns, THE Parallel_For SHALL guarantee that all invocations of the Body_Closure for the range have completed.
3. IF the count passed to Parallel_For is 0, THEN THE Parallel_For SHALL return without invoking the Body_Closure.
4. WHILE Core_Count equals 1, THE Parallel_For SHALL execute every index serially on the calling thread.
5. IF OS threads are unavailable on the target platform, THEN THE Parallel_For SHALL execute every index serially on the calling thread via the Serial_Fallback.
6. THE Parallel_For SHALL produce identical observable results for a Pure_Mapping regardless of the Core_Count or worker scheduling.

### Requirement 4: Work-Stealing Load Balancing

**User Story:** كـ application developer، بدي الـ worker threads الخاملة تسرق شغل من المشغولة، عشان الأحمال غير المتساوية (كل index بياخد وقت مختلف) تتوزّع لحالها من غير ما أعمل tuning.

#### Acceptance Criteria

1. WHILE a Worker_Thread has an empty Work_Stealing_Deque, THE Worker_Thread SHALL attempt to steal work items from another Worker_Thread's Work_Stealing_Deque.
2. THE Work_Stealing_Deque SHALL allow its owning Worker_Thread to push and pop from one end while other Worker_Threads steal from the opposite end.
3. WHEN multiple Worker_Threads attempt to steal the same work item concurrently, THE Work_Stealing_Deque SHALL ensure that exactly one Worker_Thread acquires that work item.
4. WHILE the per-index cost of a Parallel_For range is uneven, THE Thread_Pool SHALL redistribute pending work items across idle Worker_Threads through stealing.

### Requirement 5: Persistent Thread Pool Lifecycle

**User Story:** كـ application developer، بدي الـ thread pool ينخلق مرة وحدة عند الـ startup وتنعاد فيه الـ worker threads، عشان ما ندفع تكلفة spawn (~50µs) لكل task صغير.

#### Acceptance Criteria

1. WHEN the Thread_Pool is initialized, THE Thread_Pool SHALL create all Worker_Threads once and keep them alive for reuse across many Parallel_For and Task_Closure submissions.
2. THE Thread_Pool SHALL NOT create a new OS thread per Parallel_For invocation or per Task_Closure submission.
3. WHILE the Thread_Pool has no pending work, THE Worker_Threads SHALL park via the Park_Wake_Primitive instead of busy-spinning indefinitely.
4. WHEN work is submitted to an idle Thread_Pool, THE Thread_Pool SHALL wake the parked Worker_Threads through the Park_Wake_Primitive.
5. WHEN the Thread_Pool is shut down, THE Thread_Pool SHALL signal every Worker_Thread to exit and join every Worker_Thread before returning.
6. WHEN the Thread_Pool is shut down, THE Thread_Pool SHALL release the Work_Stealing_Deque storage and all OS thread handles without leaking memory or threads.
7. IF Pool_Lifecycle initialization is invoked when the Thread_Pool is already initialized, THEN THE Thread_Pool SHALL leave the existing Worker_Threads unchanged.
8. IF Pool_Lifecycle shutdown is invoked when the Thread_Pool is already shut down, THEN THE Thread_Pool SHALL return without error.

### Requirement 6: Background Task Spawn and Wait

**User Story:** كـ application developer، بدي أرمي مهمة في الخلفية (مثلًا تحميل asset) وأرجع أستناها لما أحتاجها، عشان أشغّل شغل خلفي من غير ما أوقف الـ thread الرئيسي.

#### Acceptance Criteria

1. WHEN `spawn_task` is called with a Task_Closure, THE Thread_Pool SHALL schedule the Task_Closure for execution on a Worker_Thread and return a Task_Handle.
2. THE Thread_Pool SHALL invoke each submitted Task_Closure exactly once.
3. WHEN `wait` is called on a Task_Handle, THE Task_Handle SHALL block the calling thread until the associated Task_Closure has completed.
4. WHEN a Task_Closure has already completed before `wait` is called, THE Task_Handle SHALL return from `wait` immediately.
5. IF OS threads are unavailable on the target platform, THEN THE Thread_Pool SHALL execute the Task_Closure on the calling thread before returning the Task_Handle.

### Requirement 7: Scheduler Correctness and Thread Safety

**User Story:** كـ Dolet library maintainer، بدي الـ pool والـ scheduler نفسهم يكونوا خاليين من data races و deadlocks ومن تسريب الـ threads، عشان أبني فوقهم بثقة وأقدر أعمل property-based tests على الصحّة.

#### Acceptance Criteria

1. THE Thread_Pool SHALL guard all shared mutable pool state and Work_Stealing_Deque state using Atomic operations or a Mutex so that concurrent access is free of data races.
2. WHEN Parallel_For executes a Pure_Mapping over the range `[0, N)`, THE Parallel_For SHALL produce results equal to those of a serial loop over the same range and Body_Closure (determinism of results independent of thread count).
3. WHEN Parallel_For completes over the range `[0, N)`, THE Thread_Pool SHALL ensure that each index in `[0, N)` is processed exactly once with no lost or duplicated indices.
4. WHEN N independent indices each perform one Atomic increment on a shared counter inside a Parallel_For, THE shared counter SHALL equal N after Parallel_For returns (exact-count invariant).
5. WHEN Pool_Lifecycle initialization is invoked more than once without an intervening shutdown, THE Thread_Pool SHALL behave identically to a single initialization (idempotence of init).
6. WHEN Pool_Lifecycle shutdown is invoked more than once, THE Thread_Pool SHALL behave identically to a single shutdown (idempotence of shutdown).
7. WHILE Worker_Threads are stealing and the Thread_Pool is draining its work, THE Thread_Pool SHALL terminate Parallel_For without deadlock for any Core_Count from 1 upward.

### Requirement 8: Performance Intent

**User Story:** كـ engine developer، بدي الشغل المتوازي يقرّب من linear speedup مع عدد الـ cores، عشان الـ CPU culling يصير أسرع فعليًا على الأجهزة متعددة الـ cores.

#### Acceptance Criteria

1. WHILE running an embarrassingly-parallel workload on a machine with multiple cores, THE Parallel_For SHALL complete measurably faster than the Serial_Fallback over the same workload.
2. THE Thread_Pool SHALL keep per-Task_Closure scheduling overhead low enough that fine-grained work items benefit from pooling rather than per-task OS thread spawn.
3. WHEN Cpu_Frustum_Culling is executed through Engine_Parallel_For on a multi-core machine, THE Cpu_Frustum_Culling SHALL complete measurably faster than its serial implementation over the same scene.

### Requirement 9: Real-Machine Verifiability

**User Story:** كـ Dolet library maintainer، بدي أتحقق من الصحّة على جهاز حقيقي عبر stress tests و exact-count invariants، عشان أثبت إن الـ scheduler صحيح قبل ما أشحنه.

#### Acceptance Criteria

1. THE Dolet_Parallel SHALL provide a stress test that runs Parallel_For over a large range with each index performing one Atomic increment and asserts the final counter equals the range size.
2. THE Dolet_Parallel SHALL provide a test that asserts Parallel_For over a Pure_Mapping produces output equal to the serial loop result.
3. THE Dolet_Parallel SHALL provide a test that initializes and shuts down the Thread_Pool repeatedly and asserts no thread or memory leak across the cycles.
4. WHEN the project test suite is run via `run_tests.bat`, THE Dolet_Parallel tests SHALL pass alongside the existing tests with zero regressions.

### Requirement 10: Engine Integration

**User Story:** كـ engine developer، بدي wrapper رفيع `Engine.parallel_for(...)` و auto-parallel للـ CPU frustum culling كأول مستهلك داخلي، عشان أوازي شغل المحرك من غير ما أغيّر السلوك المرئي.

#### Acceptance Criteria

1. THE Engine_Parallel_For SHALL delegate to the `std/` Parallel_For without reimplementing the scheduler in the engine.
2. WHEN Cpu_Frustum_Culling is computed through Engine_Parallel_For, THE Cpu_Frustum_Culling SHALL produce the same visible set as the existing serial Cpu_Frustum_Culling for the same scene and camera.
3. WHERE OS threads are unavailable, THE Engine_Parallel_For SHALL compute Cpu_Frustum_Culling serially while producing the same visible set.

### Requirement 11: Thread-Crossing Closure Safety

**User Story:** كـ application developer، بدي الـ closures اللي بتعبر حدود الـ threads تنحكم بقاعدة `@heap` واضحة، عشان ما يصير use-after-free لما الـ closure env يطلع برّا الـ frame اللي خلقه.

#### Acceptance Criteria

1. THE Parallel_For SHALL require the Body_Closure to be a `@heap` closure.
2. THE `spawn_task` API SHALL require the Task_Closure to be a `@heap` closure.
3. WHEN a Worker_Thread invokes a Body_Closure or Task_Closure, THE Worker_Thread SHALL access the closure environment through the heap pointer so that the environment remains valid across the thread boundary.

### Requirement 12: CPU Core Count FFI Binding

**User Story:** كـ Dolet library maintainer، بدي الـ Windows platform layer يقرأ عدد الـ cores عبر GetSystemInfo، عشان الـ Thread_Pool يعرف Core_Count الحقيقي وقت التشغيل.

#### Acceptance Criteria

1. THE Windows platform layer SHALL bind the `GetSystemInfo` Win32 API through an `extern lib "kernel32"` declaration.
2. WHEN the Cpu_Info_Provider is queried on Windows, THE Cpu_Info_Provider SHALL return the number of logical processors reported by `GetSystemInfo`.
3. WHEN the `GetSystemInfo` binding is added to the compiler-consumed library, THE binding SHALL build through the 3-stage byte-stable bootstrap via `build.bat`.
