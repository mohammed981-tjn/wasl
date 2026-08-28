-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار نظام الشكاوى
-- ═══════════════════════════════════════════════════════════════════════════
-- **الخطر هنا ثلاثة، وكلُّها صامتة:**
--
--   ١) **مالٌ يخرج مرّتين.** «تأكيد الحلّ» يُضغط من جهازين، أو شكويان على
--      طلبٍ واحد تُحلّان معًا — فيُستردّ فوق ما دُفع. لا رسالةَ خطأ، فقط
--      رقمٌ ناقصٌ في نهاية الشهر.
--
--   ٢) **شكوى تُغلق بغير رضا صاحبها.** موظّفٌ يكتب `status = 'closed'`
--      مباشرةً فيقفز فوق دالّة الحلّ — فتصير الشكوى «منجَزة» بلا استردادٍ
--      صُرف ولا سؤالٍ سُئل.
--
--   ٣) **المشكوُّ منه يقرأ الشكوى.** سائقٌ يعرف من اشتكى عليه اليوم يوصّل
--      له غدًا. وسياسةٌ واحدةٌ ناقصة تكفي.
--
-- ولذلك يُختبر **ما يجب أن يُرفض** أكثرَ ممّا يُقبل.

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
  when insufficient_privilege or check_violation or no_data_found then
    raise notice '✓ %', label;
end $$;

-- منعُ التحديث بـRLS **لا يرفع استثناءً**: يمسّ صفر صفوف و«ينجح».
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
        'المركز', st_point(39.6142,24.4672)::geography);

insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000001','+966500000001'),  -- العميل الشاكي
  ('a0000000-0000-0000-0000-000000000002','+966500000002'),  -- مدير الفرع
  ('a0000000-0000-0000-0000-000000000003','+966500000003'),  -- السائق المشكوّ منه
  ('a0000000-0000-0000-0000-000000000005','+966500000005'),  -- خدمة العملاء
  ('a0000000-0000-0000-0000-000000000009','+966500000009');  -- عميلٌ أجنبيّ
insert into profiles (id, phone) select id, phone from auth.users;

insert into user_roles (user_id, role, laundry_id, branch_id) values
  ('a0000000-0000-0000-0000-000000000002','branch_manager',
   '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000003','driver',
   '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'),
  ('a0000000-0000-0000-0000-000000000005','customer_service',
   '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');

-- طلبٌ سُلّم: مئةُ ريالٍ منها عشرون رسمَ توصيل، مدفوعٌ بالبطاقة ومقبوض.
insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, delivery_fee, total, delivery_driver_id, delivered_at)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'delivered', 80, 20, 100, 'a0000000-0000-0000-0000-000000000003', now());

insert into payment_providers (id, laundry_id, code, display_name_ar, is_active)
values ('bbbb0000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111','moyasar','ميسر', true);
insert into payments (id, order_id, provider_id, method, amount, status)
values ('cccc0000-0000-0000-0000-000000000001','0dd00000-0000-0000-0000-00000000000a',
        'bbbb0000-0000-0000-0000-000000000001', 'card', 100, 'captured');

-- طلبٌ نقديٌّ لاختبار «لا دفعةَ مقبوضة».
insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, delivery_fee, total, delivered_at)
values ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'delivered', 50, 10, 60, now());

-- ═══ ١) البذرةُ وقعت: مغسلةٌ جديدة تبدأ بقائمةٍ لا بفراغ ═════════════════
select assert_eq(
  (select count(*)::int > 10 from complaint_types
   where laundry_id = '11111111-1111-1111-1111-111111111111'),
  true, 'البذرة: المغسلة الجديدة تبدأ بقائمة أنواعٍ لا بفراغ');

select assert_eq(
  (select is_enabled from complaint_settings
   where laundry_id = '11111111-1111-1111-1111-111111111111'),
  true, 'البذرة: وإعداداتٌ جاهزة — نظامٌ يحتاج تهيئةً يدويّة معطَّلٌ بصمت');

-- ═══ ٢) نطاقُ النوع: كلُّ دورٍ وأنواعُه ══════════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

-- «العميل لا يردّ» نوعُ سائقٍ — والعميل لا يفتحه على نفسه.
select expect_denied(format($$
  insert into complaints (laundry_id, order_id, type_id, submitted_by,
                          submitted_by_role, description)
  values ('11111111-1111-1111-1111-111111111111',
          '0dd00000-0000-0000-0000-00000000000a', %L,
          'a0000000-0000-0000-0000-000000000001', 'customer', 'وصف كافٍ للاختبار')
$$, (select id from complaint_types where code = 'customer_unreachable')),
 'النطاق: العميل لا يفتح نوعًا للسائق');

-- ═══ ٣) الشكوى لأطراف الطلب وحدهم ═══════════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000009');
select expect_denied(format($$
  insert into complaints (laundry_id, order_id, type_id, submitted_by,
                          submitted_by_role, description)
  values ('11111111-1111-1111-1111-111111111111',
          '0dd00000-0000-0000-0000-00000000000a', %L,
          'a0000000-0000-0000-0000-000000000009', 'customer', 'وصف كافٍ للاختبار')
$$, (select id from complaint_types where code = 'stain_remains')),
 'الأطراف: أجنبيٌّ عن الطلب لا يشتكي عليه');

-- ═══ ٤) والفتحُ يُصحَّح ولا يُصدَّق ══════════════════════════════════════
-- شاكٍ يرسل مغسلةً غير مغسلة الطلب، وحالةً محلولة، وردَّ إدارةٍ ملفَّقًا.
select auth.login_as('a0000000-0000-0000-0000-000000000001');
insert into complaints (laundry_id, branch_id, order_id, type_id, submitted_by,
                        submitted_by_role, against_id, against_role,
                        description, status, resolution)
select '99999999-9999-9999-9999-999999999999',   -- مغسلةٌ ليست مغسلته
       null,
       '0dd00000-0000-0000-0000-00000000000a',
       id, 'a0000000-0000-0000-0000-000000000009',  -- ينتحل شخصًا
       'branch_manager',                            -- وينتحل دورًا
       'a0000000-0000-0000-0000-000000000003', 'driver',
       'وصلت القطع وفيها بقعةٌ لم تُزل',
       'resolved',                                  -- ويولد محلولًا
       'تم حلّ شكواك — من الإدارة'                  -- ويكتب ردَّ الإدارة
from complaint_types where code = 'stain_remains';

