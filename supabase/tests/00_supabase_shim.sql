-- محاكي طبقة Supabase — للاختبار المحلي وحده، لا يُنشر.
-- Supabase يوفّر schema اسمه auth وفيه users و uid()؛ ولاختبار المهاجرات على
-- Postgres عاديّ يجب أن يوجد نظيره، وإلا فشلت المهاجرة الأولى عند أول مرجع.
create schema if not exists auth;

create table if not exists auth.users (
  id                   uuid primary key default gen_random_uuid(),
  phone                text unique,
  email                text unique,
  raw_user_meta_data   jsonb not null default '{}'::jsonb,
  created_at           timestamptz not null default now()
);

-- المستخدم الحالي في الاختبار — يُضبط بـ set_config.
create or replace function auth.uid()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.role()
returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;

-- أدوار Supabase التي تشير إليها سياسات RLS.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
end $$;

-- اختصار للاختبار: «تقمَّص هذا المستخدم».
create or replace function auth.login_as(p_user uuid)
returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_user::text, false),
         set_config('request.jwt.claim.role', 'authenticated', false);
  select null::void;
$$;

create or replace function auth.logout()
returns void language sql as $$
  select set_config('request.jwt.claim.sub', '', false),
         set_config('request.jwt.claim.role', 'anon', false);
  select null::void;
$$;

-- Supabase يمنح أدوار الواجهة حقّ استدعاء auth.uid()؛ ومحاكيه يجب أن يفعل
-- المثل، وإلا فشل كل اختبار بـ«permission denied for schema auth» قبل أن يصل
-- إلى سياسةٍ واحدة.
-- ═══════════════════════════════════════════════════════════════════════════
-- الصلاحيات الافتراضية كما يضبطها Supabase
-- ═══════════════════════════════════════════════════════════════════════════
-- **هذا السطر هو ما جعل اختبارًا يمرّ محلّيًّا ويفشل على المشروع الحيّ.**
--
-- Supabase يمنح `anon` و`authenticated` كلَّ شيءٍ على كل جدولٍ في `public`
-- افتراضًا، ويتّكل على RLS وحدها في المنع. ومحاكاةٌ لا تفعل ذلك تجعل كل فحص
-- صلاحيّاتٍ **يمرّ بلا معنى**: لا صلاحية أصلًا فلا شيء يُكتشف.
--
-- فتُحاكى هنا، ثم تُشدَّد المهاجرات ما يجب تشديده — ويُرى أثرُه في الاختبار.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
grant select on auth.users to authenticated, service_role;
