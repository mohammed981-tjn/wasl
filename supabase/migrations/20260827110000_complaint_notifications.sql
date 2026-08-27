-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | إشعاراتُ الشكاوى — وسكوتٌ لا يُفسَّر رضًا إلا إن سُئل صاحبُه
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **ثغرةٌ في ما بنيناه أمس، تُغلق هنا.**
--
-- بنينا دورةَ حياةٍ محورُها سؤالُ الشاكي: «هل حُلّت فعلًا؟». وجعلنا صمتَه
-- ثلاثةَ أيّامٍ إغلاقًا. وذلك عدلٌ **بشرطٍ واحد**: أن يكون قد سُئل.
--
-- ولم يكن يُسأل. لا إشعارَ يقول له إنّ ردًّا وصل ولا أنّ مهلةً تجري. فمن
-- لم يفتح التطبيق في ثلاثة أيّام تُغلق شكواه — **لا بصمتٍ بل بجهل**. وهذا
-- ليس نقصَ ميزةٍ بل خللٌ في العدل الذي بُني عليه النظام كلُّه.
--
-- فيُبنى هنا شيئان:
--
--   ١) **قوالبُ إشعارٍ للشكاوى** بجانب قوالب الطلبات — نصوصٌ تعدّلها الإدارة
--      لا سلاسلُ في شيفرة Dart.
--
--   ٢) **وحارسٌ في الكنس**: `close_stale_complaints()` لا تُغلق شكوى **لم
--      يُصفَّ لصاحبها إشعارُ حلٍّ** أصلًا. فإن لم تُضبط القوالب، أو تعذّر
--      الإرسال، بقيت الشكوى في الطابور ظاهرةً — وبقاؤها ظاهرةً أهونُ من
--      إغلاقها على من لم يُسأل.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- أحداثُ الشكوى التي تستحقّ رسالة
-- ─────────────────────────────────────────────────────────────────────────
-- **ليست كلَّ تغيّرٍ في الحالة.** «التُقطت» رسالةٌ تطمئن، و«حُلّت» رسالةٌ
-- **تطلب فعلًا**، و«ارتدّت» رسالةٌ للإدارة لا للشاكي. وإرسالُ رسالةٍ عند كل
-- تغيّرٍ يجعل المستخدم يُسكت الإشعارات كلَّها — فتضيع التي تهمّ.
create type complaint_event as enum (
  'opened',            -- فُتحت    ⟶ للإدارة: شكوى جديدة في الطابور
  'acknowledged',      -- التُقطت  ⟶ للشاكي: قرأها إنسان
  'resolved',          -- حُلّت    ⟶ للشاكي: **وهي التي تطلب جوابًا**
  'reopened',          -- ارتدّت   ⟶ للإدارة: الحلُّ لم يقنع صاحبَها
  'closed_by_timeout'  -- أُغلقت بالصمت ⟶ للشاكي: مجاملةً وإعلامًا
);

create table complaint_templates (
  id           uuid primary key default uuid_generate_v4(),
  laundry_id   uuid not null references laundries(id) on delete cascade,
  event        complaint_event not null,
  channel      notification_channel not null,
  audience     app_role not null default 'customer',

  title_ar     text,
  body_ar      text not null,
  title_en     text,
  body_en      text,

  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (laundry_id, event, channel, audience)
);

create index on complaint_templates (laundry_id, event) where is_active;

comment on table complaint_templates is
  'نصوصُ رسائل الشكوى — صفوفٌ تعدّلها الإدارة لا سلاسلُ تحتاج إصدارًا على المتجر.';

create trigger t_complaint_templates_updated
  before update on complaint_templates
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- الطابور يعرف الشكوى كما يعرف الطلب
-- ─────────────────────────────────────────────────────────────────────────
-- **ولماذا عمودٌ لا `order_id` وحده**: تذكرةٌ عامّةٌ بلا طلب لا مكان لها في
-- عمود الطلب، ورسالةٌ عن شكوى تُفتح على شكواها لا على طلبها.
alter table notifications
  add column complaint_id uuid references complaints(id) on delete cascade;

create index on notifications (complaint_id) where complaint_id is not null;

