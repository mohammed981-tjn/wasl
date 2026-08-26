-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار رسم مناطق التوصيل
-- ═══════════════════════════════════════════════════════════════════════════
-- **الخطر هنا رسمٌ يُقبل ولا يعمل**: مضلَّعٌ يقطع نفسه يدخل العمود بلا شكوى،
-- ثم يُعطي `ST_Contains` نتائج لا معنى لها — فيُحسب رسمُ توصيلٍ خاطئ لحيٍّ
-- كامل، ولا يظهر خطأٌ في أيّ سجلّ.

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
        'المركز', st_point(39.6142,24.4672)::geography),
       ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
        'قباء', st_point(39.6170,24.4390)::geography);

insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000002','+966500000002'),
  ('a0000000-0000-0000-0000-000000000007','+966500000007');
insert into profiles (id, phone) select id, phone from auth.users;
insert into user_roles (user_id, role, laundry_id, branch_id) values
  ('a0000000-0000-0000-0000-000000000002','branch_manager',
   '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000007','branch_manager',
   '11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333');

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000002');

-- ═══ ١) الحلقة تُغلق في القاعدة لا في الشاشة ═════════════════════════════
-- ثلاثُ نقاطٍ بلا إغلاق: PostGIS يشترط عودة الأخيرة إلى الأولى.
do $$
declare v_id uuid;
begin
  v_id := save_delivery_zone(
    '22222222-2222-2222-2222-222222222222', 'وسط المدينة',
    '[{"lat":24.470,"lng":39.610},
      {"lat":24.470,"lng":39.620},
      {"lat":24.460,"lng":39.620}]'::jsonb,
    10, 15, 20, 5, true);
  if v_id is null then
    raise exception '✗ الإغلاق: لم تُحفظ المنطقة';
  end if;
  raise notice '✓ الإغلاق: ثلاثُ نقاطٍ بلا إغلاقٍ تُقبل وتُغلق في القاعدة';
end $$;

select assert_eq(
  (select count(*)::int from delivery_zones), 1,
  'الرسم: المنطقة حُفظت');

-- ═══ ٢) ما لا يصلح يُرفض برسالةٍ تُقرأ ═══════════════════════════════════
do $$ begin
  perform save_delivery_zone('22222222-2222-2222-2222-222222222222', 'خطّ',
    '[{"lat":24.47,"lng":39.61},{"lat":24.46,"lng":39.62}]'::jsonb);
  raise exception '✗ الحدّ الأدنى: قُبلت نقطتان — وهما خطٌّ لا منطقة';
exception when check_violation then
  raise notice '✓ الحدّ الأدنى: نقطتان تُرفضان (%)', sqlerrm;
end $$;

-- مضلَّعٌ على شكل ٨: يقطع نفسه.
do $$ begin
  perform save_delivery_zone('22222222-2222-2222-2222-222222222222', 'فراشة',
    '[{"lat":24.470,"lng":39.610},
      {"lat":24.460,"lng":39.620},
      {"lat":24.470,"lng":39.620},
      {"lat":24.460,"lng":39.610}]'::jsonb);
  raise exception '✗ الصحّة: قُبل مضلَّعٌ يقطع نفسه — وكلُّ حسابٍ بعده بلا معنى';
exception when check_violation then
  raise notice '✓ الصحّة: المضلَّع القاطع لنفسه مرفوض';
end $$;

do $$ begin
  perform save_delivery_zone('22222222-2222-2222-2222-222222222222', 'فارغة',
    '[]'::jsonb);
  raise exception '✗ الفراغ: قُبلت منطقةٌ بلا نقاط';
exception when check_violation then
  raise notice '✓ الفراغ: منطقةٌ بلا نقاطٍ مرفوضة';
end $$;

-- ═══ ٣) المنطقة تُقرأ نقاطًا لا نصًّا سداسيًّا ═══════════════════════════
select assert_eq(
  (select area_geojson ->> 'type' from delivery_zones_map),
  'Polygon', 'القراءة: تصل GeoJSON لا EWKB');

select assert_eq(
  (select jsonb_array_length(area_geojson -> 'coordinates' -> 0)
   from delivery_zones_map),
  4, 'القراءة: أربع نقاطٍ — الثلاث والإغلاق');

