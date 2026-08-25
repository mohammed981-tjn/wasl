-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار الإسناد ورمز التسليم وموقع السائق
-- ═══════════════════════════════════════════════════════════════════════════
-- **الخطر هنا ليس بطءًا بل تسليمًا لغير صاحبه**: رمزٌ يُخمَّن، أو إسنادٌ يكتبه
-- من ليس إدارة، أو سائقٌ يُتمّ تسليمًا بلا ما يُثبته — وكلُّها تنتهي بملابسٍ
-- عند بابٍ آخر وبنزاعٍ لا سند فيه.

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

create or replace function expect_denied(sql_text text, label text)
returns void language plpgsql as $$
begin
  execute sql_text;
  raise exception '✗ %: مرّ ما كان يجب أن يُرفض', label;
exception
  when insufficient_privilege or check_violation then
    raise notice '✓ %', label;
end $$;

-- منعُ التحديث بـRLS **لا يرفع استثناءً**: يمسّ صفر صفوف و«ينجح». فالفحص
-- يقع على عدد الصفوف لا على الاستثناء وحده.
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

-- ── تجهيز ────────────────────────────────────────────────────────────────
insert into laundries (id, name_ar, slug)
values ('11111111-1111-1111-1111-111111111111','مغسلة وصل','wasl');
insert into branches (id, laundry_id, name_ar, location)
values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111',
        'المركز', st_point(39.6142,24.4672)::geography),
       ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
        'قباء', st_point(39.6170,24.4390)::geography);

insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001','+966500000001'),  -- عميل
  ('a0000000-0000-0000-0000-000000000002','+966500000002'),  -- مدير الفرع
  ('a0000000-0000-0000-0000-000000000003','+966500000003'),  -- سائق المركز
  ('a0000000-0000-0000-0000-000000000004','+966500000004'),  -- سائق قباء
  ('a0000000-0000-0000-0000-000000000006','+966500000006');  -- لا دور له
insert into profiles (id, phone) select id, phone from auth.users;

insert into user_roles (user_id, role, laundry_id, branch_id) values
  ('a0000000-0000-0000-0000-000000000002','branch_manager',
   '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000003','driver',
   '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000004','driver',
   '11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333');

insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'accepted', 100);

-- ═══ ١) الإسناد فعلُ إدارة ═══════════════════════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

-- العميل يرى طلبه ويحدّثه — ولا يكتب من يوصّله.
select expect_denied($$
  update orders set pickup_driver_id = 'a0000000-0000-0000-0000-000000000003'
  where id = '0dd00000-0000-0000-0000-00000000000a'
$$, 'الإسناد: العميل لا يُسنِد سائقًا إلى طلبه');

select auth.login_as('a0000000-0000-0000-0000-000000000002');

-- ولا يُسنَد إلى من ليس سائقًا: طلبٌ في عهدة من لا يراه.
select expect_denied($$
  update orders set pickup_driver_id = 'a0000000-0000-0000-0000-000000000006'
  where id = '0dd00000-0000-0000-0000-00000000000a'
$$, 'الإسناد: لا يُسنَد إلى من ليس سائقًا');

-- ولا إلى سائق فرعٍ آخر: هو لا يرى الطلب أصلًا، فيبقى معلَّقًا بلا أثر.
select expect_denied($$
  update orders set pickup_driver_id = 'a0000000-0000-0000-0000-000000000004'
  where id = '0dd00000-0000-0000-0000-00000000000a'
$$, 'الإسناد: لا يُسنَد إلى سائق فرعٍ آخر');

update orders set pickup_driver_id = 'a0000000-0000-0000-0000-000000000003'
where id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select pickup_driver_id from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'a0000000-0000-0000-0000-000000000003'::uuid,
  'الإسناد: مدير الفرع يُسنِد إلى سائق فرعه');

-- ═══ ٢) سقف المهامّ النشطة ═══════════════════════════════════════════════
select auth.logout();
set local role postgres;
insert into driver_settings (branch_id, max_active_jobs)
values ('22222222-2222-2222-2222-222222222222', 1);

insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'accepted', 100);

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000002');

update orders set status = 'pickup_assigned'
where id = '0dd00000-0000-0000-0000-00000000000a';

select expect_denied($$
  update orders set pickup_driver_id = 'a0000000-0000-0000-0000-000000000003'
  where id = '0dd00000-0000-0000-0000-00000000000b'
$$, 'السقف: لا يُحمَّل السائق فوق سقف الفرع');

select auth.logout();
set local role postgres;
update driver_settings set max_active_jobs = 0
where branch_id = '22222222-2222-2222-2222-222222222222';

-- ═══ ٣) السائق ينفّذ مهمّته ولا يرى غيرها ════════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000003');

-- وهذا هو الفحص الذي كشف التسريب: قبل استثناء دور السائق من
-- `auth_branch_ids()` كان يرى الطلبين — المسنَد إليه وغيره.
select assert_eq(
  (select count(*)::int from orders),
  1, 'الرؤية: السائق يرى المسنَد إليه وحده لا دفتر الفرع');

