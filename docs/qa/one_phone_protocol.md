# بروتوكول جهاز واحد · Allo Service

> **الفكرة:** ما تحتاجش جهازين. **التليفون = المحترف (A)**، و**الـPC (Supabase Dashboard) = الأدمن (B)**.
> كل خطوة كانت "من الجهاز الآخر" تولّي **UPDATE في SQL Editor**.
>
> **المدة:** 20-25 دقيقة · **يلزمك:** تليفون + PC + متصفح.

---

## 1. ابنِ وثبّت نسخة جديدة

⚠️ **الـAPK القديم (19/10) ما فيهش الإصلاحات** — لازم build جديد.

```bash
cd C:\Users\feres\Documents\allo_service_pro
flutter build apk --release --dart-define-from-file=.env
```

- **المخرج:** `build/app/outputs/flutter-apk/app-release.apk`
- **التثبيت:** `adb install -r build\app\outputs\flutter-apk\app-release.apk`
  (أو انسخ الملف للتليفون وثبّته يدويًا)

⚠️ **بلا `--dart-define-from-file=.env`** التطبيق يدخل **LOCAL-ONLY** (ما يتصلش بـSupabase) ⇒ الاختبار كله بلا معنى.

**قبل ما تبدا:** إعدادات التليفون ← التطبيق ← **مسح البيانات** (باش تبدأ من صفر).

---

## 2. جهّز Supabase

افتح **SQL Editor** في مشروعك. خلي هذي الاستعلامات جاهزة:

**أ) عرّف المحترف (خذ الـAUTH_UID):**
```sql
select u.id as auth_uid, u.email, p.status, p.is_verified, p.rejection_reason
  from auth.users u
  left join public.professionals p on p.id = u.id
 order by u.created_at desc
 limit 10;
```

**ب) موافقة:**
```sql
update public.professionals
   set status = 'approved', is_verified = true,
       approved_at = now(), rejection_reason = null
 where id = '<AUTH_UID>';
```

**ج) رفض:**
```sql
update public.professionals
   set status = 'rejected', is_verified = false,
       approved_at = null, rejection_reason = 'Photo illisible'
 where id = '<AUTH_UID>';
```

**د) تحقّق:**
```sql
select id, status, is_verified, rejection_reason, approved_at
  from public.professionals
 where id = '<AUTH_UID>';
```

> ⚠️ هذي UPDATE مباشرة (SQL Editor يتجاوز RLS). **للاختبار فقط** — الإنتاج يمرّ عبر RPC الأدمن.
> إذا طلع خطأ على عمود ناقص (`approved_at` / `rejection_reason`)، وقّف وقوللي.

---

## 3. السيناريوهات

> لكل سيناريو سجّل: ✅/❌ + صورة شاشة.

| # | على التليفون (A) | على الـPC (B) | المتوقّع |
|---|---|---|---|
| **S1** | سجّل محترف جديد، ارفع الوثيقة، **Force stop** (ماشي غير background) | موافقة (استعلام ب) | افتح التطبيق ← **Dashboard مباشرة**. ممنوع «في انتظار التحقق» |
| **S2** | ابقَ واقف في «في انتظار التحقق» والـتطبيق مفتوح | موافقة (استعلام ب) | خلال **≤ 10 ثواني** تتبدّل الشاشة للـDashboard **وحدها** (بلا لمس) |
| **S3** | — | رفض بسباب (استعلام ج) | افتح التطبيق ← «Compte refusé» + **السبب** + زر إعادة الرفع |
| **S4** | «Re-téléverser la preuve» ← **«Choisir dans la galerie»** ← صورة ← أرسل | تحقّق (استعلام د) | الشاشة ترجع «في انتظار التحقق» · `status = 'pending'` |
| **S5** | **وضع الطيران** | موافقة (استعلام ب) | أطفئ الطيران ← «جارٍ التحقق» ثم **Dashboard**. **أبداً** `pending` |
| **S6** | أغلق التطبيق وافتحه **3 مرات** | — | Dashboard في كل مرة، بلا وميض «pending» |
| **S7** | من الـDashboard: **طيران 30s** ← رجّع | — | ما يروحش لـLogin، ما يعلّقش؛ يرجع ويتزامن |
| **S8** | خروج (Logout) ← دخول نفس الحساب | — | Dashboard + **Disponible** كما كان |
| **S9** | *(اختياري)* Supabase ← Auth ← إعدادات المشروع ← خفّض **JWT expiry** لـ60s ← انتظر دقيقتين ← أغلق/افتح التطبيق | — | **شاشة الدخول** — لا دوّامة ولا «pending» |
| **S10** | خروج ← سجّل محترف **آخر** غير موافق | — | شاشة انتظار **هذا** الحساب — ولا أثر لحالة الأول |

