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

- [x] 0.6 **Checkpoint بصري**: المستخدم يبني ويشغّل اللعبة — تتأكد إنها
      تشتغل بالضبط زي قبل (صفر تغيير بصري/أداء) ويقرأ سطر الـ caps على
      جهازه. لا متابعة قبل التأكيد.
  - _Requirements: 5.4, 7.1_
  - ✅ **تم** على RTX: `[frog.caps] api=4206592 bindless=1 indirect_count=1
    dynamic_rendering=1 max_desc=65536`. اللعبة اشتغلت كامل (rendering +
    GPU cull self_test visible=2 + 100k bots) صفر regression بصري.
  - **اكتشاف NVIDIA**: الـ Vulkan-1.2 aggregate (sType 49) بيرجّع
    descriptor-indexing sub-features = 0؛ الـ struct المخصص
    `VkPhysicalDeviceDescriptorIndexingFeatures` (sType 1000161001) بيرجّعها
    صح. الكشف صار يقرأ من الاثنين (OR). **تفعيل bindless على الجهاز مؤجّل
    للمرحلة 1** (لإنه ممنوع تحط struct-ين بنفس pNext chain — VUID-02830 —
    والـ NVIDIA driver بينهار؛ لسا ما في مسار رسم بستعمله).

---

## المرحلة 1 — Bindless Texture Table (R1) — أكبر مكسب معماري ✅ مكتملة

- [x] 1.1 حقول الـ bindless في `GpuRendererCore` (layout/pool/set/count/
      capacity/supported/flag/enabled) + `set_bindless_caps`.
  - _Requirements: 1.1_

- [x] 1.2 `_bindless_init`: descriptor set layout (binding 0، count=cap،
      PARTIALLY_BOUND + UPDATE_AFTER_BIND) + pool (UPDATE_AFTER_BIND) + set.
      تفعيل descriptor-indexing على الجهاز عبر الـ struct المخصص
      `VkPhysicalDeviceDescriptorIndexingFeatures` (sType 1000161001) — بدون
      الـ Vulkan12 aggregate (VUID-02830). fallback متدرّج.
  - _Requirements: 1.1_

- [x] 1.3 `_bindless_register(view, sampler) -> i32` + ربطه بـ
      `register_texture` (بالتوازي مع المسار القديم). `tex_bindless_slots[]`.
  - _Requirements: 1.2_

- [x] 1.4 الـ shaders: `textured_bindless.vert` (يمرّر uvec4×2 texidx) +
      `textured_bindless.frag` (`sampler2D textures[]` set 2،
      `nonuniformEXT`). توسيع الـ instance record 96→128 (5 slots + spare)؛
      الـ cull compute ينسخها. اضطر رفع `MAX_TOKENS` بالكمبايلر (الـ frag
      الكبير سبّب token-buffer overflow) + bootstrap.
  - _Requirements: 1.3_

- [x] 1.5 `_create_bindless_pipeline`: 3-set layout (material/lights/bindless)
      + 22 vertex attribute (loc 21/22 texidx)، نفس fixed-function state.
  - _Requirements: 1.1, 1.3_

- [x] 1.6 الرسم: لو `bindless_enabled` → bindless pipeline + ربط الجدول مرة
      (set 2) + set 0 مرة (shadow sampler) + **صفر per-group descriptor bind**.
      المسار الكلاسيكي fallback.
  - _Requirements: 1.1, 1.4_

- [x] 1.7 **Checkpoint بصري**: ✅ تم على RTX — الصورة **متطابقة** مع الكلاسيكي
      (rendering كامل + 100k bots)، صفر تشويه، `[frog.bindless] pipeline ready`.
      الـ flag `Engine.set_bindless(0/1)` للتبديل.
  - _Requirements: 1.5, 7.1, 7.3_

> ملاحظة: `gpu_draw_main` (مسار الـ GPU-culling indirect draw) لسا ما اتعدّل
> للـ bindless — هاد بيتغطّى مع المرحلة 2 (indirect-count) اللي بتعيد بناءه.
> المسار النشط حالياً (CPU draw mode) bindless كامل.

---

## المرحلة 2 — Indirect-Count Draw (R2) ✅ مكتملة (بالقدر العملي)

- [x] 2.1 `draw_count_buffer` في `GpuCullPipeline` + helpers
      (`set_draw_count`/`draw_count_offset`/`draw_count_handle`). تفعيل
      `drawIndirectCount` على الجهاز عبر extension `VK_KHR_draw_indirect_count`
      (مش feature struct — لتجنّب تعارض pNext مع descriptor-indexing). +
      base features `multiDrawIndirect` + `drawIndirectFirstInstance`.
  - _Requirements: 2.1_

- [x] 2.2 الـ cull compute بيكتب `VkDrawIndexedIndirectCommand` array +
      `instanceCount` (atomic) على الـ GPU. الـ draw-count CPU-known بدقة
      (مفيش round-trip فعلي).
  - _Requirements: 2.1, 2.2_

- [x] 2.3 `gpu_draw_main` صار يستعمل `vkCmdDrawIndexedIndirectCount` (الاسم
      الـ core — الـ KHR مش مُصدّر بالـ import lib). الـ GPU بيقرأ عدد الـ
      draws + عدد الـ instances. fallback للمسار الكلاسيكي محفوظ.
  - _Requirements: 2.1, 2.3, 2.4_

- [x] 2.4 **Checkpoint بصري**: ✅ تم على RTX — صورة متطابقة، السيارة ثابتة،
      100k bots صح. الـ GPU يقرّر الـ draw count + instanceCount بدون CPU
      round-trip.
  - _Requirements: 2.4, 2.5, 7.1_

> **batching الكامل (أمر draw واحد لمجموعات متعددة) مؤجّل**: المعمارية
> الأقوى (SSBO + `gl_InstanceIndex`، pipeline ثالث) مبنية بالكامل بس **معطّلة
> خلف `ssbo_batch_path=0`** لأنه الـ NVIDIA driver ما بيحترم `firstInstance>0`
> عملياً (السيارة كانت تظهر بمواضع الـ bots مع طريقتين مختلفتين). السبب الجذري
> (غالباً `drawIndirectFirstInstance` مش مفعّل فعلياً، أو يحتاج
> `VK_KHR_shader_draw_parameters` + `gl_DrawID`) يحتاج تحقيق منفصل. المسار
> النشط (per-group indirect-count) بيحقق هدف R2 الأساسي، والـ batching مكسبه
> ضئيل في المشاهد ذات mesh-واحد (زي الـ bots).

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
