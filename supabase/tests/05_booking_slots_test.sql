-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار محرّك المواعيد
-- ═══════════════════════════════════════════════════════════════════════════
-- الفتحة التي تُعرض ولا تُنفَّذ أسوأ من فتحةٍ لا تُعرض: العميل انتظر، والفرع
-- تجاوز طاقته، والوعد الذي قُطع لم يُوفَ. فما يُختبر هنا هو أن كل قيدٍ من
-- الخمسة يُغلق الفتحة فعلًا — وأن سببه يُقال.

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
values ('11111111-1111-1111-1111-111111111111', 'مغسلة وصل', 'wasl');

insert into branches (id, laundry_id, name_ar, location, daily_capacity_pieces)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
        'فرع المركز', st_point(39.6142, 24.4672)::geography, 40);

-- يعمل كل يوم ٨ص–١٠م، ويومٌ واحدٌ مغلق.
--
-- **واليومُ المغلق يُحسب ولا يُثبَّت.** كان الجمعةَ ثابتًا، وفحصُ «مهلة
-- التجهيز» أدناه يسأل عن فتحات **اليوم** — فكان الملفّ يمرّ ستّة أيّامٍ في
-- الأسبوع ويسقط يوم الجمعة، لأنّ اليوم حينها بلا فتحةٍ أصلًا. واختبارٌ
-- يتعلّق نجاحُه بيوم تشغيله ليس اختبارًا.
--
-- فيُغلق **يومُ غد**: مغلقٌ دائمًا (فيبقى فحص الإغلاق قائمًا)، ومفتوحٌ
-- اليومُ دائمًا (فيبقى فحص المهلة قائمًا) — أيًّا كان يوم التشغيل.
create temporary table _t_closed as
select ((extract(dow from current_date)::int + 1) % 7) as weekday;

insert into branch_hours (branch_id, weekday, opens_at, closes_at, is_closed)
select '22222222-2222-2222-2222-222222222222', w, '08:00', '22:00',
       (w = (select weekday from _t_closed))
from generate_series(0,6) w;

insert into booking_settings
  (branch_id, slot_minutes, lead_time_minutes, horizon_days,
   max_orders_per_slot, max_pieces_per_slot, cutoff_before_close_minutes)
values ('22222222-2222-2222-2222-222222222222', 60, 120, 7, 2, 20, 30);

insert into service_categories (id, laundry_id, name_ar)
values ('cc000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','ملابس');
insert into services (id, laundry_id, category_id, name_ar, unit, base_price) values
  ('55000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
   'cc000000-0000-0000-0000-000000000001','ثوب غسيل','piece',8),
  ('55000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',
   'cc000000-0000-0000-0000-000000000001','غسيل بالوزن','kilogram',12),
  ('55000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111',
   'cc000000-0000-0000-0000-000000000001','سلّة','basket',60);

insert into auth.users (id, phone) values ('a0000000-0000-0000-0000-000000000001','+966500000001');
insert into profiles (id, phone) values ('a0000000-0000-0000-0000-000000000001','+966500000001');

-- يومٌ عاملٌ ثابتٌ لكل الفحوص التالية — لا «غدًا» الذي قد يكون جمعة.
create temporary table _t_open as
select d::date as day
from generate_series(current_date + 1, current_date + 6, '1 day') d
where extract(dow from d)::int <> (select weekday from _t_closed)
limit 1;

create temporary table _t_open2 as
select d::date as day
from generate_series(current_date + 1, current_date + 6, '1 day') d
where extract(dow from d)::int <> (select weekday from _t_closed)
offset 1 limit 1;