comment on column notifications.complaint_id is
  'الرسالةُ تُفتح على شكواها. وهو أيضًا أثرُ «سُئل صاحبُها» الذي يفحصه الكنس.';

-- ─────────────────────────────────────────────────────────────────────────
-- من يُرسَل إليه في كل حدث
-- ─────────────────────────────────────────────────────────────────────────
-- موظّفو خدمة العملاء ومديرُ الفرع — لا كلُّ من في المغسلة.
create or replace function complaint_staff_recipients(p_complaint complaints)
returns setof uuid
language sql stable security definer set search_path = public, extensions
as $$
  select distinct ur.user_id
  from user_roles ur
  where ur.laundry_id = p_complaint.laundry_id
    and (
      ur.role = 'customer_service'
      or (ur.role = 'branch_manager' and ur.branch_id = p_complaint.branch_id)
    );
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- التصفيف
-- ─────────────────────────────────────────────────────────────────────────
create or replace function queue_complaint_notifications()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_event  complaint_event;
  t        complaint_templates%rowtype;
  prefs    notification_preferences%rowtype;
  v_target uuid;
  v_vars   jsonb;
  v_days   int;
  v_type   text;
  v_branch text;
  v_allowed boolean;
  v_status notification_status;
begin
  -- **أيُّ حدثٍ وقع؟** لا يُرسَل عند كل تغيّر: التقاطٌ مكرَّرٌ لا حدث فيه،
  -- وحلٌّ ثانٍ بعد ارتدادٍ حدثٌ كالأوّل.
  if tg_op = 'INSERT' then
    v_event := 'opened';
  elsif new.status = 'in_progress' and old.status = 'open' then
    v_event := 'acknowledged';
  elsif new.status = 'resolved' and old.status is distinct from 'resolved' then
    v_event := 'resolved';
  elsif new.status = 'in_progress' and old.status = 'resolved' then
    v_event := 'reopened';
  elsif new.status = 'closed' and new.closed_by_timeout then
    v_event := 'closed_by_timeout';
  else
    return new;
  end if;

  select label_ar into v_type from complaint_types where id = new.type_id;
  select name_ar  into v_branch from branches where id = new.branch_id;
  select auto_close_days into v_days
  from complaint_settings where laundry_id = new.laundry_id;

  v_vars := jsonb_build_object(
    'رقم_الشكوى',  new.complaint_number::text,
    'نوع_الشكوى',  coalesce(v_type, ''),
    'رقم_الطلب',   coalesce((select order_number::text from orders where id = new.order_id), ''),
    'الفرع',       coalesce(v_branch, ''),
    'مهلة_التأكيد', coalesce(v_days, 3)::text,
    'ردّ_الإدارة',  coalesce(new.resolution, '')
  );

  for t in
    select * from complaint_templates
    where laundry_id = new.laundry_id and event = v_event and is_active
  loop
    -- الجمهورُ يُترجَم إلى أشخاص: «العميل» هو **الشاكي** أيًّا كان دورُه —
    -- فسائقٌ اشتكى يقرأ الردّ على شكواه كما يقرؤه عميل.
    for v_target in
      select case
        when t.audience in ('customer','driver','laundry_staff')
          then new.submitted_by
        else null end
      where t.audience in ('customer','driver','laundry_staff')
      union all
      select complaint_staff_recipients(new)
      where t.audience in ('customer_service','branch_manager','super_admin')
    loop
      if v_target is null then
        continue;
      end if;

      select * into prefs from notification_preferences where user_id = v_target;
      v_allowed := true;
      if found then
        v_allowed := case t.channel
          when 'push'     then prefs.push_enabled
          when 'sms'      then prefs.sms_enabled
          when 'whatsapp' then prefs.whatsapp_enabled
          when 'email'    then prefs.email_enabled
          else true
        end;
      end if;

      v_status := case when v_allowed then 'queued' else 'skipped' end::notification_status;

      insert into notifications
        (user_id, order_id, complaint_id, channel, title, body, status)
      values (
        v_target, new.order_id, new.id, t.channel,
        render_template(coalesce(t.title_ar, ''), v_vars),
        render_template(t.body_ar, v_vars),
        v_status);
    end loop;
  end loop;

  return new;