-- والمركزُ داخل المنطقة، فتُفتح الخريطة عليها لا على المحيط.
select assert_eq(
  (select round(center_lat::numeric, 2) from delivery_zones_map),
  24.47::numeric, 'القراءة: مركزُ المنطقة يُحسب لفتح الخريطة عليه');

select assert_eq(
  (select area_km2 > 0 from delivery_zones_map),
  true, 'القراءة: المساحة تُقاس — والمنطقة الضخمة خطأُ رسمٍ يُرى');

-- ═══ ٤) الحدود تُحترم: منطقة الفرع لفرعه ════════════════════════════════
do $$ begin
  perform save_delivery_zone('33333333-3333-3333-3333-333333333333', 'قباء',
    '[{"lat":24.44,"lng":39.61},
      {"lat":24.44,"lng":39.62},
      {"lat":24.43,"lng":39.62}]'::jsonb);
  raise exception '✗ الحدود: مدير المركز رسم منطقةً في فرعٍ ليس فرعه';
exception when insufficient_privilege then
  raise notice '✓ الحدود: لا يرسم مديرُ فرعٍ منطقةً في فرعٍ آخر';
end $$;

-- والتعديل كذلك: منطقةُ فرعٍ لا يعدّلها مديرُ فرعٍ آخر.
do $$
declare v_zone uuid;
begin
  select id into v_zone from delivery_zones limit 1;
  perform auth.login_as('a0000000-0000-0000-0000-000000000007');
  perform save_delivery_zone('33333333-3333-3333-3333-333333333333', 'سرقة',
    '[{"lat":24.44,"lng":39.61},
      {"lat":24.44,"lng":39.62},
      {"lat":24.43,"lng":39.62}]'::jsonb,
    0, 0, null, 0, true, v_zone);
  raise exception '✗ الحدود: عُدِّلت منطقةُ فرعٍ آخر';
exception when insufficient_privilege then
  raise notice '✓ الحدود: تعديلُ منطقةِ فرعٍ آخر مرفوضٌ برسالةٍ لا بصمت';
end $$;

-- ═══ ٥) التعديل يُبقي المعرّف ولا يُنشئ منطقةً ثانية ════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000002');

do $$
declare v_zone uuid; v_same uuid;
begin
  select id into v_zone from delivery_zones limit 1;
  v_same := save_delivery_zone(
    '22222222-2222-2222-2222-222222222222', 'وسط المدينة (موسَّع)',
    '[{"lat":24.475,"lng":39.605},
      {"lat":24.475,"lng":39.625},
      {"lat":24.455,"lng":39.625},
      {"lat":24.455,"lng":39.605}]'::jsonb,
    12, 18, 25, 9, true, v_zone);

  if v_same <> v_zone then
    raise exception '✗ التعديل: تغيّر المعرّف — والطلبات المرتبطة تفقد منطقتها';
  end if;
  raise notice '✓ التعديل: المعرّف يبقى';
end $$;

select assert_eq(
  (select count(*)::int from delivery_zones), 1,
  'التعديل: منطقةٌ واحدة لا اثنتان');

select assert_eq(
  (select name_ar from delivery_zones),
  'وسط المدينة (موسَّع)', 'التعديل: الاسم تغيّر');

select assert_eq(
  (select priority from delivery_zones), 9,
  'التعديل: الأولوية تغيّرت — وبها يُحسم تداخل المناطق');

-- ═══ ٦) والمضلَّع المحفوظ يعمل فعلًا في حساب الرسم ══════════════════════
-- وهذا هو الفحص الذي يجعل ما سبق ذا معنى: نقطةٌ داخل الحدود تُعرف داخلًا.
select assert_eq(
  (select st_contains(area::geometry,
                      st_setsrid(st_makepoint(39.615, 24.465), 4326))
   from delivery_zones),
  true, 'الاحتواء: نقطةٌ داخل الحدود تقع داخلها');

select assert_eq(
  (select st_contains(area::geometry,
                      st_setsrid(st_makepoint(39.700, 24.500), 4326))
   from delivery_zones),
  false, 'الاحتواء: نقطةٌ خارجها تقع خارجها');

rollback;
