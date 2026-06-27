# Implementation Plan: GPU-Driven Culling

## Overview

هاي الخطة بتحوّل تصميم الـ unified GPU-driven draw path لسلسلة خطوات coding متدرّجة. الترتيب
مقصود: أول إشي إصلاح الـ moving-object flicker (correctness)، بعدها validation، بعدها قياس
الأداء، وآخر إشي الـ extensibility الاختياري. كل task بتبني على اللي قبلها وبتنتهي بحالة
buildable + runnable.

الشغل engine-only — الـ bootstrap/compiler ما بدّه أي تعديل. بناء تغييرات الـ frog engine
بيصير عبر إعادة بناء لعبة الاختبار اللي بتستورد المحرك:

```
# من مجلد collision-demo-frog-oop-3d
bin\doletc.exe src\main.dlt -o build\app.exe -O3        # ~15-20s
```

تعديلات الـ shader بدها: glslc compile لـ `render/shaders/cull.comp` → `spv_to_dolet.py`
لتحويل الـ SPIR-V → splice داخل `_frog_init_cull_shader` بـ `render/gpu_shaders.dlt` →
تصليح حجم البايتات بـ `get_cull_compute_shader` (حاليًا 7168).

## Tasks

- [ ] 1. إصلاح الـ flicker: clear + تقوية الـ compute→graphics synchronization
  - [x] 1.1 صفّر output range لكل group قبل الـ dispatch
    - بـ `gpu_precull_main` (gpu_renderer_core.dlt): قبل ما تنادي `cull.dispatch_group`
      لكل group، نفّذ `vkCmdFillBuffer` على شريحة الـ out_buffer تبعت الـ group
      (offset = `group_in_base * FROG_CULL_OUT_STRIDE`، size = `group_n * FROG_CULL_OUT_STRIDE`)
      وعلى slot's indirect-command range، عشان ما يضل في stale records من frame سابق
    - أضف transfer→compute `VkBufferMemoryBarrier` بعد الـ fill وقبل الـ dispatch
      (src=TRANSFER_WRITE, dst=SHADER_READ|SHADER_WRITE; srcStage=TRANSFER, dstStage=COMPUTE)
    - عرّف helper جديد بـ `GpuCullPipeline` (gpu_culling.dlt) زي `fill_out_range(cmd, out_base, count)`
      عشان الـ fill يستعمل الـ out_buffer handle الداخلي
    - _Requirements: 2.1, 2.5, 5.1_

  - [x] 1.2 قوّي الـ compute→graphics barrier بـ explicit buffer barriers
    - بدّل (أو دعّم) الـ global `MEMORY_BARRIER` بـ `barrier_after_dispatches`
      (gpu_culling.dlt) بـ `VkBufferMemoryBarrier`-ات صريحة على out_buffer +
      count_buffer (indirect)
    - out_buffer: src=SHADER_WRITE → dst=VERTEX_ATTRIBUTE_READ (0x8)
    - count_buffer: src=SHADER_WRITE → dst=INDIRECT_COMMAND_READ (0x2)
    - srcStage=COMPUTE (0x800), dstStage=DRAW_INDIRECT|VERTEX_INPUT (0x6)
    - _Requirements: 2.1, 2.2, 5.2_

  - [x] 1.3 ابني وشغّل collision-demo وتأكد إنه الـ flicker راح
    - ابني اللعبة بالأمر فوق، شغّل المشهد فيه الـ car + moving cube مع
      `gpu_draw_enabled = 1` وراقب إنه الأجسام المتحركة ثابتة بكل frame
    - راقب counter الـ `[frog.cull] readback` إنه الـ visible count ثابت
      للـ static camera (Requirement 4.4)
    - _Requirements: 2.1, 2.3, 8.4_

- [ ]* 2. (OPTIONAL — شرطي) deterministic per-candidate compaction fallback
  - بس إذا ضل في flicker بعد task 1: بدّل الـ `atomicAdd` ordering بـ
    cull.comp بـ stable output slot لكل candidate (كل candidate بيكتب على
    `outBase + local` بدل slot عشوائي من atomic)، مع منطق per-group لتعبئة
    الـ instanceCount عبر prefix-count أو second pass
    - عدّل `cull.comp`، أعد توليد الـ SPIR-V عبر `spv_to_dolet.py`، اعمل splice
      بـ `_frog_init_cull_shader` (gpu_shaders.dlt) وصحّح حجم البايتات بـ
      `get_cull_compute_shader`
    - ابني collision-demo وتأكد إنه الـ visible set صحيح والـ flicker راح
  - _Requirements: 2.2, 2.5_

- [ ] 3. Checkpoint — تأكد إنه الـ build ناجح والمشهد بيتعرض صح
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. تحقق من الـ visual parity مع مسار الـ CPU
  - [ ] 4.1 قارن GPU path مقابل CPU path على نفس المشهد
    - بدّل `set_gpu_draw(0)` و `set_gpu_draw(1)` على نفس مشهد collision-demo
      ونفس الكاميرا وتأكد إنه نفس الأجسام بنفس الشكل
    - تأكد إنه grouping keys بـ `gpu_precull_main` (vb/ib/ic + كل texture ids
      عبر `_grp_tex`) مطابقة لمنطق الـ CPU draw loop
    - تأكد إنه الـ material + uv + shadow-receive bit packing بـ
      `_cull_upload_instance` مطابق للـ CPU (نفس الـ FROG_GPU_INSTANCE offsets
      ونفس الـ +65536.0 للـ shadow bit)
    - تأكد إنه الـ Cull_Margin بـ cull.comp = `radius * maxScale * 2.25 + 2.0`
      مطابق للـ CPU `_frog_instance_visible`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 5. فرض الـ slot/frames-in-flight invariants
  - [ ] 5.1 تأكد frames-in-flight == FROG_CULL_SLOTS == 2 وحدود الـ partition
    - أضف assert/guard بـ `gpu_precull_main` و/أو بالـ init إنه `rp.max_frames`
      == `FROG_CULL_SLOTS` (2)؛ اطبع تحذير `[frog.cull]` واسقط بأمان لو اختلفوا
    - تأكد إنه `slot_in_base`/`slot_cmd_base` + `in_cursor` ما بيتعدّوا
      `slot_cap` و `FROG_CULL_MAX_GROUPS` بكل group؛ أضف bounds clamp/guard
    - تأكد إنه firstInstance = 0 بكل indirect command وإنه الـ instance vertex
      buffer متربّط على byte offset الـ group (gpu_draw_main)
    - _Requirements: 5.1, 7.1, 7.2, 7.3, 7.4_

