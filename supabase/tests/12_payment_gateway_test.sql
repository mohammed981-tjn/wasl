-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار بوّابة الدفع
-- ═══════════════════════════════════════════════════════════════════════════
-- **الخطر هنا مالٌ في الدفاتر لا شاشةٌ لا تعمل**: إشعارٌ يُعالَج مرّتين يضاعف
-- الإيراد، وإشعارٌ متأخّر يعيد المقبوض معلَّقًا، ومبلغٌ لا يُتحقَّق منه يجعل
-- طلبًا بخمس مئةٍ مدفوعًا بخمسة.

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
  when insufficient_privilege then
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
  ('a0000000-0000-0000-0000-000000000009','+966500000009');
insert into profiles (id, phone) select id, phone from auth.users;

insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'placed', 230.00);

-- ═══ ١) الجلسة تُفتح بمبلغ القاعدة لا بمبلغ العميل ═══════════════════════
select assert_eq(
  (open_payment_session('0dd00000-0000-0000-0000-00000000000a',
                        'a0000000-0000-0000-0000-000000000001') ->> 'amount')::numeric,
  230.00::numeric, 'الجلسة: المبلغ من الطلب لا ممّن يطلب الدفع');

select assert_eq(
  open_payment_session('0dd00000-0000-0000-0000-00000000000a',
                       'a0000000-0000-0000-0000-000000000009') ->> 'reason',
  'الطلب ليس لك', 'الجلسة: لا يدفع أحدٌ طلب غيره');

-- والمسوّدة لا تُدفع: طلبٌ لم يُرسل قد تتغيّر مبالغه بعد الدفع.
insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000d','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'draft', 99.00);
select assert_eq(
  open_payment_session('0dd00000-0000-0000-0000-00000000000d',
                       'a0000000-0000-0000-0000-000000000001') ->> 'reason',
  'الطلب لم يُرسل بعد', 'الجلسة: المسوّدة لا تُدفع');

-- ═══ ٢) المبلغ يُتحقَّق منه لا يُصدَّق ═══════════════════════════════════
select assert_eq(
  apply_payment_result('moy_test_1', 'captured', 5.00,
                       '0dd00000-0000-0000-0000-00000000000a') ->> 'reason',
  'المبلغ لا يطابق إجمالي الطلب',
  'النتيجة: مبلغٌ لا يطابق الطلب لا يُعلن دفعًا');

select assert_eq(
  (select count(*)::int from payments), 0,
  'النتيجة: ولا تُسجَّل دفعةٌ بمبلغٍ مرفوض');

-- ═══ ٣) النتيجة الصحيحة تُسجَّل وتنعكس على الطلب ═════════════════════════
select assert_eq(
  (apply_payment_result('moy_test_1', 'captured', 230.00,
                        '0dd00000-0000-0000-0000-00000000000a',
                        'card', 'mada', '4242') ->> 'created')::boolean,
  true, 'النتيجة: الدفعة تُنشأ عند أوّل إشعار');

select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'paid'::payment_status, 'النتيجة: حالة الدفع على الطلب تُشتقّ ولا تُكتب');

select assert_eq(
  (select card_last4 from payments where provider_ref = 'moy_test_1'),
  '4242'::bpchar, 'النتيجة: آخر أربعة أرقام تُحفظ — ولا شيء غيرها');

-- ═══ ٤) الإشعار المكرَّر لا يضاعف شيئًا ══════════════════════════════════
select assert_eq(
  (apply_payment_result('moy_test_1', 'captured', 230.00) ->> 'unchanged')::boolean,
  true, 'التكرار: الإشعار نفسه لا يغيّر شيئًا');

select assert_eq(
  (select count(*)::int from payments), 1,
  'التكرار: دفعةٌ واحدة لا دفعتان');

-- وقيدُ التفرّد على معرّف العملية يمنع التسجيل المزدوج ولو من طريقٍ آخر.
do $$ begin
  insert into payments (order_id, method, status, amount, provider_ref)
  values ('0dd00000-0000-0000-0000-00000000000a','card','captured',230.00,'moy_test_1');
  raise exception '✗ التكرار: قُبل معرّف عمليةٍ مكرَّر — والإيراد يتضاعف';
exception when unique_violation then
  raise notice '✓ التكرار: معرّف العملية فريدٌ في القاعدة';
end $$;

