-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار الكوبونات ونقاط الولاء
-- ═══════════════════════════════════════════════════════════════════════════
-- الخصم مالٌ يخرج. وأخطر ما فيه ليس حساب النسبة بل الحدود: كوبونٌ بلا سقف
-- يُنشر في مجموعة واتساب فيُستهلك آلافًا في ساعة، وخصمٌ يتجاوز الفاتورة يجعل
-- المغسلة تدفع للعميل.

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
insert into branches (id, laundry_id, name_ar, location) values
  ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111','المركز',st_point(39.6,24.4)::geography),
  ('22222222-2222-2222-2222-333333333333','11111111-1111-1111-1111-111111111111','قباء',st_point(39.6,24.4)::geography);

insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001','+966500000001'),
  ('a0000000-0000-0000-0000-000000000002','+966500000002');
insert into profiles (id, phone) select id, phone from auth.users;

-- ═══ الكوبونات ═══════════════════════════════════════════════════════════

-- ١) نسبة بسقف — «٥٠٪ بحدّ أقصى ٣٠ ريال»
insert into coupons (id, laundry_id, code, kind, value, max_discount)
values ('c0000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
        'HALF50','percentage',50,30);

select assert_eq(
  (select discount from quote_coupon('HALF50','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',40,10)),
  20::numeric, 'نسبة: ٥٠٪ من ٤٠ = ٢٠');

select assert_eq(
  (select discount from quote_coupon('HALF50','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',1000,10)),
  30::numeric, 'السقف: ٥٠٪ من ١٠٠٠ يُقصّ إلى ٣٠ — لا يبتلع فاتورة السجّاد');

-- الرمز غير حسّاس لحالة الأحرف والمسافات
select assert_eq(
  (select valid from quote_coupon('  half50  ','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',40,10)),
  true, 'الرمز: يقبل الأحرف الصغيرة والمسافات');

-- ٢) مبلغ ثابت لا يتجاوز الفاتورة
insert into coupons (id, laundry_id, code, kind, value)
values ('c0000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',
        'FLAT50','fixed',50);

select assert_eq(
  (select discount from quote_coupon('FLAT50','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',30,10)),
  30::numeric, 'المبلغ: خصم ٥٠ على فاتورة ٣٠ يخصم ٣٠ — لا إجمالي سالب');

-- ٣) توصيل مجاني يخصم رسم التوصيل لا الفاتورة
insert into coupons (id, laundry_id, code, kind)
values ('c0000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111',
        'FREESHIP','free_delivery');

select assert_eq(
  (select discount from quote_coupon('FREESHIP','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',80,15)),
  15::numeric, 'توصيل مجاني: يخصم رسم التوصيل (١٥) لا الفاتورة');

-- ٤) الحدّ الأدنى
insert into coupons (id, laundry_id, code, kind, value, min_subtotal)
values ('c0000000-0000-0000-0000-000000000004','11111111-1111-1111-1111-111111111111',
        'OVER100','fixed',20,100);

select assert_eq(
  (select valid from quote_coupon('OVER100','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',99,0)),
  false, 'الحدّ الأدنى: ٩٩ ريال ترفض كوبون المئة');

select assert_eq(
  (select reason from quote_coupon('OVER100','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',99,0)),
  'الكوبون يبدأ من 100.00 ريال', 'الحدّ الأدنى: السبب يُقال بالرقم');

-- ٥) انتهاء الصلاحية
insert into coupons (id, laundry_id, code, kind, value, starts_at, ends_at)
values ('c0000000-0000-0000-0000-000000000005','11111111-1111-1111-1111-111111111111',
        'OLD','fixed',10, now() - interval '10 days', now() - interval '1 day');

select assert_eq(
  (select reason from quote_coupon('OLD','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',100,0)),
  'انتهت صلاحية الكوبون', 'الصلاحية: المنتهي يُرفض بسببه — لا «رمز خاطئ»');

