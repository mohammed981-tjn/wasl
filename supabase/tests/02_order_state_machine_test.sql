-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار آلة حالات الطلب
-- ═══════════════════════════════════════════════════════════════════════════
-- الخطر الذي يمسكه هذا الملف: عميلٌ بتطبيق معدَّل يقفز بطلبه من 'placed' إلى
-- 'delivered' فيسقط عنه الدفع، أو موظّف مغسلة يغيّر حالة طلب فرعٍ ليس فرعه.
-- كلاهما لا يُمنع بشاشة — يُمنع هنا أو لا يُمنع أبدًا.

\set ON_ERROR_STOP on
begin;

create or replace function expect_fail(sql_text text, label text)
returns void language plpgsql as $$
begin
  execute sql_text;
  raise exception '✗ %: نجح وكان يجب أن يفشل', label;
exception
  when check_violation or insufficient_privilege then
    raise notice '✓ % (رُفض كما يجب)', label;
end $$;

create or replace function expect_status(p_order uuid, expected order_status, label text)
returns void language plpgsql as $$
declare v order_status;
begin
  select status into v from orders where id = p_order;
  if v is distinct from expected then
    raise exception '✗ %: توقّعنا % وجاء %', label, expected, v;
  end if;
  raise notice '✓ %', label;
end $$;

-- ── تجهيز ────────────────────────────────────────────────────────────────
insert into laundries (id, name_ar, slug)
values ('11111111-1111-1111-1111-111111111111', 'مغسلة وصل', 'wasl');

insert into branches (id, laundry_id, name_ar, location)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
        'فرع المركز', st_point(39.6142, 24.4672)::geography);

-- فرع ثانٍ — لاختبار أن موظّف فرعٍ لا يمسّ طلب فرع آخر
insert into branches (id, laundry_id, name_ar, location)
values ('22222222-2222-2222-2222-333333333333', '11111111-1111-1111-1111-111111111111',
        'فرع قباء', st_point(39.6180, 24.4390)::geography);

-- المستخدمون. المحفّز on_auth_user_created ينشئ profiles و user_roles تلقائيًا،
-- فالإدراج في auth.users وحده يجب أن يكفي — وهذا في ذاته اختبار.
insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001', '+966500000001'), -- عميل
  ('a0000000-0000-0000-0000-000000000002', '+966500000002'), -- عميل آخر
  ('a0000000-0000-0000-0000-000000000003', '+966500000003'), -- مدير فرع المركز
  ('a0000000-0000-0000-0000-000000000004', '+966500000004'), -- سائق
  ('a0000000-0000-0000-0000-000000000005', '+966500000005'), -- موظف مغسلة (المركز)
  ('a0000000-0000-0000-0000-000000000006', '+966500000006'); -- موظف مغسلة (قباء)

do $$ begin
  if (select count(*) from profiles) <> 6 then
    raise exception '✗ المحفّز: لم يُنشأ ملف شخصي لكل مستخدم';
  end if;
  if (select count(*) from user_roles where role = 'customer') <> 6 then
    raise exception '✗ المحفّز: لم يُمنح دور customer تلقائيًا';
  end if;
  raise notice '✓ المحفّز: ملف شخصي ودور customer أُنشئا لكل مستخدم جديد';
end $$;

insert into user_roles (user_id, role, laundry_id, branch_id) values
  ('a0000000-0000-0000-0000-000000000003', 'branch_manager',
   '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000004', 'driver',
   '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000005', 'laundry_staff',
   '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000006', 'laundry_staff',
   '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-333333333333');

-- قيد النطاق: مدير فرع بلا فرع يجب أن يُرفض
do $$ begin
  insert into user_roles (user_id, role) values
    ('a0000000-0000-0000-0000-000000000003', 'branch_manager');
  raise exception '✗ نطاق الدور: قُبل مدير فرع بلا فرع';
exception when check_violation then
  raise notice '✓ نطاق الدور: مدير فرع بلا فرع رُفض';
end $$;

-- الطلب
insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        'a0000000-0000-0000-0000-000000000001', 'draft', 40);

-- ═══ المسار السعيد ═══════════════════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000001');
update orders set status = 'placed' where id = '0dd00000-0000-0000-0000-000000000001';
select expect_status('0dd00000-0000-0000-0000-000000000001', 'placed', 'العميل يرسل الطلب');

do $$ begin
  if (select placed_at from orders where id = '0dd00000-0000-0000-0000-000000000001') is null then
    raise exception '✗ placed_at لم يُضبط تلقائيًا';
  end if;
  raise notice '✓ placed_at ضُبط تلقائيًا عند الإرسال';
end $$;

select auth.login_as('a0000000-0000-0000-0000-000000000003');
update orders set status = 'accepted'        where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'pickup_assigned' where id = '0dd00000-0000-0000-0000-000000000001';
select expect_status('0dd00000-0000-0000-0000-000000000001', 'pickup_assigned', 'مدير الفرع يقبل ويُسند');

select auth.login_as('a0000000-0000-0000-0000-000000000004');
update orders set status = 'pickup_en_route' where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'picked_up'       where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'at_laundry'      where id = '0dd00000-0000-0000-0000-000000000001';
select expect_status('0dd00000-0000-0000-0000-000000000001', 'at_laundry', 'السائق يستلم ويُوصل للمغسلة');

