# Design — GPU-Driven Renderer (Frog Engine)

## Overview

هاد المستند بيوصف تحويل الـ Frog renderer لمعمارية GPU-driven حديثة على
مستوى محركات AAA، فوق المعمارية الشغّالة الحالية (render-pass + GPU cull +
indirect draw + CPU thread pool). الفلسفة: **كل مسار حديث خلف flag/قدرة،
fallback آمن للمسار الكلاسيكي، وتحقق بصري من المستخدم بعد كل مرحلة.**

اكتشاف معماري مهم من فحص الكود: **الـ Vulkan FFI شامل بالكامل** (1396
دالة مربوطة في `packages/vulkan`، بما فيها `vkCmdDrawIndexedIndirectCount`,
`vkCmdBeginRendering`, `vkCmdExecuteCommands`, `vkGetPhysicalDeviceFeatures2`,
descriptor indexing structs). يعني **ما في حاجة لإضافة FFI** — كل الشغل
هو في طبقة الـ engine (`packages/frog/render/`).

### المعمارية الحالية (نقطة البداية)

```
VulkanContext (instance, device, queues)
  → Swapchain (images, depth)
  → RenderPass (vk_render_pass + framebuffers + graphics pipeline)
  → GpuRendererCore (mesh registry, per-mesh descriptor sets, model matrices)
  → GpuCullPipeline (compute frustum cull → per-group vkCmdDrawIndexedIndirect)
  → CPU thread pool (parallel cull pre-pass / transform refresh)
```

نقاط الضعف المعمارية مقابل الـ state-of-the-art:
1. **descriptor set منفصل لكل texture/mesh** → `vkCmdBindDescriptorSets`
   لكل مجموعة. (R1 يعالجها بـ bindless.)
2. **`vkCmdDrawIndexedIndirect` لكل مجموعة** → عدد draw calls خطّي بعدد
   المجموعات. (R2 يعالجها بـ indirect-count.)
3. **تسجيل الأوامر على thread واحد** (الـ primary command buffer). (R3
   يعالجها بـ secondary command buffers متوازية.)
4. **TRS على الـ CPU** لكل كائن متحرك. (R4 يعالجها بـ GPU transforms.)
5. **render-pass/framebuffer objects** ثابتة. (R6 dynamic rendering، اختياري.)

### المعمارية المستهدفة

```
Capability detection (R5) → tier: { classic | modern }
  modern path:
    Bindless table (one giant descriptor set, all textures) (R1)
    GPU cull/compaction → draw-command buffer + count buffer on GPU (R2)
    vkCmdDrawIndexedIndirectCount (one call per material-batch)
    Multi-threaded secondary command buffer recording (R3)
    GPU compute instance transforms (R4)
    (optional) dynamic rendering (R6)
  classic path: المعمارية الحالية بالكامل (fallback)
```

### مبدأ التصميم الحاكم: الصحّة قبل السرعة، flag-gated، بصري-التحقق

النظام renderer على محرك حي، والمطوّر (وأنا) ما يقدر يشوف bugs بصرية إلا
بالتشغيل. القرار الحاكم: **كل مرحلة معزولة خلف flag، fallback للمسار
القديم دايماً موجود، وما ننتقل لمرحلة إلا بعد تحقق بصري من المستخدم +
bootstrap byte-stable + الـ tests الخفيفة 0 FAIL.**

### Requirement Coverage Map

| Req | الموضوع | القسم في الـ design |
|---|---|---|
| R1 | Bindless resources | §1 Bindless Texture Table |
| R2 | GPU-decided draw count | §2 Indirect-Count Draw |
| R3 | Multi-threaded command recording | §3 Secondary Command Buffers |
| R4 | GPU-side instance transforms | §4 GPU Transform Compute |
| R5 | Modern Vulkan + capability detection | §0 Capability Detection |
| R6 | Dynamic rendering | §5 Dynamic Rendering (optional) |
| R7 | No regression | §6 Verification Strategy |
| R8 | Incremental flag-gated rollout | §7 Rollout Plan |

---

## §0 — Capability Detection (R5) — المرحلة الأولى، الأساس

أول شي وأقلّه خطراً: نكتشف قدرات الجهاز ونخزّنها، **بدون تغيير أي مسار رسم
بعد**. هاد بيبني الأساس اللي كل المراحل اللاحقة تبني عليه.

### بنية البيانات: `GpuCaps`

```dolet
struct GpuCaps:
    api_version:           i32 = 0   # VK_MAKE_VERSION المكتشَف
    descriptor_indexing:   i32 = 0   # bindless ممكن؟ (R1)
    draw_indirect_count:   i32 = 0   # indirect-count ممكن؟ (R2)
    dynamic_rendering:     i32 = 0   # dynamic rendering ممكن؟ (R6)
    max_descriptor_array:  i32 = 0   # سقف bindless table
    timestamp_valid_bits:  i32 = 0   # GPU timing (للقياس)
```