-- ═══ ١) توليد الفتحات من ساعات العمل ═════════════════════════════════════
-- ٨ص–١٠م بفتحة ساعة، وآخر خروجٍ قبل الإغلاق بنصف ساعة ⇒ آخر فتحة ٢٠:٠٠
select assert_eq(
  (select count(*)::int from available_slots(
     '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1)),
  13, 'التوليد: ١٣ فتحة في اليوم (٨ص–٩م)');

select assert_eq(
  (select max(to_char(slot_start,'HH24:MI')) from available_slots(
     '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1)),
  '20:00', 'مهلة الخروج: آخر فتحة ٢٠:٠٠ لا ٢١:٠٠');

-- ═══ ٢) اليوم المغلق لا فتحة فيه ═════════════════════════════════════════
select assert_eq(
  (select count(*)::int from available_slots(
     '22222222-2222-2222-2222-222222222222','pickup',
     (select d::date from generate_series(current_date, current_date+7, '1 day') d
      where extract(dow from d)::int = (select weekday from _t_closed) limit 1), 1)),
  0, 'الإغلاق: اليوم المغلق بلا فتحة واحدة');

-- ═══ ٣) مهلة التجهيز تُغلق ما قرُب ═══════════════════════════════════════
do $$
declare n int;
begin
  select count(*) into n from available_slots(
    '22222222-2222-2222-2222-222222222222','pickup', current_date, 1)
  where not is_available and blocked_reason = 'أقرب من مهلة التجهيز';
  if n = 0 then
    raise exception '✗ المهلة: لم تُغلق فتحةٌ واحدة اليوم';
  end if;
  raise notice '✓ المهلة: % فتحة اليوم مغلقة لقربها', n;
end $$;

-- ═══ ٤) تحويل الوحدات في حِمل الطلب ══════════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status)
values ('0dd00000-0000-0000-0000-0000000000f0','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001','draft');
insert into order_items (order_id, service_id, service_name_ar, unit, quantity, unit_price, line_total) values
  ('0dd00000-0000-0000-0000-0000000000f0','55000000-0000-0000-0000-000000000001','ثوب','piece',3,8,24),
  ('0dd00000-0000-0000-0000-0000000000f0','55000000-0000-0000-0000-000000000002','وزن','kilogram',5,12,60),
  ('0dd00000-0000-0000-0000-0000000000f0','55000000-0000-0000-0000-000000000003','سلّة','basket',1,60,60);

-- ٣ قطع + (٥ كجم × ٤) + (سلّة × ١٥) = ٣٨
select assert_eq(order_piece_load('0dd00000-0000-0000-0000-0000000000f0'), 38::numeric,
  'الحِمل: ٣ قطع + ٥ كجم + سلّة = ٣٨ قطعة مكافئة');

-- ═══ ٥) سقف الفتحة بعدد الطلبات ══════════════════════════════════════════
-- الفتحة تقبل طلبين. نملؤها بطلبين خفيفين ثم نتحقّق أنها أُغلقت.
do $$
declare
  v_slot timestamptz;
  i int;
  v_id uuid;
