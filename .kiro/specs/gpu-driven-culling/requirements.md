# Requirements Document

## Introduction

هاد المستند بيوصف متطلبات نظام الـ GPU-driven culling لمحرك Frog (وهو Vulkan renderer مكتوب بلغة Dolet). الهدف إنه يكون عنا مسار رسم موحّد (unified GPU-driven draw path) صحيح ومضبوط، بيشتغل بالكامل على الـ GPU من غير ما نرجع نعتمد على مسارين منفصلين (CPU + GPU). المحرك حاليًا فيه نواة شغّالة جزئيًا: الـ frustum culling على الـ GPU مثبت وبيشتغل، بس في bug معروف بإن الأجسام المتحركة (moving objects) بتعمل flicker لما يكون مسار الرسم الـ GPU-driven مفعّل.

الشغل لهلأ انعمل عبر كذا session بشكل ad-hoc، وهاد الـ spec غرضه يجيب structure لميزة معقّدة متعددة المراحل. المطلوب نركّز على أربع محاور: (1) مسار culling + draw موحّد وصحيح دايمًا — وعلى رأسه إصلاح الـ moving-object flicker كمتطلب correctness أساسي، (2) قياس الأداء الحقيقي عبر stress scene فيها instancing تقيل، (3) visual parity تامة مع مسار الـ CPU القديم، و(4) مسار قابل للتوسّع (extensibility) باتجاه الـ occlusion culling لاحقًا.

النطاق (scope): المسار الرئيسي (main pass) بس هو اللي بصير GPU-driven. الـ shadow pass بيظل يستخدم CPU culling — وهاد حد واضح للنطاق. الـ CPU draw path بيظل موجود كـ safe fallback toggle.

## Glossary

- **Frog_Engine**: محرك الرسم المبني على Vulkan، frames-in-flight = 2.
- **Gpu_Cull_Pipeline**: الـ compute pipeline اللي بيملك جانب الـ culling (buffers + descriptor set + dispatch)، معرّف في `packages/frog/render/gpu_culling.dlt`.
- **Cull_Compute_Shader**: الـ compute shader `packages/frog/render/shaders/cull.comp`، invocation وحدة لكل candidate instance، بيختبر الـ bounding sphere ضد الـ 6 frustum planes وبيعمل compaction للـ visible records.
- **Gpu_Renderer_Core**: النواة `GpuRendererCore` في `packages/frog/render/gpu_renderer_core.dlt`، بتسجّل cull dispatches (`gpu_precull_main`) وبتصدر الـ indirect draws (`gpu_draw_main`).
- **Unified_Draw_Path**: مسار رسم واحد GPU-driven بيغطي indexed و non-indexed meshes، مع persistent GPU buffers و double/triple buffering من غير `vkQueueWaitIdle`.
- **CPU_Draw_Path**: المسار القديم اللي بيعمل culling + draw على الـ CPU، موجود كـ fallback.
- **Candidate_Instance**: سجل instance بطول candidate stride = 112 bytes (model matrix 64 + material 16 + uv 16 + bounds sphere 16).
- **Output_Instance**: سجل instance مضغوط (compacted) بطول FROG_GPU_INSTANCE_STRIDE = 96 bytes (model 64 + material 16 + uv 16).
- **Instance_Stride**: FROG_GPU_INSTANCE_STRIDE = 96 bytes.
- **Candidate_Stride**: FROG_CULL_INSTANCE_STRIDE = 112 bytes.
- **Mesh_Group**: مجموعة instances بتتشارك بنفس الـ vertex buffer / index buffer / index count / textures، وبتنرسم بـ draw call واحد.
- **Indirect_Command**: عنصر VkDrawIndexedIndirectCommand (20 bytes) أو VkDrawIndirectCommand (16 bytes) داخل الـ indirect command buffer.
- **Frame_Slot**: قسم (partition) من الـ cull buffers مخصص لإطار محدد ضمن frames-in-flight، FROG_CULL_SLOTS = 2.
- **Frustum_Planes**: الـ 6 مستويات المستخرجة من VP matrix بطريقة Gribb/Hartmann.
- **Cull_Margin**: هامش الـ culling = radius * maxScale * 2.25 + 2.0، لازم يطابق مسار الـ CPU.
- **Stress_Scene**: مشهد اختبار فيه عشرات الآلاف من الـ identical instances لقياس الفرق بين CPU و GPU culling.
- **Hi_Z_Occlusion_Culling**: culling متقدّم بيخفي الأجسام المحجوبة خلف أجسام تانية، مش بس خارج الـ frustum (مرحلة لاحقة).
- **Draw_Indirect_First_Instance**: ميزة Vulkan اختيارية لاستخدام firstInstance غير صفري في الـ indirect draws؛ حاليًا غير مفعّلة (pEnabledFeatures = NULL).
- **Visual_Parity**: تطابق بصري كامل بين مخرجات الـ Unified_Draw_Path ومسار الـ CPU_Draw_Path.
- **Debug_Counters**: سطور اللوج التشخيصية `[frog.cull]` و `[frog.render]` و `[frog.pacing]`.

