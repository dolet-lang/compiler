# Requirements — GPU-Driven Renderer (Frog Engine, state-of-the-art Vulkan)

## مقدمة

الهدف: تحويل الـ Frog renderer من معمارية Vulkan الكلاسيكية (render-pass +
per-group descriptor binds + per-group indirect draws) إلى معمارية
**GPU-driven حديثة** على مستوى محركات الألعاب الكبيرة (Unreal 5 / modern
AAA): **bindless resources**, **GPU-decided draw counts**
(`vkCmdDrawIndexedIndirectCount`), **multi-threaded command recording**,
و**GPU-side instance transforms** — بحيث المحرك يخدم مشاهد متنوعة بعدد
ضخم من الـ entities (مئات الآلاف → ملايين) بأعلى أداء ممكن من Vulkan.

المحرك حالياً **شغّال** (600–1800 FPS فارغ، GPU-driven culling + indirect
draw، CPU thread pool 5.8–9x). هاد التحوّل بيبني فوق الموجود، **ما يكسره**:
كل مرحلة تحافظ على نفس المخرجات البصرية، مع fallback آمن لو فشل feature.

### مبدأ حاكم: الصحّة البصرية قبل السرعة، خطوة بخطوة

التحوّل خطر بصرياً (renderer على محرك حي). القرار الحاكم: **كل مرحلة
صغيرة، قابلة للبناء والتشغيل والتحقق البصري من المستخدم، ومعزولة خلف flag
يسمح بالرجوع للمسار القديم.** ما في "إعادة كتابة دفعة وحدة".

### قيد الأجهزة (Hardware tiers)

الـ features الحديثة (descriptor indexing, draw-indirect-count, dynamic
rendering) متوفرة على Vulkan 1.2+ (NVIDIA/AMD/Intel الحديثة). لكن لازم:
- **كشف القدرات وقت التشغيل** (query features/limits)
- **fallback للمسار الكلاسيكي** لو الـ feature غير مدعوم (graceful degradation)
- المحرك **ما ينهار** على أي جهاز — أسوأ حالة = المسار القديم الأبطأ-قليلاً

---

## المصطلحات (Glossary)

- **Bindless / Descriptor Indexing**: descriptor array واحد ضخم لكل
  الموارد (textures/buffers)؛ الـ shader يـ index فيه بـ ID بدل bind
  منفصل لكل draw.
- **Draw-Indirect-Count**: الـ GPU يكتب **عدد** الـ draw commands في
  buffer، والـ CPU يصدر `vkCmdDrawIndexedIndirectCount` مرة وحدة.
- **Secondary Command Buffer**: command buffer ثانوي يُسجَّل بالتوازي على
  thread منفصل ثم يُنفَّذ ضمن الـ primary.
- **Material/Draw batch**: مجموعة instances تتشارك pipeline + vertex
  format، تُرسم بأمر واحد.
- **Capability tier**: مستوى قدرات الجهاز المكتشَف (modern / classic).

---

## Requirements

### Requirement 1 — Bindless resource model

**User Story:** كمطوّر، بدي أرسم مشهد فيه آلاف الـ materials/textures
المختلفة بأقل عدد من descriptor binds، عشان عدد ضخم من الـ entities
المتنوعة ما يخنق الـ CPU بالـ state changes.

#### Acceptance Criteria
1. WHEN المحرك يقلع على جهاز يدعم `shaderSampledImageArrayNonUniformIndexing`
   + `descriptorBindingPartiallyBound` THEN المحرك SHALL ينشئ descriptor
   set واحد كبير (bindless table) يحتوي كل الـ textures المسجّلة.
2. WHEN texture جديدة تُسجَّل THEN المحرك SHALL يكتب الـ image view في
   فتحة (slot) ضمن الـ bindless table ويرجّع الـ slot index، بدون إنشاء
   descriptor set منفصل لكل texture.
