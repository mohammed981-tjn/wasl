-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار نظافة المخطّط والأمان البنيويّ
-- ═══════════════════════════════════════════════════════════════════════════
-- حارسُ انحدار: هذه ثغراتٌ لا تظهر في اختبارٍ وظيفيّ. جدولٌ يُضاف غدًا بلا
-- RLS يعمل تمامًا — ويُقرأ من الجميع. وجدولٌ بـRLS وبلا سياسة يعمل تمامًا —
-- ولا يقرؤه أحد، فتظهر «شاشةٌ فارغة» لا خطأ. كلاهما يُمسك هنا أو في الإنتاج.

\set ON_ERROR_STOP on
begin;

set local search_path = public, extensions;

do $$
declare n int; names text;
begin
  -- ١) الامتدادات في `extensions` لا في `public`
  -- PostGIS وحدها تسع مئة دالّة: تركُها في public يُغرق توليد الأنواع
  -- وقوائم الاستكشاف، ويجعل cascade خطرًا لا يُقرأ أثره.
  select count(*) into n
  from pg_extension e join pg_namespace ns on ns.oid = e.extnamespace
  where ns.nspname = 'public';
  if n <> 0 then
    raise exception '✗ النظافة: % امتدادًا في public — موضعها extensions', n;
  end if;
  raise notice '✓ النظافة: لا امتداد في public';

  -- ٢) ودوالّنا وحدها فيه: عددٌ كبير يعني امتدادًا تسرّب
  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public';
  if n > 60 then
    raise exception '✗ النظافة: % دالّة في public — امتدادٌ تسرّب إليه', n;
  end if;
  raise notice '✓ النظافة: % دالّة في public — دوالّنا وحدها', n;

  -- ٣) RLS مفعّلة على كل جدول، بلا استثناء منسيّ
  select count(*), string_agg(t.tablename, '، ') into n, names
  from pg_tables t
  join pg_class c on c.relname = t.tablename
  join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = t.schemaname
  where t.schemaname = 'public' and not c.relrowsecurity;
  if n <> 0 then
    raise exception '✗ ثغرة: % جدولًا بلا RLS — يُقرأ من الجميع: %', n, names;
  end if;
  raise notice '✓ الأمان: RLS مفعّلة على كل جدول';

  -- ٤) و`force` كذلك: بدونها يتجاوزها مالك الجدول بصمت، فيبدو الاختبار
  -- ناجحًا وهو لم يمرّ بسياسةٍ أصلًا
  select count(*), string_agg(t.tablename, '، ') into n, names
  from pg_tables t
  join pg_class c on c.relname = t.tablename
  join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = t.schemaname
  where t.schemaname = 'public' and not c.relforcerowsecurity;
  if n <> 0 then
    raise exception '✗ ثغرة: % جدولًا بلا force RLS: %', n, names;
  end if;
  raise notice '✓ الأمان: force RLS مفعّلة على كل جدول';

  -- ٥) ولا جدول بـRLS وبلا سياسة: يعمل تمامًا ولا يقرؤه أحد
  select count(*), string_agg(t.tablename, '، ') into n, names
  from pg_tables t
  where t.schemaname = 'public'
    and not exists (select 1 from pg_policies p
                    where p.schemaname = 'public' and p.tablename = t.tablename);
  if n <> 0 then
    raise exception '✗ عطل: % جدولًا بـRLS وبلا سياسة — شاشةٌ فارغة لا خطأ: %', n, names;
  end if;
  raise notice '✓ الأمان: كل جدول له سياسة واحدة على الأقل';

  -- ٦) كل دالّة بمسار بحثٍ مثبَّت — لا `security definer` وحدها.
  -- كان هذا الفحص مقصورًا عليها، ومدقّق Supabase أمسك ثلاث عشرة دالّة عادية
  -- فاتته. والعادية تعمل بصلاحية مناديها، لكنها تُستدعى من داخل سياسات RLS
  -- ومن المحفّزات — ومسارٌ قابل للتلاعب يجعلها تحلّ اسم جدولٍ إلى جدولٍ يزرعه
  -- المهاجم في schema يسبقنا.
  select count(*), string_agg(p.proname, '، ') into n, names
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.prokind = 'f'
    and not exists (
      select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
      where cfg like 'search_path=%');
  if n <> 0 then
    raise exception '✗ ثغرة: % دالّة بلا search_path مثبَّت: %', n, names;
  end if;
  raise notice '✓ الأمان: كل دالّة بمسار بحثٍ مثبَّت';

  -- ٧) لا دالّة محفّزٍ مكشوفةٌ على الواجهة.
  -- `grant execute on all functions` يكشف الحرّاس أنفسهم عبر /rest/v1/rpc/ —
  -- وهي ليست واجهةً يُنادى منها بل حرّاسٌ يستدعيهم Postgres بصلاحية مالك
  -- الجدول. كشفُها يوسّع سطح الهجوم بلا مقابل.
  select count(*), string_agg(p.proname, '، ') into n, names
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.prorettype = 'trigger'::regtype
    and (has_function_privilege('anon', p.oid, 'execute')
      or has_function_privilege('authenticated', p.oid, 'execute'));
  if n <> 0 then
    raise exception '✗ سطح هجوم: % دالّة محفّز مكشوفة على الواجهة: %', n, names;
  end if;
  raise notice '✓ الأمان: لا دالّة محفّز مكشوفة على الواجهة';