select auth.login_as('a0000000-0000-0000-0000-000000000005');
update orders set status = 'sorting'   where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'washing'   where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'drying'    where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'ironing'   where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'packaging' where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'ready'     where id = '0dd00000-0000-0000-0000-000000000001';
select expect_status('0dd00000-0000-0000-0000-000000000001', 'ready', 'خط المغسلة: فرز←غسيل←تجفيف←كوي←تغليف←جاهز');

select auth.login_as('a0000000-0000-0000-0000-000000000003');
update orders set status = 'delivery_assigned' where id = '0dd00000-0000-0000-0000-000000000001';
select auth.login_as('a0000000-0000-0000-0000-000000000004');
update orders set status = 'out_for_delivery' where id = '0dd00000-0000-0000-0000-000000000001';
update orders set status = 'delivered'        where id = '0dd00000-0000-0000-0000-000000000001';
select expect_status('0dd00000-0000-0000-0000-000000000001', 'delivered', 'التسليم للعميل');

do $$ begin
  if (select delivered_at from orders where id = '0dd00000-0000-0000-0000-000000000001') is null then
    raise exception '✗ delivered_at لم يُضبط';
  end if;
  raise notice '✓ delivered_at ضُبط تلقائيًا';
end $$;

-- سجلّ الأحداث: 15 انتقالًا من draft إلى delivered
do $$
declare n int;
begin
  select count(*) into n from order_events
  where order_id = '0dd00000-0000-0000-0000-000000000001';
  if n <> 15 then
    raise exception '✗ السجلّ: توقّعنا 15 حدثًا وجاء %', n;
  end if;
  raise notice '✓ السجلّ: 15 حدثًا مسجّلة بالمنفّذ ودوره';
end $$;

-- ═══ ما يجب أن يُرفض ═════════════════════════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        'a0000000-0000-0000-0000-000000000001', 'placed', 40);

-- القفزة: من placed إلى delivered مباشرة
select auth.login_as('a0000000-0000-0000-0000-000000000001');
select expect_fail(
  $q$update orders set status = 'delivered' where id = '0dd00000-0000-0000-0000-000000000002'$q$,
  'قفزة: placed ← delivered');

-- العميل يقبل طلبه بنفسه (accepted ليست من صلاحياته)
select expect_fail(
  $q$update orders set status = 'accepted' where id = '0dd00000-0000-0000-0000-000000000002'$q$,
  'صلاحية: العميل يقبل طلبه بنفسه');

-- عميل آخر يلغي طلبًا ليس له
select auth.login_as('a0000000-0000-0000-0000-000000000002');
select expect_fail(
  $q$update orders set status = 'cancelled' where id = '0dd00000-0000-0000-0000-000000000002'$q$,
  'ملكية: عميل يلغي طلب غيره');

-- السائق يغسل
select auth.login_as('a0000000-0000-0000-0000-000000000004');
select expect_fail(
  $q$update orders set status = 'accepted' where id = '0dd00000-0000-0000-0000-000000000002'$q$,
  'صلاحية: السائق يقبل الطلب');

-- موظّف فرع قباء يمسّ طلب فرع المركز
select auth.login_as('a0000000-0000-0000-0000-000000000003');
update orders set status = 'accepted' where id = '0dd00000-0000-0000-0000-000000000002';
update orders set status = 'pickup_assigned' where id = '0dd00000-0000-0000-0000-000000000002';
select auth.login_as('a0000000-0000-0000-0000-000000000004');
update orders set status = 'pickup_en_route' where id = '0dd00000-0000-0000-0000-000000000002';
update orders set status = 'picked_up'  where id = '0dd00000-0000-0000-0000-000000000002';
update orders set status = 'at_laundry' where id = '0dd00000-0000-0000-0000-000000000002';

select auth.login_as('a0000000-0000-0000-0000-000000000006');
select expect_fail(
  $q$update orders set status = 'sorting' where id = '0dd00000-0000-0000-0000-000000000002'$q$,
  'نطاق: موظّف قباء يفرز طلب المركز');

-- وموظّف المركز يستطيع
select auth.login_as('a0000000-0000-0000-0000-000000000005');
update orders set status = 'sorting' where id = '0dd00000-0000-0000-0000-000000000002';
select expect_status('0dd00000-0000-0000-0000-000000000002', 'sorting', 'نطاق: موظّف المركز يفرز طلب فرعه');

-- ═══ الباركود فريد ═══════════════════════════════════════════════════════
do $$ begin
  update orders set barcode = 'WSL-10001' where id = '0dd00000-0000-0000-0000-000000000001';
  update orders set barcode = 'WSL-10001' where id = '0dd00000-0000-0000-0000-000000000002';
  raise exception '✗ الباركود: قُبل تكرار';
exception when unique_violation then
  raise notice '✓ الباركود: التكرار مرفوض';
end $$;

-- ═══ عنوان فندق بلا اسم فندق ═════════════════════════════════════════════
do $$ begin
  insert into addresses (user_id, kind, location, hotel_name)
  values ('a0000000-0000-0000-0000-000000000001', 'hotel', st_point(39.61, 24.46)::geography, null);
  raise exception '✗ الزائر: قُبل عنوان فندق بلا اسم فندق';
exception when check_violation then
  raise notice '✓ الزائر: عنوان فندق ناقص رُفض';
end $$;

insert into addresses (user_id, kind, location, hotel_name, room_number, checkout_date)
values ('a0000000-0000-0000-0000-000000000001', 'hotel',
        st_point(39.6105, 24.4685)::geography, 'فندق دار الإيمان', '412', current_date + 3);
do $$ begin raise notice '✓ الزائر: عنوان فندق كامل قُبل'; end $$;

rollback;
