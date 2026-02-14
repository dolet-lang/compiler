# External Modules - Developer Guide

هذا الدليل يشرح كيفية إضافة مكتبات خارجية جديدة لـ Dolet بدون تعديل الـ compiler.

## البنية (Structure)

```
external-modules/
  your-module/
    your-module.dlt    # Dolet bindings
    module.meta        # Metadata file (required for native libraries)
    lib.dll/.so        # Runtime libraries
    lib.lib/.a         # Import/static libraries
```

## إضافة مكتبة جديدة (Adding a New Library)

### 1. إنشاء المجلد

```bash
mkdir external-modules/your-module
```

### 2. كتابة Dolet Bindings (your-module.dlt)

```dolet
extern lib "your-native-lib":
    fun init() -> i32
    fun cleanup()

struct YourModule:
    handle: i64 = 0
    
    fun create() -> YourModule:
        result: YourModule = YourModule()
        return result
```

### 3. إنشاء module.meta

```ini
[libs]
windows = your-lib.lib
linux = libyour-lib.so
macos = libyour-lib.dylib

[dlls]
windows = your-lib.dll
linux = libyour-lib.so.1
macos = libyour-lib.1.dylib
```

### 4. إضافة المكتبات الأصلية

ضع ملفات .lib/.dll في المجلد.

### 5. الاستخدام

```dolet
import your-module

init()
cleanup()
```

**الـ compiler سيقرأ metadata تلقائياً ويربط المكتبات!**

## مميزات:

✅ لا تحتاج تعديل compiler
✅ Multi-platform support
✅ Auto-linking من metadata
✅ DLL/SO copying تلقائي

**أمثلة: glfw/, vulkan/**
