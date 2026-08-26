# النشر إلى الإنتاج

> آخر تحديث: ٢٠٢٦-٠٨-٢٦

هذا دليلُ تشغيلٍ لا شرحُ معمار. المعمارُ في [`roadmap-ar.md`](roadmap-ar.md)،
والمؤجَّلُ على المالك في [`pending-ar.md`](pending-ar.md).

---

## ١) ما قبل أوّل نشر — قائمةٌ تُمشى بالترتيب

### أ) القاعدة

| الفحص | كيف يُتحقَّق |
|---|---|
| كل المهاجرات مطبَّقة | `supabase/tests/apply.sh` محلّيًّا، ثم مقارنةُ القائمة بالمشروع الحيّ |
| كل الاختبارات تمرّ | `supabase/tests/run.sh` — ٢٩١ اختبارًا |
| RLS على كل جدول، ولكل جدولٍ سياسة | يفحصه `04_schema_hygiene_test.sql` |
| الزائر يقرأ ولا يكتب | يفحصه الاختبار نفسه — وقد كان مفتوحًا حتى المرحلة ١٠ |
| نسخٌ احتياطيّ | Supabase ← Database ← Backups. **الخطة المجانية: نسخةٌ يوميّة بلا PITR** |

**النسخُ الاحتياطيّ ليس اختياريًّا قبل أوّل ريال.** الخطةُ المجانية تحفظ نسخةً
يوميّةً فقط؛ ومن يريد استعادةً إلى لحظةٍ بعينها (PITR) يحتاج خطّةً مدفوعة.
واعرف الآن أيَّهما عندك لا يوم تحتاجه.

### ب) المصادقة (Supabase ← Authentication)

| الإعداد | القيمة | لماذا |
|---|---|---|
| Providers ← Phone | مزوّد SMS | الجوال هويّةُ العميل في السوق السعودي |
| Leaked password protection | **مفعَّل** | يمنع كلمةً سُرِّبت في اختراقٍ سابق |
| OTP expiry | ≤ ١٥ دقيقة | رمزٌ يعيش ساعةً هو رمزٌ يُخمَّن ساعة |
| Site URL / Redirect URLs | نطاقُك | بلا ضبطها تُعاد رسائل التحقّق إلى `localhost` |

### ج) دوالّ Edge (Supabase ← Edge Functions ← Secrets)

```
MOYASAR_SECRET_KEY      = sk_…
MOYASAR_WEBHOOK_SECRET  = رمزٌ تختاره
PAYMENT_CALLBACK_URL    = رابط العودة
```

والدوالّ الثلاث منشورة: `payments-start` و`payments-webhook` و`payments-refund`.

### د) الحزم

| الفحص | الحالة |
|---|---|
| معرّف الحزمة | `sa.wasl.app` (+ `.driver` / `.laundry` / `.admin`) |
| توقيع release | من `android/key.properties` — **وليس مفتاح التطوير** |
| أذونات iOS | أوصافُ الكاميرا والموقع موجودة — **بدونها ينهار التطبيق** |
| `<queries>` في أندرويد | موجود — بدونه يفشل زرّا الاتصال والملاحة صامتين |

---

## ٢) البناء

### الويب (أربع نكهات)

```bash
for f in customer driver laundry admin; do
  flutter build web --release --no-web-resources-cdn \
    --dart-define=WASL_FLAVOR=$f -o build/web-$f
done
```

**`--no-web-resources-cdn` ليس خيارًا**: بدونه تُجلب CanvasKit من `gstatic.com`،
وأيّ حجبٍ لها يعطي **صفحةً بيضاء بلا رسالة**.

وكلُّ نكهةٍ تُنشر على نطاقٍ فرعيّ:

```
app.wasl.sa      → build/web-customer
driver.wasl.sa   → build/web-driver
laundry.wasl.sa  → build/web-laundry
admin.wasl.sa    → build/web-admin
```

### أندرويد

```bash
# أنشئ المفتاح مرّةً واحدة، واحفظ نسخةً احتياطية منه في مكانٍ آمن
keytool -genkey -v -keystore ~/wasl-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias wasl

cp android/key.properties.example android/key.properties   # ثم املأه

for f in customer driver laundry admin; do
  flutter build appbundle --release --flavor $f \
    -t lib/main.dart --dart-define=WASL_FLAVOR=$f
done
```

**النكهة تُمرَّر مرّتين ولا غنى عن إحداهما**: `--flavor` يفصل الحزم في
أندرويد، و`--dart-define` يفصل الشاشات في Dart. ونسيانُ الثانية يبني **تطبيق
العميل** بمعرّف حزمة السائق — ويُنشر كذلك.

### iOS

يحتاج جهاز macOS وحساب مطوّر. والنكهات تُضبط بـSchemes في Xcode.

---

## ٣) بعد النشر — ما يُراقَب

| ماذا | أين | العلامة السيّئة |
|---|---|---|
| أخطاء القاعدة | Supabase ← Logs ← Postgres | تكرارُ `insufficient_privilege` = سياسةٌ أضيق ممّا يجب |
| دوالّ Edge | Supabase ← Edge Functions ← Logs | `401` متكرّر على `payments-webhook` = رمزُ الإشعار غير مطابق |
| إشعاراتٌ عالقة | `select count(*) from notifications where status='queued'` | رقمٌ يكبر = لا عاملَ يرسل |
| دفعاتٌ معلَّقة | `select count(*) from payments where status='pending' and created_at < now() - interval '1 hour'` | عميلٌ فتح الدفع ولم يُكمل، أو إشعارٌ لم يصل |
| تقييماتٌ منخفضة | لوحة الإدارة ← التقارير | عددُ ما دون الحدّ لا المتوسّط |

### استعلامُ صحّةٍ سريع

```sql
select
  (select count(*) from orders where status not in ('delivered','cancelled','refunded')) as طلبات_مفتوحة,
  (select count(*) from orders where promised_ready_at < now()
     and status not in ('ready','out_for_delivery','delivered','cancelled','refunded')) as متأخّرة,
  (select count(*) from notifications where status='queued') as إشعارات_عالقة,
  (select count(*) from payments where status='pending'
     and created_at < now() - interval '1 hour') as دفعات_معلّقة,
  (select count(*) from driver_locations where is_online and updated_at > now() - interval '15 minutes') as سائقون_متاحون;
```

---

## ٤) ما يجب ألّا يُنسى

- **مفتاحُ التوقيع**: من يفقده لا يستطيع تحديث تطبيقه على المتجر أبدًا.
  احفظ نسخةً خارج جهازك.
- **`service_role` key**: يتجاوز RLS كلَّها. مكانُه أسرارُ الخادم وحدها — لا
  في حزمة، ولا في مستودع، ولا في رسالة.
- **المفتاح المنشور** (`publishable`/`anon`) في `lib/config/supabase_config.dart`
  **ليس سرًّا**: هو مصمَّمٌ ليكون في كل حزمة، والحارسُ عليه RLS.
- **قبل كل نشر**: `flutter analyze` و`flutter test` و`supabase/tests/run.sh`.