end $$;

-- ٧) لا محفّز لنا على auth.users.
-- Supabase يملك هذا الجدول ولا نملكه؛ ومحفّزٌ عليه يربط تسجيلَ كل مستخدم
-- بنجاح شيفرتنا — فيفشل التسجيل نفسه إن أخطأنا.
do $$
declare n int;
begin
  select count(*) into n from pg_trigger tg
  join pg_class c on c.oid = tg.tgrelid
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'auth' and c.relname = 'users' and not tg.tgisinternal;
  if n <> 0 then
    raise exception '✗ % محفّزًا على auth.users — تسجيلُ كل مستخدم مرهونٌ بشيفرتنا', n;
  end if;
  raise notice '✓ العزل: لا محفّز على auth.users';
end $$;

-- ٨) كل مفتاح أجنبيّ مفهرس. غيابُ الفهرس لا يُفسد نتيجةً — يُبطئ كل استعلام
-- ربطٍ بصمت، ويجعل حذفَ الأب مسحًا كاملًا للابن.
do $$
declare n int; names text;
begin
  select count(*), string_agg(format('%s.%s', c.relname, a.attname), '، ')
    into n, names
  from pg_constraint fk
  join pg_class c on c.oid = fk.conrelid
  join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = 'public'
  join pg_attribute a on a.attrelid = c.oid and a.attnum = fk.conkey[1]
  where fk.contype = 'f'
    and array_length(fk.conkey, 1) = 1
    and not exists (
      select 1 from pg_index i
      where i.indrelid = fk.conrelid and i.indkey[0] = fk.conkey[1]);
  if n > 0 then
    raise exception '✗ الأداء: % مفتاحًا أجنبيًّا بلا فهرس: %', n, names;
  end if;
  raise notice '✓ الأداء: كل مفتاح أجنبيّ مفهرس';
end $$;

-- ٩) الإحداثيّات تُقرأ أرقامًا لا نصًّا سداسيًّا.
-- عمود `geography` يصل عبر PostgREST نصًّا مثل `0101000020E6100000...`،
-- والتطبيق الذي يقرأ منه `lat` يجد فراغًا فيضع صفرًا — فيصير موقع العميل عند
-- تقاطع خطّ الاستواء وغرينتش، وتُحسب مسافة التوصيل بآلاف الكيلومترات.
-- ولا يمسك ذلك اختبارُ SQL (القاعدة تحسب بالنوع الأصليّ صحيحًا) ولا محلّلُ
-- Dart (النوع dynamic). فيُمسك هنا.
do $$
declare v_lat double precision; v_lng double precision;
begin
  insert into laundries (id, name_ar, slug)
  values ('99999999-9999-9999-9999-999999999999', 'فحص', 'probe');
  insert into branches (id, laundry_id, name_ar, location)
  values ('99999999-9999-9999-9999-999999999998',
          '99999999-9999-9999-9999-999999999999', 'فحص',
          st_point(39.6142, 24.4672)::geography);

  select lat, lng into v_lat, v_lng
  from branches where id = '99999999-9999-9999-9999-999999999998';

  if round(v_lat::numeric, 4) <> 24.4672 or round(v_lng::numeric, 4) <> 39.6142 then
    raise exception '✗ الإحداثيّات: توقّعنا (24.4672, 39.6142) وجاء (%, %)', v_lat, v_lng;
  end if;
  raise notice '✓ الإحداثيّات: lat/lng عمودان مشتقّان يُقرآن أرقامًا';
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- فحوصُ ما قبل النشر
-- ═══════════════════════════════════════════════════════════════════════════

