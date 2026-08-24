-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | تحسين تقييم سياسات RLS
-- ═══════════════════════════════════════════════════════════════════════════
--
-- عطلُ أداءٍ لا يظهر في اختبارٍ ولا على جدولٍ فارغ، ويظهر بعد أشهر:
--
--   `auth.uid()` داخل سياسة RLS تُقيَّم **لكل صفّ يُفحص**. فقراءةُ جدولٍ فيه
--   مئة ألف طلبٍ تنادي الدالّة مئة ألف مرّة لتعطي القيمة نفسها في كل مرّة.
--
-- والحلّ لفّها في استعلامٍ فرعيّ: `(select auth.uid())`. فيرفعها المخطِّط إلى
-- **InitPlan** يُنفَّذ مرّةً واحدة قبل المسح، وتُستعمل نتيجته لكل الصفوف. لا
-- تتغيّر الدلالة بحرف — ويتغيّر الزمن من خطّيٍّ في عدد الصفوف إلى ثابت.
--
-- ولماذا كتلةٌ ديناميكية لا إحدى وأربعين جملة مكتوبة: النصّ المخزَّن للسياسة
-- هو مصدر الحقيقة، وإعادةُ بنائه منه تضمن أن يبقى ما عدا النداء كما هو حرفيًّا
-- — بينما إعادة كتابة إحدى وأربعين سياسة يدويًّا تدعو إلى خطأ صامت في واحدة.

set search_path = public, extensions;

do $$
declare
  r   record;
  ddl text;
begin
  for r in
    select tablename, policyname, permissive, roles, cmd, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (coalesce(qual,'') like '%auth.uid()%'
        or coalesce(with_check,'') like '%auth.uid()%'
        or coalesce(qual,'') like '%auth_is_super_admin()%'
        or coalesce(with_check,'') like '%auth_is_super_admin()%')
      -- ما لُفّ من قبل يُترك: إعادة التشغيل لا تضاعف الأقواس.
      and coalesce(qual,'') not like '%( SELECT auth.uid()%'
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);

    ddl := format('create policy %I on public.%I as %s for %s to %s',
      r.policyname, r.tablename,
      case when r.permissive = 'PERMISSIVE' then 'permissive' else 'restrictive' end,
      r.cmd,
      array_to_string(r.roles, ', '));

    if r.qual is not null then
      ddl := ddl || format(' using (%s)',
        replace(replace(r.qual,
          'auth.uid()', '(select auth.uid())'),
          'auth_is_super_admin()', '(select auth_is_super_admin())'));
    end if;

    if r.with_check is not null then
      ddl := ddl || format(' with check (%s)',
        replace(replace(r.with_check,
          'auth.uid()', '(select auth.uid())'),
          'auth_is_super_admin()', '(select auth_is_super_admin())'));
    end if;

    execute ddl;
  end loop;
end $$;

-- ملاحظة على ما لا يُلَفّ: `auth_has_branch_role(branch_id, ...)` تأخذ عمودًا
-- من الصفّ، فهي per-row بطبيعتها ولا تُرفع إلى InitPlan. ولا يُصلحها لفٌّ —
-- يُصلحها فهرسٌ على `branch_id`، وهو موجود.