do $$
declare c complaints%rowtype;
begin
  select * into c from complaints
  where order_id = '0dd00000-0000-0000-0000-00000000000a';

  if c.laundry_id <> '11111111-1111-1111-1111-111111111111' then
    raise exception '✗ التصحيح: المغسلة قُبلت ممّن كتب';
  end if;
  if c.branch_id <> '22222222-2222-2222-2222-222222222222' then
    raise exception '✗ التصحيح: الفرع لم يُشتقّ من الطلب';
  end if;
  if c.submitted_by <> 'a0000000-0000-0000-0000-000000000001' then
    raise exception '✗ الانتحال: قُبل مقدِّمٌ غيرُ صاحب الجلسة';
  end if;
  if c.submitted_by_role <> 'customer' then
    raise exception '✗ الانتحال: قُبل دورٌ ادّعاه المُدخِل — وجاء %', c.submitted_by_role;
  end if;
  if c.status <> 'open' then
    raise exception '✗ الحالة: وُلدت الشكوى خارج الطابور (%)', c.status;
  end if;
  if c.resolution is not null then
    raise exception '✗ التلفيق: ردُّ إدارةٍ كتبه الشاكي على نفسه';
  end if;
  raise notice '✓ التصحيح: المغسلةُ والفرعُ والمقدِّمُ ودورُه تُشتقّ ولا تُقبل';
  raise notice '✓ التلفيق: الحالةُ والردُّ يفرضهما النظام لا المُدخِل';
end $$;

-- ═══ ٥) ولا شكوى على من ليس طرفًا، ولا على النفس ═════════════════════════
select expect_denied(format($$
  insert into complaints (laundry_id, order_id, type_id, submitted_by,
                          submitted_by_role, against_id, against_role, description)
  values ('11111111-1111-1111-1111-111111111111',
          '0dd00000-0000-0000-0000-00000000000a', %L,
          'a0000000-0000-0000-0000-000000000001','customer',
          'a0000000-0000-0000-0000-000000000009','customer','وصف كافٍ للاختبار')
$$, (select id from complaint_types where code = 'stain_remains')),
 'التلطيخ: لا شكوى على من لم يمسّ الطلب');

select expect_denied(format($$
  insert into complaints (laundry_id, order_id, type_id, submitted_by,
                          submitted_by_role, against_id, against_role, description)
  values ('11111111-1111-1111-1111-111111111111',
          '0dd00000-0000-0000-0000-00000000000a', %L,
          'a0000000-0000-0000-0000-000000000001','customer',
          'a0000000-0000-0000-0000-000000000001','customer','وصف كافٍ للاختبار')
$$, (select id from complaint_types where code = 'stain_remains')),
 'العبث: لا تشتكي على نفسك');

-- ═══ ٦) المهلة تُحسب من التسليم، وتُفحص عند الإرسال ══════════════════════
select auth.logout();
set local role postgres;
update orders set delivered_at = now() - interval '10 days'
where id = '0dd00000-0000-0000-0000-00000000000b';

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');

select expect_denied(format($$
  insert into complaints (laundry_id, order_id, type_id, submitted_by,
                          submitted_by_role, description)
  values ('11111111-1111-1111-1111-111111111111',
          '0dd00000-0000-0000-0000-00000000000b', %L,
          'a0000000-0000-0000-0000-000000000001','customer','وصف كافٍ للاختبار')
$$, (select id from complaint_types where code = 'stain_remains')),
 'المهلة: طلبٌ سُلّم قبل عشرة أيّام والمهلةُ ٤٨ ساعة');

-- والمهلةُ معطًى لا ثابت: ترفعها الإدارة فيُقبل ما رُفض.
select auth.logout();
set local role postgres;
update complaint_settings set window_hours = 720
where laundry_id = '11111111-1111-1111-1111-111111111111';

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');
insert into complaints (laundry_id, order_id, type_id, submitted_by,
                        submitted_by_role, description)
select '11111111-1111-1111-1111-111111111111',
       '0dd00000-0000-0000-0000-00000000000b', id,
       'a0000000-0000-0000-0000-000000000001','customer','الطلب النقديّ فيه رائحة'
from complaint_types where code = 'bad_smell';

select assert_eq(
  (select count(*)::int from complaints
   where order_id = '0dd00000-0000-0000-0000-00000000000b'),
  1, 'المهلة: رقمٌ للإدارة لا ثابتٌ في الشيفرة — رُفعت فقُبل ما رُفض');

select auth.logout();
set local role postgres;
update complaint_settings set window_hours = 48
where laundry_id = '11111111-1111-1111-1111-111111111111';

-- ═══ ٧) المشكوُّ منه لا يقرأ الشكوى ══════════════════════════════════════
-- سائقٌ يعرف من اشتكى عليه اليوم يوصّل له غدًا.
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000003');
select assert_eq(
  (select count(*)::int from complaints
   where against_id = 'a0000000-0000-0000-0000-000000000003'),
  0, 'الحدود: المشكوُّ منه لا يقرأ الشكوى عليه — والمواجهة تمرّ بالإدارة');

-- وعميلٌ آخر لا يقرأ شكوى غيره.
select auth.login_as('a0000000-0000-0000-0000-000000000009');
select assert_eq((select count(*)::int from complaints), 0,
  'الحدود: عميلٌ لا يرى شكاوى غيره');

-- وصاحبُها يراها.
select auth.login_as('a0000000-0000-0000-0000-000000000001');
select assert_eq((select count(*)::int from complaints), 2,
  'الحدود: صاحبُ الشكوى يرى شكواه');

-- وخدمةُ العملاء ترى الطابور.
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select assert_eq((select count(*)::int from complaints), 2,
  'الحدود: خدمةُ العملاء ترى الطابور');

-- ═══ ٨) الحالةُ لا تُكتب بتحديثٍ مباشر ═══════════════════════════════════
-- موظّفٌ يكتب `closed` مباشرةً يقفز فوق دالّة الحلّ: شكوى «منجَزة» بلا
-- استردادٍ صُرف ولا سؤالٍ سُئل.
select expect_denied($$
  update complaints set status = 'closed'
  where order_id = '0dd00000-0000-0000-0000-00000000000a'
$$, 'القفز: الحالة لا تُكتب بتحديثٍ مباشر — لها دوالُّها');

select expect_denied($$
  update complaints set status = 'resolved', resolution = 'حُلّت'
  where order_id = '0dd00000-0000-0000-0000-00000000000a'
$$, 'القفز: ولا «محلولة» بلا مالٍ يُصرف');

-- والشاكي لا يكتب لنفسه ردَّ إدارة.
select auth.login_as('a0000000-0000-0000-0000-000000000001');
select expect_no_rows($$
  update complaints set resolution = 'الإدارة تعتذر وتعيد لك مئة ريال'
  where order_id = '0dd00000-0000-0000-0000-00000000000a'
$$, 'التلفيق: الشاكي لا يكتب ردَّ الإدارة على نفسه');