3. WHEN الـ shader يرسم instance THEN SHALL يقرأ texture index من بيانات
   الـ instance ويـ sample من الـ bindless array (`nonuniformEXT`).
4. WHEN الجهاز لا يدعم descriptor indexing THEN المحرك SHALL يرجع للمسار
   الكلاسيكي (per-mesh descriptor set) بدون انهيار، وينتج نفس الصورة.
5. الـ visible set والصورة الناتجة عبر المسار bindless SHALL تكون مطابقة
   بصرياً للمسار الكلاسيكي على نفس المشهد والكاميرا.

### Requirement 2 — GPU-decided draw count (indirect-count)

**User Story:** كمطوّر، بدي الـ GPU يقرّر كم وأي شي يُرسم، عشان CPU ما
يلف على آلاف المجموعات كل frame.

#### Acceptance Criteria
1. WHEN الجهاز يدعم `drawIndirectCount` (VK 1.2 أو
   `VK_KHR_draw_indirect_count`) THEN المحرك SHALL يستعمل
   `vkCmdDrawIndexedIndirectCount` لإصدار كل الـ draws لـ batch بأمر واحد،
   حيث الـ count يُقرأ من GPU buffer كتبه الـ cull/compaction pass.
2. WHEN الـ compute cull pass يخلص THEN عدد الـ draw commands المُولّدة
   SHALL يُكتب في count buffer على الـ GPU، بدون round-trip للـ CPU.
3. WHEN الجهاز لا يدعم indirect-count THEN المحرك SHALL يرجع للمسار
   الحالي (per-group `vkCmdDrawIndexedIndirect`) بدون انهيار.
4. عدد الـ draw calls المُصدَرة من الـ CPU لكل frame SHALL لا يتناسب
   طردياً مع عدد المجموعات عندما الـ indirect-count مفعّل (ثابت/لوغاريتمي
   بدل خطّي).
5. الصورة الناتجة SHALL تطابق المسار القديم بصرياً.

### Requirement 3 — Multi-threaded command recording

**User Story:** كمطوّر بمشهد ضخم، بدي تسجيل أوامر الرسم يتوزّع على كل
الـ cores، عشان تسجيل الـ command buffer ما يصير عنق CPU.

#### Acceptance Criteria
1. WHEN عدد الـ draw batches يتجاوز عتبة قابلة للضبط THEN المحرك SHALL
   يسجّل الـ batches على **secondary command buffers** متعددة بالتوازي
   عبر الـ std thread pool، ثم ينفّذها ضمن الـ primary.
2. WHEN التسجيل المتوازي مفعّل THEN كل secondary command buffer SHALL
   يُسجَّل من thread واحد فقط (Vulkan: pool واحد لكل thread)، بلا data race.
3. WHEN عدد الـ batches تحت العتبة OR الـ thread pool serial THEN المحرك
   SHALL يسجّل على الـ primary مباشرة (مسار واحد، نفس النتيجة).
4. الصورة الناتجة من المسار المتوازي SHALL تطابق المسار المتسلسل بصرياً.
5. الـ frame SHALL لا يحتوي data race على Vulkan objects (كل thread له
   command pool خاص؛ الموارد المشتركة read-only أثناء التسجيل).

### Requirement 4 — GPU-side instance transforms

**User Story:** كمطوّر بآلاف الكائنات المتحركة، بدي حساب مصفوفات التحويل
يصير على الـ GPU، عشان CPU ما يبني TRS لكل كائن كل frame.

#### Acceptance Criteria
1. WHEN كائن يتحرك ببارامترات بسيطة (position/rotation/scale) THEN المحرك
   SHALL يقدر يرفع البارامترات (مش المصفوفة الكاملة) ويبني الـ model
   matrix في compute shader على الـ GPU.
2. WHEN الـ GPU instance transforms مفعّل THEN الـ CPU SHALL لا يستدعي
   `Mat4.trs` لكل كائن متحرك كل frame.
