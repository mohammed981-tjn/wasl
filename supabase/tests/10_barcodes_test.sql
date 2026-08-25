-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار الباركود وتشغيل المغسلة
-- ═══════════════════════════════════════════════════════════════════════════
-- **الخطر هنا ليس خطأً في الحساب بل تكرارٌ في رقم**: باركودٌ يتكرّر يعني كيسًا
-- يُمسح فيظهر طلبُ غيره — وتُسلَّم ملابسُ رجلٍ لآخر.

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
insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001','+966500000001'),
  ('a0000000-0000-0000-0000-000000000005','+966500000005');
insert into profiles (id, phone) select id, phone from auth.users;
insert into user_roles (user_id, role, laundry_id, branch_id)
values ('a0000000-0000-0000-0000-000000000005','laundry_staff',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');

insert into orders (id, laundry_id, branch_id, customer_id, status)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001','draft');

-- ═══ ١) لا باركود للمسوّدة ═══════════════════════════════════════════════
select assert_eq(
  (select barcode from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  null::text, 'المسوّدة بلا باركود — لا تُطبع ملصقات لطلبٍ قد يُهجر');

-- ═══ ٢) يُولَّد عند الإرسال، بصيغةٍ تُملى في الهاتف ═══════════════════════
update orders set status = 'placed' where id = '0dd00000-0000-0000-0000-00000000000a';

do $$
declare v text; n bigint;
begin
  select barcode, order_number into v, n
  from orders where id = '0dd00000-0000-0000-0000-00000000000a';
  if v <> 'WSL-' || n::text then
    raise exception '✗ الباركود: توقّعنا WSL-% وجاء %', n, v;
  end if;
  raise notice '✓ الباركود: يُولَّد عند الإرسال بصيغة %', v;
end $$;

-- ═══ ٣) وهو فريدٌ عبر المنصّة ════════════════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status)
values ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001','draft');
update orders set status = 'placed' where id = '0dd00000-0000-0000-0000-00000000000b';

select assert_eq(
  (select count(distinct barcode)::int from orders where barcode is not null),
  2, 'الباركود: طلبان ⇒ باركودان مختلفان');

do $$ begin
  update orders set barcode = (select barcode from orders
    where id = '0dd00000-0000-0000-0000-00000000000a')
  where id = '0dd00000-0000-0000-0000-00000000000b';
  raise exception '✗ التفرّد: قُبل باركود مكرَّر — كيسٌ يُمسح فيظهر طلبُ غيره';
exception when unique_violation then
  raise notice '✓ التفرّد: الباركود المكرَّر مرفوض في القاعدة';
end $$;

-- ═══ ٤) باركود القطعة مشتقٌّ ومرقَّم داخل الطلب ══════════════════════════
insert into order_garments (order_id, label_ar) values
  ('0dd00000-0000-0000-0000-00000000000a','ثوب أبيض'),
  ('0dd00000-0000-0000-0000-00000000000a','شماغ'),
  ('0dd00000-0000-0000-0000-00000000000a','بنطلون');

do $$
declare v_order text; v_codes text[];
begin
  select barcode into v_order from orders
  where id = '0dd00000-0000-0000-0000-00000000000a';

  select array_agg(barcode order by barcode) into v_codes
  from order_garments where order_id = '0dd00000-0000-0000-0000-00000000000a';

  if v_codes <> array[v_order||'-01', v_order||'-02', v_order||'-03'] then
    raise exception '✗ القطع: توقّعنا ترقيمًا داخل الطلب وجاء %', v_codes;
  end if;
  raise notice '✓ القطع: مرقّمة داخل الطلب (%-01 … -03)', v_order;
end $$;

-- والترقيم يُكمِل ولا يعيد
insert into order_garments (order_id, label_ar)
values ('0dd00000-0000-0000-0000-00000000000a','قميص');

select assert_eq(
  (select count(distinct barcode)::int from order_garments),
  4, 'القطع: الرابعة أخذت رقمًا جديدًا لا مكرَّرًا');

-- وباركودٌ مطبوعٌ مسبقًا (ملصقات جاهزة) يُحترم ولا يُستبدل
insert into order_garments (order_id, label_ar, barcode)
values ('0dd00000-0000-0000-0000-00000000000b','عباءة','PRE-PRINTED-777');

select assert_eq(
  (select barcode from order_garments where label_ar = 'عباءة'),
  'PRE-PRINTED-777', 'القطع: الملصق الجاهز يُحترم ولا يُستبدل');