### الكشف (في VulkanContext init)

- استعمال `vkEnumerateInstanceVersion` لأعلى API version؛ نطلب 1.3 بالـ
  `VkApplicationInfo.apiVersion`، fallback لـ 1.2 ثم 1.0.
- `vkGetPhysicalDeviceFeatures2` مع سلسلة pNext:
  `VkPhysicalDeviceDescriptorIndexingFeatures`,
  `VkPhysicalDeviceVulkan12Features` (drawIndirectCount,
  descriptorIndexing), `VkPhysicalDeviceDynamicRenderingFeatures`.
- `vkGetPhysicalDeviceProperties2` → `maxPerStageDescriptorSampledImages`
  / `maxDescriptorSetSampledImages` للسقف.
- نفعّل **فقط** الـ features المدعومة عند `vkCreateDevice` (عبر pNext
  features chain).

### Fallback

لو أي feature غير مدعوم → الحقل = 0 → النظام الفرعي المقابل يختار المسار
الكلاسيكي. المحرك ما ينهار.

### التحقق

طباعة سطر تشخيصي عند الإقلاع:
`[frog.caps] api=1.3 bindless=1 indirect_count=1 dynamic_rendering=1 max_desc=1048576`
يتأكد المستخدم إنه القدرات اتكتشفت صح على جهازه (RTX = كلها 1).

---

## §1 — Bindless Texture Table (R1)

### الفكرة

descriptor set واحد، binding واحد من نوع
`VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER` مع `descriptorCount =
max_textures` (مثلاً 65536) و flags
`VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT |
VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT`. كل texture مسجّلة بتاخد slot
index؛ الـ instance record بيحمل `texture_index`؛ الـ fragment shader
يـ `sample(textures[nonuniformEXT(idx)], uv)`.

### البنية: امتداد `GpuRendererCore`

```dolet
# داخل GpuRendererCore (modern path fields):
bindless_layout:   i64 = 0   # VkDescriptorSetLayout (واحد، update-after-bind)
bindless_pool:     i64 = 0   # VkDescriptorPool (update-after-bind)
bindless_set:      i64 = 0   # VkDescriptorSet (الجدول الكبير)
bindless_count:    i32 = 0   # عدد الـ slots المستعملة
bindless_enabled:  i32 = 0   # caps.descriptor_indexing && flag
```

### العمليات

- **`_bindless_init`**: ينشئ layout (binding 0، count=cap، partially-bound
  + update-after-bind) + pool + set مرة وحدة.
- **`_bindless_register(view, sampler) -> i32`**: يكتب
  `VkWriteDescriptorSet` للـ slot `bindless_count`، يرجّع الـ index،
  `bindless_count++`. (update-after-bind يسمح بالكتابة حتى لو الـ set
  مربوط.)
- الـ instance record (الـ 96-byte output / candidate) بيضيف
  `texture_index` (موجود ضمن الـ material vec4 — نستعمل قناة منه، أو
  نوسّع الـ record). الـ cull compute ينسخه زي ما هو.

### الـ shaders

نسخة جديدة من الـ fragment shader (`*_bindless.frag`) فيها:
```glsl
#extension GL_EXT_nonuniform_qualifier : require
layout(set = 1, binding = 0) uniform sampler2D textures[];
// ... color = texture(textures[nonuniformEXT(inTexIndex)], uv);
```
الـ vertex shader يمرّر `texture_index` (من الـ instance data) للـ fragment.

### Dispatch & fallback

- لو `bindless_enabled == 1`: المحرك يربط الـ bindless set **مرة وحدة**
  بداية الـ frame، ويرسم كل المجموعات بدون أي `vkCmdBindDescriptorSets`
  بينها (الـ texture index من الـ instance data).
- لو `bindless_enabled == 0`: المسار الحالي (per-mesh descriptor set عبر
  `mesh_descriptor_set`) بالضبط زي ما هو.

### الأثر المعماري

هاد بيلغي الـ per-group descriptor bind في `gpu_draw_main` — وبيفتح الباب
للـ R2 (كل المجموعات اللي تتشارك pipeline تنرسم بأمر واحد، لأنه ما عاد في
حاجة تبدّل descriptor بينها).

---

## §2 — Indirect-Count Draw (R2)

### الفكرة

