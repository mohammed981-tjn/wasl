-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | الأساس: الهوية والمُلكيّة والصلاحيات
-- ═══════════════════════════════════════════════════════════════════════════
--
-- لماذا يبدأ المخطّط من هنا: لا جدول في هذا النظام يخلو من سؤال «مَن يراه؟».
-- والإجابة لا تصلح أن تكون فحصًا في التطبيق — لأنّ ما في الحزمة يُقرأ ويُعدَّل،
-- ومن يعدّل الحزمة يجعلها تصدّق ما يشاء. فالصلاحية تسكن القاعدة نفسها عبر RLS،
-- وكل جدول لاحق يبني عليها.
--
-- والمنصّة متعدّدة المغاسل والفروع من الجذر لا كترقية لاحقة: إضافة `branch_id`
-- بعد امتلاء الجداول هجرةُ بيانات مؤلمة، وإضافتها اليوم عمود.

create extension if not exists "uuid-ossp";
create extension if not exists postgis;
-- btree_gist يلزم لقيد الاستبعاد في شرائح المسافة: مزج `uuid with =` مع مدى
-- رقميّ في فهرس GiST واحد لا يعمل بدونها.
create extension if not exists btree_gist;

-- ─────────────────────────────────────────────────────────────────────────
-- الأدوار
-- ─────────────────────────────────────────────────────────────────────────
-- ستة أدوار تشغيلية + العميل. ولماذا نوع مُعدَّد لا نصّ حرّ: النصّ الحرّ يقبل
-- 'admin' و'Admin' و'adminn'، وثالثها ثغرة صامتة — الحساب يبدو إداريًا في
-- الجدول ولا تطابقه أي سياسة، أو العكس.
create type app_role as enum (
  'super_admin',      -- مالك المنصّة: كل شيء، عبر كل المغاسل
  'branch_manager',   -- مدير فرع: تشغيل فرعه وأسعاره وموظفيه
  'laundry_staff',    -- موظف مغسلة: مراحل الطلب فقط — لا أسعار ولا إيرادات
  'driver',           -- سائق: طلبات الاستلام والتسليم المسندة إليه
  'customer_service', -- خدمة العملاء: الطلبات والشكاوى — لا مالية
  'accountant',       -- محاسب: المالية والتقارير — لا يغيّر حالة طلب
  'customer'          -- العميل
);

