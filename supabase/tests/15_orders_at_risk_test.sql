-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار التنبّؤ بالتأخير
-- ═══════════════════════════════════════════════════════════════════════════
-- **الخطر هنا رقمٌ يُصدَّق ولا يستحقّ**: تقديرٌ مبنيٌّ على طلبين يُعرض كأنه
-- علم، فتُستعجل طلباتٌ لا تحتاج استعجالًا وتُهمَل التي تحتاجه. ولذلك يُختبر
-- **إعلانُ الضعف** كما تُختبر صحّةُ الحساب.
--
-- ويُختبر أن الوسيط لا المتوسّط: طلبٌ واحدٌ نُسي في الغسّالة يومين يرفع
-- المتوسّط فيجعل كلَّ طلبٍ يبدو معرَّضًا — والوسيط لا يتأثّر به.

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
  ('a0000000-0000-0000-0000-000000000001','+966500000001');
insert into profiles (id, phone, full_name)
values ('a0000000-0000-0000-0000-000000000001','+966500000001','محمد');

-- ── تاريخٌ صناعيّ: عشرةُ طلباتٍ مرّت بالأطوار بمُددٍ معلومة ───────────────
-- الغسيل ساعتان، والتجفيف ساعة، والكيّ ساعة، والتغليف نصف ساعة.
-- فمن دخل «الغسيل» يبقى أمامه ٤٫٥ ساعة حتى الجاهزية.
do $$
declare
  i int;
  v_order uuid;
  v_base timestamptz := now() - interval '10 days';
begin
  for i in 1..10 loop
    v_order := uuid_generate_v4();
    insert into orders (id, laundry_id, branch_id, customer_id, status, total,
                        created_at)
    values (v_order, '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222',
            'a0000000-0000-0000-0000-000000000001', 'ready', 100,
            v_base + make_interval(days => i));

    -- تُكتب الأحداث مباشرةً: المحفّز يكتب بوقت `now()`، والاختبار يحتاج
    -- تاريخًا بمُددٍ يتحكّم فيها.
    insert into order_events (order_id, from_status, to_status, created_at) values
      (v_order, 'at_laundry', 'sorting',   v_base + make_interval(days => i)),
      (v_order, 'sorting',    'washing',   v_base + make_interval(days => i, mins => 30)),
      (v_order, 'washing',    'drying',    v_base + make_interval(days => i, mins => 150)),
      (v_order, 'drying',     'ironing',   v_base + make_interval(days => i, mins => 210)),
      (v_order, 'ironing',    'packaging', v_base + make_interval(days => i, mins => 270)),
      (v_order, 'packaging',  'ready',     v_base + make_interval(days => i, mins => 300));
  end loop;
end $$;

-- ═══ ١) المُدد تُقرأ من الواقع لا من تقدير ═══════════════════════════════
-- الغسيل: من دخوله (٣٠ د) إلى دخول التجفيف (١٥٠ د) = ١٢٠ دقيقة.
select assert_eq(
  (select round(median_hours * 60) from
     report_stage_durations('22222222-2222-2222-2222-222222222222',
                            (current_date - 30), current_date)
   where stage = 'washing'),
  120::numeric, 'المُدد: الغسيل ساعتان كما وقع فعلًا');

-- ═══ ٢) طلبٌ في الغسيل ووعدُه بعد ساعة ⇒ معرَّض ═════════════════════════
-- أمامه ٤٫٥ ساعة (غسيل ساعتان + تجفيف + كيّ + تغليف)، ووعدُه بعد ساعة.
insert into orders (id, laundry_id, branch_id, customer_id, status, total,
                    promised_ready_at)
values ('0dd00000-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'washing', 100, now() + interval '1 hour');
insert into order_events (order_id, from_status, to_status, created_at)
values ('0dd00000-0000-0000-0000-00000000000a','sorting','washing', now());

select assert_eq(
  (select count(*)::int from orders_at_risk('22222222-2222-2222-2222-222222222222')),
  1, 'الإنذار: الطلب المعرَّض يُلتقط');

do $$
declare r record;
begin
  select * into r from orders_at_risk('22222222-2222-2222-2222-222222222222');
  -- ٤٫٥ ساعة أمامه، ووعدُه بعد ساعة ⇒ يتأخّر ٣٫٥ ساعة = ٢١٠ دقيقة.
  if abs(r.late_by_minutes - 210) > 5 then
    raise exception '✗ الحساب: توقّعنا تأخّرًا نحو ٢١٠ د وجاء % د', r.late_by_minutes;
  end if;
  raise notice '✓ الحساب: التأخّر المتوقّع % دقيقة — من مُدد الأطوار', r.late_by_minutes;

  if r.already_late then
    raise exception '✗ التمييز: طلبٌ لم يتجاوز وعدَه عُدَّ متأخّرًا';
  end if;
  raise notice '✓ التمييز: «سيتأخّر» ليست «تأخّر» — والفرق هو الفائدة كلُّها';

  if not r.confident then
    raise exception '✗ الثقة: عشرةُ طلباتٍ في التاريخ ولم يُعَدّ التقدير موثوقًا';
  end if;
  raise notice '✓ الثقة: عشرُ عيّناتٍ تكفي (% عيّنة)', r.samples;
end $$;

-- ═══ ٣) طلبٌ وعدُه بعد أسبوع لا يُنذَر عنه ══════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status, total,
                    promised_ready_at)
