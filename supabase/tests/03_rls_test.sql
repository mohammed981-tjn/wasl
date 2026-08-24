-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار أمان مستوى الصفّ
-- ═══════════════════════════════════════════════════════════════════════════
-- **نقطةٌ تُبطل الاختبار إن فاتت**: المستخدم الخارق يتجاوز RLS تجاوزًا كاملًا،
-- حتى مع `force`. فاختبارٌ يُنفَّذ بـpostgres يمرّ دائمًا ولا يمسّ سياسةً واحدة.
-- ولذلك كل فحص هنا يقع بعد `set local role authenticated`.

\set ON_ERROR_STOP on
begin;

set local search_path = public, extensions;

create or replace function count_visible(q text)
returns bigint language plpgsql as $$
declare n bigint;
begin execute q into n; return n; end $$;

create or replace function assert_count(q text, expected bigint, label text)
returns void language plpgsql as $$
declare n bigint;
begin
  execute q into n;
  if n <> expected then
    raise exception '✗ %: توقّعنا % وجاء %', label, expected, n;
  end if;
  raise notice '✓ %', label;
end $$;

create or replace function expect_denied(sql_text text, label text)
returns void language plpgsql as $$
begin
  execute sql_text;
  raise exception '✗ %: نجح وكان يجب أن يُمنع', label;
exception
  when insufficient_privilege or check_violation then
    raise notice '✓ % (مُنع)', label;
end $$;

-- **الفرق الذي يوقع الجميع**: منعُ الإدراج يرفع استثناءً، ومنعُ التحديث لا
-- يرفع شيئًا — عبارةُ `using` ترشّح الصفوف، فيُحدَّث صفرٌ منها و«ينجح» الأمر.
-- ومن يقيس المنع بالتقاط استثناء يظنّ التحديثَ ممنوعًا وهو مسموح، أو يكتب
-- واجهةً تقول للمستخدم «تمّ الحفظ» ولم يُحفظ شيء. فيُقاس هنا بعدّ الصفوف.
create or replace function expect_no_rows(sql_text text, label text)
returns void language plpgsql as $$
declare n bigint;
begin
  execute sql_text;
  get diagnostics n = row_count;
  if n <> 0 then
    raise exception '✗ %: مسّ % صفًّا وكان يجب ألّا يمسّ شيئًا', label, n;
  end if;
  raise notice '✓ % (صفر صفوف)', label;
exception
  when insufficient_privilege or check_violation then
    raise notice '✓ % (مُنع باستثناء)', label;
end $$;

-- ── تجهيز (بالسياق الخادميّ) ──────────────────────────────────────────────
insert into laundries (id, name_ar, slug)
values ('11111111-1111-1111-1111-111111111111', 'مغسلة وصل', 'wasl');

insert into branches (id, laundry_id, name_ar, location) values
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
   'فرع المركز', st_point(39.6142, 24.4672)::geography),
  ('22222222-2222-2222-2222-333333333333', '11111111-1111-1111-1111-111111111111',
   'فرع قباء', st_point(39.6180, 24.4390)::geography);

insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001', '+966500000001'), -- عميل أ
  ('a0000000-0000-0000-0000-000000000002', '+966500000002'), -- عميل ب
  ('a0000000-0000-0000-0000-000000000003', '+966500000003'), -- مدير المركز
  ('a0000000-0000-0000-0000-000000000004', '+966500000004'), -- سائق المركز
  ('a0000000-0000-0000-0000-000000000005', '+966500000005'), -- موظّف قباء
  ('a0000000-0000-0000-0000-000000000009', '+966500000009'); -- super_admin

-- لا محفّز على auth.users بعد عزل المخطّط، فالملفّات تُنشأ صراحةً هنا
-- (سياق خادميّ) كما ينشئها ensure_profile عند أوّل دخول حقيقيّ.
insert into profiles (id, phone)
select id, phone from auth.users;

insert into user_roles (user_id, role, laundry_id, branch_id) values
  ('a0000000-0000-0000-0000-000000000003', 'branch_manager',
   '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000004', 'driver',
   '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000005', 'laundry_staff',
   '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-333333333333');
insert into user_roles (user_id, role) values
  ('a0000000-0000-0000-0000-000000000009', 'super_admin');