بدل `vkCmdDrawIndexedIndirect` لكل مجموعة (CPU loop خطّي)، نستعمل
`vkCmdDrawIndexedIndirectCount`: الـ GPU cull/compaction pass يكتب مصفوفة
من `VkDrawIndexedIndirectCommand` + قيمة **count** في count buffer؛ الـ
CPU يصدر أمر واحد لكل **batch** (مجموعة meshes تتشارك vertex/index buffer
+ pipeline)، والـ GPU يقرأ كم draw ينفّذ.

### المتطلب المسبق

- **bindless** (R1) — عشان المجموعات اللي تختلف بس بالـ texture تنرسم
  بأمر واحد (الـ texture index في الـ instance data، مش descriptor bind).
- نفس الـ vertex buffer / index buffer للـ batch (الـ instancing الحالي
  أصلاً يحقق هاد للـ bots: مصدر واحد + N instances).

### البنية

```dolet
# في GpuCullPipeline:
count_buffer:  i64 = 0   # GPU buffer فيه uint count لكل batch
cmd_buffer:    i64 = 0   # VkDrawIndexedIndirectCommand[] (موجود جزئياً)
```

الـ cull compute (R2.2) يكتب الـ commands + يـ atomic-increment الـ count
في count buffer. الـ CPU:
```
vkCmdDrawIndexedIndirectCount(cmd, cmd_buffer, offset,
                              count_buffer, count_offset,
                              max_draw_count, stride)
```

### Fallback

لو `caps.draw_indirect_count == 0` → المسار الحالي (per-group
`vkCmdDrawIndexedIndirect` loop). نفس الصورة.

---

## §3 — Multi-Threaded Command Recording (R3)

### الفكرة

تسجيل أوامر الرسم لمشهد ضخم على thread واحد بيصير عنق CPU. الحل:
**secondary command buffers** — نقسّم الـ batches على K مجموعات، كل thread
(من الـ std thread pool) يسجّل secondary command buffer لمجموعته بالتوازي،
ثم الـ primary ينفّذها بـ `vkCmdExecuteCommands`.

### قيد Vulkan الحاسم (thread safety)

- `VkCommandPool` **مش thread-safe**: لا يجوز تسجيل أمرين من نفس الـ pool
  بالتوازي. الحل: **command pool منفصل لكل worker thread** (نخصّص
  `num_workers + 1` pools مرة وحدة).
- الموارد المقروءة أثناء التسجيل (mesh registry, bindless set) read-only
  أثناء الـ frame → آمنة.
- الـ secondary يُسجَّل مع `VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE`
  + inheritance info (render pass / dynamic rendering formats).

### البنية

```dolet
# في RenderPass أو GpuRendererCore:
thread_cmd_pools:  i64 = 0   # VkCommandPool[num_workers+1]، pool لكل thread
sec_cmd_buffers:   i64 = 0   # VkCommandBuffer[][] أو ring لكل thread/frame
mt_record_enabled: i32 = 0   # flag + (worker_count > 0) + (batches > threshold)
```

### التدفّق

```
parallel_for(num_batches, fun(b):
    tid = current worker slot
    sec = sec_cmd_buffers[tid][...]
    vkBeginCommandBuffer(sec, RENDER_PASS_CONTINUE + inheritance)
    record batch b draws into sec
    vkEndCommandBuffer(sec)
)
# على الـ primary، داخل الـ render pass:
vkCmdExecuteCommands(primary, K, all_secondaries)
```

ملاحظة: كل worker يكتب على secondary buffers **خاصة بـ tid تبعه** (ما في
slot مشترك بين threads) — Pure_Mapping، race-free. هاد بالضبط نمط الـ
parallel transform refresh اللي اشتغل.

### Fallback

لو `worker_count == 0` OR `batches < threshold` OR flag off → تسجيل على
الـ primary مباشرة (المسار الحالي). نفس الصورة.

---

## §4 — GPU-Side Instance Transforms (R4)

### الفكرة

بدل بناء `Mat4.trs` لكل كائن متحرك على الـ CPU، نرفع البارامترات الخام
(pos/rot/scale = 9 floats أو أقل) لـ GPU buffer، و compute shader يبني الـ
model matrix مباشرة في الـ candidate buffer قبل الـ cull pass.

### البنية

- buffer `instance_params` (host-mapped): 9 floats لكل instance متحرك.
- compute shader `transform.comp`: invocation لكل instance، يقرأ
  params → يبني TRS → يكتب الـ 64-byte model في الـ candidate record.
- يُدمج كـ pass قبل الـ cull (أو يُدمج بالـ cull shader نفسه).

### Dispatch & fallback

- API: `Engine.set_instance_motion(mesh_id, px,py,pz, rx,ry,rz, sx,sy,sz)`
  — يكتب params، يعلّم الـ buffer dirty.
- لو الـ GPU transforms معطّل OR المطوّر استعمل `set_model_matrix_raw` →
  المسار الحالي (CPU TRS / transform refresh).