values ('0dd00000-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'washing', 100, now() + interval '7 days');
insert into order_events (order_id, from_status, to_status, created_at)
values ('0dd00000-0000-0000-0000-00000000000b','sorting','washing', now());

select assert_eq(
  (select count(*)::int from orders_at_risk('22222222-2222-2222-2222-222222222222')
   where order_id = '0dd00000-0000-0000-0000-00000000000b'),
  0, 'الهدوء: ما يسع وقتُه لا يُنذَر عنه — والإنذار الكاذب يُدرَّب على تجاهله');

-- ═══ ٤) والمتأخّر فعلًا يُميَّز ═══════════════════════════════════════════
insert into orders (id, laundry_id, branch_id, customer_id, status, total,
                    promised_ready_at)
values ('0dd00000-0000-0000-0000-00000000000c','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001',
        'drying', 100, now() - interval '2 hours');
insert into order_events (order_id, from_status, to_status, created_at)
values ('0dd00000-0000-0000-0000-00000000000c','washing','drying', now() - interval '1 hour');

select assert_eq(
  (select already_late from orders_at_risk('22222222-2222-2222-2222-222222222222')
   where order_id = '0dd00000-0000-0000-0000-00000000000c'),
  true, 'المتأخّر: من تجاوز وعدَه يُوسَم متأخّرًا لا متوقَّعًا');

-- ═══ ٥) الوسيط لا يتأثّر بطلبٍ نُسي ═════════════════════════════════════
-- يُضاف طلبٌ بقي في الغسيل ثلاثة أيام: المتوسّط يقفز، والوسيط يثبت.
do $$
declare v_order uuid := uuid_generate_v4(); v_late numeric;
begin
  select late_by_minutes into v_late
  from orders_at_risk('22222222-2222-2222-2222-222222222222')
  where order_id = '0dd00000-0000-0000-0000-00000000000a';

  insert into orders (id, laundry_id, branch_id, customer_id, status, total, created_at)
  values (v_order, '11111111-1111-1111-1111-111111111111',
          '22222222-2222-2222-2222-222222222222',
          'a0000000-0000-0000-0000-000000000001', 'ready', 100,
          now() - interval '5 days');
  insert into order_events (order_id, from_status, to_status, created_at) values
    (v_order, 'sorting', 'washing', now() - interval '5 days'),
    (v_order, 'washing', 'drying',  now() - interval '2 days');

  if abs((select late_by_minutes from orders_at_risk('22222222-2222-2222-2222-222222222222')
          where order_id = '0dd00000-0000-0000-0000-00000000000a') - v_late) > 20 then
    raise exception '✗ الوسيط: طلبٌ شاذٌّ واحد غيّر التقدير — فالمستعمَل متوسّط';
  end if;
  raise notice '✓ الوسيط: طلبٌ نُسي ثلاثة أيام لا يقلب التقدير';
end $$;

-- ═══ ٦) فرعٌ بلا تاريخ: يُعلَن ضعفُ التقدير ولا يُخترع رقم ══════════════
insert into branches (id, laundry_id, name_ar, location)
values ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
        'فرعٌ جديد', st_point(39.6170,24.4390)::geography);
insert into orders (id, laundry_id, branch_id, customer_id, status, total,
                    promised_ready_at)
values ('0dd00000-0000-0000-0000-00000000000d','11111111-1111-1111-1111-111111111111',
        '33333333-3333-3333-3333-333333333333','a0000000-0000-0000-0000-000000000001',
        'washing', 100, now() - interval '1 hour');

do $$
declare r record; n int;
begin
  select count(*) into n from orders_at_risk('33333333-3333-3333-3333-333333333333');
  if n <> 1 then
    raise exception '✗ الفرع الجديد: توقّعنا صفًّا واحدًا (متأخّرٌ فعلًا) وجاء %', n;
  end if;

  select * into r from orders_at_risk('33333333-3333-3333-3333-333333333333');
  if r.confident then
    raise exception '✗ الثقة: فرعٌ بلا تاريخٍ أعطى تقديرًا موثوقًا';
  end if;
  raise notice '✓ الفرع الجديد: يُعلَن ضعفُ التقدير (% عيّنة) ولا يُخترع رقم', r.samples;
end $$;

-- ═══ ٧) وحدُّ الثقة معطًى لا ثابت ════════════════════════════════════════
select assert_eq(
  (select confident from orders_at_risk('22222222-2222-2222-2222-222222222222', 30, 100)
   where order_id = '0dd00000-0000-0000-0000-00000000000a'),
  false, 'الثقة: رفعُ الحدّ يُسقط الثقة — القرار للإدارة لا للشيفرة');

-- ═══ ٨) والحدود محفوظة: فرعٌ لا يرى طلبات فرعٍ آخر ══════════════════════
select assert_eq(
  (select count(*)::int from orders_at_risk('33333333-3333-3333-3333-333333333333')
   where order_id in ('0dd00000-0000-0000-0000-00000000000a',
                      '0dd00000-0000-0000-0000-00000000000c')),
  0, 'الحدود: كلُّ فرعٍ وطلباتُه');

rollback;