-- ─────────────────────────────────────────────────────────────────────────
-- المغاسل والفروع
-- ─────────────────────────────────────────────────────────────────────────
create table laundries (
  id            uuid primary key default uuid_generate_v4(),
  name_ar       text not null,
  name_en       text,
  slug          text not null unique,
  logo_url      text,
  cr_number     text,                       -- السجل التجاري
  vat_number    text,                       -- الرقم الضريبي
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table laundries is 'المغسلة كمستأجر (tenant). المنصّة تحتمل أكثر من مغسلة منذ اليوم الأول.';

create table branches (
  id            uuid primary key default uuid_generate_v4(),
  laundry_id    uuid not null references laundries(id) on delete cascade,
  name_ar       text not null,
  name_en       text,
  phone         text,
  -- الموقع نقطة جغرافية لا زوج أرقام: حساب المسافة لرسوم التوصيل استعلامٌ
  -- مكانيّ، وPostGIS يفهرسه. زوج double precision لا يُفهرس مكانيًا.
  location      geography(point, 4326),
  address_ar    text,
  city          text not null default 'المدينة المنورة',
  -- الطاقة الاستيعابية اليومية: تُقاس بعدد القطع لا الطلبات — طلب فيه بطانيتان
  -- ليس كطلب فيه ثلاثين قطعة. صفر يعني «بلا سقف».
  daily_capacity_pieces int not null default 0 check (daily_capacity_pieces >= 0),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index on branches (laundry_id);
create index on branches using gist (location);

comment on column branches.daily_capacity_pieces is
  'سقف القطع اليومي — يغذّي محرّك «أقرب موعد متاح». صفر = بلا سقف.';

-- ساعات العمل: جدول لا حقل JSON، كي تُستعلم مباشرةً عند حساب المواعيد المتاحة.
create table branch_hours (
  id          uuid primary key default uuid_generate_v4(),
  branch_id   uuid not null references branches(id) on delete cascade,
  weekday     smallint not null check (weekday between 0 and 6), -- 0 = الأحد
  opens_at    time not null,
  closes_at   time not null,
  is_closed   boolean not null default false,
  unique (branch_id, weekday),
  check (is_closed or closes_at > opens_at)
);

comment on table branch_hours is 'ساعات عمل الفرع لكل يوم — تحدّها الإدارة، ويقرأها محرّك المواعيد.';

-- ─────────────────────────────────────────────────────────────────────────
-- الملفّات الشخصية
-- ─────────────────────────────────────────────────────────────────────────
-- profiles ظلّ auth.users: Supabase يملك جدول المصادقة ولا يُعدَّل، فالبيانات
-- التطبيقية تسكن هنا بمفتاح هو نفسه معرّف المستخدم.
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text,
  phone         text unique,               -- الجوال هو الهوية الفعلية: الدخول بـOTP
  email         text,
  avatar_url    text,
  preferred_locale text not null default 'ar' check (preferred_locale in ('ar','en')),
  -- وضع الزائر: الحاج والمعتمر ونزيل الفندق. من يزور المدينة لا يملك عنوانًا
  -- يعرفه، ويملك اسم فندق ورقم غرفة — فالنظام يسأله ما يعرف.
  is_visitor    boolean not null default false,
  blocked_at    timestamptz,               -- الحظر تاريخ لا راية: «متى» سؤال تشغيليّ
  blocked_reason text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index on profiles (phone);

comment on column profiles.blocked_at is 'الحظر تاريخ لا boolean — كي يُعرف متى وقع، ويُرفع بجعله NULL.';

-- ─────────────────────────────────────────────────────────────────────────
-- إسناد الأدوار
-- ─────────────────────────────────────────────────────────────────────────
-- الدور ليس عمودًا في profiles، لأن الشخص الواحد قد يكون مدير فرع في فرع
-- وموظفًا في آخر. وهو دائمًا مقيّد بنطاق: super_admin وحده بلا فرع.
create table user_roles (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references profiles(id) on delete cascade,
  role        app_role not null,
  laundry_id  uuid references laundries(id) on delete cascade,
  branch_id   uuid references branches(id) on delete cascade,
  granted_by  uuid references profiles(id),
  granted_at  timestamptz not null default now(),
  unique (user_id, role, branch_id),
  -- super_admin بلا نطاق، وكل دور تشغيلي بنطاق. القيد يمنع «مدير فرع» بلا فرع.
  constraint role_scope_matches_role check (
    (role = 'super_admin' and branch_id is null and laundry_id is null)
    or (role = 'customer'  and branch_id is null and laundry_id is null)
    or (role in ('branch_manager','laundry_staff','driver','customer_service','accountant')
        and branch_id is not null and laundry_id is not null)
  )
);

create index on user_roles (user_id);
create index on user_roles (branch_id);

-- ─────────────────────────────────────────────────────────────────────────
-- دوالّ الصلاحية — تُستدعى من كل سياسة RLS لاحقًا
-- ─────────────────────────────────────────────────────────────────────────
-- security definer كي تقرأ user_roles متجاوزةً RLS الخاص بها؛ ولولا ذلك
-- لدارت السياسة على نفسها: «لتعرف دورك اقرأ user_roles، ولتقرأها اعرف دورك».
-- و search_path مثبَّت لأن دالة بصلاحية المُعرِّف مع مسار قابل للتلاعب ثغرة
-- تصعيد امتيازات معروفة.

create or replace function auth_has_role(target app_role)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from user_roles
    where user_id = auth.uid() and role = target
  );
$$;

create or replace function auth_is_super_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from user_roles
    where user_id = auth.uid() and role = 'super_admin'
  );
$$;

-- «هل لي هذا الدور في هذا الفرع؟» — سؤال كل سياسة تشغيلية.
-- super_admin يمرّ دائمًا: نطاقه المنصّة كلها.
create or replace function auth_has_branch_role(target_branch uuid, variadic targets app_role[])
returns boolean
language sql stable security definer set search_path = public
as $$
  select auth_is_super_admin() or exists (
    select 1 from user_roles
    where user_id = auth.uid()
      and branch_id = target_branch
      and role = any(targets)
  );
$$;

-- الفروع التي يملك المستخدم فيها أيّ دور تشغيلي — تُستعمل في سياسات القراءة.
create or replace function auth_branch_ids()
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select branch_id from user_roles
  where user_id = auth.uid() and branch_id is not null;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- إنشاء الملف الشخصي تلقائيًا عند التسجيل
-- ─────────────────────────────────────────────────────────────────────────
-- بلا هذا يسجّل المستخدم في auth.users ولا يوجد له صفّ في profiles، فتفشل كل
-- سياسة تربط به — بلا رسالة خطأ مفهومة.
create or replace function handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into profiles (id, phone, email, full_name)
  values (
    new.id,
    new.phone,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', '')
  )
  on conflict (id) do nothing;

  -- كل مستخدم جديد عميل حتى يُرقّى. ولا يُمنح دور تشغيليّ إلا بإسناد صريح.
  insert into user_roles (user_id, role)
  values (new.id, 'customer')
  on conflict do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────
-- updated_at
-- ─────────────────────────────────────────────────────────────────────────
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger t_laundries_touch before update on laundries
  for each row execute function touch_updated_at();
create trigger t_branches_touch before update on branches
  for each row execute function touch_updated_at();
create trigger t_profiles_touch before update on profiles
  for each row execute function touch_updated_at();