insert into service_categories (id, laundry_id, name_ar)
values ('cc000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'ملابس');
insert into services (id, laundry_id, category_id, name_ar, unit, base_price)
values ('55000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'cc000000-0000-0000-0000-000000000001', 'ثوب غسيل', 'piece', 8);

-- طلبان: أ في المركز، ب في قباء
insert into orders (id, laundry_id, branch_id, customer_id, status, total) values
  ('0dd00000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222', 'a0000000-0000-0000-0000-000000000001', 'placed', 40),
  ('0dd00000-0000-0000-0000-00000000000b', '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-333333333333', 'a0000000-0000-0000-0000-000000000002', 'placed', 60);

update orders set pickup_driver_id = 'a0000000-0000-0000-0000-000000000004'
where id = '0dd00000-0000-0000-0000-00000000000a';

insert into addresses (id, user_id, kind, location, label) values
  ('addd0000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000001',
   'home', st_point(39.62, 24.47)::geography, 'منزل أ'),
  ('addd0000-0000-0000-0000-00000000000b', 'a0000000-0000-0000-0000-000000000002',
   'home', st_point(39.61, 24.44)::geography, 'منزل ب');

set local role authenticated;

-- ═══ العميل ══════════════════════════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000001');

select assert_count('select count(*) from orders', 1::bigint,
  'العميل أ يرى طلبه وحده لا طلب ب');

select assert_count(
  $q$select count(*) from orders where id = '0dd00000-0000-0000-0000-00000000000b'$q$,
  0::bigint, 'العميل أ لا يرى طلب العميل ب إطلاقًا');

select assert_count('select count(*) from addresses', 1::bigint,
  'العميل أ يرى عنوانه وحده');

select assert_count('select count(*) from services', 1::bigint,
  'الكتالوج يُقرأ من العميل — وإلا لم يعرف ما يشتري');

-- العميل لا يغيّر سعرًا
select expect_no_rows(
  $q$update services set base_price = 1 where id = '55000000-0000-0000-0000-000000000001'$q$,
  'العميل يغيّر سعر خدمة');
select assert_count(
  $q$select count(*) from services where base_price = 8$q$, 1::bigint,
  'السعر لم يتغيّر فعلًا');

-- العميل لا يرفع الحظر عن نفسه — الثغرة التي لا تحرسها سياسة الصفّ
select expect_denied(
  $q$update profiles set blocked_at = now(), blocked_reason = 'ذاتي' where id = auth.uid()$q$,
  'العميل يمسّ حالة حظره');

-- ولا يرقّي نفسه
select expect_denied(
  $q$insert into user_roles (user_id, role) values (auth.uid(), 'super_admin')$q$,
  'العميل يمنح نفسه super_admin');

select expect_denied(
  $q$insert into user_roles (user_id, role, laundry_id, branch_id)
     values (auth.uid(), 'branch_manager', '11111111-1111-1111-1111-111111111111',
             '22222222-2222-2222-2222-222222222222')$q$,
  'العميل يمنح نفسه إدارة فرع');

-- ولا يلفّق سجلّ أحداث
select expect_denied(
  $q$insert into order_events (order_id, to_status)
     values ('0dd00000-0000-0000-0000-00000000000a', 'delivered')$q$,
  'العميل يلفّق حدثًا في السجلّ');

-- ولا يقرأ رمز التسليم
select assert_count('select count(*) from order_delivery_codes', 0::bigint,
  'رمز التسليم لا يُقرأ من أحد');

-- ═══ السائق ══════════════════════════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000004');

select assert_count('select count(*) from orders', 1::bigint,
  'السائق يرى الطلب المسنَد إليه');

select assert_count(
  $q$select count(*) from profiles where id = 'a0000000-0000-0000-0000-000000000001'$q$,
  1::bigint, 'السائق يرى بيانات عميل طلبه — يحتاج اسمًا ورقمًا');

select assert_count(
  $q$select count(*) from profiles where id = 'a0000000-0000-0000-0000-000000000002'$q$,
  0::bigint, 'السائق لا يرى عميلًا لا علاقة له به');

select assert_count(
  $q$select count(*) from addresses where id = 'addd0000-0000-0000-0000-00000000000b'$q$,
  0::bigint, 'السائق لا يرى عنوان عميل آخر');

select expect_no_rows(
  $q$update services set base_price = 1 where id = '55000000-0000-0000-0000-000000000001'$q$,
  'السائق يغيّر سعر خدمة');

-- ═══ موظّف فرع قباء ══════════════════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000005');

select assert_count('select count(*) from orders', 1::bigint,
  'موظّف قباء يرى طلبات فرعه وحده');

select assert_count(
  $q$select count(*) from orders where branch_id = '22222222-2222-2222-2222-222222222222'$q$,
  0::bigint, 'موظّف قباء لا يرى طلبات المركز');

-- الشرط الصريح في التصميم: موظّف المغسلة لا يمسّ الأسعار
select expect_no_rows(
  $q$update services set base_price = 99 where id = '55000000-0000-0000-0000-000000000001'$q$,
  'موظّف المغسلة يغيّر سعرًا');

select expect_denied(
  $q$insert into delivery_settings (branch_id, strategy, flat_delivery_fee)
     values ('22222222-2222-2222-2222-333333333333', 'flat', 0)$q$,
  'موظّف المغسلة يضبط رسوم التوصيل');

-- ═══ مدير الفرع ══════════════════════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000003');

select assert_count('select count(*) from orders', 1::bigint,
  'مدير المركز يرى طلبات فرعه');

update services set base_price = 9 where id = '55000000-0000-0000-0000-000000000001';
select assert_count(
  $q$select count(*) from services where base_price = 9$q$, 1::bigint,
  'مدير الفرع يعدّل السعر — وهذا حقّه');

insert into delivery_settings (branch_id, strategy, flat_pickup_fee, flat_delivery_fee)
values ('22222222-2222-2222-2222-222222222222', 'flat', 8, 8);
select assert_count(
  $q$select count(*) from delivery_settings$q$, 1::bigint,
  'مدير الفرع يضبط رسوم فرعه');

-- ولا يضبط رسوم فرع ليس فرعه
select expect_denied(
  $q$insert into delivery_settings (branch_id, strategy, flat_delivery_fee)
     values ('22222222-2222-2222-2222-333333333333', 'flat', 99)$q$,
  'مدير المركز يضبط رسوم فرع قباء');

-- ولا يصنع super_admin — تصعيد الامتيازات
select expect_denied(
  $q$insert into user_roles (user_id, role)
     values ('a0000000-0000-0000-0000-000000000001', 'super_admin')$q$,
  'مدير الفرع يصنع super_admin');

-- ولا يوظّف في فرع غيره
select expect_denied(
  $q$insert into user_roles (user_id, role, laundry_id, branch_id)
     values ('a0000000-0000-0000-0000-000000000001', 'laundry_staff',
             '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-333333333333')$q$,
  'مدير المركز يوظّف في فرع قباء');

-- ويوظّف في فرعه
insert into user_roles (user_id, role, laundry_id, branch_id)
values ('a0000000-0000-0000-0000-000000000001', 'laundry_staff',
        '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');
select assert_count(
  $q$select count(*) from user_roles where role = 'laundry_staff'
     and branch_id = '22222222-2222-2222-2222-222222222222'$q$,
  1::bigint, 'مدير المركز يوظّف في فرعه');

-- ═══ super_admin ═════════════════════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000009');

select assert_count('select count(*) from orders', 2::bigint,
  'super_admin يرى كل الطلبات عبر الفروع');

select assert_count('select count(*) from profiles', 6::bigint,
  'super_admin يرى كل الملفّات');

update profiles set blocked_at = now(), blocked_reason = 'اختبار'
where id = 'a0000000-0000-0000-0000-000000000001';
select assert_count(
  $q$select count(*) from profiles where blocked_at is not null$q$, 1::bigint,
  'super_admin يحظر — وهذا حقّه وحده');

-- ═══ الزائر غير المسجَّل ═════════════════════════════════════════════════
reset role;
set local role anon;
select auth.logout();

select assert_count('select count(*) from services', 1::bigint,
  'الزائر يرى الكتالوج — يتصفّح قبل أن يسجّل');

select assert_count('select count(*) from orders', 0::bigint,
  'الزائر لا يرى طلبًا واحدًا');

select assert_count('select count(*) from profiles', 0::bigint,
  'الزائر لا يرى ملفًّا واحدًا');

select expect_denied(
  $q$insert into orders (laundry_id, branch_id, customer_id, status)
     values ('11111111-1111-1111-1111-111111111111',
             '22222222-2222-2222-2222-222222222222',
             'a0000000-0000-0000-0000-000000000001', 'draft')$q$,
  'الزائر ينشئ طلبًا');

reset role;
rollback;