-- وله وصفُه ما دامت لم تُقرأ.
update complaints set description = 'البقعةُ في الكمّ الأيمن — أوضّح'
where order_id = '0dd00000-0000-0000-0000-00000000000a';
select assert_eq(
  (select description from complaints
   where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  'البقعةُ في الكمّ الأيمن — أوضّح',
  'الوصف: لصاحب الشكوى أن يوضّح ما دامت لم تُقرأ');

-- ═══ ٩) الالتقاط: أوّلُ يدٍ تلمسها تُختم ═════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000005');
do $$
declare c complaints%rowtype;
begin
  select * into c from complaints
  where order_id = '0dd00000-0000-0000-0000-00000000000a';
  c := claim_complaint(c.id);

  if c.status <> 'in_progress' then
    raise exception '✗ الالتقاط: الحالة % لا in_progress', c.status;
  end if;
  if c.first_response_at is null then
    raise exception '✗ المهلة: لم تُختم أوّلُ لمسة — فبأيّ شيءٍ تُقاس؟';
  end if;
  raise notice '✓ الالتقاط: تخرج من الطابور وتُختم أوّلُ لمسة';

  -- التقاطٌ مكرَّر ليس خطأً.
  c := claim_complaint(c.id);
  if c.status <> 'in_progress' then
    raise exception '✗ الالتقاط المكرّر: قلب الحالة';
  end if;
  raise notice '✓ الالتقاط: تكرارُه لا يقلب شيئًا';
end $$;

-- وبعد الالتقاط لا يعدّل الشاكي وصفَه: نصٌّ يتبدّل بعد قراءته ليس شكوى.
select auth.login_as('a0000000-0000-0000-0000-000000000001');
select expect_no_rows($$
  update complaints set description = 'بل كانت قطعتان'
  where order_id = '0dd00000-0000-0000-0000-00000000000a'
$$, 'الوصف: لا يُبدَّل بعد أن قرأته الإدارة');

-- ═══ ١٠) الاسترداد: النسبةُ تُقبل والمبلغُ يُقرأ من القاعدة ══════════════
-- **مئةُ ريالٍ منها عشرون توصيلًا.** فخمسون بالمئة من الخدمة = ٤٠ لا ٥٠:
-- رسمُ التوصيل خدمةٌ أُدّيت وسائقٌ قطع الطريق.
select auth.login_as('a0000000-0000-0000-0000-000000000005');
do $$
declare c_id uuid; r jsonb;
begin
  select id into c_id from complaints
  where order_id = '0dd00000-0000-0000-0000-00000000000a';

  r := resolve_complaint(c_id, 'نعتذر — أُعيد غسلُ القطعة واستُرِدّ نصفُ قيمة الخدمة',
                         p_refund_percent => 50, p_warn_against => true);

  if (r->>'refund_amount')::numeric <> 40 then
    raise exception '✗ الأساس: توقّعنا ٤٠ (٥٠%% من ٨٠) وجاء %', r->>'refund_amount';
  end if;
  raise notice '✓ الأساس: رسمُ التوصيل لا يُردّ في الاسترداد الجزئيّ (٤٠ لا ٥٠)';
end $$;

select assert_eq(
  (select sum(amount) from refunds where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  40::numeric, 'الاسترداد: صفٌّ في `refunds` بالمبلغ المقروء من الطلب');

-- **والحلُّ لا يُغلق**: يفتح مهلةَ تأكيدِ صاحبها.
select assert_eq(
  (select status from complaints where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  'resolved'::complaint_status,
  'الدورة: الحلُّ لا يُغلق — يفتح سؤالَ صاحبها');

-- ═══ ١١) ولا يُنفَّذ الحلُّ مرّتين ════════════════════════════════════════
-- ضغطتان على «تأكيد الحلّ» من جهازين كانتا في زادقو تصرفان الاسترداد مرّتين.
select expect_denied($$
  select resolve_complaint(
    (select id from complaints where order_id = '0dd00000-0000-0000-0000-00000000000a'),
    'مرّةً أخرى', 50)
$$, 'المضاعفة: الحلُّ لا يُنفَّذ مرّتين على الشكوى نفسها');

-- ═══ ١٢) والإنذار صفٌّ يُراجَع لا عدّادٌ يُزاد ════════════════════════════
select assert_eq(
  (select count(*)::int from driver_warnings
   where driver_id = 'a0000000-0000-0000-0000-000000000003'),
  1, 'الإنذار: صفٌّ يقول من أنذر ولماذا — لا عدّادٌ لا يجيب');

-- **والعدّادُ نفسُه ليس واجهةً**: `driver_active_warnings` تُستدعى من داخل
-- الحرّاس، ونداؤها من حزمةٍ يعطي أيَّ مسجَّلٍ مسبارًا عن غيره.
select expect_denied($$
  select driver_active_warnings('a0000000-0000-0000-0000-000000000003',
                                '11111111-1111-1111-1111-111111111111')
$$, 'المسبار: عدُّ إنذارات غيرك ليس واجهةً تُنادى');

-- والعدُّ للحزمة يمرّ بالسياسات: خدمةُ العملاء تعدّ الصفوف التي تراها.
select assert_eq(
  (select count(*)::int from driver_warnings
   where driver_id = 'a0000000-0000-0000-0000-000000000003'
     and revoked_at is null
     and (expires_at is null or expires_at > now())),
  1, 'الإنذار: يُعدّ الساري وحده');

-- ولا يُكتب من حزمة: سائقٌ يمحو إنذارَه يُفرغ النظام من معناه.
select auth.login_as('a0000000-0000-0000-0000-000000000003');
select expect_denied($$
  delete from driver_warnings where driver_id = 'a0000000-0000-0000-0000-000000000003'
$$, 'الإنذار: لا يُمحى من حزمة');
select expect_denied($$
  insert into driver_warnings (driver_id, laundry_id, reason)
  values ('a0000000-0000-0000-0000-000000000001',
          '11111111-1111-1111-1111-111111111111','ملفَّق')
$$, 'الإنذار: ولا يُلفَّق من حزمة');

-- والسائق يرى إنذاراته: عقوبةٌ لا يعرفها صاحبُها ليست تقويمًا.
select assert_eq(
  (select count(*)::int from driver_warnings), 1,
  'الشفافيّة: السائق يقرأ إنذاراته — عقوبةٌ سرّيّةٌ ليست تقويمًا');

-- ═══ ١٣) الوقفُ يمنع الجديد ولا يقطع الجاري ══════════════════════════════
select auth.logout();
set local role postgres;
-- إنذاران آخران: يبلغ الحدَّ (٣).
insert into driver_warnings (driver_id, laundry_id, reason) values
  ('a0000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','ثانٍ'),
  ('a0000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','ثالث');