end;
$$;

create trigger t_complaints_notify
  after insert or update of status on complaints
  for each row execute function queue_complaint_notifications();

-- ─────────────────────────────────────────────────────────────────────────
-- والكنسُ لا يُغلق على من لم يُسأل
-- ─────────────────────────────────────────────────────────────────────────
-- **هذا هو جوهرُ هذه المهاجرة.** «الصمتُ رضًا» حكمٌ لا يصحّ إلا على من
-- بلغه السؤال. فيُشترط أن يكون قد صُفَّ للشاكي إشعارُ حلٍّ **بعد آخر حلّ**.
--
--   • `skipped` تُحتسب: العميل أوقف تلك القناة بنفسه، وذلك اختيارُه.
--   • ولا قوالبَ أصلًا ⟶ لا إغلاق. فتبقى الشكوى في الطابور ظاهرةً — وبقاءُ
--     صفٍّ في لوحةٍ أهونُ من إغلاقٍ على من لم يعلم أنّ أحدًا ردّ عليه.
create or replace function close_stale_complaints()
returns int
language plpgsql security definer set search_path = public, extensions
as $$
declare v_count int;
begin
  perform set_config('wasl.complaint_flow', 'on', true);

  with due as (
    select c.id
    from complaints c
    left join complaint_settings s on s.laundry_id = c.laundry_id
    where c.status = 'resolved'
      and c.resolved_at is not null
      and c.resolved_at + make_interval(days => coalesce(s.auto_close_days, 3)) < now()
      and exists (
        select 1 from notifications n
        where n.complaint_id = c.id
          and n.user_id = c.submitted_by
          and n.created_at >= c.resolved_at
      )
  )
  update complaints c set status = 'closed', closed_at = now(),
                          closed_by_timeout = true
  from due where c.id = due.id;

  get diagnostics v_count = row_count;
  perform set_config('wasl.complaint_flow', 'off', true);
  return v_count;
end;
$$;

comment on function close_stale_complaints() is
  'يُجدوَل على الخادم، ولا يُغلق شكوى لم يُصفَّ لصاحبها إشعارُ حلٍّ — الصمتُ رضًا لمن سُئل وحده.';

revoke execute on function close_stale_complaints() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- كم شكوى تنتظر جوابًا لم يبلغ صاحبَه؟
-- ─────────────────────────────────────────────────────────────────────────
-- **رقمٌ يجب أن يُرى.** شكوى محلولةٌ بلا إشعارٍ لن تُغلق أبدًا، وستقعد في
-- الطابور بلا سببٍ ظاهر. فيُعرض السببُ صريحًا بدل أن يُكتشف بعد شهر.
create or replace function complaints_unnotified(p_laundry uuid)
returns table (
  complaint_id     uuid,
  complaint_number bigint,
  resolved_at      timestamptz
)
language sql stable security invoker set search_path = public, extensions
as $$
  select c.id, c.complaint_number, c.resolved_at
  from complaints c
  where c.laundry_id = p_laundry
    and c.status = 'resolved'
    and c.resolved_at is not null
    and not exists (
      select 1 from notifications n
      where n.complaint_id = c.id
        and n.user_id = c.submitted_by
        and n.created_at >= c.resolved_at
    )
  order by c.resolved_at;
$$;

comment on function complaints_unnotified(uuid) is
  'شكاوى حُلّت ولم يبلغ أصحابَها — لن تُغلق تلقائيًّا، والسببُ يُعرض لا يُخبَّأ.';

-- ═════════════════════════════════════════════════════════════════════════
-- الأمان
-- ═════════════════════════════════════════════════════════════════════════
alter table complaint_templates enable row level security;
alter table complaint_templates force row level security;

create policy complaint_templates_read on complaint_templates
  for select using (auth.uid() is not null);
create policy complaint_templates_write on complaint_templates
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

grant select on complaint_templates to authenticated;
revoke insert, update, delete, truncate on complaint_templates
  from anon, authenticated;

revoke execute on function queue_complaint_notifications()
  from public, anon, authenticated;