update orders set status = 'pickup_en_route'
where id = '0dd00000-0000-0000-0000-00000000000a';

-- الاستلام: إثباتٌ وانتقالٌ في نداءٍ واحد.
select assert_eq(
  (complete_pickup('0dd00000-0000-0000-0000-00000000000a',
                   24.4672, 39.6142, 'استُلم من الباب') ->> 'ok')::boolean,
  true, 'الاستلام: الإثبات والانتقال في نداءٍ واحد');

select assert_eq(
  (select status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'picked_up'::order_status, 'الاستلام: الحالة انتقلت');

-- والإثبات يحمل موقع من نفّذه: «كان عند الباب» سندٌ يُحسم به نزاع.
select assert_eq(
  (select round(st_y(location::geometry)::numeric, 4) from order_proofs
   where order_id = '0dd00000-0000-0000-0000-00000000000a' and kind = 'pickup'),
  24.4672::numeric, 'الاستلام: الإثبات يحمل موقع السائق لا كلمته وحدها');

select assert_eq(
  (select note from order_events
   where order_id = '0dd00000-0000-0000-0000-00000000000a' and to_status = 'picked_up'),
  'استُلم من الباب', 'الاستلام: ملاحظة السائق تُكتب في السجلّ');

-- ═══ ٤) رمز التسليم يُولَّد عند الخروج ═══════════════════════════════════
select auth.logout();
set local role postgres;
update orders set status = 'at_laundry' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'sorting'    where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'washing'    where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'drying'     where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'packaging'  where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'ready'      where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set delivery_driver_id = 'a0000000-0000-0000-0000-000000000003',
                  status = 'delivery_assigned'
where id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select count(*)::int from order_delivery_codes
   where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  0, 'الرمز: لا يُولَّد قبل الخروج — رمزٌ يعيش يومًا في الجيب ليس رمزًا');

-- قالبٌ يحمل الرمز، وآخر جمهوره السائق: الأوّل يجب أن يمتلئ والثاني لا.
insert into notification_templates (laundry_id, trigger_status, channel, audience, body_ar)
values ('11111111-1111-1111-1111-111111111111','out_for_delivery','sms','customer',
        'طلبك #{رقم_الطلب} في الطريق. رمز الاستلام: {رمز_التسليم}'),
       ('11111111-1111-1111-1111-111111111111','out_for_delivery','push','driver',
        'خرجتَ بالطلب #{رقم_الطلب}. الرمز: {رمز_التسليم}');

update orders set status = 'out_for_delivery'
where id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select length(code_hash) from order_delivery_codes
   where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  64, 'الرمز: يُخزَّن مُجزَّأً بـsha256 لا نصًّا صريحًا');

-- ورسالةُ العميل تحمله فعلًا — أربعةُ أرقامٍ لا العنصر النائب.
do $$
declare v_body text;
begin
  select body into v_body from notifications n
  join notification_templates t on t.id = n.template_id
  where n.order_id = '0dd00000-0000-0000-0000-00000000000a' and t.audience = 'customer';

  if v_body !~ 'رمز الاستلام: [0-9]{4}$' then
    raise exception '✗ الرمز: رسالة العميل لم تحمل رمزًا (%)', v_body;
  end if;
  raise notice '✓ الرمز: يصل العميل في رسالته';
end $$;

-- ورسالةُ السائق لا تحمله: من يُفترض أن يتحقّق لا يُعطى ما يتحقّق منه.
do $$
declare v_body text;
begin
  select body into v_body from notifications n
  join notification_templates t on t.id = n.template_id
  where n.order_id = '0dd00000-0000-0000-0000-00000000000a' and t.audience = 'driver';

  if v_body ~ 'الرمز: [0-9]' then
    raise exception '✗ الرمز: وصل السائق — فصار الإثبات توقيعَ المرء على نفسه';
  end if;
  raise notice '✓ الرمز: لا يصل السائق ولو طلبه القالب';
end $$;

-- ═══ ٥) التخمين محدود، والرمز الصحيح يُستهلك مرّة ════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000003');

select assert_eq(
  (verify_delivery_code('0dd00000-0000-0000-0000-00000000000a','0000') ->> 'ok')::boolean
    or (verify_delivery_code('0dd00000-0000-0000-0000-00000000000a','1111') ->> 'ok')::boolean,
  false, 'الرمز: التخمين يفشل');

-- العدّاد يُقرأ بالسياق الخادميّ: السائق لا يقرأ جدول الرموز أصلًا (فحص ٧).
select auth.logout();
set local role postgres;
select assert_eq(
  (select attempts::int from order_delivery_codes
   where order_id = '0dd00000-0000-0000-0000-00000000000a') >= 2,
  true, 'الرمز: المحاولة الخاطئة تُحصى ولا تتراجع مع الاستثناء');
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000003');

