-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | إحداثيّاتٌ يقرؤها التطبيق
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **عطلٌ يمرّ صامتًا**: عمود `geography` يصل عبر PostgREST نصًّا سداسيًّا
-- (EWKB) مثل `0101000020E6100000...`. والتطبيق الذي يقرأ منه `lat` يجد فراغًا
-- فيضع صفرًا — فيصير موقع العميل عند تقاطع خطّ الاستواء وخطّ غرينتش، وتُحسب
-- مسافة التوصيل بآلاف الكيلومترات، ويُرفض الطلب بـ«خارج نطاق الخدمة».
--
-- ولا يظهر ذلك في اختبار SQL (القاعدة تحسب بالنوع الأصليّ صحيحًا)، ولا في
-- محلّل Dart (النوع `dynamic`). يظهر عند أوّل طلب.
--
-- والحلّ عمودان مشتقّان مخزَّنان: `ST_Y` و`ST_X` **ثابتتان** (immutable)
-- فتصلحان لعمودٍ مولَّد، ويُحسبان مرّةً عند الكتابة لا عند كل قراءة.

set search_path = public, extensions;

alter table addresses
  add column lat double precision
    generated always as (st_y(location::geometry)) stored,
  add column lng double precision
    generated always as (st_x(location::geometry)) stored;

alter table branches
  add column lat double precision
    generated always as (st_y(location::geometry)) stored,
  add column lng double precision
    generated always as (st_x(location::geometry)) stored;

comment on column addresses.lat is
  'مشتقّ من location. عمود geography يصل نصًّا سداسيًّا لا رقمًا — والقراءة منه مباشرةً تعطي صفرًا صامتًا.';