3. WHEN المطوّر يحتاج تحكّم كامل بالمصفوفة THEN المسار اليدوي
   (`set_model_matrix_raw`) SHALL يبقى متاح.
4. النتيجة البصرية (مواضع الكائنات) SHALL تطابق المسار CPU.

### Requirement 5 — Modern Vulkan setup & capability detection

**User Story:** كمحرك، بدي أطلب Vulkan حديث وأكتشف قدرات الجهاز وقت
التشغيل، عشان أفعّل المسارات القوية لما تتوفر وأرجع للكلاسيكي لما لأ.

#### Acceptance Criteria
1. WHEN المحرك يقلع THEN SHALL يطلب أعلى Vulkan API version متاح
   (هدف 1.3، بحد أدنى 1.2)، مع fallback لـ 1.0 إذا لزم.
2. WHEN يُنشئ الـ logical device THEN SHALL يفعّل الـ features المطلوبة
   فقط بعد التأكد من دعمها (descriptor indexing, draw-indirect-count,
   dynamic rendering, ...).
3. WHEN feature غير مدعوم THEN المحرك SHALL يسجّل قدرة الجهاز في
   **capability tier** ويختار المسار المناسب لكل نظام فرعي.
4. WHEN أي feature حديث مفعّل THEN المحرك SHALL يبني وينفّذ بدون validation
   errors على جهاز يدعمه.

### Requirement 6 — Dynamic rendering (تبسيط، اختياري)

**User Story:** كمطوّر للمحرك، بدي ألغي تعقيد render-pass/framebuffer
objects عبر dynamic rendering، عشان الكود أبسط وأمرن للمسارات الحديثة.

#### Acceptance Criteria
1. WHEN الجهاز يدعم `VK_KHR_dynamic_rendering` (VK 1.3) THEN المحرك MAY
   يستعمل `vkCmdBeginRendering`/`vkCmdEndRendering` بدل render-pass objects.
2. WHEN dynamic rendering غير مدعوم THEN المحرك SHALL يستعمل الـ
   render-pass الكلاسيكي الموجود.
3. الصورة الناتجة SHALL تطابق المسار الكلاسيكي.

### Requirement 7 — No visual or stability regression

**User Story:** كمطوّر، بدي كل تحديث معماري ما يكسر الصورة ولا الاستقرار
ولا الأداء الحالي.

#### Acceptance Criteria
1. WHEN أي مرحلة تكتمل THEN كل البرامج/الألعاب الحالية SHALL تبني وتشتغل
   وتنتج نفس الصورة (يتحقق منها المستخدم بصرياً قبل المتابعة).
2. WHEN أي مرحلة تكتمل THEN الـ bootstrap SHALL يبقى byte-stable و
   `run_tests.bat` (المجموعة الخفيفة) SHALL يبقى 0 FAIL.
3. WHEN feature حديث مفعّل على جهاز يدعمه THEN الأداء (FPS) SHALL لا يقل
   عن المسار القديم على نفس المشهد؛ ويُفضّل أن يزيد على المشاهد الكثيفة.
4. WHEN feature حديث غير مدعوم THEN المحرك SHALL يرجع للمسار القديم تلقائياً.

### Requirement 8 — Incremental, flag-gated, verifiable rollout

**User Story:** كفريق، بدي كل تغيير معماري خلف flag وقابل للرجوع، عشان
نطوّر بأمان على محرك حي.

#### Acceptance Criteria
1. كل مسار حديث (bindless, indirect-count, MT recording, GPU transforms)
   SHALL يكون خلف flag/قدرة قابلة للتفعيل والتعطيل وقت التشغيل.
2. WHEN flag حديث معطّل THEN المحرك SHALL يسلك بالضبط كالمسار القديم.
3. كل مرحلة SHALL تُسلَّم كـ خطوة صغيرة قابلة لـ: build → run → تحقق بصري
   من المستخدم → push.