- [ ] 6. ابني host-side correctness test harness
  - [ ] 6.1 ابني الـ harness الأساسي (على نمط self_test / gpu_cull_verify)
    - أضف function جديدة بـ `GpuCullPipeline` (gpu_culling.dlt) بتعمل: upload
      candidate set معروف عبر `write_full_instance`، dispatch عبر one-shot
      command buffer (`gpu_tex_begin_oneshot`/`gpu_tex_end_oneshot`)، wait idle،
      وقراءة الـ out_buffer + الـ indirect instanceCounts عبر
      `group_visible_count`
    - أضف random generators: random transforms، random in/out-of-frustum
      positions، random group partitions
    - _Requirements: 8.1, 8.2, 9.1_

  - [ ]* 6.2 Property test — round-trip لسجلات الـ instance
    - **Property 1: Instance record round-trip**
    - الـ Output_Instance المقروء (model + material + uv) = حقول الـ
      Candidate_Instance اللي انعمله upload لنفس الـ visible instance
    - **Validates: Requirements 9.1**

  - [ ]* 6.3 Property test — invariant عدد الـ visible
    - **Property 2: Visible-count invariant**
    - مجموع per-group visible counts = عدد الـ candidates اللي عبروا الـ
      frustum test
    - **Validates: Requirements 9.2, 4.3**

  - [ ]* 6.4 Property test — idempotence القرار
    - **Property 3: Cull idempotence**
    - نفس VP + نفس candidate set مرتين → نفس مجموعة الـ visible Output_Instances
    - **Validates: Requirements 9.3, 4.4**

  - [ ]* 6.5 Property test — حدّ الـ visible <= candidate
    - **Property 4: Visible-count bound**
    - الـ visible count <= مجموع الـ candidates لكل Mesh_Group
    - **Validates: Requirements 9.4**

- [ ] 7. Checkpoint — تأكد إنه الـ harness والـ properties بتمرّ
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 8. ابني الـ stress scene وقيس CPU مقابل GPU
  - [ ] 8.1 ابني مشهد stress فيه عشرات الآلاف من الـ identical instances
    - أضف مشهد بـ collision-demo (أو scene module منفصل) بيرفع عشرات الآلاف
      من نفس الـ Mesh_Group instances عشان يحرّك instancing حقيقي
    - _Requirements: 6.1_

  - [ ] 8.2 سجّل الفرق CPU-path مقابل GPU-path بالـ ms/frame
    - شغّل المشهد مرة مع `set_gpu_draw(0)` ومرة مع `set_gpu_draw(1)`، اقرأ
      counters `[frog.pacing]` (engine.dlt) + `[frog.render]`
      (`_debug_record_frame`) + `[frog.cull]` (`_gpu_cull_dbg_readback`)
    - تأكد إنه الـ visible instance count + frame time ms بينطبعوا لكل path
      وسجّل المقارنة بـ commit message أو ملاحظة بالكود
    - _Requirements: 6.2, 6.3, 6.4_

- [ ] 9. نظّف الـ debug counters أو حطّها خلف debug flag
  - بعد ما تتأكد من الـ correctness: شيل أو gate الـ diagnostic readback
    (`_gpu_cull_dbg_readback`) و `gpu_slot_runs` tracking خلف debug flag
    موجود بدل ما يشتغلوا كل frame
    - تأكد إنه إزالة/gating ما بتكسر الـ build ولا الـ render path
  - _Requirements: 8.3_

- [ ] 10. Final checkpoint — تأكد إنه كل إشي بيبني وبيشتغل
  - Ensure all tests pass, ask the user if questions arise.

- [ ]* 11. (OPTIONAL — مستقبلي) hook للـ Hi-Z occlusion culling
  - وثّق بـ `cull.comp` بالضبط وين بينحط الـ occlusion test بعد الـ frustum
    test من غير ما يتغيّر الـ Candidate / Output / Indirect_Command I/O layout
  - أضف comment marker واضح بالـ shader + بـ `gpu_precull_main` يبيّن نقطة
    الإدراج المستقبلية بحيث القرار يضل بـ compute stage واحدة
  - _Requirements: 10.1, 10.2, 10.3_

## Notes

- الـ tasks المعلّمة بـ `*` اختيارية: task 2 شرطي (بس إذا ضل flicker)،
  property tests (6.2-6.5) للتحقق، و task 11 مستقبلي.
- الـ shadow pass خارج النطاق — بيظل CPU culling (Requirement 11).
- كل task بيشير لـ requirements محدّدة للـ traceability.
- الـ property tests بتتحقق من خصائص Requirement 9 العامة؛ الـ harness بـ
  task 6.1 لازم يشتغل قبلهم.
- ما في تعديل على الـ bootstrap/compiler — engine-only، والبناء عبر إعادة
  بناء لعبة الاختبار.
