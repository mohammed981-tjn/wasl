-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار التقارير
-- ═══════════════════════════════════════════════════════════════════════════
-- **رقمٌ خاطئ في تقرير أسوأ من غياب التقرير**: يُبنى عليه قرارُ تسعيرٍ أو
-- توظيف، ولا يشتكي منه أحد لأنه لا يبدو خطأً. فما يُختبر هنا هو ما يُستبعَد
-- لا ما يُجمَع: الملغى، والمسترَدّ، والمسوّدة.

\set ON_ERROR_STOP on
begin;

set local search_path = public, extensions;

create or replace function assert_eq(actual anyelement, expected anyelement, label text)
returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception '✗ %: توقّعنا % وجاء %', label, expected, actual;
  end if;
  raise notice '✓ %', label;
end $$;

-- ── تجهيز ────────────────────────────────────────────────────────────────
insert into laundries (id, name_ar, slug)
values ('11111111-1111-1111-1111-111111111111','مغسلة وصل','wasl');
insert into branches (id, laundry_id, name_ar, location)
values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111',
        'المركز', st_point(39.6142,24.4672)::geography);
insert into auth.users (id, phone) values ('a0000000-0000-0000-0000-000000000001','+966500000001');
insert into profiles (id, phone) values ('a0000000-0000-0000-0000-000000000001','+966500000001');

insert into service_categories (id, laundry_id, name_ar)
values ('cc000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','ملابس');
insert into services (id, laundry_id, category_id, name_ar, unit, base_price) values
  ('55000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
   'cc000000-0000-0000-0000-000000000001','ثوب','piece',8),
  ('55000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',
   'cc000000-0000-0000-0000-000000000001','بطانية','piece',25);

-- أربعة طلبات: اثنان محتسبان، وملغى، ومسترَدّ.
insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, delivery_fee, discount_amount, total, created_at) values
  ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
   'delivered', 100, 15, 10, 105, now() - interval '1 day'),
  ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
   'washing',   200, 15,  0, 215, now()),
  ('0dd00000-0000-0000-0000-00000000000c','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
   'cancelled', 500, 15,  0, 515, now()),
  ('0dd00000-0000-0000-0000-00000000000d','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
   'refunded',  300, 15,  0, 315, now()),
  -- ومسوّدةٌ لم تُرسل: لا تُحتسب في شيء.
  ('0dd00000-0000-0000-0000-00000000000e','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
   'draft',     900, 15,  0, 915, now());

insert into order_items (order_id, service_id, service_name_ar, unit, quantity, unit_price, line_total) values
  ('0dd00000-0000-0000-0000-00000000000a','55000000-0000-0000-0000-000000000001','ثوب','piece',5,8,40),
  ('0dd00000-0000-0000-0000-00000000000a','55000000-0000-0000-0000-000000000002','بطانية','piece',2,25,50),
  ('0dd00000-0000-0000-0000-00000000000b','55000000-0000-0000-0000-000000000001','ثوب','piece',10,8,80),
  ('0dd00000-0000-0000-0000-00000000000c','55000000-0000-0000-0000-000000000001','ثوب','piece',60,8,480);

