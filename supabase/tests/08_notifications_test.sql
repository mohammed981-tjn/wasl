-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار الإشعارات
-- ═══════════════════════════════════════════════════════════════════════════
-- ما يُختبر: أن النصّ يأتي من الجدول لا من الشيفرة، وأن الطابور لا يربط نجاح
-- الطلب بنجاح مزوّد الإشعارات، وأن إيقاف التسويق لا يُوقِف رسائل الطلب.

\set ON_ERROR_STOP on
begin;

set local search_path = wasl, public, extensions;

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
        'فرع قباء', st_point(39.6,24.4)::geography);
insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001','+966500000001'),
  ('a0000000-0000-0000-0000-000000000004','+966500000004');
insert into profiles (id, phone) select id, phone from auth.users;

-- ═══ ١) التفضيلات تُنشأ مع الملفّ ════════════════════════════════════════
select assert_eq(
  (select count(*)::int from notification_preferences),
  2, 'التفضيلات: صفٌّ لكل ملفّ شخصيّ تلقائيًّا');

-- ═══ ٢) القوالب ═════════════════════════════════════════════════════════
insert into notification_templates (laundry_id, trigger_status, channel, audience, title_ar, body_ar) values
  ('11111111-1111-1111-1111-111111111111','picked_up','push','customer',
   'تم استلام ملابسك','استلمنا طلبك رقم {رقم_الطلب} من {الفرع}.'),
  ('11111111-1111-1111-1111-111111111111','picked_up','sms','customer',
   null,'وصل: استلمنا طلبك {رقم_الطلب}.'),
  ('11111111-1111-1111-1111-111111111111','ready','push','customer',
   'طلبك جاهز','طلبك {رقم_الطلب} جاهز. الإجمالي {الإجمالي} ريال.'),
  ('11111111-1111-1111-1111-111111111111','delivered','push','customer',
   'تم التسليم','سلّمنا طلبك {رقم_الطلب}. شكرًا لك.');

select assert_eq(
  (select render_template('طلبك {رقم_الطلب} جاهز في {الفرع}',
     '{"رقم_الطلب":"10042","الفرع":"قباء"}'::jsonb)),
  'طلبك 10042 جاهز في قباء', 'القالب: المتغيّرات تُملأ');

select assert_eq(
  (select render_template('لا متغيّر هنا', '{"س":"ص"}'::jsonb)),
  'لا متغيّر هنا', 'القالب: نصٌّ بلا متغيّرات يمرّ كما هو');

-- ═══ ٣) الصفّ عند تغيّر الحالة ═══════════════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'placed', 88);

update orders set status = 'accepted'        where id = '0dd00000-0000-0000-0000-00000000000a';
select assert_eq(
  (select count(*)::int from notifications),
  0, 'الطابور: حالةٌ بلا قالب لا تُصفّ شيئًا');

update orders set status = 'pickup_assigned' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'pickup_en_route' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'picked_up'       where id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select count(*)::int from notifications where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  2, 'الطابور: قالبان لحالة picked_up ⇒ رسالتان (push + sms)');

select assert_eq(
  (select body from notifications where channel = 'push'
   and order_id = '0dd00000-0000-0000-0000-00000000000a'),
  'استلمنا طلبك رقم ' ||
    (select order_number::text from orders where id = '0dd00000-0000-0000-0000-00000000000a')
    || ' من فرع قباء.',
  'الطابور: المتغيّرات مملوءةٌ بقيم الطلب الحقيقية');

select assert_eq(
  (select distinct status from notifications where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  'queued'::notification_status, 'الطابور: تُصفّ ولا تُرسل — الحالة تُحفظ ولو تعطّل المزوّد');

-- ═══ ٤) الإجمالي في القالب ═══════════════════════════════════════════════
update orders set status = 'at_laundry' where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'sorting'    where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'washing'    where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'drying'     where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'packaging'  where id = '0dd00000-0000-0000-0000-00000000000a';
update orders set status = 'ready'      where id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select body from notifications where template_id in
     (select id from notification_templates where trigger_status = 'ready')),
  'طلبك ' || (select order_number::text from orders where id = '0dd00000-0000-0000-0000-00000000000a')
    || ' جاهز. الإجمالي 88.00 ريال.',
  'القالب: الإجمالي يُملأ من الطلب');

