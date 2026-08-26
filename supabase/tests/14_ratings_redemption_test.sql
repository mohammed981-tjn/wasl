-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار التقييم وصرف نقاط الولاء
-- ═══════════════════════════════════════════════════════════════════════════
-- **خطرُ التقييم أن يُصدَّق ما لا يستحقّ التصديق**: تقييمٌ على طلبٍ لم يُسلَّم،
-- أو من غير صاحبه، أو بعد شهرين — كلُّها أرقامٌ تدخل المتوسّط وتوجّه قرارًا.
--
-- **وخطرُ النقاط أخطر**: قيمةٌ تُقبل من التطبيق تعني فاتورةً يحدّد خصمَها من
-- يدفعها.

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
  ('a0000000-0000-0000-0000-000000000001','+966500000001'),  -- صاحب الطلب
  ('a0000000-0000-0000-0000-000000000008','+966500000008'),  -- عميلٌ آخر
  ('a0000000-0000-0000-0000-000000000003','+966500000003');  -- سائق
insert into profiles (id, phone) select id, phone from auth.users;
insert into user_roles (user_id, role, laundry_id, branch_id)
values ('a0000000-0000-0000-0000-000000000003','driver',
        '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');

insert into loyalty_settings (laundry_id, points_per_riyal, riyal_per_point,
                              min_points_to_redeem, max_redeem_percent)
values ('11111111-1111-1111-1111-111111111111', 1, 0.10, 100, 50);

-- طلبٌ مُسلَّم لصاحبه
insert into orders (id, laundry_id, branch_id, customer_id, status, total,
                    delivery_driver_id, delivered_at)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'delivered', 200, 'a0000000-0000-0000-0000-000000000003', now());

-- ═══ ١) لا يُقيَّم إلا طلبٌ سُلّم ════════════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'washing', 150);

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

do $$ begin
  insert into order_ratings (order_id, customer_id, branch_id, stars)
  values ('0dd00000-0000-0000-0000-00000000000b',
          'a0000000-0000-0000-0000-000000000001',
          '22222222-2222-2222-2222-222222222222', 5);
  raise exception '✗ الحالة: قُيّم طلبٌ ما زال في الغسيل';
exception when check_violation then
  raise notice '✓ الحالة: لا يُقيَّم إلا المسلَّم';
end $$;

-- ═══ ٢) ولا يقيّمه إلا صاحبه ════════════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000008');
do $$ begin
  insert into order_ratings (order_id, customer_id, branch_id, stars)
  values ('0dd00000-0000-0000-0000-00000000000a',
          'a0000000-0000-0000-0000-000000000008',
          '22222222-2222-2222-2222-222222222222', 1);
  raise exception '✗ الملكيّة: قيّم غريبٌ طلبَ غيره';
exception when insufficient_privilege or check_violation then
  raise notice '✓ الملكيّة: لا يقيّم أحدٌ طلبَ غيره';
end $$;

-- ═══ ٣) التقييم الصحيح، والحقول تُملأ من الطلب ══════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000001');

-- يُرسَل فرعٌ خاطئ عمدًا: الحارس يستبدله بفرع الطلب.
insert into order_ratings (order_id, customer_id, branch_id, stars,
                           delivery_stars, tags, comment)
values ('0dd00000-0000-0000-0000-00000000000a',
        'a0000000-0000-0000-0000-000000000008',      -- عميلٌ خاطئ
        '00000000-0000-0000-0000-000000000000',      -- فرعٌ لا وجود له
        4, 5, array['سريع'], 'شكرًا');

select assert_eq(
  (select customer_id from order_ratings),
  'a0000000-0000-0000-0000-000000000001'::uuid,
  'التعبئة: العميل يُؤخذ من الطلب لا ممّا أُرسل');

select assert_eq(
  (select branch_id from order_ratings),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'التعبئة: الفرع من الطلب — وإلّا أفسد متوسّط فرعٍ لم يخدمه');

select assert_eq(
  (select driver_id from order_ratings),
  'a0000000-0000-0000-0000-000000000003'::uuid,
  'التعبئة: السائق يُجمَّد لحظة التقييم');

-- ═══ ٤) تقييمٌ واحدٌ لكل طلب ════════════════════════════════════════════
do $$ begin
  insert into order_ratings (order_id, customer_id, branch_id, stars)
  values ('0dd00000-0000-0000-0000-00000000000a',
          'a0000000-0000-0000-0000-000000000001',
          '22222222-2222-2222-2222-222222222222', 1);
  raise exception '✗ التفرّد: قُبل تقييمٌ ثانٍ لنفس الطلب';
exception when unique_violation then
  raise notice '✓ التفرّد: تقييمٌ واحدٌ لكل طلب لا سجلُّ محاولات';
end $$;

-- والتعديل داخل النافذة مسموح: من غيّر رأيه بعد ساعةٍ يُسمَع.
update order_ratings set stars = 5, comment = 'أفضل ممّا ظننت'
where order_id = '0dd00000-0000-0000-0000-00000000000a';

select assert_eq(
  (select stars::int from order_ratings), 5,
  'التعديل: داخل النافذة يُسمع');

