-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | تحصين الدوالّ
-- ═══════════════════════════════════════════════════════════════════════════
--
-- ثغرتان كشفهما مدقّق Supabase ولم يمسكهما اختبارنا:
--
-- ١) **مسار البحث في كل دالّة لا في `security definer` وحدها.** كان اختبارنا
--    يفحص الأخيرة فقط. والدالّة العادية تعمل بصلاحية مناديها — لكنها تُستدعى
--    من داخل سياسات RLS ومن المحفّزات، ومسارٌ قابل للتلاعب يجعلها تحلّ اسم
--    جدولٍ إلى جدولٍ آخر يزرعه المهاجم في schema يسبقنا في المسار.
--
-- ٢) **`grant execute on all functions` كان فضفاضًا.** كشف دوالَّ المحفّزات
--    نفسها على الواجهة: `/rest/v1/rpc/guard_role_grants` و
--    `/rest/v1/rpc/enforce_order_transition`. وهي ليست واجهةً يُنادى منها،
--    بل حرّاسٌ يستدعيهم Postgres. وكشفُها لا يفيد أحدًا ويوسّع سطح الهجوم
--    بلا مقابل.

set search_path = public, extensions;

-- ── ١) تثبيت مسار البحث في كل دالّة ──────────────────────────────────────
-- بالدوران لا بالتعداد: دالّةٌ تُضاف غدًا في مهاجرةٍ تنسى `set search_path`
-- تُصلَح بإعادة تشغيل هذه الكتلة، ولا تحتاج تذكّر اسمها.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
        where cfg like 'search_path=%')
  loop
    execute format('alter function %s set search_path = public, extensions', r.sig);
  end loop;
end $$;

-- ── ٢) سحب التنفيذ من دوالّ المحفّزات ────────────────────────────────────
-- دالّةُ المحفّز تُعرَف بنوع إرجاعها (`trigger`)، فلا حاجة لقائمةٍ تُحدَّث.
-- وPostgres يستدعيها بصلاحية مالك الجدول لا بصلاحية المستخدم، فسحبُ المنح
-- لا يعطّل محفّزًا واحدًا — يُخفيها عن الواجهة وحدها.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke execute on function %s from anon, authenticated, public', r.sig);
  end loop;
end $$;

-- ── ٣) وسحبه من الزائر على ما لا يخصّه ───────────────────────────────────
-- **مصيدةٌ تُبطل السحب**: Postgres يمنح `EXECUTE` لـ`PUBLIC` على كل دالّة
-- جديدة تلقائيًّا. و`anon` يرث ذلك المنح. فـ`revoke ... from anon` وحده لا
-- يمنع شيئًا — تبقى الدالّة مكشوفة، ويبدو الإصلاح ناجحًا وهو لم يفعل شيئًا.
-- ولذلك السحب من `public` أوّلًا، ثم المنح لمن يستحقّ صراحةً.
do $$
declare r record;
begin
  for r in
    select unnest(array[
      'ensure_profile(text)',
      'loyalty_balance(uuid, uuid)',
      'quote_loyalty_redemption(uuid, uuid, numeric)',
      'quote_coupon(text, uuid, uuid, uuid, numeric, numeric)',
      'order_piece_load(uuid)'
    ]) as sig
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

-- ── ما بقي مكشوفًا عمدًا ─────────────────────────────────────────────────
-- دوالّ الصلاحية (auth_has_role وأخواتها و can_see_order) تبقى منشورةً
-- للدورين. وهذا ليس تساهلًا بل ضرورة أثبتها التجريب: **سياسة RLS تُقيَّم
-- بصلاحية المستخدم، فتشترط عليه صلاحية التنفيذ على ما تستدعيه.** وسحبُ المنح
-- عنها يجعل كل قراءةٍ تفشل بـ«permission denied for function».
--
-- وهي لا تُفشي شيئًا على أي حال: كلٌّ منها تجيب عن **مُناديها هو** لا عن
-- غيره، فنداؤها مباشرةً يعطي المهاجم ما يعرفه أصلًا عن نفسه. ومدقّق Supabase
-- سيظلّ يحذّر منها — وهو تحذيرٌ مقروءٌ ومقصود، لا إهمال.