-- ٦) نطاق الفرع
insert into coupons (id, laundry_id, code, kind, value, branch_id)
values ('c0000000-0000-0000-0000-000000000006','11111111-1111-1111-1111-111111111111',
        'QUBA','fixed',10,'22222222-2222-2222-2222-333333333333');

select assert_eq(
  (select valid from quote_coupon('QUBA','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',100,0)),
  false, 'النطاق: كوبون قباء لا يعمل في المركز');
select assert_eq(
  (select valid from quote_coupon('QUBA','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-333333333333','a0000000-0000-0000-0000-000000000001',100,0)),
  true, 'النطاق: ويعمل في قباء');

-- ٧) الحدود بالاستخدام
insert into coupons (id, laundry_id, code, kind, value, max_uses_total, max_uses_per_user)
values ('c0000000-0000-0000-0000-000000000007','11111111-1111-1111-1111-111111111111',
        'LIMITED','fixed',5,2,1);

insert into orders (id, laundry_id, branch_id, customer_id, status) values
  ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001','placed'),
  ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001','placed'),
  ('0dd00000-0000-0000-0000-00000000000c','11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000002','placed');

insert into coupon_redemptions (coupon_id, user_id, order_id, amount)
values ('c0000000-0000-0000-0000-000000000007','a0000000-0000-0000-0000-000000000001',
        '0dd00000-0000-0000-0000-00000000000a',5);

select assert_eq(
  (select reason from quote_coupon('LIMITED','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',100,0)),
  'استعملت هذا الكوبون من قبل', 'حدّ العميل: مرّة واحدة لكل عميل');

select assert_eq(
  (select valid from quote_coupon('LIMITED','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000002',100,0)),
  true, 'حدّ العميل: عميلٌ آخر ما زال يستطيع');

insert into coupon_redemptions (coupon_id, user_id, order_id, amount)
values ('c0000000-0000-0000-0000-000000000007','a0000000-0000-0000-0000-000000000002',
        '0dd00000-0000-0000-0000-00000000000c',5);

select assert_eq(
  (select reason from quote_coupon('LIMITED','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222',
     (select id from profiles where phone = '+966500000001'),100,0)),
  'استُهلك الكوبون بالكامل', 'الحدّ الكلّي: استُهلك بعد مرّتين');

-- والقيد الفريد يحسم السباق: كوبونٌ مرّتين على الطلب نفسه مستحيل في القاعدة
do $$ begin
  insert into coupon_redemptions (coupon_id, user_id, order_id, amount)
  values ('c0000000-0000-0000-0000-000000000007','a0000000-0000-0000-0000-000000000001',
          '0dd00000-0000-0000-0000-00000000000a',5);
  raise exception '✗ السباق: قُبل استهلاك الكوبون مرّتين على الطلب نفسه';
exception when unique_violation then
  raise notice '✓ السباق: القيد الفريد يمنع استهلاك الكوبون مرّتين على طلب واحد';
end $$;

-- ٨) كوبون أوّل طلب
insert into coupons (id, laundry_id, code, kind, value, first_order_only)
values ('c0000000-0000-0000-0000-000000000008','11111111-1111-1111-1111-111111111111',
        'WELCOME','percentage',30,true);

select assert_eq(
  (select reason from quote_coupon('WELCOME','11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',100,0)),
  'الكوبون لأول طلب فقط', 'أوّل طلب: من له طلبٌ سابق يُرفض');

-- ═══ نقاط الولاء ═════════════════════════════════════════════════════════
insert into loyalty_settings (laundry_id, points_per_riyal, riyal_per_point,
                              min_points_to_redeem, max_redeem_percent)
values ('11111111-1111-1111-1111-111111111111', 1, 0.10, 100, 50);

