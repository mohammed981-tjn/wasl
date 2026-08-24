-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار محرّك التوصيل
-- ═══════════════════════════════════════════════════════════════════════════
-- ما يُختبر هنا ليس أن الجداول تُنشأ، بل أن الأرقام صحيحة. رسمُ توصيلٍ خاطئ
-- لا يُسقط التطبيق — يُحصّل مالًا خطأً من كل عميل حتى يشتكي أحدهم.

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

-- ── تجهيز: مغسلة وفرع في المدينة المنورة ─────────────────────────────────
insert into laundries (id, name_ar, slug)
values ('11111111-1111-1111-1111-111111111111', 'مغسلة وصل', 'wasl');

-- المسجد النبوي تقريبًا: 39.6142 شرقًا، 24.4672 شمالًا
insert into branches (id, laundry_id, name_ar, location, daily_capacity_pieces)
values ('22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        'فرع المركز',
        st_point(39.6142, 24.4672)::geography,
        500);

-- ═══ الحالة 1: رسم ثابت، استلام 8 وتسليم 8 ═══════════════════════════════
insert into delivery_settings (branch_id, strategy, flat_pickup_fee, flat_delivery_fee, max_radius_km)
values ('22222222-2222-2222-2222-222222222222', 'flat', 8, 8, 20);

-- نقطة على بُعد ~1 كم
select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6242, 24.4672)::geography, 50, true, true)),
  16::numeric, 'ثابت: استلام + تسليم = 16');

select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6242, 24.4672)::geography, 50, true, false)),
  8::numeric, 'ثابت: استلام فقط = 8');

-- ═══ الحالة 2: رسم الرحلتين معًا — «الاثنان بـ15 لا 16» ═══════════════════
update delivery_settings set combined_fee = 15
where branch_id = '22222222-2222-2222-2222-222222222222';

select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6242, 24.4672)::geography, 50, true, true)),
  15::numeric, 'مجمَّع: الرحلتان = 15 لا 16');

select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6242, 24.4672)::geography, 50, true, false)),
  8::numeric, 'مجمَّع: رحلة واحدة تبقى 8');

-- ═══ الحالة 3: توصيل مجاني فوق 100 ريال ══════════════════════════════════
update delivery_settings set free_above_subtotal = 100
where branch_id = '22222222-2222-2222-2222-222222222222';

select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6242, 24.4672)::geography, 120, true, true)),
  0::numeric, 'إعفاء: 120 ريال ← توصيل مجاني');

select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6242, 24.4672)::geography, 99.99, true, true)),
  15::numeric, 'إعفاء: 99.99 ريال ← لا إعفاء');

-- ═══ الحالة 4: خارج النطاق ═══════════════════════════════════════════════
-- جدة تقريبًا — أبعد من 20 كم بكثير
select assert_eq(
  (select serviceable from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.1979, 21.4858)::geography, 50, true, true)),
  false, 'نطاق: جدة خارج خدمة فرع المدينة');

-- ═══ الحالة 5: شرائح المسافة ══════════════════════════════════════════════
update delivery_settings
set strategy = 'distance', combined_fee = null, free_above_subtotal = null
where branch_id = '22222222-2222-2222-2222-222222222222';

insert into delivery_distance_tiers (branch_id, from_km, to_km, pickup_fee, delivery_fee) values
  ('22222222-2222-2222-2222-222222222222', 0,  3,  2.5, 2.5),
  ('22222222-2222-2222-2222-222222222222', 3,  7,  5,   5),
  ('22222222-2222-2222-2222-222222222222', 7,  12, 7.5, 7.5);

-- ~1 كم ← الشريحة الأولى
select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6242, 24.4672)::geography, 50, true, true)),
  5::numeric, 'شرائح: 1 كم ← 2.5+2.5 = 5');

-- ~5 كم شرقًا ← الشريحة الثانية
select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.6635, 24.4672)::geography, 50, true, true)),
  10::numeric, 'شرائح: 5 كم ← 5+5 = 10');

-- ~9 كم ← الشريحة الثالثة
select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.7130, 24.4672)::geography, 50, true, true)),
  15::numeric, 'شرائح: 9 كم ← 7.5+7.5 = 15');

-- ثغرة في الإعداد: 13 كم داخل النطاق (20) ولا شريحة تغطّيها.
-- الصمت هنا يعني توصيلًا مجانيًا بالخطأ — فيجب أن تُعلن غير قابلة للخدمة.
select assert_eq(
  (select serviceable from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.7530, 24.4672)::geography, 50, true, true)),
  false, 'شرائح: مسافة بلا شريحة ← تُرفض لا تُمجَّن');

-- ═══ الحالة 6: قيد التداخل يمنع شريحتين متقاطعتين ════════════════════════
do $$
begin
  insert into delivery_distance_tiers (branch_id, from_km, to_km, pickup_fee, delivery_fee)
  values ('22222222-2222-2222-2222-222222222222', 5, 9, 99, 99);
  raise exception '✗ تداخل: قُبلت شريحة متداخلة وكان يجب رفضها';
exception when exclusion_violation then
  raise notice '✓ تداخل: الشريحة المتقاطعة رُفضت';
end $$;

-- ═══ الحالة 7: المناطق الجغرافية ═════════════════════════════════════════
update delivery_settings set strategy = 'zone'
where branch_id = '22222222-2222-2222-2222-222222222222';

-- مربّع صغير حول المسجد النبوي
insert into delivery_zones (branch_id, name_ar, area, pickup_fee, delivery_fee, priority)
values ('22222222-2222-2222-2222-222222222222', 'المنطقة المركزية',
        st_geogfromtext('POLYGON((39.60 24.45, 39.63 24.45, 39.63 24.48, 39.60 24.48, 39.60 24.45))'),
        3, 3, 0);

-- منطقة أصغر داخلها بأولوية أعلى — التداخل مقصود
insert into delivery_zones (branch_id, name_ar, area, pickup_fee, delivery_fee, combined_fee, priority)
values ('22222222-2222-2222-2222-222222222222', 'محيط الحرم',
        st_geogfromtext('POLYGON((39.610 24.465, 39.618 24.465, 39.618 24.470, 39.610 24.470, 39.610 24.465))'),
        1, 1, 1.5, 10);

select assert_eq(
  (select reason from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.614, 24.467)::geography, 50, true, true)),
  'منطقة: محيط الحرم — استلام وتسليم', 'مناطق: الأعلى أولوية تفوز عند التداخل');

select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.614, 24.467)::geography, 50, true, true)),
  1.5::numeric, 'مناطق: رسم مجمَّع للمنطقة = 1.5');

select assert_eq(
  (select fee from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.625, 24.475)::geography, 50, true, true)),
  6::numeric, 'مناطق: خارج الحرم داخل المركزية = 3+3');

select assert_eq(
  (select serviceable from quote_delivery_fee('22222222-2222-2222-2222-222222222222',
     st_point(39.700, 24.500)::geography, 50, true, true)),
  false, 'مناطق: خارج كل المناطق المعرَّفة ← لا خدمة');

rollback;