## Requirements

### Requirement 1: Unified GPU-Driven Draw Path

**User Story:** كـ engine developer، بدي مسار رسم واحد GPU-driven بيغطي كل الـ meshes، عشان ما أضل أصين مسارين منفصلين CPU و GPU وأضمن سلوك متّسق.

#### Acceptance Criteria

1. THE Gpu_Renderer_Core SHALL provide a single Unified_Draw_Path that renders both indexed and non-indexed Mesh_Groups from GPU-culled output.
2. WHEN the Unified_Draw_Path is enabled, THE Gpu_Renderer_Core SHALL issue draw calls only from the compacted Output_Instance buffer produced by the Cull_Compute_Shader.
3. THE Gpu_Renderer_Core SHALL allocate persistent GPU buffers for the Unified_Draw_Path that survive across frames without per-frame reallocation when the instance budget is unchanged.
4. WHILE rendering with frames-in-flight = 2, THE Gpu_Renderer_Core SHALL partition cull buffers into FROG_CULL_SLOTS slots so that the compute pass for one frame writes only its own Frame_Slot partition.
5. THE Gpu_Renderer_Core SHALL record cull dispatches and indirect draws without calling vkQueueWaitIdle in the per-frame render path.
6. THE Gpu_Renderer_Core SHALL batch instances that share the same vertex buffer, index buffer, index count, and texture identifiers into one Mesh_Group drawn by a single Indirect_Command.

### Requirement 2: Moving-Object Flicker Correctness

**User Story:** كـ game developer، بدي الأجسام المتحركة (car + moving cube) تظهر ثابتة كل frame من غير flicker، عشان الرسم يكون صحيح ومستقر بصريًا.

#### Acceptance Criteria

1. WHILE the Unified_Draw_Path is enabled, THE Gpu_Renderer_Core SHALL render every visible moving instance in every consecutive frame without intermittent disappearance.
2. WHEN the Cull_Compute_Shader compacts visible instances via atomicAdd, THE Gpu_Renderer_Core SHALL bind each Output_Instance to its correct Mesh_Group regardless of the compaction slot order assigned within a frame.
3. WHILE an instance transform changes between consecutive frames, THE Gpu_Renderer_Core SHALL render that instance with its current-frame transform and material in the same Mesh_Group as a static instance of the same mesh.
4. THE Gpu_Renderer_Core SHALL bind the per-group instance vertex buffer at the byte offset corresponding to that group's Output_Instance slice without relying on Draw_Indirect_First_Instance.
5. THE Cull_Compute_Shader SHALL write each visible Output_Instance into a slot that lies within the bounds of its own Mesh_Group's output partition.

### Requirement 3: Visual Parity With CPU Draw Path

**User Story:** كـ engine developer، بدي مخرجات الـ GPU path تكون مطابقة بصريًا لمخرجات الـ CPU path، عشان أبدّل بينهم بأمان من غير فرق ظاهر.

#### Acceptance Criteria

