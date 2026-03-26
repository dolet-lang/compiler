# Dolet Compiler — Known Bugs

> آخر تحديث: 2026-03-26
> الحالة: 38/38 tests pass — هذه الباقات لسا ما انصلحت

---

## 1. Parser: `map<K, V>` comma inside generics

**المشكلة:** الـ parser ما بيدعم الفاصلة `,` جوا الأقواس `<>` للـ generic types.

**مثال يفشل:**
```dolet
scores: map<str, i32> = ["Ali": 100, "Sara": 95]
```

**الخطأ:**
```
Expected token kind 29, got 44 (value=',')
```

**السبب:** في `parser_expr.dlt`، لما الـ parser يقرأ نوع generic بعد `<`، يتوقع `>` مباشرة بعد النوع الأول. ما عنده منطق يقرأ فاصلة ويكمل يقرأ أنواع إضافية.

**الملف:** `parser/parser_expr.dlt` — دالة `parse_type()` أو `parse_generic_type()`

**الحل المقترح:**
```
بعد ما يقرأ أول نوع جوا <>:
- تحقق إذا التوكن التالي هو ','
- إذا نعم: اقرأ التوكن التالي كـ نوع ثاني
- كرر حتى تلاقي '>'
- خزّن كل الأنواع في node list
```

**تست للتحقق:**
```dolet
scores: map<str, i32> = ["Ali": 100, "Sara": 95]
for key in scores:
    print(key)
```

---

## 2. Tokenizer: `>>` nested generics

**المشكلة:** الـ tokenizer يقرأ `>>` كـ token واحد (right-shift operator) بدل ما يقرأهم كـ `>` `>` (إغلاق generic مزدوج).

**مثال يفشل:**
```dolet
matrix: array<array<i32>> = [[1, 2], [3, 4]]
```

**الخطأ:**
```
Expected token kind 29, got 40 (value='>>')
```

**السبب:** في `tokenizer.dlt`، لما يشوف `>>` بيولد token واحد نوعه `TOKEN_RSHIFT`. الحل هو contextual tokenization — لما نكون جوا generic type declaration، لازم `>>` ينقسم لـ `>` `>`.

**الملف:** `tokenizer/tokenizer.dlt` أو `parser/parser_expr.dlt`

**الحل المقترح (خيارين):**
```
خيار 1 — في الـ tokenizer:
  أضف state flag "inside_generic_brackets" 
  لما نكون جوا <> ونشوف >> نولد > > بدل >>

خيار 2 — في الـ parser (أسهل):
  لما الـ parser يتوقع '>' ويلاقي '>>'
  استهلك نص التوكن واعمل lookahead يدوي
```

**تست للتحقق:**
```dolet
matrix: array<array<i32>> = [[1, 2], [3, 4]]
nested: list<list<str>> = [["a", "b"], ["c", "d"]]
```

---

## 3. Codegen: `is null` double bool conversion

**المشكلة:** `if x is null:` يشتغل لحاله، بس لما تحط `is null` و `is not null` على نفس المتغير بالتتالي بيصير خطأ SSA type mismatch.

**مثال يفشل:**
```dolet
name?: str = null
if name is null:
    print("null")
if name is not null:     # <-- هون بيفشل
    print(name)
```

**الخطأ:**
```
use of value '%5' expects different type than prior uses: '!llvm.ptr' vs 'i1'
```

**السبب:** `gen_is_null()` يرجع `i1` (نتيجة `icmp`). بعدين `gen_if_condition()` يحاول يحول النتيجة لـ bool عن طريق مقارنة ثانية مع zero pointer — بس القيمة هي أصلاً `i1` مش `!llvm.ptr`.

**الملفات:**
- `codegen/codegen_expr.dlt` — `gen_is_null()`, `gen_is_not_null()`
- `codegen/codegen_stmt.dlt` — `gen_if_stmt()` — التحقق من نوع الشرط

**الحل المقترح:**
```
في gen_if_stmt أو gen_condition:
- قبل ما تعمل "convert to bool" تحقق إذا الـ expression هو NODE_IS_NULL أو NODE_IS_NOT_NULL
- إذا نعم: النتيجة أصلاً i1 — استخدمها مباشرة بدون تحويل إضافي

أو:
- في infer_expr_type: لما nt == NODE_IS_NULL أو NODE_IS_NOT_NULL ارجع "bool"
- هيك gen_if_stmt يعرف إنه أصلاً bool وما يسوي conversion
```

**تست للتحقق:**
```dolet
x?: str = null
if x is null:
    print("x is null")
if x is not null:
    print(x)
x = "hello"
if x is not null:
    print(x)
```

---

## 4. Codegen: Method call f32 parameter mismatch