-- ═══ ٥) وبعد النافذة يُقفل ══════════════════════════════════════════════
select auth.logout();
set local role postgres;
insert into feedback_settings (laundry_id, window_days)
values ('11111111-1111-1111-1111-111111111111', 7);
-- يُقدَّم التسليم شهرين إلى الوراء.
update orders set delivered_at = now() - interval '60 days'
where id = '0dd00000-0000-0000-0000-00000000000a';

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

do $$ begin
  update order_ratings set stars = 1
  where order_id = '0dd00000-0000-0000-0000-00000000000a';
  raise exception '✗ النافذة: عُدِّل تقييمٌ بعد شهرين';
exception when check_violation then
  raise notice '✓ النافذة: بعدها يُقفل التقييم ويبقى شهادة';
end $$;

-- ═══ ٦) الملخّص يُعيد التوزيع لا المتوسّط وحده ══════════════════════════
select auth.logout();
set local role postgres;
update orders set delivered_at = now() where id = '0dd00000-0000-0000-0000-00000000000a';

-- طلبٌ ثانٍ بنجمةٍ واحدة: المتوسّط يصير ٣، والشكوى يجب أن تُعدّ وحدها.
insert into orders (id, laundry_id, branch_id, customer_id, status, total, delivered_at)
values ('0dd00000-0000-0000-0000-00000000000c','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'delivered', 100, now());
insert into order_ratings (order_id, customer_id, branch_id, stars)
values ('0dd00000-0000-0000-0000-00000000000c',
        'a0000000-0000-0000-0000-000000000001',
        '22222222-2222-2222-2222-222222222222', 1);

select assert_eq(
  (select ratings_count from rating_summary('22222222-2222-2222-2222-222222222222')),
  2, 'الملخّص: يعدّ التقييمات');

select assert_eq(
  (select avg_stars from rating_summary('22222222-2222-2222-2222-222222222222')),
  3.00::numeric, 'الملخّص: المتوسّط يُحسب');

select assert_eq(
  (select low_count from rating_summary('22222222-2222-2222-2222-222222222222')),
  1, 'الملخّص: الشكوى تُعدّ وحدها — والمتوسّط يخفيها');

select assert_eq(
  (select stars_1 from rating_summary('22222222-2222-2222-2222-222222222222')),
  1, 'الملخّص: التوزيع يُعاد كاملًا');

-- ═══ ٧) صرف النقاط: القيمة من القاعدة لا من التطبيق ═════════════════════
insert into loyalty_transactions (user_id, laundry_id, kind, points, note)
values ('a0000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'earn', 1000, 'رصيد سابق');

insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, delivery_fee, discount_amount, vat_amount, total)
values ('0dd00000-0000-0000-0000-00000000000d','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'draft', 200, 15, 0, 0, 215);

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

-- يطلب صرف ١٠٠٠ نقطة (= ١٠٠ ريال)، والسقف نصفُ المبلغ الأساس (= ١٠٠ ريال).
do $$
declare r jsonb;
begin
  r := redeem_loyalty_on_order('0dd00000-0000-0000-0000-00000000000d', 1000);
  if not (r ->> 'ok')::boolean then
    raise exception '✗ الصرف: رُفض (%)', r ->> 'reason';
  end if;
  raise notice '✓ الصرف: % نقطة = % ريال', r ->> 'points', r ->> 'riyal';
end $$;

select assert_eq(
  (select total from orders where id = '0dd00000-0000-0000-0000-00000000000d'),
  115.00::numeric, 'الصرف: الإجماليّ نقص بقيمة النقاط لا بما أرسله التطبيق');

select assert_eq(
  (select loyalty_balance('a0000000-0000-0000-0000-000000000001',
                          '11111111-1111-1111-1111-111111111111')),
  0, 'الصرف: الرصيد نقص');

-- ولا يُصرف مرّتين على طلبٍ واحد.
select assert_eq(
  redeem_loyalty_on_order('0dd00000-0000-0000-0000-00000000000d', 100) ->> 'reason',
  'صُرفت نقاطٌ على هذا الطلب', 'الصرف: لا يتكرّر على الطلب نفسه');

-- ═══ ٨) ولا يُصرف على طلبٍ أُرسل ════════════════════════════════════════
select auth.logout();
set local role postgres;
insert into loyalty_transactions (user_id, laundry_id, kind, points, note)
values ('a0000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'earn', 500, 'رصيد آخر');

insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, total)
values ('0dd00000-0000-0000-0000-00000000000e','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'placed', 300, 300);

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

select assert_eq(
  redeem_loyalty_on_order('0dd00000-0000-0000-0000-00000000000e', 500) ->> 'reason',
  'لا تُصرف النقاط بعد إرسال الطلب',
  'الصرف: بعد الإرسال تُجمَّد المبالغ فلا يُخصم منها');

-- ═══ ٩) ولا يصرف أحدٌ من رصيد غيره ══════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000008');
do $$ begin
  perform redeem_loyalty_on_order('0dd00000-0000-0000-0000-00000000000d', 100);
  raise exception '✗ الملكيّة: صرف غريبٌ على طلبٍ ليس له';
exception when insufficient_privilege then
  raise notice '✓ الملكيّة: لا يصرف أحدٌ على طلب غيره';
end $$;

rollback;