insert into orders (id, laundry_id, branch_id, customer_id, status, total)
values ('0dd00000-0000-0000-0000-00000000000c','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'ready', 70);

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000002');

select expect_denied($$
  update orders set delivery_driver_id = 'a0000000-0000-0000-0000-000000000003'
  where id = '0dd00000-0000-0000-0000-00000000000c'
$$, 'الوقف: من بلغ حدَّ الإنذارات لا يُسنَد إليه جديد');

-- **وما في سيّارته الآن يُسلَّم**: الطلب المسنَد سابقًا لم يُمَسّ.
select assert_eq(
  (select delivery_driver_id from orders
   where id = '0dd00000-0000-0000-0000-00000000000a'),
  'a0000000-0000-0000-0000-000000000003'::uuid,
  'الوقف: لا يقطع الجولة الجارية — قطعُ عميلٍ في صندوقٍ لا يعرفه أحد');

-- والحدُّ معطًى: ترفعه الإدارة فيعود.
select auth.logout();
set local role postgres;
update complaint_settings set driver_warning_threshold = 10
where laundry_id = '11111111-1111-1111-1111-111111111111';

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000002');
update orders set delivery_driver_id = 'a0000000-0000-0000-0000-000000000003'
where id = '0dd00000-0000-0000-0000-00000000000c';
select assert_eq(
  (select delivery_driver_id from orders where id = '0dd00000-0000-0000-0000-00000000000c'),
  'a0000000-0000-0000-0000-000000000003'::uuid,
  'الحدّ: رقمٌ للإدارة لا ثابتٌ في الشيفرة');

-- والإنذارُ يسقط: خطأٌ قبل سنةٍ ليس كخطأٍ أمس.
select auth.logout();
set local role postgres;
update complaint_settings set driver_warning_threshold = 3
where laundry_id = '11111111-1111-1111-1111-111111111111';
update driver_warnings set expires_at = now() - interval '1 day' where reason = 'ثانٍ';
update driver_warnings set revoked_at = now(), revoked_reason = 'راجعناه فبرّئناه'
where reason = 'ثالث';

select assert_eq(
  (select count(*)::int from driver_warnings
   where driver_id = 'a0000000-0000-0000-0000-000000000003'
     and revoked_at is null
     and (expires_at is null or expires_at > now())),
  1, 'السقوط: الساقطُ والمُلغى لا يُعدّان — والعقوبةُ الأبديّة ليست تقويمًا');

-- ═══ ١٤) جوابُ الشاكي هو الذي يُغلق ══════════════════════════════════════
set local role authenticated;
-- ولا يجيب عنه غيرُه.
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select expect_denied($$
  select confirm_complaint_resolution(
    (select id from complaints where order_id = '0dd00000-0000-0000-0000-00000000000a'),
    true)
$$, 'الجواب: الإدارة لا تجيب نيابةً عن الشاكي — وإلّا فالسؤال زينة');

-- «لا، لم تُحل» تعيدها بأولوية ولا تمحو ما صُرف.
select auth.login_as('a0000000-0000-0000-0000-000000000001');
do $$
declare c complaints%rowtype;
begin
  select * into c from complaints
  where order_id = '0dd00000-0000-0000-0000-00000000000a';
  c := confirm_complaint_resolution(c.id, false, 'البقعة ما زالت موجودة');

  if c.status <> 'in_progress' then
    raise exception '✗ الارتداد: الحالة % لا in_progress', c.status;
  end if;
  if c.reopen_count <> 1 then
    raise exception '✗ الارتداد: العدّاد % لا ١', c.reopen_count;
  end if;
  raise notice '✓ الارتداد: «لم تُحل» تعيدها للطابور ويُعدّ ارتدادُها';
end $$;

select assert_eq(
  (select sum(amount) from refunds where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  40::numeric,
  'الارتداد: لا يمحو ما صُرف — الاسترداد وقع، وتُستكمل لا تُعاد من الصفر');

select assert_eq(
  (select count(*)::int from complaint_messages
   where body = 'البقعة ما زالت موجودة'),
  1, 'الارتداد: وسببُه يُقيَّد في المحادثة لا يضيع');

-- ═══ ١٥) والسقفُ يمنع الاسترداد فوق المقبوض ══════════════════════════════
-- الشكوى نفسها تُحلّ ثانيةً باسترداد ١٠٠%: المقبوض ١٠٠ وقد استُرِدّ ٤٠،
-- فلا يخرج إلا ٦٠ — والباقي يرفضه `enforce_refund_ceiling` في القاعدة.
select auth.login_as('a0000000-0000-0000-0000-000000000005');
do $$
declare r jsonb;
begin
  r := resolve_complaint(
    (select id from complaints where order_id = '0dd00000-0000-0000-0000-00000000000a'),
    'استرداد كامل', p_refund_percent => 100);
  if (r->>'refund_amount')::numeric <> 60 then
    raise exception '✗ السقف: توقّعنا ٦٠ (١٠٠ مقبوضة − ٤٠ مستردّة) وجاء %',
      r->>'refund_amount';
  end if;
  raise notice '✓ السقف: لا يخرج فوق المقبوض ولو طُلبت المئة كاملة';
end $$;

select assert_eq(
  (select sum(amount) from refunds where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  100::numeric, 'السقف: مجموعُ المستردّ = المقبوض تمامًا، لا فوقه');

-- ولا شيء بعده.
select auth.login_as('a0000000-0000-0000-0000-000000000001');
select confirm_complaint_resolution(
  (select id from complaints where order_id = '0dd00000-0000-0000-0000-00000000000a'), false);
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select expect_denied($$
  select resolve_complaint(
    (select id from complaints where order_id = '0dd00000-0000-0000-0000-00000000000a'),
    'وثالثة', 100)
$$, 'السقف: طلبٌ استُرِدّ بكامله لا استرداد فوقه');

-- ═══ ١٦) والطلبُ النقديّ يُقال فيه الحقّ لا يُبتلع ═══════════════════════
-- لا دفعةَ مقبوضة ⇒ لا استرداد بطاقة. والرسالةُ تقول البديل بدل أن تصمت.
select expect_denied($$
  select resolve_complaint(
    (select id from complaints where order_id = '0dd00000-0000-0000-0000-00000000000b'),
    'استرداد', 50)
$$, 'النقديّ: لا استرداد بطاقةٍ بلا دفعةٍ مقبوضة — والرسالة تقول البديل');

-- والبديلُ يعمل: تعويضٌ بالنقاط.
do $$
declare r jsonb;
begin
  r := resolve_complaint(
    (select id from complaints where order_id = '0dd00000-0000-0000-0000-00000000000b'),
    'نعتذر — عوّضناك بنقاط', p_loyalty_points => 200);
  if (r->>'loyalty_points')::int <> 200 then
    raise exception '✗ التعويض: جاء %', r->>'loyalty_points';
  end if;
  raise notice '✓ التعويض: النقاطُ بابٌ حين لا يكون ثمّ ما يُستردّ';
end $$;

select assert_eq(
  loyalty_balance('a0000000-0000-0000-0000-000000000001',
                  '11111111-1111-1111-1111-111111111111'),
  200, 'التعويض: النقاطُ قُيّدت في رصيد العميل فعلًا');

-- ═══ ١٧) «نعم، حُلّت» تُغلق — ويُميَّز عن الإغلاق بالصمت ═════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000001');
do $$
declare c complaints%rowtype;
begin
  select * into c from complaints
  where order_id = '0dd00000-0000-0000-0000-00000000000b';
  c := confirm_complaint_resolution(c.id, true);
  if c.status <> 'closed' then
    raise exception '✗ الإغلاق: الحالة %', c.status;
  end if;
  if c.closed_by_timeout then
    raise exception '✗ التمييز: إقرارُ صاحبها عُدَّ صمتًا';
  end if;
  raise notice '✓ الإغلاق: «نعم، حُلّت» تُغلق — بإقرارٍ لا بصمت';