-- ═══ ٥) التفضيلات تُحترم — والرسالة المتخطّاة تُسجَّل لا تُطمس ═══════════
update notification_preferences set sms_enabled = false
where user_id = 'a0000000-0000-0000-0000-000000000001';

insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'placed', 50);
update orders set status = 'accepted'        where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'pickup_assigned' where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'pickup_en_route' where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'picked_up'       where id = '0dd00000-0000-0000-0000-00000000000b';

select assert_eq(
  (select status from notifications
   where order_id = '0dd00000-0000-0000-0000-00000000000b' and channel = 'sms'),
  'skipped'::notification_status, 'التفضيلات: من أوقف الرسائل النصّية تُسجَّل رسالته skipped');

select assert_eq(
  (select status from notifications
   where order_id = '0dd00000-0000-0000-0000-00000000000b' and channel = 'push'),
  'queued'::notification_status, 'التفضيلات: وقناة الدفع ما زالت تعمل');

-- إيقاف التسويق لا يُوقِف رسائل الطلب: الأولى إزعاجٌ يُرفض، والثانية خدمةٌ اشتُريت
select assert_eq(
  (select marketing_opt_in from notification_preferences
   where user_id = 'a0000000-0000-0000-0000-000000000001'),
  false, 'الفصل: التسويق موقوفٌ افتراضًا');
select assert_eq(
  (select count(*)::int from notifications
   where order_id = '0dd00000-0000-0000-0000-00000000000b' and status = 'queued'),
  1, 'الفصل: ورسائل الطلب تصل رغم إيقاف التسويق');

-- ═══ ٦) القالب الموقوف لا يُرسل ══════════════════════════════════════════
update notification_templates set is_active = false where trigger_status = 'delivered';

update orders set status = 'at_laundry'        where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'sorting'           where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'washing'           where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'drying'            where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'packaging'         where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'ready'             where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'delivery_assigned' where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'out_for_delivery'  where id = '0dd00000-0000-0000-0000-00000000000b';
update orders set status = 'delivered'         where id = '0dd00000-0000-0000-0000-00000000000b';

select assert_eq(
  (select count(*)::int from notifications
   where order_id = '0dd00000-0000-0000-0000-00000000000b'
     and body like '%سلّمنا%'),
  0, 'الإيقاف: قالبٌ موقوف لا يُصفّ رسالة');

-- ═══ ٧) الأمان ═══════════════════════════════════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

select assert_eq(
  (select count(*)::int from notifications where user_id <> auth.uid()),
  0, 'الأمان: العميل لا يرى رسائل غيره');

-- يعلّمها مقروءة
update notifications set read_at = now()
where user_id = auth.uid() and read_at is null;
do $$ begin
  if (select count(*) from notifications where read_at is null and user_id = auth.uid()) > 0 then
    raise exception '✗ القراءة: لم تُعلَّم مقروءة';
  end if;
  raise notice '✓ القراءة: صاحب الرسالة يعلّمها مقروءة';
end $$;

-- ولا يعيد كتابة نصّها
do $$ begin
  update notifications set body = 'خصم ١٠٠٪ لك وحدك'
  where user_id = auth.uid();
  raise exception '✗ الأمان: العميل أعاد كتابة نصّ رسالته';
exception when insufficient_privilege then
  raise notice '✓ الأمان: العميل لا يعيد كتابة نصّ الرسالة';
end $$;

-- ولا ينشئ رسالةً باسم المغسلة
do $$ begin
  insert into notifications (user_id, channel, body)
  values (auth.uid(),'push','رسالة ملفَّقة');
  raise exception '✗ الأمان: العميل أنشأ إشعارًا باسم المغسلة';
exception when insufficient_privilege or check_violation then
  raise notice '✓ الأمان: العميل لا يُنشئ إشعارًا';
end $$;

-- ورمز جهازه له وحده
insert into device_tokens (user_id, token, platform)
values (auth.uid(), 'tok_abc', 'android');
do $$ begin
  insert into device_tokens (user_id, token, platform)
  values ('a0000000-0000-0000-0000-000000000004','tok_xyz','ios');
  raise exception '✗ الأمان: سجّل رمز جهازٍ لمستخدم آخر';
exception when insufficient_privilege or check_violation then
  raise notice '✓ الأمان: لا يسجّل رمز جهازٍ لغيره';
end $$;

reset role;
rollback;
