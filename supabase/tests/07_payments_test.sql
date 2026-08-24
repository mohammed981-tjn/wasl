-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار المدفوعات والاسترداد والضريبة
-- ═══════════════════════════════════════════════════════════════════════════
-- خطأٌ هنا يخرج مالًا لا يعود، أو يضاعف إيرادًا في تقرير. فما يُختبر هو
-- الحدود: سقف الاسترداد، وتكرار الـwebhook، ومن يملك أن يكتب دفعة.

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
        'المركز', st_point(39.6,24.4)::geography);
insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001','+966500000001'),
  ('a0000000-0000-0000-0000-000000000009','+966500000009');
insert into profiles (id, phone) select id, phone from auth.users;
insert into user_roles (user_id, role) values ('a0000000-0000-0000-0000-000000000009','super_admin');

insert into payment_providers (id, laundry_id, code, display_name_ar, methods, is_default, publishable_key)
values ('99000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',
        'moyasar','ميسر','{card,apple_pay}',true,'pk_test_xxx');

insert into orders (id, laundry_id, branch_id, customer_id, status, subtotal, delivery_fee, total)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'placed', 100, 15, 115);

-- ═══ ١) حالة الدفع مشتقّة لا مكتوبة ══════════════════════════════════════
select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'unpaid'::payment_status, 'الحالة: طلبٌ بلا دفعة = غير مدفوع');

insert into payments (id, order_id, provider_id, method, status, amount, provider_ref)
values ('0aa00000-0000-0000-0000-000000000001','0dd00000-0000-0000-0000-00000000000a',
        '99000000-0000-0000-0000-000000000001','card','pending',115,'moy_pending_1');

select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'unpaid'::payment_status, 'الحالة: دفعةٌ معلّقة لا تجعله مدفوعًا');

update payments set status = 'authorized', authorized_at = now()
where id = '0aa00000-0000-0000-0000-000000000001';
select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'authorized'::payment_status, 'الحالة: محجوزٌ ولم يُقبض = authorized');

update payments set status = 'captured', captured_at = now()
where id = '0aa00000-0000-0000-0000-000000000001';
select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'paid'::payment_status, 'الحالة: قُبض المبلغ كاملًا = مدفوع');

-- ═══ ٢) الدفعة الجزئية ليست دفعًا ════════════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status, subtotal, total)
values ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'placed', 200, 200);
insert into payments (order_id, method, status, amount, provider_ref)
values ('0dd00000-0000-0000-0000-00000000000b','card','captured',50,'moy_partial');

select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000b'),
  'unpaid'::payment_status, 'الحالة: ٥٠ من ٢٠٠ ليست دفعًا — لا تُعلَن مدفوعة');

-- ═══ ٣) تكرار الـwebhook ═════════════════════════════════════════════════
-- البوّابات تعيد الإرسال عند غياب الإقرار. والتسجيل المكرّر يضاعف الإيراد.
do $$ begin
  insert into payments (order_id, method, status, amount, provider_ref)
  values ('0dd00000-0000-0000-0000-00000000000a','card','captured',115,'moy_pending_1');
  raise exception '✗ التكرار: سُجّلت العملية نفسها مرّتين — الإيراد تضاعف';
exception when unique_violation then
  raise notice '✓ التكرار: معرّف المزوّد الفريد يمنع تسجيل webhook مرّتين';
end $$;

-- ═══ ٤) سقف الاسترداد ════════════════════════════════════════════════════
insert into refunds (payment_id, order_id, amount, reason, status)
values ('0aa00000-0000-0000-0000-000000000001','0dd00000-0000-0000-0000-00000000000a',
        40,'قطعة تالفة','completed');

select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'partially_refunded'::payment_status, 'الاسترداد: جزئيٌّ يجعل الحالة partially_refunded');

-- جزئيٌّ ثانٍ ممكن ما دام المجموع تحت الأصل
insert into refunds (payment_id, order_id, amount, reason, status)
values ('0aa00000-0000-0000-0000-000000000001','0dd00000-0000-0000-0000-00000000000a',
        30,'تأخير','completed');