-- ١٠) كل عرضٍ بصلاحية مناديه لا بصلاحية منشئه.
-- **العرضُ `security definer` يتجاوز RLS الناظر إليه**: يقرأ بصلاحية من
-- أنشأه (وهو مالك الجدول)، فيصير نافذةً مفتوحةً على كل الصفوف. وهو الافتراض
-- في Postgres القديم، ولا يظهر أثره إلا حين ينظر مستخدمٌ فيرى ما ليس له.
do $$
declare n int; names text;
begin
  select count(*), string_agg(c.relname, '، ') into n, names
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relkind = 'v'
    and not exists (
      select 1 from unnest(coalesce(c.reloptions, '{}')) opt
      where opt = 'security_invoker=true' or opt = 'security_invoker=on');
  if n <> 0 then
    raise exception '✗ ثغرة: % عرضًا يقرأ بصلاحية منشئه لا مناديه: %', n, names;
  end if;
  raise notice '✓ الأمان: كل عرضٍ بصلاحية مناديه';
end $$;

-- ١١) الزائر يقرأ ولا يكتب.
-- `anon` هو من يفتح التطبيق ولم يسجّل بعد. وأيُّ منحِ كتابةٍ له يعني أن من
-- يملك المفتاح المنشور — وهو في كل حزمة — يكتب في القاعدة بلا حساب.
do $$
declare n int; names text;
begin
  select count(*), string_agg(format('%s:%s', table_name, privilege_type), '، ')
    into n, names
  from information_schema.role_table_grants
  where grantee = 'anon' and table_schema = 'public'
    and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if n <> 0 then
    raise exception '✗ ثغرة: الزائر يكتب في % موضعًا: %', n, names;
  end if;
  raise notice '✓ الأمان: الزائر يقرأ ولا يكتب';
end $$;

-- ١٢) لا سرَّ مخزَّنٌ نصًّا صريحًا.
-- عمودٌ اسمه `password` أو `secret` أو `api_key` في جدولٍ يقرؤه التطبيق هو
-- تسريبٌ مؤجَّل. والمسموح: ما ينتهي بـ`_hash` (مُجزَّأ لا يُفكّ)، والمفتاح
-- **المنشور** (`publishable_key`) وهو غير سرّيّ بتعريفه.
do $$
declare n int; names text;
begin
  select count(*), string_agg(format('%s.%s', c.relname, a.attname), '، ')
    into n, names
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = 'public'
  where c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
    and (a.attname ~* '(password|secret|api_key|private_key|token)')
    and a.attname !~* '_hash$'
    and a.attname <> 'publishable_key'
    -- رمز الجهاز للإشعارات ليس سرًّا يفتح شيئًا: يُرسَل إليه ولا يُقرأ منه.
    and not (c.relname = 'device_tokens' and a.attname = 'token');
  if n <> 0 then
    raise exception '✗ ثغرة: % عمودًا يبدو سرًّا نصًّا صريحًا: %', n, names;
  end if;
  raise notice '✓ الأمان: لا سرَّ نصًّا صريحًا في جدول';
end $$;

-- ١٣) طرقُ الخادم مغلقةٌ على الحزم.
-- هذه دوالٌّ تُنادى بمفتاح `service_role` من دوالّ Edge. وكشفُ إحداها
-- لـ`authenticated` يعني أن أيّ مستخدمٍ مسجَّل يطبّق نتيجة دفعٍ على طلبه.
do $$
declare fn text; n int := 0; names text := '';
begin
  foreach fn in array array[
    'apply_payment_result', 'open_payment_session', 'record_webhook_event'
  ] loop
    if exists (
      select 1 from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
      where p.proname = fn
        and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute'))
    ) then
      n := n + 1;
      names := names || fn || '، ';
    end if;
  end loop;
  if n <> 0 then
    raise exception '✗ ثغرة: % من طرق الخادم مكشوفةٌ على الحزم: %', n, names;
  end if;
  raise notice '✓ الأمان: طرقُ الخادم مغلقةٌ على الحزم';
end $$;


rollback;