revoke execute on function complaint_staff_recipients(complaints)
  from public, anon, authenticated;
revoke execute on function complaints_unnotified(uuid) from public, anon;
grant execute on function complaints_unnotified(uuid) to authenticated;

-- ═════════════════════════════════════════════════════════════════════════
-- قوالبُ افتراضيّة — كي يعمل النظام من أوّل يوم
-- ═════════════════════════════════════════════════════════════════════════
-- **ونظامٌ يحتاج تهيئةً يدويّةً قبل أن يعمل نظامٌ معطَّلٌ بصمت.** ولو تُركت
-- القوالب فارغة لَما أُغلقت شكوى واحدة أبدًا — بحكم الحارس أعلاه — ولَبدا
-- ذلك عطلًا لا حراسة.
--
-- والقناة `in_app` عمدًا: هي الوحيدة التي تعمل بلا مزوّدٍ خارجيّ (ومزوّد
-- الرسائل معلَّقٌ على المالك). فالسؤالُ يصل ولو لم يُضبط مفتاحٌ بعد.
create or replace function seed_complaint_templates(p_laundry uuid)
returns int
language plpgsql security definer set search_path = public, extensions
as $$
declare v_count int;
begin
  if not (auth_is_service_context() or auth_is_super_admin()) then
    raise exception 'بذرُ القوالب للمالك وحده' using errcode = 'insufficient_privilege';
  end if;

  insert into complaint_templates
    (laundry_id, event, channel, audience, title_ar, body_ar)
  values
    (p_laundry, 'opened', 'in_app', 'customer_service',
     'شكوى جديدة #{رقم_الشكوى}',
     '{نوع_الشكوى} — فرع {الفرع}، طلب #{رقم_الطلب}.'),

    (p_laundry, 'acknowledged', 'in_app', 'customer',
     'شكواك #{رقم_الشكوى} قيد المراجعة',
     'قرأنا شكواك «{نوع_الشكوى}» وبدأنا مراجعتها. سنعود إليك بالنتيجة.'),

    -- **وهذه الرسالةُ هي التي يقوم عليها النظام**: تقول إنّ ردًّا وصل، وإنّ
    -- جوابَه مطلوب، وإنّ للمهلة نهاية. وبلا هذه الثلاثة يصير الإغلاقُ
    -- بالصمت إغلاقًا بالجهل.
    (p_laundry, 'resolved', 'in_app', 'customer',
     'ردٌّ على شكواك #{رقم_الشكوى}',
     '{ردّ_الإدارة}

هل حُلّت مشكلتك فعلًا؟ افتح «شكاويّ» وأخبرنا: «نعم» تُغلق الملفّ، و«لا» تعيده إلينا بأولويّة. وإن لم تُجب خلال {مهلة_التأكيد} أيّام أُغلق تلقائيًّا.'),

    (p_laundry, 'reopened', 'in_app', 'customer_service',
     'شكوى ارتدّت #{رقم_الشكوى}',
     'قال صاحبُها إنّها لم تُحل. {نوع_الشكوى} — فرع {الفرع}.'),

    (p_laundry, 'closed_by_timeout', 'in_app', 'customer',
     'أُغلقت شكواك #{رقم_الشكوى}',
     'أُغلقت لانقضاء مهلة التأكيد ({مهلة_التأكيد} أيّام). ولك أن تفتح شكوى جديدةً إن بقيت المشكلة.')
  on conflict (laundry_id, event, channel, audience) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function seed_complaint_templates(uuid)
  from public, anon, authenticated;

do $$
declare l record;
begin
  for l in select id from laundries loop
    perform seed_complaint_templates(l.id);
  end loop;
end $$;

-- ولمغسلةٍ تُنشأ غدًا كذلك: تُضاف البذرةُ إلى المحفّز القائم.
create or replace function ensure_complaint_defaults()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  insert into complaint_settings (laundry_id) values (new.id) on conflict do nothing;
  perform seed_complaint_types(new.id);
  perform seed_complaint_templates(new.id);
  return new;
end;
$$;

revoke execute on function ensure_complaint_defaults() from public, anon, authenticated;