**المشكلة:** لما دالة method تتوقع `f32` parameter وتمرر float literal `100.0`، الـ literal دايماً ينولد كـ `f64` والـ method call codegen ما بيعمل implicit cast للـ arguments.

**مثال يفشل:**
```dolet
struct Account:
    balance: f32 = 0.0

impl Account:
    fun deposit(self, amount: f32):
        self.balance = self.balance + amount

a: Account = Account()
a.deposit(100.0)    # <-- f64 بتنبعث بدل f32
```

**الخطأ:**
```
'llvm.call' op operand type mismatch for operand 1: 'f64' != 'f32'
```

**السبب:** في `gen_method_call()` أو `gen_instance_method_call()`، لما يولد الـ arguments ما بيقارن نوع الـ argument مع نوع الـ parameter المتوقع ويعمل implicit_cast.

**الملفات:**
- `codegen/codegen_access.dlt` — `gen_instance_method_call()`
- `codegen/codegen_expr.dlt` — `gen_fun_call()`

**الحل المقترح:**
```
في gen_instance_method_call / gen_fun_call:
- بعد ما تولد كل argument عن طريق gen_expr
- قارن infer_expr_type(arg) مع النوع المتوقع من function signature
- إذا مختلفين: arg = implicit_cast(arg, actual, expected)
```

**تست للتحقق:**
```dolet
struct Temp:
    val: f32 = 0.0

impl Temp:
    fun set(self, v: f32):
        self.val = v

t: Temp = Temp()
t.set(3.14)
print(t.val)
```

---

## 5. Codegen: Variadic function body

**المشكلة:** `fun sum(nums...) -> i32` — الـ variadic parameter codegen يولد `llvm.store` فاضي (بدون value).

**مثال يفشل:**
```dolet
fun sum(nums...) -> i32:
    total: i32 = 0
    return total

result: i32 = sum(1, 2, 3)
print(result)
```

**الخطأ:**
```
llvm.store , %4 : i32, !llvm.ptr
              ^  expected SSA operand
```

**السبب:** في `gen_var_decl` أو `gen_fun_params`، لما يشوف parameter variadic (`...`) بيحاول يولد store بس ما عنده القيمة الصحيحة.

**الملفات:**
- `codegen/codegen_stmt.dlt` — `gen_var_decl()` أو `gen_fun_decl()`
- `codegen/codegen_core.dlt` — function parameter handling

**الحل المقترح:**
```
- تحقق كيف الـ variadic parameters منخزنين في الـ AST
- تأكد إنه gen_fun_params يولد alloca + store صحيح للـ variadic list
- الـ variadic بيتحول لـ list<ptr> داخلياً
```

---

## 6. Codegen: Inherited method calls missing self

**المشكلة:** لما struct يرث من struct ثاني ويحاول يستدعي method من الأب، الـ codegen ما بيمرر `self` argument.

**مثال يفشل:**
```dolet
struct Animal:
    name: str

impl Animal:
    fun speak(self) -> str:
        return self.name

struct Dog extends Animal:
    breed: str

d: Dog = Dog(name="Rex", breed="Husky")
print(d.speak())    # <-- ما بيمرر self
```

**الخطأ:**
```
'llvm.call' number of operands and types do not match: got 0 operands and 1 types
```

**السبب:** في `gen_instance_method_call()`، لما الـ method مش موجودة في الـ struct الحالي بيدور عليها في الأب، بس لما يلاقيها ما بيضيف `self` (pointer للـ instance) كأول argument.

**الملف:** `codegen/codegen_access.dlt` — `gen_instance_method_call()`

**الحل المقترح:**
```
في gen_instance_method_call:
- لما يلاقي الـ method في parent struct
- لازم يضيف self pointer كأول argument
- يعمل call بنفس طريقة الـ methods العادية
```

**تست للتحقق:**
```dolet
struct Base:
    x: i32

impl Base:
    fun get_x(self) -> i32:
        return self.x

struct Child extends Base:
    y: i32

c: Child = Child(x=10, y=20)
print(c.get_x())    # لازم يطبع 10
```

---

## ترتيب الأولوية المقترح

| # | Bug | صعوبة | أولوية |
|---|-----|-------|--------|
| 1 | `is null` double conversion | متوسطة | 🔴 عالية — يأثر على nullable كاملة |
| 2 | Method call f32 cast | سهلة | 🔴 عالية — يأثر على كل method call |
| 3 | Inherited method self | متوسطة | 🟡 متوسطة — يأثر على inheritance |
| 4 | `map<K, V>` comma | سهلة | 🟡 متوسطة — يأثر على maps |
| 5 | `>>` tokenizer | متوسطة | 🟡 متوسطة — يأثر على nested generics |
| 6 | Variadic body | صعبة | 🟢 منخفضة — ميزة متقدمة |