-- ٩) الكسب عند التسليم لا عند الطلب
insert into orders (id, laundry_id, branch_id, customer_id, status, subtotal, discount_amount, total)
values ('0dd00000-0000-0000-0000-0000000000d1','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'placed', 200, 50, 150);

select assert_eq(loyalty_balance('a0000000-0000-0000-0000-000000000001',
                                 '11111111-1111-1111-1111-111111111111'),
  0, 'الكسب: لا نقطة عند الطلب — النقاط تُمنح على طلبٍ قد يُلغى');

-- تُنقل عبر المراحل حتى التسليم (بالسياق الخادميّ)
update orders set status = 'accepted'          where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'pickup_assigned'   where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'pickup_en_route'   where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'picked_up'         where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'at_laundry'        where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'sorting'           where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'washing'           where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'drying'            where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'packaging'         where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'ready'             where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'delivery_assigned' where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'out_for_delivery'  where id = '0dd00000-0000-0000-0000-0000000000d1';
update orders set status = 'delivered'         where id = '0dd00000-0000-0000-0000-0000000000d1';

-- ٢٠٠ ريال ناقصَ خصم ٥٠ = ١٥٠ ⇒ ١٥٠ نقطة
select assert_eq(loyalty_balance('a0000000-0000-0000-0000-000000000001',
                                 '11111111-1111-1111-1111-111111111111'),
  150, 'الكسب: على المبلغ بعد الخصم (٢٠٠−٥٠) لا قبله');

select assert_eq(
  (select loyalty_points_earned from orders where id = '0dd00000-0000-0000-0000-0000000000d1'),
  150, 'الكسب: مسجَّل على الطلب نفسه');

-- ١٠) الصرف محدودٌ بنسبة الفاتورة
-- ١٥٠ نقطة = ١٥ ريال، لكن سقف نصف فاتورةٍ من ٢٠ ريالًا = ١٠
select assert_eq(
  (select riyal_value from quote_loyalty_redemption(
     'a0000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111', 20)),
  10::numeric, 'الصرف: سقف نصف الفاتورة يقصّ ١٥ ريالًا إلى ١٠');

select assert_eq(
  (select riyal_value from quote_loyalty_redemption(
     'a0000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111', 500)),
  15::numeric, 'الصرف: على فاتورةٍ كبيرة يُصرف الرصيد كلّه (١٥ ريالًا)');

-- ١١) الحدّ الأدنى للصرف
insert into loyalty_transactions (user_id, laundry_id, kind, points, note)
values ('a0000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',
        'earn', 40, 'اختبار');

select assert_eq(
  (select points_to_spend from quote_loyalty_redemption(
     'a0000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111', 100)),
  0, 'الحدّ الأدنى: ٤٠ نقطة لا تُصرف والحدّ ١٠٠');

-- ١٢) النقاط المنتهية لا تُحسب في الرصيد
insert into loyalty_transactions (user_id, laundry_id, kind, points, note, expires_at)
values ('a0000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111',
        'earn', 500, 'منتهية', now() - interval '1 day');

select assert_eq(loyalty_balance('a0000000-0000-0000-0000-000000000002',
                                 '11111111-1111-1111-1111-111111111111'),
  40, 'الانتهاء: ٥٠٠ نقطة منتهية لا تدخل الرصيد');

-- ١٣) العميل لا يكتب نقاطه — من يكتب نقاطه يكتب مالًا
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

do $$ begin
  insert into loyalty_transactions (user_id, laundry_id, kind, points, note)
  values (auth.uid(),'11111111-1111-1111-1111-111111111111','earn', 99999, 'هدية لنفسي');
  raise exception '✗ الأمان: العميل سكّ نقاطًا لنفسه';
exception when insufficient_privilege or check_violation then
  raise notice '✓ الأمان: العميل لا يسكّ نقاطًا لنفسه';
end $$;

select assert_eq(
  (select count(*)::int from loyalty_transactions
   where user_id = 'a0000000-0000-0000-0000-000000000002'),
  0, 'الأمان: العميل لا يرى حركات نقاط غيره');

reset role;
rollback;