### S10 — تحقّق إضافي
```sql
select u.email, p.status, p.is_verified
  from auth.users u
  left join public.professionals p on p.id = u.id
 where u.email in ('<compte1@…>', '<compte2@…>');
```
كل حساب بحالته الخاصة — لا تسريب.

---

## 4. ممنوعات (إذا شفت واحدة منهم، السيناريو فاشل)

1. ❌ حساب `approved` يعرض «في انتظار التحقق» — ولو للحظة في S1/S5/S6.
2. ❌ دوّامة (spinner) بلا زر خروج ولا AppBar.
3. ❌ تطبيق يطلب Login مع إنّ الجلسة صالحة.
4. ❌ بطاقة مزدوجة لنفس المحترف في لوحة الأدمن.
5. ❌ الموافقة ما توصلش وحدها في S2 (أكثر من 15 ثانية).

---

## 5. النتيجة

### سجل التنفيذ

| التاريخ | البيئة | النتيجة |
|---|---|---|
| 2026-11-07 | تليفون واحد + Supabase Dashboard (SQL) · APK release مبني بـ`--dart-define-from-file=.env` | **S1–S10 ✅ كلهم نجحوا** |

| # | النتيجة |
|---|---|
| S1 · موافقة والتطبيق مسكّر ← إعادة تشغيل | ✅ Dashboard مباشرة |
| S2 · موافقة والتطبيق مفتوح على شاشة الانتظار | ✅ تبدّلت وحدها في ≤10 ثواني |
| S3 · رفض | ✅ «Compte refusé» + السبب |
| S4 · إعادة رفع عبر **المعرض** | ✅ رجع «pending» (مؤكَّد بـSQL) |
| S5 · طيران + موافقة + عودة | ✅ Dashboard، بلا `pending` كاذب |
| S6 · إعادة تشغيل ×3 | ✅ Dashboard كل مرة |
| S7 · انقطاع/عودة | ✅ ما راحش لـLogin، ما علّقش |
| S8 · خروج ودخول | ✅ Dashboard + Disponible |
| S10 · حساب ثاني | ✅ شاشة انتظار الحساب الجديد، بلا تسريب |

### ملاحظتان من التنفيذ

1. **الموافقة بـ`UPDATE` مباشر تتخطّى منح 150 توكن** — لأن المنح يصير في `AdminStore.approvePro`
   (والـRPC `admin_provision_professional`). للاختبار: `update … set tokens = 150`. في الإنتاج
   الموافقة من لوحة الأدمن تعطي التوكنز أوتوماتيك.
2. **«معتمد ← pending» ما فيهاش تحديث فوري** وأنت واقف في الـDashboard: ما فماش قناة realtime
   على `professionals`. الحالة تُقرأ عند الإقلاع / الـresume (بعد TTL 5 دقائق) / تغيير الشبكة.
   هذا هو البند **R8** (مؤجَّل، يحتاج `alter publication supabase_realtime add table public.professionals`).

### معايير الفشل

- ❌ أي فشل ⇒ سجّل: **رقم السيناريو** + **الشاشة الظاهرة** + **نتيجة استعلام التحقّق** + صورة.
  هذا يكفي لتحديد الطبقة: جلسة / سلطة السيرفر / تنقّل.