-- ═══ ١) الملخّص يستبعد ما يجب استبعاده ═══════════════════════════════════
select assert_eq(
  (select orders_count from report_summary('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date)),
  4, 'الملخّص: أربعة طلبات — والمسوّدة لا تُعدّ');

select assert_eq(
  (select revenue from report_summary('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date)),
  320::numeric, 'الملخّص: الإيراد ١٠٥+٢١٥ — لا الملغى ولا المسترَدّ');

select assert_eq(
  (select avg_order_value from report_summary('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date)),
  160::numeric, 'الملخّص: متوسّط الطلب ٣٢٠÷٢');

select assert_eq(
  (select cancelled_count from report_summary('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date)),
  1, 'الملخّص: ملغًى واحد');

select assert_eq(
  (select delivery_revenue from report_summary('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date)),
  30::numeric, 'الملخّص: إيراد التوصيل ١٥+١٥');

select assert_eq(
  (select discounts_given from report_summary('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date)),
  10::numeric, 'الملخّص: الخصومات الممنوحة');

-- القطع المعالَجة: (٥ ثياب + ٢ بطانية) + ١٠ ثياب = ١٧ — ولا تشمل الملغى (٦٠)
select assert_eq(
  (select pieces_processed from report_summary('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date)),
  17::numeric, 'الملخّص: القطع المعالَجة لا تشمل قطع الملغى');

-- ═══ ٢) السلسلة اليومية كاملةٌ بلا فجوات ═════════════════════════════════
select assert_eq(
  (select count(*)::int from report_daily('22222222-2222-2222-2222-222222222222',
     current_date - 6, current_date)),
  7, 'اليوميّ: سبعة صفوف لسبعة أيام — واليوم الفارغ يظهر صفرًا لا يُحذف');

select assert_eq(
  (select revenue from report_daily('22222222-2222-2222-2222-222222222222',
     current_date - 6, current_date) where day = current_date - 3),
  0::numeric, 'اليوميّ: يومٌ بلا طلبات = صفر لا فجوة');

select assert_eq(
  (select revenue from report_daily('22222222-2222-2222-2222-222222222222',
     current_date - 6, current_date) where day = current_date - 1),
  105::numeric, 'اليوميّ: إيراد الأمس');

-- ═══ ٣) مزيج الخدمات ═════════════════════════════════════════════════════
select assert_eq(
  (select revenue from report_service_mix('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) where service_name = 'ثوب'),
  120::numeric, 'المزيج: الثوب ٤٠+٨٠ — لا ٤٨٠ من الملغى');

select assert_eq(
  (select orders_count from report_service_mix('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) where service_name = 'ثوب'),
  2, 'المزيج: الثوب في طلبين');

-- الترتيب بالإيراد تنازليًّا: الثوب (١٢٠) قبل البطانية (٥٠)
select assert_eq(
  (select service_name from report_service_mix('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) limit 1),
  'ثوب', 'المزيج: مرتَّبٌ بالإيراد تنازليًّا');

-- الخدمة المحذوفة من الكتالوج تبقى في التقرير: التجميع على الاسم المنسوخ
delete from services where id = '55000000-0000-0000-0000-000000000002';
select assert_eq(
  (select revenue from report_service_mix('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) where service_name = 'بطانية'),
  50::numeric, 'المزيج: خدمةٌ حُذفت من الكتالوج تبقى في تقرير فاتورتها');

-- ═══ ٤) أزمنة المراحل ════════════════════════════════════════════════════
-- سجلٌّ مصطنع: فرزٌ ساعة، وغسيلٌ ساعتان، وفي طلبٍ ثانٍ غسيلٌ عشر ساعات.
insert into order_events (order_id, from_status, to_status, created_at) values
  ('0dd00000-0000-0000-0000-00000000000a','at_laundry','sorting', now() - interval '20 hours'),
  ('0dd00000-0000-0000-0000-00000000000a','sorting','washing',    now() - interval '19 hours'),
  ('0dd00000-0000-0000-0000-00000000000a','washing','drying',     now() - interval '17 hours'),
  ('0dd00000-0000-0000-0000-00000000000b','at_laundry','sorting', now() - interval '15 hours'),
  ('0dd00000-0000-0000-0000-00000000000b','sorting','washing',    now() - interval '14 hours'),
  ('0dd00000-0000-0000-0000-00000000000b','washing','drying',     now() - interval '4 hours');

select assert_eq(
  (select samples from report_stage_durations('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) where stage = 'washing'),
  2, 'المراحل: عيّنتان للغسيل');

select assert_eq(
  (select avg_hours from report_stage_durations('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) where stage = 'washing'),
  6::numeric, 'المراحل: متوسّط الغسيل (٢+١٠)÷٢ = ٦');

select assert_eq(
  (select max_hours from report_stage_durations('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) where stage = 'washing'),
  10::numeric, 'المراحل: أقصى زمن غسيل ١٠ ساعات');

select assert_eq(
  (select avg_hours from report_stage_durations('22222222-2222-2222-2222-222222222222',
     current_date - 7, current_date) where stage = 'sorting'),
  1::numeric, 'المراحل: الفرز ساعة');

-- المرحلة الجارية (drying بلا انتقالٍ بعدها) لا تُحتسب: زمنُها لم ينتهِ.
select assert_eq(
  (select count(*)::int from report_stage_durations(
     '22222222-2222-2222-2222-222222222222', current_date - 7, current_date)
   where stage = 'drying'),
  0, 'المراحل: الجارية لا تُحتسب — زمنُها لم ينتهِ بعد');

-- ═══ ٥) فرعٌ آخر لا تتسرّب أرقامه ════════════════════════════════════════
insert into branches (id, laundry_id, name_ar, location)
values ('22222222-2222-2222-2222-333333333333','11111111-1111-1111-1111-111111111111',
        'قباء', st_point(39.61,24.44)::geography);

select assert_eq(
  (select orders_count from report_summary('22222222-2222-2222-2222-333333333333',
     current_date - 7, current_date)),
  0, 'العزل: فرعٌ بلا طلبات يعطي صفرًا لا أرقام غيره');

rollback;