1. WHEN the same scene and camera are rendered through the Unified_Draw_Path and the CPU_Draw_Path, THE Frog_Engine SHALL produce visually identical output.
2. THE Gpu_Renderer_Core SHALL group instances in the Unified_Draw_Path using the same grouping keys (vertex buffer, index buffer, index count, and all texture identifiers) used by the CPU_Draw_Path.
3. THE Gpu_Renderer_Core SHALL pack material parameters, uv transform, and the shadow-receive bit into each Output_Instance using the same packing layout as the CPU_Draw_Path.
4. THE Cull_Compute_Shader SHALL apply a Cull_Margin equal to radius * maxScale * 2.25 + 2.0, matching the CPU culling path margin.
5. THE Frog_Engine SHALL retain the CPU_Draw_Path as a runtime-selectable fallback via the gpu_draw_enabled toggle.

### Requirement 4: GPU Frustum Culling Correctness

**User Story:** كـ engine developer، بدي الـ frustum culling على الـ GPU يكون صحيح ومستقر، عشان عدد الأجسام الظاهرة يطابق منطق الـ CPU.

#### Acceptance Criteria

1. THE Cull_Compute_Shader SHALL test each Candidate_Instance's bounding sphere against all six Frustum_Planes extracted from the VP matrix.
2. WHEN a Candidate_Instance's bounding sphere lies entirely outside any Frustum_Plane by more than the Cull_Margin, THE Cull_Compute_Shader SHALL exclude that instance from the Output_Instance buffer.
3. WHEN a Candidate_Instance's bounding sphere intersects or lies inside the frustum, THE Cull_Compute_Shader SHALL include that instance in the Output_Instance buffer exactly once.
4. WHILE the camera and scene are static across consecutive frames, THE Gpu_Cull_Pipeline SHALL report a stable visible count for each Frame_Slot.
5. THE Gpu_Cull_Pipeline SHALL extract the six Frustum_Planes from the VP matrix using the Gribb/Hartmann method.

### Requirement 5: Frame Synchronization And Buffering

**User Story:** كـ engine developer، بدي الـ double/triple buffering يشتغل صح من غير CPU/GPU races، عشان frame ما يكتب على ذاكرة لسا frame تاني عم يقرأها.

#### Acceptance Criteria

1. WHILE a frame is in flight, THE Gpu_Renderer_Core SHALL write candidate and output data only into that frame's Frame_Slot partition.
2. THE Gpu_Renderer_Core SHALL insert a compute-to-vertex/indirect pipeline barrier after the cull dispatches so the graphics pass observes the compute writes.
3. WHEN reading back GPU-computed visible counts for diagnostics, THE Gpu_Renderer_Core SHALL read a Frame_Slot's counts only after that slot's fence has been waited.
4. IF the per-frame instance budget exceeds the current slot capacity, THEN THE Gpu_Cull_Pipeline SHALL grow the buffers before recording dispatches for that frame.

### Requirement 6: Performance Validation Via Stress Scene

**User Story:** كـ engine developer، بدي stress scene فيها instancing تقيل، عشان أقيس الربح الحقيقي للـ GPU culling مقابل الـ CPU بالـ ms/frame.

#### Acceptance Criteria

1. THE Stress_Scene SHALL contain at least tens of thousands of identical Mesh_Group instances to exercise real instancing.
2. WHEN the Stress_Scene is rendered, THE Frog_Engine SHALL emit Debug_Counters reporting per-frame timing for both the CPU_Draw_Path and the Unified_Draw_Path.
3. WHEN the Stress_Scene is rendered through both paths, THE Frog_Engine SHALL report the visible instance count and the frame time in milliseconds for each path.
4. THE Frog_Engine SHALL emit `[frog.cull]`, `[frog.render]`, and `[frog.pacing]` Debug_Counters during Stress_Scene rendering.

### Requirement 7: Vulkan Feature And Device Constraints

**User Story:** كـ engine developer، بدي المسار يحترم قيود الـ Vulkan device الحالية، عشان ما نعتمد على features غير مفعّلة وينكسر على أجهزة معيّنة.

#### Acceptance Criteria