begin
  select slot_start into v_slot from available_slots(
    '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1)
  where is_available order by slot_start limit 1;

  for i in 1..2 loop
    v_id := uuid_generate_v4();
    insert into orders (id, laundry_id, branch_id, customer_id, status, pickup_slot_start)
    values (v_id,'11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222',
            'a0000000-0000-0000-0000-000000000001','placed', v_slot);
    insert into order_items (order_id, service_id, service_name_ar, unit, quantity, unit_price, line_total)
    values (v_id,'55000000-0000-0000-0000-000000000001','ثوب','piece',1,8,8);
  end loop;

  if (select is_available from available_slots(
        '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1)
      where slot_start = v_slot) then
    raise exception '✗ سقف الفتحة: ما زالت متاحةً بعد طلبين والسقف طلبان';
  end if;
  if (select blocked_reason from available_slots(
        '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1)
      where slot_start = v_slot) <> 'الفتحة ممتلئة' then
    raise exception '✗ سقف الفتحة: السبب المعلن غير صحيح';
  end if;
  raise notice '✓ سقف الفتحة: أُغلقت بعد طلبين، والسبب «الفتحة ممتلئة»';

  -- والفتحة التالية ما زالت مفتوحة — الامتلاء موضعيّ لا عامّ
  if not (select is_available from available_slots(
            '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1)
          where slot_start = v_slot + interval '1 hour') then
    raise exception '✗ سقف الفتحة: أغلق الفتحة التالية أيضًا';
  end if;
  raise notice '✓ سقف الفتحة: التالية ما زالت مفتوحة — الامتلاء موضعيّ';
end $$;

-- ═══ ٦) طاقة اليوم ═══════════════════════════════════════════════════════
-- الفرع يحتمل ٤٠ قطعة يوميًّا، وحُجز طلبان بقطعتين. طلبٌ بـ٣٩ قطعة لا يتّسع.
do $$
declare v_open int;
begin
  select count(*) into v_open from available_slots(
    '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1, 39)
  where is_available;
  if v_open <> 0 then
    raise exception '✗ طاقة اليوم: % فتحة قبلت ٣٩ قطعة والطاقة ٤٠ وفيها قطعتان', v_open;
  end if;
  raise notice '✓ طاقة اليوم: طلبٌ بـ٣٩ قطعة لا يتّسع في يومٍ طاقته ٤٠ وفيه قطعتان';

  select count(*) into v_open from available_slots(
    '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open), 1, 10)
  where is_available;
  if v_open = 0 then
    raise exception '✗ طاقة اليوم: رفضت طلبًا بـ١٠ قطع وفيها متّسع';
  end if;
  raise notice '✓ طاقة اليوم: طلبٌ بـ١٠ قطع يتّسع — % فتحة مفتوحة', v_open;
end $$;

-- ═══ ٧) سقف قطع الفتحة ═══════════════════════════════════════════════════
-- سقف الفتحة ٢٠ قطعة. طلبٌ بـ٢٥ لا يدخل فتحةً واحدة مهما كانت فارغة.
select assert_eq(
  (select count(*)::int from available_slots(
     '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open2), 1, 25)
   where is_available),
  0, 'سقف قطع الفتحة: طلبٌ بـ٢٥ قطعة لا يدخل فتحةً سقفها ٢٠');

select assert_eq(
  (select distinct blocked_reason from available_slots(
     '22222222-2222-2222-2222-222222222222','pickup', (select day from _t_open2), 1, 25)
   where blocked_reason is not null limit 1),
  'طاقة الفتحة لا تتّسع لهذا الطلب', 'سقف قطع الفتحة: السبب معلن');

-- ═══ ٨) التعطيل ══════════════════════════════════════════════════════════
-- **اليوم يُختار ولا يُفترض**: كُتب هذا الفحص أوّلًا على `current_date + 3`،
-- فنجح يومًا وفشل في اليوم التالي — لأن اليوم الثالث صادف الجمعة، والفرع مغلق
-- فيها فلا فتحة تُغلَق أصلًا. واختبارٌ ينجح بعض الأيام أسوأ من لا اختبار:
-- يفشل في CI بلا سبب ظاهر، فيُدرَّب الناس على تجاهله.
--
-- فيُنتقى أوّل يومٍ عاملٍ ضمن الأفق، أيًّا كان تاريخ التشغيل.
create temporary table _t_day as
select d::date as day
from generate_series(current_date + 1, current_date + 6, '1 day') d
where extract(dow from d)::int <> (select weekday from _t_closed)
limit 1;

insert into slot_blackouts (branch_id, starts_at, ends_at, reason)
select '22222222-2222-2222-2222-222222222222',
       (day + time '10:00')::timestamptz,
       (day + time '13:00')::timestamptz,
       'صيانة الآلات'
from _t_day;

select assert_eq(
  (select count(*)::int from available_slots(
     '22222222-2222-2222-2222-222222222222','pickup',
     (select day from _t_day), 1)
   where blocked_reason = 'صيانة الآلات'),
  3, 'التعطيل: ثلاث فتحات (١٠–١٣) مغلقة بسبب الصيانة');

select assert_eq(
  (select is_available from available_slots(
     '22222222-2222-2222-2222-222222222222','pickup',
     (select day from _t_day), 1)
   where slot_start = ((select day from _t_day) + time '14:00')::timestamptz),
  true, 'التعطيل: ما بعد الصيانة مفتوح');

-- ═══ ٩) أقرب موعد متاح ═══════════════════════════════════════════════════
do $$
declare v timestamptz;
begin
  v := earliest_slot('22222222-2222-2222-2222-222222222222','pickup', 1);
  if v is null then
    raise exception '✗ أقرب موعد: لم يُرجع شيئًا';
  end if;
  if v < now() then
    raise exception '✗ أقرب موعد: أعاد موعدًا في الماضي (%)', v;
  end if;
  raise notice '✓ أقرب موعد متاح: %', to_char(v, 'MM-DD HH24:MI');
end $$;

-- ═══ ١٠) الحارس: لا يُحجز موعدٌ غير متاح ═════════════════════════════════
insert into user_roles (user_id, role, laundry_id, branch_id)
values ('a0000000-0000-0000-0000-000000000001','branch_manager',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');

select auth.login_as('a0000000-0000-0000-0000-000000000001');

-- موعدٌ في الماضي
do $$ begin
  update orders set pickup_slot_start = (current_date - 1 + time '10:00')::timestamptz
  where id = '0dd00000-0000-0000-0000-0000000000f0';
  raise exception '✗ الحارس: قُبل موعدٌ في الماضي';
exception when check_violation then
  raise notice '✓ الحارس: موعدٌ في الماضي مرفوض';
end $$;

-- موعدٌ في يوم الإغلاق.
--
-- **ويُؤخذ اليومُ من `_t_closed` لا من «الجمعة»**: بعد أن صار المغلق يُحسب،
-- بقي هذا الفحص يختار الجمعةَ — وهي يومٌ عاملٌ الآن. فكان ينجح **لسببٍ
-- آخر** (طاقة أو مهلة، وكلاهما `check_violation` أيضًا) ولا يفحص الإغلاق
-- إطلاقًا. ونجاحٌ لسببٍ غير المقصود أسوأُ من فشل: لا أحد ينظر فيه.
do $$
declare v_closed date; v_ok boolean := false;
begin
  select d::date into v_closed
  from generate_series(current_date+1, current_date+8, '1 day') d
  where extract(dow from d)::int = (select weekday from _t_closed) limit 1;

  -- الوقتُ ١٠ص بعد أيّامٍ من الآن: بعيدٌ عن مهلة التجهيز، والفتحةُ فارغة.
  -- فإن رُفض فلسببٍ واحدٍ لا ثالثَ له: الفرعُ مغلقٌ في ذلك اليوم.
  begin
    update orders set pickup_slot_start = (v_closed + time '10:00')::timestamptz
    where id = '0dd00000-0000-0000-0000-0000000000f0';
  exception when check_violation then
    v_ok := true;
  end;

  if not v_ok then
    raise exception '✗ الحارس: قُبل موعدٌ في يوم إغلاق (%)', v_closed;
  end if;
  raise notice '✓ الحارس: موعدٌ في يوم الإغلاق مرفوض (%)', v_closed;
end $$;

-- وموعدٌ صحيح يُقبل. الطلب حِمله ٣٨ قطعة، فيحتاج فتحةً وطاقةً تتّسعان —
-- ولذلك يُخفَّض إلى بندٍ واحد أوّلًا.
delete from order_items where order_id = '0dd00000-0000-0000-0000-0000000000f0';
insert into order_items (order_id, service_id, service_name_ar, unit, quantity, unit_price, line_total)
values ('0dd00000-0000-0000-0000-0000000000f0','55000000-0000-0000-0000-000000000001','ثوب','piece',2,8,16);

do $$
declare v timestamptz;
begin
  v := earliest_slot('22222222-2222-2222-2222-222222222222','pickup', 2);
  update orders set pickup_slot_start = v
  where id = '0dd00000-0000-0000-0000-0000000000f0';
  if (select pickup_slot_start from orders where id = '0dd00000-0000-0000-0000-0000000000f0') <> v then
    raise exception '✗ الحارس: لم يُحفظ الموعد الصحيح';
  end if;
  raise notice '✓ الحارس: الموعد المتاح يُقبل ويُحفظ';
end $$;

rollback;
