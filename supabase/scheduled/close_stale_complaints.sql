-- ═══════════════════════════════════════════════════════════════════════════
-- كنسُ الشكاوى المنقضية مهلةُ تأكيدها
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **قاعدةُ عملٍ تنتظر أن يفتح أحدٌ شاشةً ليست قاعدةَ عمل.** الدالّة مقفلةٌ
-- على الحزم عمدًا، فتُنادى من هنا بصلاحية القاعدة.
--
-- وكلَّ ساعة لا كلَّ دقيقة: المهلةُ بالأيّام، فدقّةُ ساعةٍ تكفي — ودقيقةٌ
-- تُشغّل الخادم ٦٠ مرّةً في الساعة على جدولٍ يكون فارغًا غالبًا.
--
-- والدالّةُ نفسُها لا تُغلق شكوى لم يُصفَّ لصاحبها إشعارُ حلّ: الصمتُ رضًا
-- لمن سُئل وحده.

create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'close-stale-complaints') then
    perform cron.unschedule('close-stale-complaints');
  end if;
  perform cron.schedule(
    'close-stale-complaints', '7 * * * *',
    $cmd$select public.close_stale_complaints()$cmd$);
end $$;