end $$;

-- ═══ ١٨) الإغلاق التلقائيّ: يعمل ولو نام الجميع ══════════════════════════
select auth.logout();
set local role postgres;

-- شكوى محلولةٌ منذ خمسة أيّام (المهلة ٣)، وأخرى منذ ساعة.
insert into complaints (id, laundry_id, branch_id, order_id, type_id, submitted_by,
                        submitted_by_role, description, status, resolved_at)
select 'ccc00000-0000-0000-0000-00000000000f',
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '0dd00000-0000-0000-0000-00000000000c', id,
       'a0000000-0000-0000-0000-000000000001','customer',
       'شكوى قديمةٌ سكت عنها صاحبُها','resolved', now() - interval '5 days'
from complaint_types where code = 'poor_ironing';

insert into complaints (id, laundry_id, branch_id, order_id, type_id, submitted_by,
                        submitted_by_role, description, status, resolved_at)
select 'ccc00000-0000-0000-0000-0000000000ee',
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '0dd00000-0000-0000-0000-00000000000c', id,
       'a0000000-0000-0000-0000-000000000001','customer',
       'شكوى حُلّت للتوّ','resolved', now() - interval '1 hour'
from complaint_types where code = 'late_delivery';

-- **وتُصفَّ رسالةُ الحلّ يدويًّا لهاتين**: أُدرِجتا `resolved` مباشرةً في
-- سياق الخادم، والمحفّزُ لا يرى انتقالًا فلا يُصفّ شيئًا. وبلا الرسالة
-- يمنعهما حارسُ «لا إغلاق على من لم يُسأل» — وهو ما يجب أن يفعل.
insert into notifications (user_id, complaint_id, channel, body, created_at)
values
  ('a0000000-0000-0000-0000-000000000001','ccc00000-0000-0000-0000-00000000000f',
   'in_app','ردٌّ على شكواك', now() - interval '5 days'),
  ('a0000000-0000-0000-0000-000000000001','ccc00000-0000-0000-0000-0000000000ee',
   'in_app','ردٌّ على شكواك', now() - interval '1 hour');

select assert_eq(close_stale_complaints(), 1,
  'الكنس: يُغلق ما تجاوز المهلة وحده — لا ما حُلّ للتوّ');

select assert_eq(
  (select closed_by_timeout from complaints
   where id = 'ccc00000-0000-0000-0000-00000000000f'),
  true, 'الكنس: ويُختم أنّه إغلاقٌ بالصمت — والصمتُ ليس رضًا');

select assert_eq(
  (select status from complaints where id = 'ccc00000-0000-0000-0000-0000000000ee'),
  'resolved'::complaint_status, 'الكنس: وما لم تنقضِ مهلتُه يُترك');

-- والمهلةُ معطًى: تقصيرُها يكنس ما بقي.
update complaint_settings set auto_close_days = 1
where laundry_id = '11111111-1111-1111-1111-111111111111';
select assert_eq(close_stale_complaints(), 0,
  'الكنس: ساعةٌ واحدة لم تبلغ اليومَ بعد');
update complaint_settings set auto_close_days = 3
where laundry_id = '11111111-1111-1111-1111-111111111111';

-- ولا تُنادى من حزمة: دالّةٌ تُغلق شكاوى الناس لا تُنادى من هاتف.
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select expect_denied($$ select close_stale_complaints() $$,
  'الكنس: لا يُنادى من حزمة — للخادم وحده');

-- ═══ ١٩) الطابور مرتَّبٌ في القاعدة لا في الجهاز ═════════════════════════
-- في زادقو تُبَثّ كلُّ الشكاوى إلى كلِّ جهازِ مدير ثم تُرتَّب في الذاكرة.
select assert_eq(
  (select status from complaints_queue limit 1),
  'in_progress'::complaint_status,
  'الطابور: ما ينتظر عملًا أوّلًا — والمنجَزُ في الذيل');

-- وتجاوزُ مهلة الردّ يُحسب ويُعرض.
select auth.logout();
set local role postgres;
insert into complaints (id, laundry_id, branch_id, order_id, type_id, submitted_by,
                        submitted_by_role, description, created_at)
select 'ccc00000-0000-0000-0000-0000000000dd',
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '0dd00000-0000-0000-0000-00000000000c', id,
       'a0000000-0000-0000-0000-000000000001','customer',
       'شكوى لم يلمسها أحدٌ منذ يومين', now() - interval '48 hours'
from complaint_types where code = 'item_missing';

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select assert_eq(
  (select sla_breached from complaints_queue
   where id = 'ccc00000-0000-0000-0000-0000000000dd'),
  true, 'المهلة: وعدُ الردّ يُقاس ويُعرض تجاوزُه — ووعدٌ لا يُقاس ليس وعدًا');

-- والمنظرُ يحترم الحدود: RLS سارية عليه (security_invoker).
select auth.login_as('a0000000-0000-0000-0000-000000000009');
select assert_eq((select count(*)::int from complaints_queue), 0,
  'الطابور: منظرٌ لا يلتفّ على السياسات — أجنبيٌّ لا يرى شيئًا');

-- ═══ ٢٠) الملخّص يفرّق بين الإقرار والصمت ════════════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000005');
do $$
declare s record;
begin
  select * into s from complaint_summary('11111111-1111-1111-1111-111111111111');

  if s.closed_confirmed <> 1 then
    raise exception '✗ الملخّص: المُقَرّ بحلّه % لا ١', s.closed_confirmed;
  end if;
  if s.closed_by_silence <> 1 then
    raise exception '✗ الملخّص: المُغلَق بالصمت % لا ١', s.closed_by_silence;
  end if;
  if s.reopened <> 1 then
    raise exception '✗ الملخّص: المرتدّ % لا ١', s.reopened;
  end if;
  raise notice '✓ الملخّص: «أُغلق بإقرار صاحبه» و«أُغلق بصمته» سطران لا سطر';
  raise notice '✓ الملخّص: والمرتدُّ يُعدّ — الرقمُ وحده يكشف حلولًا شكليّة';

  if s.by_type = '{}'::jsonb then
    raise exception '✗ التجميع: لا تصنيف — والنصُّ الحرُّ لا يُجمَّع';
  end if;
  raise notice '✓ التجميع: القائمةُ المغلقة تُجمَّع — % ', s.by_type;
end $$;

-- ═══ ٢١) والرسالةُ الداخليّة لا يقرؤها الشاكي ════════════════════════════
insert into complaint_messages (complaint_id, sender_id, sender_role, body, is_internal)
values ('ccc00000-0000-0000-0000-0000000000dd',
        'a0000000-0000-0000-0000-000000000005','customer_service',
        'العميلُ هذا كثيرُ الشكاوى — راجعوا سجلَّه', true);

