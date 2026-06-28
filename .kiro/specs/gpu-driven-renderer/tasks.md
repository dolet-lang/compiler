# Tasks — GPU-Driven Renderer (Frog Engine)

> القاعدة الحاكمة: **الصحّة والجودة فوق السرعة.** كل مهمة صغيرة، خلف flag،
> fallback آمن، وتنتهي بـ checkpoint تحقق بصري من المستخدم قبل المتابعة.
> ما ننتقل لمهمة إلا بعد: build نظيف + (إن لزم) bootstrap byte-stable +
> `run_tests.bat` الخفيف 0 FAIL + **تأكيد بصري من المستخدم**.
>
> التحقق الآمن (عشان ما نعلّق الجهاز): `getDiagnostics` للكود +
> background process للبناء (مش executePwsh ثقيل) + المستخدم يشغّل اللعبة.

---

## المرحلة 0 — Capability Detection (R5) — الأساس، صفر خطر بصري

- [x] 0.1 أضف `struct GpuCaps` (6 حقول i32) لـ `VulkanContext` layer + حقل
      `caps: GpuCaps` يُملأ مرة عند الإقلاع.
  - _Requirements: 5.1, 5.3_

- [x] 0.2 نفّذ كشف الـ API version (`vkEnumerateInstanceVersion`) واطلب
      أعلى نسخة في `VkApplicationInfo` مع fallback (1.3 → 1.2 → 1.0).
  - _Requirements: 5.1_

- [x] 0.3 نفّذ كشف الـ features عبر `vkGetPhysicalDeviceFeatures2` + pNext
      chain (descriptor indexing, draw-indirect-count, dynamic rendering)
      و `vkGetPhysicalDeviceProperties2` للسقوف؛ خزّنها في `caps`.
  - _Requirements: 5.2, 5.3_

- [x] 0.4 فعّل **فقط** الـ features المدعومة عند `vkCreateDevice` (pNext
      features chain). لو مدعوم → مفعّل؛ لو لا → 0 في caps.
  - _Requirements: 5.2, 5.4_

- [x] 0.5 اطبع سطر تشخيصي عند الإقلاع:
      `[frog.caps] api=.. bindless=.. indirect_count=.. dynamic_rendering=.. max_desc=..`
  - _Requirements: 5.3_

- [ ] 0.6 **Checkpoint بصري**: المستخدم يبني ويشغّل اللعبة — تتأكد إنها
      تشتغل بالضبط زي قبل (صفر تغيير بصري/أداء) ويقرأ سطر الـ caps على
      جهازه. لا متابعة قبل التأكيد.
  - _Requirements: 5.4, 7.1_

---

## المرحلة 1 — Bindless Texture Table (R1) — أكبر مكسب معماري

- [ ] 1.1 أضف حقول الـ bindless لـ `GpuRendererCore` (layout/pool/set/
      count/enabled) + `bindless_enabled = caps.descriptor_indexing && flag`.
  - _Requirements: 1.1_

- [ ] 1.2 نفّذ `_bindless_init`: ينشئ descriptor set layout (binding 0،
      count=cap، PARTIALLY_BOUND + UPDATE_AFTER_BIND) + pool + set. خلف
      `bindless_enabled`.
  - _Requirements: 1.1_

- [ ] 1.3 نفّذ `_bindless_register(view, sampler) -> i32`: يكتب الـ slot،
      يرجّع الـ index. اربط تسجيل الـ texture الموجود ليكتب slot في الجدول
      (بالتوازي مع المسار القديم — ما نكسر الـ classic بعد).
  - _Requirements: 1.2_

- [ ] 1.4 اكتب fragment shader bindless (`*_bindless.frag`) مع
      `GL_EXT_nonuniform_qualifier` + `sampler2D textures[]`؛ مرّر
      `texture_index` من الـ vertex shader (من الـ instance data،
      مُحزَّم في material vec4). ترجم لـ SPIR-V واضمّنه.
  - _Requirements: 1.3_

- [ ] 1.5 أنشئ pipeline variant يستعمل الـ bindless set + الـ shader
      الجديد، خلف `bindless_enabled`. اربط الـ bindless set مرة وحدة بداية
      الـ frame.
  - _Requirements: 1.1, 1.3_

- [ ] 1.6 عدّل `gpu_draw_main` (والمسار الـ CPU draw): لو `bindless_enabled`
      → لا `vkCmdBindDescriptorSets` بين المجموعات؛ الـ texture index من
      الـ instance. وإلا → المسار الحالي بالضبط.
  - _Requirements: 1.1, 1.4_

- [ ] 1.7 **Checkpoint بصري**: المستخدم يشغّل بالـ flag ON ثم OFF، يقارن
      الصورة (لازم متطابقة) والـ FPS. تأكيد: لا regression بصري + bindless
      شغّال. لا متابعة قبل التأكيد.
  - _Requirements: 1.5, 7.1, 7.3_