-- ═══ ٥) المسح يجيب بالطلب أيًّا كان الملصق ═══════════════════════════════
do $$
declare v_order text; r record;
begin
  select barcode into v_order from orders
  where id = '0dd00000-0000-0000-0000-00000000000a';

  select * into r from resolve_barcode(v_order);
  if r.order_id <> '0dd00000-0000-0000-0000-00000000000a' or r.kind <> 'order' then
    raise exception '✗ المسح: ملصق الكيس لم يُحلَّ إلى طلبه';
  end if;
  raise notice '✓ المسح: ملصق الكيس ⇒ الطلب';

  select * into r from resolve_barcode(v_order || '-02');
  if r.order_id <> '0dd00000-0000-0000-0000-00000000000a' or r.kind <> 'garment' then
    raise exception '✗ المسح: ملصق القطعة لم يُحلَّ إلى طلبه';
  end if;
  if r.garment_label <> 'شماغ' then
    raise exception '✗ المسح: القطعة الخطأ (%)', r.garment_label;
  end if;
  raise notice '✓ المسح: ملصق القطعة ⇒ الطلب نفسه، ويقول أيّ قطعة';
end $$;

select assert_eq(
  (select count(*)::int from resolve_barcode('WSL-لا-يوجد')),
  0, 'المسح: رمزٌ مجهول يعطي صفر صفوف لا خطأً');

-- الحروف الصغيرة والمسافات تُقبل: الماسح قد يعطيها، والإدخال اليدويّ كذلك
do $$
declare v_order text; n int;
begin
  select barcode into v_order from orders
  where id = '0dd00000-0000-0000-0000-00000000000a';
  select count(*) into n from resolve_barcode('  ' || lower(v_order) || ' ');
  if n <> 1 then
    raise exception '✗ المسح: لم يُقبل الرمز بمسافاتٍ وأحرفٍ صغيرة';
  end if;
  raise notice '✓ المسح: يقبل المسافات والأحرف الصغيرة';
end $$;

-- ═══ ٦) مرحلة القطع تتبع الطلب ═══════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000005');
-- يُنقل الطلب إلى المغسلة أولًا (بالسياق الخادميّ لاختصار المسار)
select auth.logout();
update orders set status = 'accepted'        where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'pickup_assigned' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'pickup_en_route' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'picked_up'       where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'at_laundry'      where id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select distinct current_stage from order_garments
   where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  'sorting'::order_status, 'القطع: تبدأ عند الفرز');

update orders set status = 'sorting' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'washing' where id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select distinct current_stage from order_garments
   where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  'washing'::order_status, 'القطع: تتبع الطلب إلى الغسيل');

update orders set status = 'drying'    where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'packaging' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'ready'     where id = '0dd00000-0000-0000-0000-00000000000a';

-- «جاهز» ليست مرحلةً داخلية: القطعة لا تكون «جاهزة» — الكيس هو الجاهز.
select assert_eq(
  (select distinct current_stage from order_garments
   where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  'packaging'::order_status,
  'القطع: تتوقّف عند آخر مرحلةٍ داخلية ولا تتبع الطلب خارج المغسلة');

-- ═══ ٧) موظّف المغسلة يسجّل القطع ويحرّك المراحل ═════════════════════════
-- الطلب يُنشأ بالسياق الخادميّ لا بحساب الموظّف: سياسة `orders_insert` لا
-- تخوّله إنشاء طلبات — وهذا مقصود. الموظّف يستقبل ما وصل ولا يخترع طلبًا.
insert into orders (id, laundry_id, branch_id, customer_id, status)
values ('0dd00000-0000-0000-0000-00000000000c','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001','at_laundry');

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000005');

-- وأنّه لا ينشئ طلبًا فحصٌ في ذاته
do $$ begin
  insert into orders (laundry_id, branch_id, customer_id, status)
  values ('11111111-1111-1111-1111-111111111111',
          '22222222-2222-2222-2222-222222222222',
          'a0000000-0000-0000-0000-000000000001','at_laundry');
  raise exception '✗ الصلاحية: أنشأ موظّف المغسلة طلبًا';
exception when insufficient_privilege or check_violation then
  raise notice '✓ الصلاحية: موظّف المغسلة لا يُنشئ طلبًا — يستقبل ما وصل';
end $$;

do $$ begin
  insert into order_garments (order_id, label_ar, defect_notes)
  values ('0dd00000-0000-0000-0000-00000000000c','ثوب','بقعة على الياقة');
  raise notice '✓ الصلاحية: موظّف المغسلة يسجّل قطعةً بعيبها';
end $$;

update orders set status = 'sorting' where id = '0dd00000-0000-0000-0000-00000000000c';
select assert_eq(
  (select status from orders where id = '0dd00000-0000-0000-0000-00000000000c'),
  'sorting'::order_status, 'الصلاحية: موظّف المغسلة ينقل إلى الفرز');

-- ولا يقبل طلبًا ولا يُسند سائقًا: ليس دورَه
do $$ begin
  update orders set status = 'ready' where id = '0dd00000-0000-0000-0000-00000000000c';
  raise exception '✗ الصلاحية: قفز الموظّف من الفرز إلى جاهز';
exception when check_violation then
  raise notice '✓ الصلاحية: القفز من الفرز إلى جاهز مرفوض';
end $$;

reset role;
rollback;