select auth.login_as('a0000000-0000-0000-0000-000000000001');
select assert_eq(
  (select count(*)::int from complaint_messages
   where complaint_id = 'ccc00000-0000-0000-0000-0000000000dd'),
  0, 'الداخليّة: ملاحظةُ الموظّفين لا تصل إلى شاشة الشاكي');

select auth.login_as('a0000000-0000-0000-0000-000000000005');
select assert_eq(
  (select count(*)::int from complaint_messages
   where complaint_id = 'ccc00000-0000-0000-0000-0000000000dd'),
  1, 'الداخليّة: ويقرؤها الموظّفون');

-- والمحادثةُ سجلٌّ: لا تُحرَّر ولا تُمحى بعد إرسالها.
select expect_no_rows($$
  update complaint_messages set body = 'لم أقل هذا'
  where complaint_id = 'ccc00000-0000-0000-0000-0000000000dd'
$$, 'السجلّ: رسالةٌ تُحرَّر بعد قراءتها ليست سجلًّا');
select expect_no_rows($$
  delete from complaint_messages
  where complaint_id = 'ccc00000-0000-0000-0000-0000000000dd'
$$, 'السجلّ: ولا تُمحى');

-- ولا تُحذف شكوى: سجلُّ نزاعٍ يُحذف يعني طرفًا يمحو ما عليه.
select expect_no_rows($$
  delete from complaints where id = 'ccc00000-0000-0000-0000-0000000000dd'
$$, 'السجلّ: لا تُحذف شكوى');

-- ═══════════════════════════════════════════════════════════════════════════
-- الإشعارات — والصمتُ لا يُفسَّر رضًا إلا إن سُئل صاحبُه
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══ ٢٢) القوالبُ تُبذر مع المغسلة ══════════════════════════════════════
select auth.logout();
set local role postgres;
select assert_eq(
  (select count(*)::int > 0 from complaint_templates
   where laundry_id = '11111111-1111-1111-1111-111111111111'
     and event = 'resolved'),
  true, 'البذرة: قالبُ «حُلّت» موجودٌ من أوّل يوم — وبلا قالبٍ لا يُغلق شيء');

-- ═══ ٢٣) والحلُّ يُصفّ رسالةً تطلب جوابًا ════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, delivery_fee, total, delivered_at)
values ('0dd00000-0000-0000-0000-0000000000e1','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'delivered', 50, 10, 60, now());

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');
insert into complaints (id, laundry_id, order_id, type_id, submitted_by,
                        submitted_by_role, description)
select 'ccc00000-0000-0000-0000-0000000000b1',
       '11111111-1111-1111-1111-111111111111',
       '0dd00000-0000-0000-0000-0000000000e1', id,
       'a0000000-0000-0000-0000-000000000001','customer','كيٌّ رديء في الثوب'
from complaint_types where code = 'poor_ironing';

-- والفتحُ يُخطر خدمةَ العملاء لا العميل: طابورٌ لا يُرى لا يُعمل فيه.
select auth.logout();
set local role postgres;
select assert_eq(
  (select count(*)::int from notifications n
   join complaints c on c.id = n.complaint_id
   where c.order_id = '0dd00000-0000-0000-0000-0000000000e1'
     and n.user_id = 'a0000000-0000-0000-0000-000000000005'),
  1, 'الفتح: خدمةُ العملاء تُخطَر بالشكوى الجديدة');

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select resolve_complaint('ccc00000-0000-0000-0000-0000000000b1',
                         'أعدنا كيَّ الثوب، ونعتذر عن التقصير');

select auth.logout();
set local role postgres;

do $$
declare n record;
begin
  select * into n from notifications
  where complaint_id = 'ccc00000-0000-0000-0000-0000000000b1'
    and user_id = 'a0000000-0000-0000-0000-000000000001'
    and title like '%ردٌّ على شكواك%';

  if n is null then
    raise exception '✗ الإشعار: حُلّت الشكوى ولم يُصفَّ لصاحبها شيء';
  end if;
  raise notice '✓ الإشعار: الحلُّ يُصفّ رسالةً لصاحب الشكوى';

  -- **والرسالةُ تحمل ثلاثة**: ردَّ الإدارة، وطلبَ الجواب، ونهايةَ المهلة.
  -- وبلا واحدةٍ منها يصير الإغلاقُ بالصمت إغلاقًا بالجهل.
  if n.body not like '%أعدنا كيَّ الثوب%' then
    raise exception '✗ الإشعار: الرسالةُ لا تحمل ردَّ الإدارة';
  end if;
  if n.body not like '%هل حُلّت مشكلتك فعلًا؟%' then
    raise exception '✗ الإشعار: الرسالةُ لا تطلب جوابًا — فبأيّ حقٍّ يُعدّ الصمتُ رضًا؟';
  end if;
  if n.body not like '%3 أيّام%' then
    raise exception '✗ الإشعار: لا تُذكر نهايةُ المهلة — والمفاجأةُ ليست عدلًا';
  end if;
  raise notice '✓ الإشعار: تحمل الردَّ وطلبَ الجواب ونهايةَ المهلة';

  if n.body like '%{%' then
    raise exception '✗ القالب: متغيّرٌ لم يُملأ ظهر للمستخدم: %', n.body;
  end if;
  raise notice '✓ القالب: لا متغيّرَ خامٌ يظهر للمستخدم';
end $$;

-- ═══ ٢٤) والكنسُ لا يُغلق على من لم يُسأل ═══════════════════════════════
-- **جوهرُ هذه المهاجرة.** شكوى حُلّت ولم يُصفَّ لصاحبها إشعار: تبقى ظاهرةً
-- في الطابور ولا تُغلق — وبقاءُ صفٍّ في لوحةٍ أهونُ من إغلاقٍ على من لم يعلم.
insert into complaints (id, laundry_id, branch_id, order_id, type_id, submitted_by,
                        submitted_by_role, description, status, resolved_at)
select 'ccc00000-0000-0000-0000-0000000000aa',
       '11111111-1111-1111-1111-111111111111',
       '22222222-2222-2222-2222-222222222222',
       '0dd00000-0000-0000-0000-0000000000e1', id,
       'a0000000-0000-0000-0000-000000000001','customer',
       'شكوى حُلّت ولم يُخطَر صاحبُها','resolved', now() - interval '10 days'
from complaint_types where code = 'wrong_item';

-- تُمحى رسائلُها كي تُحاكى حالةُ «لم يُسأل» بدقّة.
delete from notifications where complaint_id = 'ccc00000-0000-0000-0000-0000000000aa';

select assert_eq(close_stale_complaints(), 0,
  'العدل: شكوى لم يبلغ صاحبَها ردُّها لا تُغلق بصمته');

select assert_eq(
  (select status from complaints where id = 'ccc00000-0000-0000-0000-0000000000aa'),
  'resolved'::complaint_status, 'العدل: وتبقى ظاهرةً في الطابور');

