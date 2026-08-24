-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | الإشعارات: قوالبُ تعدّلها الإدارة، وطابورٌ يُرسَل منه
-- ═══════════════════════════════════════════════════════════════════════════
--
-- «تم استلام ملابسك» نصٌّ يريد صاحب المغسلة أن يغيّره — إلى صيغته، وبلهجته،
-- وبإضافة اسم الفرع. فالنصّ صفٌّ في جدول، لا سلسلةٌ في شيفرة Dart تحتاج
-- إصدارًا على المتجر ليُبدَّل فيها حرف.
--
-- والإرسال طابورٌ لا نداءٌ مباشر. لأن الإرسال المباشر عند تغيّر الحالة يربط
-- نجاح **الطلب** بنجاح **مزوّد الإشعارات**: تعطّل FCM دقيقةً فتفشل معاملة
-- تحديث الحالة، ويعلق طلبٌ لأن رسالةً لم تُرسَل. الطابور يفصلهما: الحالة
-- تُحفظ، والرسالة تُصفّ، وعاملٌ يرسل ويعيد المحاولة.

create schema if not exists wasl;
set search_path = wasl, public, extensions;

create type notification_channel as enum ('push', 'sms', 'whatsapp', 'email', 'in_app');
create type notification_status  as enum ('queued', 'sent', 'failed', 'skipped');

-- ─────────────────────────────────────────────────────────────────────────
-- القوالب
-- ─────────────────────────────────────────────────────────────────────────
-- القالب مربوطٌ بحالة الطلب: انتقالٌ إلى `picked_up` يرسل قالبه. وربطُه
-- بالحالة لا باسمٍ حرّ يعني أن حالةً جديدة تُضاف غدًا لا يُنسى قالبها —
-- الجدول يكشف الفراغ.
create table notification_templates (
  id           uuid primary key default uuid_generate_v4(),
  laundry_id   uuid not null references laundries(id) on delete cascade,
  trigger_status order_status not null,
  channel      notification_channel not null,
  -- لمن؟ العميل غالبًا، وأحيانًا الفرع أو السائق.
  audience     app_role not null default 'customer',

  title_ar     text,
  body_ar      text not null,
  title_en     text,
  body_en      text,

  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (laundry_id, trigger_status, channel, audience)
);

comment on table notification_templates is
  'النصّ صفٌّ لا سلسلةٌ في الشيفرة: تغييرُ «تم استلام ملابسك» لا يحتاج إصدارًا على المتجر.';

-- ─────────────────────────────────────────────────────────────────────────
-- تفضيلات المستخدم
-- ─────────────────────────────────────────────────────────────────────────
-- من أوقف الرسائل التسويقية يجب ألّا يُوقِف رسائل طلبه. فالفصل بينهما شرطٌ
-- لا خيار: الأولى إزعاجٌ يُرفض، والثانية خدمةٌ اشتُريت.
create table notification_preferences (
  user_id        uuid primary key references profiles(id) on delete cascade,
  push_enabled   boolean not null default true,
  sms_enabled    boolean not null default true,
  whatsapp_enabled boolean not null default true,
  email_enabled  boolean not null default false,
  marketing_opt_in boolean not null default false,
  updated_at     timestamptz not null default now()
);

