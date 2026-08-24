-- ═══════════════════════════════════════════════════════════════════════════
-- اختبار عزل المخطّط
-- ═══════════════════════════════════════════════════════════════════════════
-- المشروع مشترك مع تطبيق آخر على الخطّة نفسها. والشرط: **بقربه لا فوقه**.
-- هذه الاختبارات حارسُ انحدار: أوّل مهاجرةٍ تنسى `wasl.` أو تُثبّت امتدادًا
-- في مخطّطنا تُمسك هنا، لا بعد أن يتعطّل تطبيق الشريك في الإنتاج.

\set ON_ERROR_STOP on
begin;

do $$
declare n int;
begin
  -- ١) لا جدول لنا في public
  select count(*) into n from pg_tables where schemaname = 'public';
  if n <> 0 then
    raise exception '✗ تسرّب: % جدولًا في public — يجب أن تبقى فارغة', n;
  end if;
  raise notice '✓ العزل: لا جدول واحد في public';

  -- ٢) جداولنا كلها في wasl
  select count(*) into n from pg_tables where schemaname = 'wasl';
  if n < 20 then
    raise exception '✗ العزل: توقّعنا 20 جدولًا فأكثر في wasl وجاء %', n;
  end if;
  raise notice '✓ العزل: % جدولًا في مخطّط wasl', n;

  -- ٣) لا امتداد مثبَّت في مخطّطنا.
  -- الخطر: `drop schema wasl cascade` يُسقط الامتداد معه فيتعطّل الشريك.
  select count(*) into n
  from pg_extension e join pg_namespace ns on ns.oid = e.extnamespace
  where ns.nspname = 'wasl';
  if n <> 0 then
    raise exception '✗ خطر: % امتدادًا مثبَّتًا في wasl — حذف المخطّط يُسقطه', n;
  end if;
  raise notice '✓ العزل: لا امتداد مثبَّت في wasl';

  -- ٤) ودوالّنا وحدها فيه — لا تسع مئة دالّة PostGIS
  select count(*) into n
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'wasl';
  if n > 40 then
    raise exception '✗ تلوّث: % دالّة في wasl — امتدادٌ تسرّب إليه', n;
  end if;
  raise notice '✓ العزل: % دالّة في wasl — دوالّنا وحدها', n;

  -- ٥) RLS مفعّلة على كل جدول، بلا استثناء منسيّ
  select count(*) into n
  from pg_tables t join pg_class c on c.relname = t.tablename
  join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = t.schemaname
  where t.schemaname = 'wasl' and not c.relrowsecurity;
  if n <> 0 then
    raise exception '✗ ثغرة: % جدولًا بلا RLS', n;
  end if;
  raise notice '✓ الأمان: RLS مفعّلة على كل جدول في wasl';

  -- ٦) و`force` عليها كذلك — بدونها يتجاوزها مالك الجدول بصمت
  select count(*) into n
  from pg_tables t join pg_class c on c.relname = t.tablename
  join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = t.schemaname
  where t.schemaname = 'wasl' and not c.relforcerowsecurity;
  if n <> 0 then
    raise exception '✗ ثغرة: % جدولًا بلا force RLS', n;
  end if;
  raise notice '✓ الأمان: force RLS مفعّلة على كل جدول';

  -- ٧) ولا جدول بلا سياسة واحدة: RLS مفعّلة بلا سياسات تعني منعًا كاملًا —
  -- عطلٌ يظهر كـ«الشاشة فارغة» لا كخطأ.
  select count(*) into n
  from pg_tables t
  where t.schemaname = 'wasl'
    and not exists (select 1 from pg_policies p
                    where p.schemaname = 'wasl' and p.tablename = t.tablename);
  if n <> 0 then
    raise exception '✗ عطل: % جدولًا بـRLS وبلا سياسة — لا أحد يقرأه', n;
  end if;
  raise notice '✓ الأمان: كل جدول له سياسة واحدة على الأقل';
end $$;

-- ٨) لا محفّز لنا على auth.users — وهو ما يمنع تلوّث جدولنا بمستخدمي الشريك
do $$
declare n int;
begin
  select count(*) into n from pg_trigger tg
  join pg_class c on c.oid = tg.tgrelid
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'auth' and c.relname = 'users' and not tg.tgisinternal;
  if n <> 0 then
    raise exception '✗ تلوّث: % محفّزًا على auth.users — تسجيلُ الشريك سيصنع عميل مغسلة', n;
  end if;
  raise notice '✓ العزل: لا محفّز على auth.users';
end $$;

rollback;