-- والسببُ يُعرض لا يُخبَّأ: صفٌّ عالقٌ بلا سببٍ ظاهر يُكتشف بعد شهر.
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select assert_eq(
  (select count(*)::int from
     complaints_unnotified('11111111-1111-1111-1111-111111111111')
   where complaint_id = 'ccc00000-0000-0000-0000-0000000000aa'),
  1, 'الشفافيّة: «حُلّت ولم يبلغ صاحبَها» رقمٌ يُعرض للإدارة');

-- ═══ ٢٥) ومن سُئل ثم سكت تُغلق شكواه ════════════════════════════════════
select auth.logout();
set local role postgres;
-- يُعاد تاريخُ الشكوى المُخطَرة إلى ما قبل المهلة.
update complaints set resolved_at = now() - interval '10 days'
where id = 'ccc00000-0000-0000-0000-0000000000b1';
update notifications set created_at = now() - interval '10 days'
where complaint_id = 'ccc00000-0000-0000-0000-0000000000b1';

select assert_eq(close_stale_complaints(), 1,
  'العدل: ومن سُئل ثم سكت — يُغلق ملفُّه، والصمتُ حينها رضًا');

-- ═══ ٢٦) والإغلاقُ بالصمت يُعلَم به صاحبُه ═════════════════════════════
select assert_eq(
  (select count(*)::int from notifications
   where complaint_id = 'ccc00000-0000-0000-0000-0000000000b1'
     and title like '%أُغلقت شكواك%'),
  1, 'المجاملة: ويُعلَم بالإغلاق — لا يُكتشف بابٌ مغلقٌ صدفةً');

-- ═══ ٢٧) والارتدادُ يُخطر الإدارة لا الشاكي ═════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, delivery_fee, total, delivered_at)
values ('0dd00000-0000-0000-0000-0000000000e2','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'delivered', 50, 10, 60, now());

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');
insert into complaints (laundry_id, order_id, type_id, submitted_by,
                        submitted_by_role, description)
select '11111111-1111-1111-1111-111111111111',
       '0dd00000-0000-0000-0000-0000000000e2', id,
       'a0000000-0000-0000-0000-000000000001','customer','رائحةٌ في القطع'
from complaint_types where code = 'bad_smell';

select auth.login_as('a0000000-0000-0000-0000-000000000005');
do $$
declare c_id uuid;
begin
  select id into c_id from complaints
  where order_id = '0dd00000-0000-0000-0000-0000000000e2';
  perform resolve_complaint(c_id, 'عطّرناها');
end $$;

select auth.login_as('a0000000-0000-0000-0000-000000000001');
select confirm_complaint_resolution(
  (select id from complaints where order_id = '0dd00000-0000-0000-0000-0000000000e2'),
  false, 'الرائحة باقية');

select auth.logout();
set local role postgres;
select assert_eq(
  (select count(*)::int from notifications
   where complaint_id = (select id from complaints
                         where order_id = '0dd00000-0000-0000-0000-0000000000e2')
     and title like '%ارتدّت%'
     and user_id = 'a0000000-0000-0000-0000-000000000005'),
  1, 'الارتداد: يُخطَر به من يعالج لا من اشتكى');

-- ولا يُخطَر الشاكي بارتداد شكواه: هو من ردّها، فرسالةٌ تخبره بذلك عبث.
select assert_eq(
  (select count(*)::int from notifications
   where complaint_id = (select id from complaints
                         where order_id = '0dd00000-0000-0000-0000-0000000000e2')
     and title like '%ارتدّت%'
     and user_id = 'a0000000-0000-0000-0000-000000000001'),
  0, 'الارتداد: ولا يُخطَر به الشاكي — هو من ردّها');

-- ═══ ٢٨) ومن أوقف قناةً يُسجَّل تخطّيه ولا يُبتلع ═══════════════════════
insert into notification_preferences (user_id, push_enabled)
values ('a0000000-0000-0000-0000-000000000001', false)
on conflict (user_id) do update set push_enabled = false;

insert into complaint_templates (laundry_id, event, channel, audience, body_ar)
values ('11111111-1111-1111-1111-111111111111','acknowledged','push','customer',
        'شكواك قيد المراجعة');

insert into orders (id, laundry_id, branch_id, customer_id, status,
                    subtotal, delivery_fee, total, delivered_at)
values ('0dd00000-0000-0000-0000-0000000000e3','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'delivered', 50, 10, 60, now());

set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000001');
insert into complaints (laundry_id, order_id, type_id, submitted_by,
                        submitted_by_role, description)
select '11111111-1111-1111-1111-111111111111',
       '0dd00000-0000-0000-0000-0000000000e3', id,
       'a0000000-0000-0000-0000-000000000001','customer','لونٌ نزل على قطعة'
from complaint_types where code = 'color_run';

select auth.login_as('a0000000-0000-0000-0000-000000000005');
select claim_complaint(
  (select id from complaints where order_id = '0dd00000-0000-0000-0000-0000000000e3'));

select auth.logout();
set local role postgres;
select assert_eq(
  (select status from notifications
   where complaint_id = (select id from complaints
                         where order_id = '0dd00000-0000-0000-0000-0000000000e3')
     and channel = 'push'),
  'skipped'::notification_status,
  'التفضيل: من أوقف الدفع يُسجَّل تخطّيه صفًّا — لا يُبتلع بلا أثر');

-- والقناةُ داخل التطبيق تصل دائمًا: هي التي تحمل السؤال حين لا مزوّد بعد.
select assert_eq(
  (select status from notifications
   where complaint_id = (select id from complaints
                         where order_id = '0dd00000-0000-0000-0000-0000000000e3')
     and channel = 'in_app'
     and user_id = 'a0000000-0000-0000-0000-000000000001'),
  'queued'::notification_status,
  'داخل التطبيق: تصل بلا مزوّدٍ خارجيّ — والسؤالُ يبلغ ولو لم يُضبط مفتاح');

-- ═══════════════════════════════════════════════════════════════════════════
-- الضبط من اللوحة — وحدودُه
-- ═══════════════════════════════════════════════════════════════════════════
-- **قاعدةُ عملٍ لا تُضبط إلا بـSQL ليست مضبوطةً من الإدارة.** ويُختبر هنا
-- أنّ مدير المغسلة يضبطها، وأنّ حدودَه لا تتجاوز مغسلتَه.

-- مغسلةٌ ثانية ومديرُها — لاختبار الحدّ.
select auth.logout();
set local role postgres;
insert into laundries (id, name_ar, slug)
values ('44444444-4444-4444-4444-444444444444','مغسلةٌ أخرى','other');
insert into branches (id, laundry_id, name_ar, location)
values ('55555555-5555-5555-5555-555555555555','44444444-4444-4444-4444-444444444444',
        'فرعُ الأخرى', st_point(39.60,24.47)::geography);
insert into auth.users (id, phone) values
  ('a0000000-0000-0000-0000-000000000007','+966500000007');
insert into profiles (id, phone) values
  ('a0000000-0000-0000-0000-000000000007','+966500000007');
insert into user_roles (user_id, role, laundry_id, branch_id) values
  ('a0000000-0000-0000-0000-000000000007','branch_manager',
   '44444444-4444-4444-4444-444444444444','55555555-5555-5555-5555-555555555555');

-- ═══ ٢٩) مديرُ المغسلة يضبط مُهَلَها ════════════════════════════════════
set local role authenticated;
select auth.login_as('a0000000-0000-0000-0000-000000000002');   -- مدير «وصل»