select assert_eq(
  (select sum(amount) from refunds where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  70::numeric, 'الاسترداد: جزئيّان (٤٠+٣٠) مقبولان تحت الأصل ١١٥');

-- والثالث الذي يتجاوز يُرفض
do $$ begin
  insert into refunds (payment_id, order_id, amount, reason, status)
  values ('0aa00000-0000-0000-0000-000000000001','0dd00000-0000-0000-0000-00000000000a',
          50,'محاولة تجاوز','completed');
  raise exception '✗ السقف: خرج مالٌ يتجاوز المقبوض';
exception when check_violation then
  raise notice '✓ السقف: ٧٠+٥٠ يتجاوز ١١٥ — رُفض في القاعدة';
end $$;

-- واستردادٌ كامل يقلب الحالة
insert into refunds (payment_id, order_id, amount, reason, status)
values ('0aa00000-0000-0000-0000-000000000001','0dd00000-0000-0000-0000-00000000000a',
        45,'إلغاء','completed');
select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'refunded'::payment_status, 'الاسترداد: بلوغ الأصل (١١٥) يجعلها refunded');

-- ولا استرداد من دفعةٍ لم تُقبض
insert into payments (id, order_id, method, status, amount, provider_ref)
values ('0aa00000-0000-0000-0000-000000000009','0dd00000-0000-0000-0000-00000000000b',
        'card','failed',200,'moy_failed');
do $$ begin
  insert into refunds (payment_id, order_id, amount, reason)
  values ('0aa00000-0000-0000-0000-000000000009','0dd00000-0000-0000-0000-00000000000b',
          10,'من دفعةٍ فاشلة');
  raise exception '✗ الاسترداد: قُبل من دفعةٍ لم تُقبض';
exception when check_violation then
  raise notice '✓ الاسترداد: لا يخرج مالٌ من دفعةٍ لم تُقبض';
end $$;

-- ═══ ٥) الضريبة: شاملة أم مضافة ══════════════════════════════════════════
insert into tax_settings (laundry_id, vat_percent, prices_include_vat)
values ('11111111-1111-1111-1111-111111111111', 15, true);

select assert_eq(
  (select vat_amount from compute_vat('11111111-1111-1111-1111-111111111111', 115)),
  15::numeric, 'الضريبة شاملة: من ١١٥ تُستخرج ١٥');
select assert_eq(
  (select total from compute_vat('11111111-1111-1111-1111-111111111111', 115)),
  115::numeric, 'الضريبة شاملة: الإجمالي لا يتغيّر');

update tax_settings set prices_include_vat = false
where laundry_id = '11111111-1111-1111-1111-111111111111';

select assert_eq(
  (select vat_amount from compute_vat('11111111-1111-1111-1111-111111111111', 115)),
  17.25::numeric, 'الضريبة مضافة: فوق ١١٥ تُضاف ١٧.٢٥ — الفرق ليس تفصيلًا');
select assert_eq(
  (select total from compute_vat('11111111-1111-1111-1111-111111111111', 115)),
  132.25::numeric, 'الضريبة مضافة: الإجمالي ١٣٢.٢٥');

-- ═══ ٦) مزوّد افتراضيّ واحد ══════════════════════════════════════════════
do $$ begin
  insert into payment_providers (laundry_id, code, display_name_ar, is_default)
  values ('11111111-1111-1111-1111-111111111111','tap','تاب',true);
  raise exception '✗ الافتراضيّ: قُبل مزوّدان افتراضيّان — أيّهما يُستعمل؟';
exception when unique_violation then
  raise notice '✓ الافتراضيّ: مزوّد افتراضيّ واحد لكل مغسلة';
end $$;

-- ═══ ٧) الأمان: العميل لا يدفع طلبه بجملة SQL ════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

do $$ begin
  insert into payments (order_id, method, status, amount)
  values ('0dd00000-0000-0000-0000-00000000000b','cash_on_delivery','captured',200);
  raise exception '✗ الأمان: العميل سجّل دفعةً مقبوضة لنفسه';
exception when insufficient_privilege or check_violation then
  raise notice '✓ الأمان: العميل لا يسجّل دفعةً — من يكتب captured يدفع بجملة SQL';
end $$;

do $$ begin
  insert into refunds (payment_id, order_id, amount, reason)
  values ('0aa00000-0000-0000-0000-000000000001','0dd00000-0000-0000-0000-00000000000a',
          10,'أريد مالي');
  raise exception '✗ الأمان: العميل استردّ لنفسه';
exception when insufficient_privilege or check_violation then
  raise notice '✓ الأمان: العميل لا يستردّ لنفسه — الاسترداد قرارٌ ماليّ';
end $$;

-- لكنه يرى دفعات طلبه
select assert_eq(
  (select count(*)::int from payments where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  1, 'الشفافية: العميل يرى دفعة طلبه');

reset role;
rollback;