-- والسقف يُبلَغ فيُغلق الباب حتى بالرمز الصحيح.
select auth.logout();
set local role postgres;
update driver_settings set delivery_code_max_attempts = 2
where branch_id = '22222222-2222-2222-2222-222222222222';

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000003');

select assert_eq(
  verify_delivery_code('0dd00000-0000-0000-0000-00000000000a','9999') ->> 'reason',
  'تجاوزتَ عدد المحاولات', 'الرمز: السقف يُغلق الباب على المخمِّن');

select auth.logout();
set local role postgres;
update driver_settings set delivery_code_max_attempts = 20
where branch_id = '22222222-2222-2222-2222-222222222222';
update order_delivery_codes set attempts = 0
where order_id = '0dd00000-0000-0000-0000-00000000000a';

-- ═══ ٦) التسليم لا يقع بلا رمزٍ صحيح ═════════════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000003');

select assert_eq(
  complete_delivery('0dd00000-0000-0000-0000-00000000000a','0001') ->> 'reason',
  'الرمز غير صحيح', 'التسليم: يُرفض برمزٍ خاطئ');

select assert_eq(
  (select status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'out_for_delivery'::order_status,
  'التسليم: الحالة لم تتحرّك مع الرمز الخاطئ');

-- والرمز الصحيح. والمُجزَّأ لا يُفكّ، فيُعاد ضبطه بالسياق الخادميّ إلى رمزٍ
-- معلوم — وهو نفسه ما تفعله الإدارة حين يفقد العميل رسالته.
select auth.logout();
set local role postgres;
update order_delivery_codes
   set code_hash = hash_delivery_code('0dd00000-0000-0000-0000-00000000000a','4242'),
       attempts = 0
 where order_id = '0dd00000-0000-0000-0000-00000000000a';

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000003');

select assert_eq(
  (complete_delivery('0dd00000-0000-0000-0000-00000000000a','4242', 24.47, 39.61,
                     'سُلّم لصاحبه') ->> 'ok')::boolean,
  true, 'التسليم: يقع بالرمز الصحيح');

select assert_eq(
  (select status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'delivered'::order_status, 'التسليم: الحالة انتقلت إلى «سُلّم»');

select assert_eq(
  (select otp_verified from order_proofs
   where order_id = '0dd00000-0000-0000-0000-00000000000a' and kind = 'delivery'),
  true, 'التسليم: الإثبات يشهد أن الرمز تُحقِّق منه');

select assert_eq(
  complete_delivery('0dd00000-0000-0000-0000-00000000000a','4242') ->> 'reason',
  'الرمز استُهلك', 'الرمز: لا يُستعمل مرّتين');

-- ═══ ٧) الرمز لا يُقرأ من الواجهة إطلاقًا ════════════════════════════════
select assert_eq(
  (select count(*)::int from order_delivery_codes),
  0, 'الرمز: لا سياسة قراءة ⇒ لا يُقرأ ولو من السائق نفسه');

-- ═══ ٨) موقع السائق ══════════════════════════════════════════════════════
select ping_driver_location(24.4672, 39.6142, 12.5, true);

select assert_eq(
  (select round(lat::numeric, 4) from driver_locations
   where driver_id = 'a0000000-0000-0000-0000-000000000003'),
  24.4672::numeric, 'الموقع: يُقرأ رقمًا لا نصًّا سداسيًّا');

-- والنبضة الثانية تُحدِّث ولا تُراكم: الخريطة تريد «أين هو الآن».
select ping_driver_location(24.4700, 39.6100);
select assert_eq(
  (select count(*)::int from driver_locations
   where driver_id = 'a0000000-0000-0000-0000-000000000003'),
  1, 'الموقع: صفٌّ واحدٌ يُحدَّث لا سجلٌّ يتراكم');

select expect_denied($$
  select ping_driver_location(200, 500)
$$, 'الموقع: إحداثيّةٌ مستحيلة تُرفض في القاعدة');

-- ولا يكتبه غير صاحبه: وإلّا وضع سائقٌ زميله في حيٍّ آخر وأخذ مهمّته.
select expect_no_rows($$
  update driver_locations set is_online = false
  where driver_id = 'a0000000-0000-0000-0000-000000000004'
$$, 'الموقع: لا يكتبه إلا صاحبه');

-- ويقرؤه مدير الفرع الذي يعمل فيه.
select auth.login_as('a0000000-0000-0000-0000-000000000002');
select assert_eq(
  (select count(*)::int from driver_locations
   where driver_id = 'a0000000-0000-0000-0000-000000000003'),
  1, 'الموقع: يقرؤه من يشغّل فرع السائق');

-- ولا يقرؤه العميل: موقع الناس اللحظيّ ليس بياناتٍ عامّة.
select auth.login_as('a0000000-0000-0000-0000-000000000001');
select assert_eq(
  (select count(*)::int from driver_locations),
  0, 'الموقع: لا يقرؤه العميل');

rollback;