update complaint_settings set window_hours = 96, auto_close_days = 5
where laundry_id = '11111111-1111-1111-1111-111111111111';

select assert_eq(
  (select window_hours from complaint_settings
   where laundry_id = '11111111-1111-1111-1111-111111111111'),
  96, 'الضبط: مديرُ المغسلة يعدّل مُهَلَها — لا مالكُ المنصّة وحده');

-- ═══ ٣٠) ولا يمسّ مغسلةً غيرها ══════════════════════════════════════════
-- **وهذا هو الحدّ الذي يجب أن يُختبر**: توسيعُ الكتابة بلا حدٍّ يجعل كلَّ
-- مديرٍ يضبط مُهَل الجميع.
select expect_no_rows($$
  update complaint_settings set window_hours = 1
  where laundry_id = '44444444-4444-4444-4444-444444444444'
$$, 'الحدّ: مديرٌ لا يضبط مُهَل مغسلةٍ لا يديرها');

select expect_denied($$
  insert into complaint_types (laundry_id, code, label_ar)
  values ('44444444-4444-4444-4444-444444444444','sneaky','نوعٌ مدسوس')
$$, 'الحدّ: ولا يزرع نوعًا في قائمة غيره');

select expect_denied($$
  insert into complaint_templates (laundry_id, event, channel, audience, body_ar)
  values ('44444444-4444-4444-4444-444444444444','resolved','in_app','customer','نصٌّ مدسوس')
$$, 'الحدّ: ولا قالبَ رسالةٍ في مغسلةٍ أخرى');

-- ═══ ٣١) وخدمةُ العملاء تعالج ولا تُشرّع ════════════════════════════════
-- **من يملك تمديد مهلة التأكيد يملك إغلاق ما يشاء بالصمت.**
select auth.login_as('a0000000-0000-0000-0000-000000000005');
select expect_no_rows($$
  update complaint_settings set auto_close_days = 1
  where laundry_id = '11111111-1111-1111-1111-111111111111'
$$, 'الفصل: خدمةُ العملاء تعالج الشكاوى ولا تُعدّل قواعدَها');

-- ═══ ٣٢) والنوعُ يُعطَّل ولا يُحذف إن استُعمل ═══════════════════════════
select auth.login_as('a0000000-0000-0000-0000-000000000002');
select expect_denied($$
  delete from complaint_types
  where laundry_id = '11111111-1111-1111-1111-111111111111'
    and code = 'stain_remains'
$$, 'التاريخ: نوعٌ استُعمل لا يُحذف — والحذفُ يُفرغ شكاوى قديمةً من معناها');

update complaint_types set is_active = false
where laundry_id = '11111111-1111-1111-1111-111111111111' and code = 'stain_remains';
select assert_eq(
  (select is_active from complaint_types
   where laundry_id = '11111111-1111-1111-1111-111111111111' and code = 'stain_remains'),
  false, 'التعطيل: البديلُ الصحيح — يختفي من القائمة ويبقى في التاريخ');

-- ونوعٌ لم يُستعمل يُحذف بلا مانع.
insert into complaint_types (laundry_id, code, label_ar)
values ('11111111-1111-1111-1111-111111111111','unused','نوعٌ لم يُستعمل');
delete from complaint_types
where laundry_id = '11111111-1111-1111-1111-111111111111' and code = 'unused';
select assert_eq(
  (select count(*)::int from complaint_types
   where laundry_id = '11111111-1111-1111-1111-111111111111' and code = 'unused'),
  0, 'الحذف: ما لم يُستعمل يُحذف — الحراسةُ على المعنى لا على الحركة');

-- ═══ ٣٣) والرمزُ لا يتبدّل تحت شكوى قائمة ═══════════════════════════════
-- **الرمزُ يُجمَّع عليه في التقارير**، وتبديلُه على نوعٍ استُعمل يجعل تقريرَ
-- الشهر الماضي يقول شيئًا غير الذي وقع.
select expect_denied($$
  update complaint_types set code = 'renamed'
  where laundry_id = '11111111-1111-1111-1111-111111111111'
    and code = 'stain_remains'
$$, 'التقرير: رمزُ نوعٍ استُعمل لا يُبدَّل');

-- والاسمُ المعروض يُعدَّل بحرّيّة: صياغةٌ تُحسَّن لا هُويّةٌ تُبدَّل.
update complaint_types set label_ar = 'بقعةٌ لم تُزَل تمامًا'
where laundry_id = '11111111-1111-1111-1111-111111111111' and code = 'stain_remains';
select assert_eq(
  (select label_ar from complaint_types
   where laundry_id = '11111111-1111-1111-1111-111111111111' and code = 'stain_remains'),
  'بقعةٌ لم تُزَل تمامًا',
  'الصياغة: الاسمُ المعروض يُحسَّن — والرمزُ تحته ثابت');

-- ═══ ٣٤) ولا يُنقل صفٌّ من مغسلةٍ إلى أخرى ══════════════════════════════
select expect_denied($$
  update complaint_types set laundry_id = '44444444-4444-4444-4444-444444444444'
  where laundry_id = '11111111-1111-1111-1111-111111111111' and code = 'other'
$$, 'النقل: نوعٌ لا يُهاجر إلى مغسلةٍ أخرى');

select expect_denied($$
  update complaint_templates set laundry_id = '44444444-4444-4444-4444-444444444444'
  where laundry_id = '11111111-1111-1111-1111-111111111111' and event = 'resolved'
$$, 'النقل: ولا قالبُ رسالة');

-- ═══ ٣٥) والقالبُ يُحرَّر فعلًا — لا يُقرأ فقط ══════════════════════════
update complaint_templates
set body_ar = 'قرارُنا: {ردّ_الإدارة}. أخبرنا إن كان يكفي خلال {مهلة_التأكيد} أيّام.'
where laundry_id = '11111111-1111-1111-1111-111111111111'
  and event = 'resolved' and channel = 'in_app';

select assert_eq(
  (select body_ar like 'قرارُنا:%' from complaint_templates
   where laundry_id = '11111111-1111-1111-1111-111111111111'
     and event = 'resolved' and channel = 'in_app'),
  true, 'التحرير: نصُّ الرسالة يُعدَّل من اللوحة — بلا إصدار تطبيق');

-- ═══ ٣٦) والزائرُ لا يكتب شيئًا من هذا ══════════════════════════════════
select auth.logout();
set local role anon;
select expect_no_rows($$
  update complaint_settings set window_hours = 1
  where laundry_id = '11111111-1111-1111-1111-111111111111'
$$, 'الزائر: لا يمسّ إعداداتٍ ولا قوالب');

set local role postgres;
select auth.logout();

rollback;