---

## المرحلة 2 — Indirect-Count Draw (R2) — يحتاج المرحلة 1

- [ ] 2.1 أضف `count_buffer` لـ `GpuCullPipeline` + flag
      `indirect_count_enabled = caps.draw_indirect_count && bindless_enabled && flag`.
  - _Requirements: 2.1_

- [ ] 2.2 عدّل الـ cull compute shader ليكتب `VkDrawIndexedIndirectCommand`
      array + count في count buffer على الـ GPU (atomic)، بدون CPU
      round-trip.
  - _Requirements: 2.1, 2.2_

- [ ] 2.3 استبدل per-group `vkCmdDrawIndexedIndirect` بـ
      `vkCmdDrawIndexedIndirectCount` لكل batch، خلف الـ flag. fallback
      للمسار الحالي لو معطّل.
  - _Requirements: 2.1, 2.3, 2.4_

- [ ] 2.4 **Checkpoint بصري**: المستخدم يقارن flag ON/OFF — صورة متطابقة،
      وعدد draw calls المُصدَرة من CPU ثابت (مش خطّي بعدد المجموعات). تأكيد.
  - _Requirements: 2.4, 2.5, 7.1_

---

## المرحلة 3 — Multi-Threaded Command Recording (R3) — مستقلة (بعد 0)

- [ ] 3.1 أنشئ command pool لكل worker thread (`num_workers+1` pools)
      مرة عند init الـ render + ring من secondary command buffers لكل
      thread/frame.
  - _Requirements: 3.2, 3.5_

- [ ] 3.2 نفّذ inheritance info للـ secondary (render pass / dynamic
      rendering formats) + تسجيل batch واحد في secondary
      (RENDER_PASS_CONTINUE).
  - _Requirements: 3.1, 3.2_

- [ ] 3.3 وزّع تسجيل الـ batches عبر `engine_parallel_for` (كل worker
      يكتب على secondary buffers خاصة بـ tid تبعه — race-free)، ثم
      `vkCmdExecuteCommands` على الـ primary. خلف
      `mt_record_enabled = flag && worker_count>0 && batches>threshold`.
  - _Requirements: 3.1, 3.3_

- [ ] 3.4 fallback: لو معطّل أو batches قليلة → تسجيل على الـ primary
      مباشرة (المسار الحالي).
  - _Requirements: 3.3_

- [ ] 3.5 **Checkpoint بصري**: المستخدم يقارن flag ON/OFF على مشهد كثيف —
      صورة متطابقة، صفر crash/flicker (sync صح)، وتحسّن FPS لو CPU-bound.
      تأكيد قبل المتابعة.
  - _Requirements: 3.4, 3.5, 7.1_

---

## المرحلة 4 — GPU Instance Transforms (R4) — مستقلة (بعد 0)

- [ ] 4.1 أضف `instance_params` buffer (host-mapped، 9 floats/instance) +
      API `Engine.set_instance_motion(...)` + flag.
  - _Requirements: 4.1, 4.3_

- [ ] 4.2 اكتب `transform.comp`: invocation لكل instance، يبني TRS من الـ
      params في الـ candidate model matrix. ترجم لـ SPIR-V واضمّنه.
  - _Requirements: 4.1_

- [ ] 4.3 ادمج الـ transform pass قبل الـ cull (barrier صح). خلف الـ flag؛
      fallback للـ CPU transform refresh لو معطّل.
  - _Requirements: 4.2, 4.3_

- [ ] 4.4 **Checkpoint بصري**: المستخدم يقارن flag ON/OFF — مواضع الكائنات
      متطابقة، CPU transform شغل ينزل. تأكيد.
  - _Requirements: 4.4, 7.1_

---

## المرحلة 5 — Dynamic Rendering (R6) — اختيارية، آخراً

- [ ] 5.1* استبدل render-pass/framebuffer بـ
      `vkCmdBeginRendering`/`vkCmdEndRendering` خلف `caps.dynamic_rendering`
      + flag. fallback للـ render-pass الكلاسيكي.
  - _Requirements: 6.1, 6.2_

- [ ] 5.2* **Checkpoint بصري**: صورة متطابقة flag ON/OFF. تأكيد.
  - _Requirements: 6.3, 7.1_

---

## بعد كل مرحلة

- [ ] حدّث `AGENTS.md` لو تغيّرت معمارية/calling-convention/بنية stdlib.
- [ ] push للـ frog repo (+ vulkan/library لو لزم) بعد تأكيد المستخدم البصري.
- [ ] الـ flags الجديدة موثّقة (كيف تفعّل/تعطّل المسار الحديث).

> ملاحظة: المهام بعلامة `*` اختيارية (تبسيط مش أداء). الباقي أساسي.
> الترتيب: 0 إجباري أول. 1→2 متسلسلة. 3 و4 مستقلتان (بعد 0). 5 آخراً.