-- ═══ ٥) الإشعار المتأخّر لا يعيد المقبوض معلَّقًا ════════════════════════
select assert_eq(
  (apply_payment_result('moy_test_1', 'pending', 230.00) ->> 'ignored')::boolean,
  true, 'الترتيب: إشعارٌ متأخّر يُهمَل ولا يُوقف المعالجة');

select assert_eq(
  (select status from payments where provider_ref = 'moy_test_1'),
  'captured'::payment_txn_status, 'الترتيب: المقبوض يبقى مقبوضًا');

select assert_eq(
  (select payment_status from orders where id = '0dd00000-0000-0000-0000-00000000000a'),
  'paid'::payment_status, 'الترتيب: ولا تنقلب حالة الطلب');

-- والفشل بعد القبض مرفوضٌ كذلك — الرجوع عن مقبوضٍ **استرداد** لا فشل.
do $$ begin
  update payments set status = 'failed' where provider_ref = 'moy_test_1';
  raise exception '✗ التراجع: صار المقبوض فاشلًا';
exception when check_violation then
  raise notice '✓ التراجع: المقبوض لا يصير فاشلًا — الرجوع عنه استرداد';
end $$;

-- ═══ ٦) طلبٌ مدفوع لا تُفتح له جلسةٌ ثانية ══════════════════════════════
select assert_eq(
  open_payment_session('0dd00000-0000-0000-0000-00000000000a',
                       'a0000000-0000-0000-0000-000000000001') ->> 'reason',
  'الطلب مدفوع', 'الجلسة: لا يُدفع المدفوع مرّتين');

-- ═══ ٧) سجلُّ الوارد يمنع المعالجة المكرّرة ══════════════════════════════
select assert_eq(
  (record_webhook_event('moyasar','evt_1','payment_paid','moy_test_1',
                        '{"id":"evt_1"}'::jsonb) ->> 'ok')::boolean,
  true, 'السجلّ: الحدث الأوّل يُقبل');

select assert_eq(
  (record_webhook_event('moyasar','evt_1','payment_paid','moy_test_1',
                        '{"id":"evt_1"}'::jsonb) ->> 'duplicate')::boolean,
  true, 'السجلّ: إعادةُ الإرسال تُعرَف بمعرّفها لا بمضمونها');

-- والمرفوض يُسجَّل كذلك: «وصل إشعارٌ بتوقيعٍ خاطئ» معلومةٌ أمنية لا تُهمَل.
select record_webhook_event('moyasar','evt_bad','payment_paid',null,
                            '{"id":"evt_bad"}'::jsonb, false, 'توقيع غير صحيح');
select assert_eq(
  (select reject_reason from payment_webhook_events where event_id = 'evt_bad'),
  'توقيع غير صحيح', 'السجلّ: المرفوض يُسجَّل بسببه');

-- ═══ ٨) هذه الطرق للخادم لا لليد ════════════════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

select expect_denied($$
  select apply_payment_result('moy_hack', 'captured', 230.00,
                              '0dd00000-0000-0000-0000-00000000000a')
$$, 'الصلاحية: العميل لا يطبّق نتيجة دفع');

select expect_denied($$
  select open_payment_session('0dd00000-0000-0000-0000-00000000000a',
                              'a0000000-0000-0000-0000-000000000001')
$$, 'الصلاحية: حتى فتح الجلسة من الخادم لا من الحزمة');

select expect_denied($$
  select record_webhook_event('moyasar','evt_x','t',null,'{}'::jsonb)
$$, 'الصلاحية: سجلّ الوارد لا يُكتب من تطبيق');

-- ولا يُقرأ الوارد الخام من أحد: فيه ردُّ المزوّد كاملًا.
select assert_eq(
  (select count(*)::int from payment_webhook_events),
  0, 'الصلاحية: سجلّ الوارد لا يُقرأ من التطبيق');

-- والعميل لا يكتب دفعةً لنفسه — وهو أصل الحراسة كلّها.
select assert_eq(
  (select count(*)::int from payments where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  1, 'الرؤية: العميل يقرأ دفعات طلبه');

do $$ begin
  insert into payments (order_id, method, status, amount)
  values ('0dd00000-0000-0000-0000-00000000000a','card','captured',1.00);
  raise exception '✗ الحراسة: العميل دفع طلبه بجملة SQL';
exception when insufficient_privilege then
  raise notice '✓ الحراسة: العميل لا يكتب دفعة';
end $$;

rollback;