1. THE Gpu_Renderer_Core SHALL NOT rely on non-zero firstInstance in any Indirect_Command while Draw_Indirect_First_Instance is disabled.
2. THE Gpu_Renderer_Core SHALL set firstInstance to zero in every Indirect_Command and offset the instance vertex buffer bind to address each Mesh_Group's output slice.
3. THE Gpu_Cull_Pipeline SHALL use a Candidate_Stride of 112 bytes and an Instance_Stride of 96 bytes for all candidate and output records.
4. THE Gpu_Renderer_Core SHALL keep the Frog_Engine frames-in-flight count at 2 for the Unified_Draw_Path buffer partitioning.

### Requirement 8: Correctness Verifiability

**User Story:** كـ developer، بدي أتحقق من صحة المسار عبر التشغيل والمراقبة والـ counters، عشان أتأكد إنه شغّال صح على GPU حقيقي.

#### Acceptance Criteria

1. THE Gpu_Cull_Pipeline SHALL provide a self_test that culls a known set of instances and reports the visible count for on-startup verification.
2. WHEN the self_test runs with four instances where two lie inside the frustum, THE Gpu_Cull_Pipeline SHALL report a visible count of two.
3. THE Gpu_Renderer_Core SHALL emit a readback Debug_Counter reporting groups, candidates, and visible counts per Frame_Slot at a fixed frame interval.
4. WHILE the Unified_Draw_Path is enabled, THE Frog_Engine SHALL allow a developer to observe correct on-screen rendering of both static and moving objects.

### Requirement 9: Round-Trip Property Of Instance Records

**User Story:** كـ engine developer، بدي أضمن إن الـ instance record اللي بيتعمله pack بينقري نفسه بعد الـ compaction، عشان أتأكد إن ما في فساد بالبيانات بين الـ CPU upload والـ GPU output.

#### Acceptance Criteria

1. WHEN an Output_Instance is read back from the compacted output buffer, THE Gpu_Renderer_Core SHALL produce a record whose model matrix, material, and uv fields equal the corresponding Candidate_Instance fields uploaded for that visible instance (round-trip property).
2. THE Gpu_Cull_Pipeline SHALL preserve the count of visible instances such that the sum of per-group visible counts equals the total number of Candidate_Instances that pass the frustum test (invariant).
3. WHEN the same VP matrix and the same candidate set are culled twice, THE Cull_Compute_Shader SHALL produce the same set of visible Output_Instances (idempotence of the cull decision).
4. THE Gpu_Cull_Pipeline SHALL produce a visible count that is less than or equal to the total Candidate_Instance count for every Mesh_Group (metamorphic bound).

### Requirement 10: Extensibility Toward Occlusion Culling

**User Story:** كـ engine developer، بدي بنية المسار تكون قابلة للتوسّع باتجاه Hi-Z occlusion culling، عشان أقدر أضيف هاي المرحلة لاحقًا من غير ما أعيد بناء المسار.

#### Acceptance Criteria

1. THE Gpu_Cull_Pipeline SHALL structure its cull stage so that an additional occlusion test can be inserted after the frustum test without changing the Indirect_Command output format.
2. THE Gpu_Renderer_Core SHALL keep the per-instance visibility decision in a single compute stage that future Hi_Z_Occlusion_Culling can extend.
3. WHERE Hi_Z_Occlusion_Culling is added in a future iteration, THE Gpu_Cull_Pipeline SHALL reuse the existing Candidate_Instance and Output_Instance layouts.

### Requirement 11: Scope Boundary For Shadow Pass

**User Story:** كـ engine developer، بدي حدود النطاق تكون واضحة، عشان أعرف إنه الـ shadow pass لسا على الـ CPU وما أتوقّع منه GPU culling.

#### Acceptance Criteria

1. THE Frog_Engine SHALL apply GPU-driven culling only to the main pass.
2. THE Frog_Engine SHALL continue to use CPU culling for the shadow pass.
3. WHEN the Unified_Draw_Path is enabled for the main pass, THE Frog_Engine SHALL leave the shadow pass culling behavior unchanged.