-- أجهزة المستخدم — رمز الجهاز لا رمزٌ واحد للحساب: من يبدّل هاتفه ولا يُحذف
-- رمزه القديم يرسل النظام إلى جهازٍ لا يقرؤه أحد.
create table device_tokens (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references profiles(id) on delete cascade,
  token       text not null unique,
  platform    text not null check (platform in ('android','ios','web')),
  last_seen_at timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

create index on device_tokens (user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- الطابور
-- ─────────────────────────────────────────────────────────────────────────
create table notifications (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references profiles(id) on delete cascade,
  order_id     uuid references orders(id) on delete cascade,
  template_id  uuid references notification_templates(id) on delete set null,
  channel      notification_channel not null,
  title        text,
  body         text not null,
  status       notification_status not null default 'queued',
  attempts     smallint not null default 0,
  error        text,
  -- في التطبيق: متى قرأها؟ للقنوات الأخرى: متى أُرسلت؟
  read_at      timestamptz,
  sent_at      timestamptz,
  created_at   timestamptz not null default now()
);

create index on notifications (user_id, created_at desc);
create index on notifications (status, created_at) where status = 'queued';
create index on notifications (order_id);

-- ─────────────────────────────────────────────────────────────────────────
-- ملء القالب
-- ─────────────────────────────────────────────────────────────────────────
-- متغيّرات بسيطة `{اسم}` لا لغةَ قوالب: لغةٌ كاملة تعني تنفيذَ نصٍّ تكتبه
-- الإدارة — وهو سطحُ هجومٍ لا داعي له في رسالةٍ من عشر كلمات.
create or replace function render_template(p_body text, p_vars jsonb)
returns text
language plpgsql immutable
as $$
declare
  k text;
  out_text text := p_body;
begin
  if p_vars is null then return out_text; end if;
  for k in select jsonb_object_keys(p_vars) loop
    out_text := replace(out_text, '{' || k || '}', coalesce(p_vars ->> k, ''));
  end loop;
  return out_text;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الصفّ عند تغيّر الحالة
-- ─────────────────────────────────────────────────────────────────────────
create or replace function queue_status_notifications()
returns trigger
language plpgsql security definer set search_path = wasl, public, extensions
as $$
declare
  t     notification_templates%rowtype;
  prefs notification_preferences%rowtype;
  v_vars jsonb;
  v_target uuid;
  v_branch text;
  v_allowed boolean;
begin
  if new.status = old.status then
    return new;
  end if;

  select name_ar into v_branch from branches where id = new.branch_id;

  v_vars := jsonb_build_object(
    'رقم_الطلب', new.order_number::text,
    'الفرع',     coalesce(v_branch, ''),
    'الإجمالي',  new.total::text
  );

  for t in
    select * from notification_templates
    where laundry_id = new.laundry_id
      and trigger_status = new.status
      and is_active
  loop
    -- الجمهور يحدّد المُرسَل إليه: العميل صاحب الطلب، والسائق المسنَد.
    v_target := case t.audience
      when 'customer' then new.customer_id
      when 'driver'   then coalesce(new.delivery_driver_id, new.pickup_driver_id)
      else null
    end;

    if v_target is null then
      continue;
    end if;

    select * into prefs from notification_preferences where user_id = v_target;

    -- غياب التفضيلات يعني الافتراضَ لا الصمت: من لم يضبط شيئًا يجب أن يصله
    -- إشعار طلبه.
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

    if not v_allowed then
      insert into notifications (user_id, order_id, template_id, channel, title, body, status)
      values (v_target, new.id, t.id, t.channel,
              render_template(coalesce(t.title_ar,''), v_vars),
              render_template(t.body_ar, v_vars), 'skipped');
      continue;
    end if;

    insert into notifications (user_id, order_id, template_id, channel, title, body)
    values (v_target, new.id, t.id, t.channel,
            render_template(coalesce(t.title_ar,''), v_vars),
            render_template(t.body_ar, v_vars));
  end loop;

  return new;
end;
$$;

-- بعد المحفّز الحارس لا قبله: لا تُصفّ رسالةٌ عن انتقالٍ سيُرفض.
create trigger t_orders_queue_notifications
  after update of status on orders
  for each row execute function queue_status_notifications();

-- تفضيلات المستخدم تُنشأ مع ملفّه
create or replace function ensure_notification_prefs()
returns trigger language plpgsql security definer set search_path = wasl, public, extensions
as $$
begin
  insert into notification_preferences (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end $$;

create trigger t_profiles_notification_prefs
  after insert on profiles
  for each row execute function ensure_notification_prefs();

create trigger t_notification_templates_touch before update on notification_templates
  for each row execute function touch_updated_at();
create trigger t_notification_preferences_touch before update on notification_preferences
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحيات
-- ─────────────────────────────────────────────────────────────────────────
grant select, insert, update, delete
  on notification_templates, notification_preferences, device_tokens, notifications
  to authenticated;
grant select on notification_templates to anon;

do $$
declare t text;
begin
  foreach t in array array['notification_templates','notification_preferences',
                           'device_tokens','notifications'] loop
    execute format('alter table wasl.%I enable row level security', t);
    execute format('alter table wasl.%I force row level security', t);
  end loop;
end $$;

create policy templates_read on notification_templates for select using (true);
create policy templates_write on notification_templates
  for all using (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = notification_templates.laundry_id))
  with check (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = notification_templates.laundry_id));

create policy prefs_own on notification_preferences
  for all using (user_id = auth.uid() or auth_is_super_admin())
  with check (user_id = auth.uid() or auth_is_super_admin());

create policy device_tokens_own on device_tokens
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- الرسالة تُقرأ من صاحبها. ويعدّلها ليعلّمها مقروءةً — ولا يكتبها: من يكتب
-- إشعارًا باسم المغسلة يرسل ما يشاء إلى من يشاء.
create policy notifications_read on notifications
  for select using (user_id = auth.uid() or auth_is_super_admin()
                    or auth_has_role('customer_service'));
create policy notifications_mark_read on notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_insert on notifications
  for insert with check (auth_is_super_admin());

-- وحارسٌ على التعديل: صاحب الرسالة يعلّمها مقروءةً ولا يعيد كتابة نصّها.
create or replace function guard_notification_update()
returns trigger language plpgsql security definer set search_path = wasl, public, extensions
as $$
begin
  if auth_is_service_context() or auth_is_super_admin() then
    return new;
  end if;
  if new.body is distinct from old.body
     or new.title is distinct from old.title
     or new.status is distinct from old.status
     or new.channel is distinct from old.channel then
    raise exception 'لا تملك إلا تعليم الرسالة مقروءة' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

create trigger t_notifications_guard before update on notifications
  for each row execute function guard_notification_update();