### ملاحظة على الأولوية

هاد المسار يفيد بس لما الـ CPU transform هو العنق. في المشاهد GPU-bound
مكسبه ضئيل (موثّق في الـ rollout). بيُنفّذ بعد R1–R3.

---

## §5 — Dynamic Rendering (R6, اختياري)

استبدال `vkCmdBeginRenderPass`/framebuffers بـ
`vkCmdBeginRendering`/`vkCmdEndRendering` مع
`VkRenderingAttachmentInfo`. تبسيط كود (مش أداء). خلف
`caps.dynamic_rendering`، fallback للـ render-pass الكلاسيكي. أقل أولوية.

---

## §6 — Verification Strategy (R7)

كل مرحلة لازم تمرّ بـ:

1. **بناء خفيف**: `getDiagnostics` على الملفات المعدّلة (صفر ذاكرة)، ثم
   بناء الـ engine كـ background process (مش `executePwsh` ثقيل، عشان ما
   نعلّق الجهاز).
2. **bootstrap byte-stable**: لو تغيّر شي بالكمبايلر (مش متوقّع — كله
   engine). غالباً غير لازم.
3. **`run_tests.bat` (المجموعة الخفيفة فقط، بدون frog tests)**: 0 FAIL.
4. **تحقق بصري من المستخدم**: المستخدم يشغّل اللعبة، يقارن الصورة + الـ
   FPS قبل/بعد، ويأكّد إنه لا regression. **ما ننتقل للمرحلة التالية إلا
   بعد هالتأكيد.**
5. **GPU validation layers** (لو متاح): تشغيل بـ validation مرة للتأكد من
   صفر errors على المسار الحديث.

### Correctness anchor

الـ classic path يبقى المرجع. أي مسار حديث لازم ينتج **نفس الصورة**. الـ
flag يسمح بالتبديل المباشر بين الاثنين للمقارنة على نفس المشهد.

---

## §7 — Rollout Plan (R8) — الترتيب الآمن

من الأعلى قيمة/الأقل خطر للأعلى خطر:

| المرحلة | المحتوى | الخطر البصري | المتطلب المسبق |
|---|---|---|---|
| **0** | Capability detection (`GpuCaps`) | صفر (ما يلمس الرسم) | — |
| **1** | Bindless texture table | متوسط | المرحلة 0 |
| **2** | Indirect-count draw | متوسط | المرحلة 1 |
| **3** | Multi-threaded command recording | عالٍ (sync) | المرحلة 0 |
| **4** | GPU instance transforms | متوسط | المرحلة 0 |
| **5** | Dynamic rendering (اختياري) | منخفض | المرحلة 0 |

كل مرحلة flag-gated، fallback آمن، تحقق بصري قبل المتابعة. المرحلة 0
أولاً دايماً (الأساس). بعدها 1 → 2 (متسلسلة، 2 يحتاج 1). 3 و4 مستقلتان
(بعد 0). 5 آخر شي / اختياري.

---

## Data Models (ملخّص)

### GpuCaps (المرحلة 0)
موصوف في §0. 6 حقول i32، يُملأ مرة عند الإقلاع.

### Bindless instance record (المرحلة 1)
الـ 96-byte output instance الحالي [model 64 | material 16 | uv 16].
الـ `texture_index` يُحزَّم في قناة من الـ material vec4 (مثلاً
`material.z` كـ float-encoded int)، فلا يتغيّر حجم الـ record.

### Per-thread command pools (المرحلة 3)
`VkCommandPool[num_workers+1]`، يُنشأ مرة عند init الـ render، يُعاد
استخدامه (reset) كل frame.

### Instance params (المرحلة 4)
`f32[9 * num_instances]` host-mapped: pos(3) rot(3) scale(3).

---

## Error Handling

- كل feature حديث: لو الـ Vulkan call رجّع خطأ عند الـ init → الـ flag
  المقابل = 0 → fallback للمسار الكلاسيكي. ما في panic.
- `VK_ERROR_DEVICE_LOST` أثناء الرسم: خارج نطاق هاد الـ spec (recovery
  منفصل)، بس المسارات الحديثة ما تزيد احتماله.
- نقص الذاكرة عند إنشاء bindless pool الكبير: fallback للـ classic.

---

## Bootstrap / Build Note

كل التغييرات في `packages/frog/render/` + shaders — **صفر تغيير على
الكمبايلر**. فلا حاجة لـ bootstrap dance. الـ shaders الجديدة تُترجم لـ
SPIR-V وتُضمَّن عبر آلية الـ embed الموجودة (`tools/embed_spirv.mjs`).
البناء = إعادة بناء الـ engine + البرامج اللي تستورده.
