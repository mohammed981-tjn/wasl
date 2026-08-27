-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | الشكاوى: الملفّ الذي يُفتح ولا يُغلق إلا بإقرار صاحبه
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **التقييمُ رأيٌ يُجمَع، والشكوى ملفٌّ يُغلَق.** بنينا `order_ratings` وفيه
-- نجومٌ ونصٌّ حرّ — وهو يكفي لقياس الرضا ولا يكفي لقطعةِ ثوبٍ ضاعت. تلك
-- تحتاج مَن يقرؤها، ومهلةً يُردّ فيها، وقرارًا بمال، **وإقرارًا من صاحبها
-- أنّها حُلّت فعلًا**.
--
-- وأربعةُ قراراتٍ في هذا الملفّ تستحقّ أن تُقال قبل أوّل جدول:
--
--   ١) **«حُلّت» ليست «أُغلقت».** المدير يقرّر فتصير `resolved`، ثم يُسأل
--      الشاكي. جوابُه «نعم» يُغلق، و«لا» يعيدها بأولوية. فمقياسُ خدمة
--      العملاء يصير **كم شكوى أقرّ أصحابُها بحلّها**، لا كم شكوى ضغط عليها
--      موظّفٌ زرَّ «تمّ». والاثنان يختلفان كثيرًا.
--
--   ٢) **الشكوى ليست حكرًا على العميل.** بين المغسلة والسائق نزاعٌ متكرّر:
--      «سلّمتُه اثنتي عشرة قطعة» / «استلمتُ إحدى عشرة». فيُسجَّل `against_role`
--      و`submitted_by_role`، ويرى كلُّ دورٍ أنواعَه هو فقط.
--
--   ٣) **الأنواع قائمةٌ مغلقة** — جدولٌ تديره الإدارة لا نصٌّ حرّ. ونصٌّ حرٌّ
--      لا يُجمَّع، فلا يُعرف أبدًا أنّ سبعَ شكاوى هذا الأسبوع عن فرعٍ بعينه.
--
--   ٤) **ولا رقمَ في الشيفرة.** المهلةُ والسقفُ وحدُّ الإنذار كلُّها في
--      `complaint_settings` — لأن مغسلةً تسلّم في اليوم نفسه ليست كأخرى
--      تسلّم بعد ثلاثة أيّام، والمهلةُ الواحدة تظلم إحداهما.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- إعدادات الشكاوى
-- ─────────────────────────────────────────────────────────────────────────
create table complaint_settings (
  laundry_id   uuid primary key references laundries(id) on delete cascade,
  is_enabled   boolean not null default true,

  -- كم ساعةً يبقى الطلبُ قابلًا للشكوى بعد تسليمه؟ والطلبُ الجاري مفتوحٌ
  -- دائمًا: لا معنى لمهلةٍ على شيءٍ لم ينتهِ بعد.
  window_hours int not null default 48 check (window_hours between 1 and 8760),

  -- المهلة التي نَعِد بالردّ خلالها. لا تُنفَّذ آليًّا — تُقاس ويُعرض تجاوزُها.
  -- ووعدٌ لا يُقاس ليس وعدًا.
  response_sla_hours int not null default 24 check (response_sla_hours between 1 and 720),

  -- بعد الحلّ، كم يومًا يُنتظر جوابُ الشاكي قبل الإغلاق التلقائيّ؟
  auto_close_days int not null default 3 check (auto_close_days between 1 and 90),

  -- كم إنذارًا يحتمل السائق قبل أن يُمنع من قبول جديد؟
  driver_warning_threshold smallint not null default 3
    check (driver_warning_threshold between 1 and 20),

  -- تذكرةٌ بلا طلب (استفسارٌ ماليّ، تحديثُ بيانات). بعضُ المغاسل تريدها
  -- وبعضُها تريد كلَّ شكوى مربوطةً بطلب.
  allow_general_tickets boolean not null default true,

  updated_at   timestamptz not null default now()
);

comment on table complaint_settings is
  'مُهَلُ الشكوى وحدودُها — أربعةُ أرقامٍ ليس واحدٌ منها في الشيفرة.';
comment on column complaint_settings.auto_close_days is
  'الإغلاق التلقائيّ سكوتٌ يُفسَّر رضًا. ومدّتُه قرارُ إدارةٍ لا ثابتُ مبرمج.';

create trigger t_complaint_settings_updated
  before update on complaint_settings
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- أنواع الشكاوى — قائمةٌ مغلقة تديرها الإدارة
-- ─────────────────────────────────────────────────────────────────────────
-- **لماذا جدولٌ لا enum**: النوعُ قاعدةُ عملٍ تُعدَّل (مغسلةٌ تضيف «العطر
-- المطلوب لم يُستخدم»)، وenum يحتاج مهاجرةً لكلّ إضافة. ولماذا لا نصٌّ حرّ:
-- لأنّ الغرض من النوع أصلًا هو **العدّ**.
create table complaint_types (
  id          uuid primary key default uuid_generate_v4(),
  laundry_id  uuid not null references laundries(id) on delete cascade,

  code        text not null,
  label_ar    text not null,
  label_en    text,

  -- من يملك تقديمَ هذا النوع. `null` = كلُّ الأدوار.
  -- والعميلُ لا يرى «العميل لا يردّ»، والسائقُ لا يرى «بقعةٌ لم تُزل».
  for_role    app_role,

  -- الطرفُ المشكوّ منه المقترَح — تُملأ به الشاشة، ويبقى للشاكي تغييرُه.
  suggested_against app_role,

  -- هل يُقبل بلا طلب؟ (استفسارٌ ماليّ، تحديثُ بيانات)
  allows_general boolean not null default false,

  is_active   boolean not null default true,
  sort_order  int not null default 100,
  created_at  timestamptz not null default now(),

  unique (laundry_id, code)
);

create index on complaint_types (laundry_id, is_active, sort_order);

comment on table complaint_types is
  'قائمةٌ مغلقة — نصٌّ حرٌّ لا يُجمَّع، وشكوى لا تُجمَّع لا تُصلَح.';

-- ─────────────────────────────────────────────────────────────────────────
-- دورة حياة الشكوى
-- ─────────────────────────────────────────────────────────────────────────
--   open ── يقرؤها موظّف ──▶ in_progress ── قرارُ الحلّ ──▶ resolved
--                                                            │
--                              «نعم، حُلّت» أو صمتُ المهلة ───┴──▶ closed
--                              «لا، لم تُحل» ──────────────────▶ in_progress
create type complaint_status as enum ('open', 'in_progress', 'resolved', 'closed');

create table complaints (
  id              uuid primary key default uuid_generate_v4(),
  -- رقمٌ بشريٌّ يُقال في الهاتف. UUID لا يُملى على عميلٍ غاضب.
  complaint_number bigint generated always as identity (start with 1000),

  laundry_id      uuid not null references laundries(id) on delete cascade,
  -- الفرعُ قد يكون مجهولًا في تذكرةٍ عامّة بلا طلب.
  branch_id       uuid references branches(id) on delete set null,
  order_id        uuid references orders(id) on delete set null,

  type_id         uuid not null references complaint_types(id),

  submitted_by      uuid not null references profiles(id) on delete cascade,
  submitted_by_role app_role not null,

  -- الطرفُ المشكوّ منه. `null` = شكوى عامّة على الخدمة لا على شخص.
  against_id      uuid references profiles(id) on delete set null,
  against_role    app_role,

  description     text not null check (length(btrim(description)) >= 5),

  -- صورٌ في دلو تخزين. **لا base64 في عمود**: كلُّ استعلامٍ على الشكاوى
  -- كان سيسحب الصور معه، والقائمةُ تُقرأ عشراتِ المرّات في اليوم.
  photo_urls      text[] not null default '{}',

  status          complaint_status not null default 'open',

  -- ما كُتب للشاكي — يُقرأ في تطبيقه.
  resolution      text,
  -- وما كُتب للإدارة — لا يُقرأ في تطبيقه.
  internal_note   text,

  first_response_at timestamptz,   -- متى لمسها موظّفٌ أوّلَ مرّة
  resolved_at     timestamptz,     -- أساسُ مهلة التأكيد والإغلاق التلقائيّ
  closed_at       timestamptz,
  closed_by_timeout boolean not null default false,

  -- «لا، لم تُحل» — رايةٌ ترفع الشكوى فوق أخواتها في الطابور.
  reopen_count    smallint not null default 0 check (reopen_count >= 0),

  resolved_by     uuid references profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create unique index on complaints (complaint_number);
create index on complaints (laundry_id, status, created_at desc);
create index on complaints (branch_id, status) where branch_id is not null;
create index on complaints (order_id) where order_id is not null;
create index on complaints (submitted_by, created_at desc);
create index on complaints (against_id) where against_id is not null;
create index on complaints (type_id);
create index on complaints (resolved_by) where resolved_by is not null;
-- الطابور: ما ينتظر عملًا. فهرسٌ جزئيٌّ لأنّ المغلقة تتراكم والمفتوحة قليلة.
create index on complaints (created_at) where status in ('open', 'in_progress');

comment on column complaints.closed_by_timeout is
  'أُغلقت بالصمت لا بالرضا. والفرقُ يظهر في التقرير: إغلاقٌ بالصمت ليس نجاحًا.';
comment on column complaints.reopen_count is
  'كم مرّةً قال صاحبُها «لم تُحل». الرقمُ وحده يكشف حلولًا شكليّة.';

create trigger t_complaints_updated
  before update on complaints
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- محادثة الشكوى
-- ─────────────────────────────────────────────────────────────────────────
-- **منفصلةٌ عن الطلب عمدًا**: دردشةُ الطلب بين العميل والسائق تُقرأ أثناء
-- التوصيل، ومحادثةُ الشكوى بين الشاكي والإدارة تُقرأ بعده. وخلطُهما يجعل
-- سائقًا يقرأ شكوى عليه.
create table complaint_messages (
  id           uuid primary key default uuid_generate_v4(),
  complaint_id uuid not null references complaints(id) on delete cascade,
  sender_id    uuid not null references profiles(id) on delete cascade,
  sender_role  app_role not null,
  body         text not null check (length(btrim(body)) > 0),
  -- رسالةٌ داخليّة بين الموظّفين لا يراها الشاكي.
  is_internal  boolean not null default false,
  created_at   timestamptz not null default now()
);

create index on complaint_messages (complaint_id, created_at);
create index on complaint_messages (sender_id);

-- ─────────────────────────────────────────────────────────────────────────
-- إنذارات السائقين
-- ─────────────────────────────────────────────────────────────────────────
-- **الإنذار سجلٌّ لا عدّاد.** عدّادٌ يُزاد لا يقول من أنذر ولا لماذا، ولا
-- يُراجَع حين يعترض السائق. والصفُّ يقول: هذه الشكوى، وهذا التاريخ.
create table driver_warnings (
  id           uuid primary key default uuid_generate_v4(),
  driver_id    uuid not null references profiles(id) on delete cascade,
  laundry_id   uuid not null references laundries(id) on delete cascade,
  complaint_id uuid references complaints(id) on delete set null,
  reason       text not null,
  issued_by    uuid references profiles(id),
  -- الإنذارُ يسقط: خطأٌ قبل سنةٍ ليس كخطأٍ أمس. `null` = لا يسقط.
  expires_at   timestamptz,
  revoked_at   timestamptz,
  revoked_reason text,
  created_at   timestamptz not null default now()
);

create index on driver_warnings (driver_id, created_at desc);
create index on driver_warnings (laundry_id);
create index on driver_warnings (complaint_id);
create index on driver_warnings (issued_by);

comment on table driver_warnings is
  'الإنذار صفٌّ يُراجَع لا عدّادٌ يُزاد — لأنّ السائق يعترض، والعدّاد لا يجيب.';

-- الإنذاراتُ السارية: ما لم يسقط ولم يُلغَ.
create or replace function driver_active_warnings(p_driver uuid, p_laundry uuid)
returns int
language sql stable security definer set search_path = public, extensions
as $$
  select count(*)::int from driver_warnings
  where driver_id = p_driver
    and laundry_id = p_laundry
    and revoked_at is null
    and (expires_at is null or expires_at > now());
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- من يجوز أن يشتكي على هذا الطلب؟
-- ─────────────────────────────────────────────────────────────────────────
-- **أطرافُ الطلب وحدهم**، لا كلُّ من يراه. وخدمةُ العملاء ترى كلَّ الطلبات
-- بحكم دورها — ولو اتّكلنا على `can_see_order` لصار موظّفُ خدمةِ العملاء
-- قادرًا على تقديم شكوى **باسم** العميل على طلبٍ لا يعرفه.
create or replace function is_party_to_order(p_order uuid, p_user uuid)
returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select exists (
    select 1 from orders o
    where o.id = p_order
      and (o.customer_id = p_user
        or o.pickup_driver_id = p_user
        or o.delivery_driver_id = p_user
        or auth_has_branch_role(o.branch_id, 'branch_manager', 'laundry_staff'))
  );
$$;

-- دورُ الشاكي **في هذا الطلب** لا دورُه في النظام: صاحبُ المغسلة قد يطلب
-- لنفسه، فهو حينئذٍ عميلٌ لا مدير.
create or replace function complainant_role(p_order uuid, p_user uuid)
returns app_role
language plpgsql stable security definer set search_path = public, extensions
as $$
declare o orders%rowtype;
begin
  if p_order is null then
    return case
      when auth_has_role('driver') then 'driver'::app_role
      when auth_has_role('laundry_staff') then 'laundry_staff'::app_role
      else 'customer'::app_role end;
  end if;

  select * into o from orders where id = p_order;
  if o.customer_id = p_user then return 'customer'; end if;
  if o.pickup_driver_id = p_user or o.delivery_driver_id = p_user then
    return 'driver';
  end if;
  if auth_has_branch_role(o.branch_id, 'branch_manager') then return 'branch_manager'; end if;
  return 'laundry_staff';
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- حارسُ فتح الشكوى
-- ─────────────────────────────────────────────────────────────────────────
-- **كلُّ ما يمكن اشتقاقُه من الطلب يُشتقّ منه**، ولا يُقبل ممّن يكتب. فشاكٍ
-- يرسل `laundry_id` لمغسلةٍ أخرى يزرع شكواه في طابور غيره؛ وشاكٍ يرسل
-- `submitted_by` لغيره ينتحل شخصًا.
create or replace function guard_complaint_insert()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  o  orders%rowtype;
  s  complaint_settings%rowtype;
  ct complaint_types%rowtype;
  v_window int;
  v_deadline timestamptz;
begin
  -- الخادمُ يستورد ويُصلح؛ والحارسُ للحزم.
  if auth_is_service_context() then
    return new;
  end if;

  new.submitted_by := auth.uid();
  if new.submitted_by is null then
    raise exception 'لا شكوى بلا هويّة' using errcode = 'insufficient_privilege';
  end if;

  -- حالةٌ يفرضها النظام لا المُدخِل: شكوى تُولد `resolved` تخرج من الطابور
  -- قبل أن تدخله.
  new.status            := 'open';
  new.resolution        := null;
  new.internal_note     := null;
  new.first_response_at := null;
  new.resolved_at       := null;
  new.closed_at         := null;
  new.closed_by_timeout := false;
  new.reopen_count      := 0;
  new.resolved_by       := null;

  select * into ct from complaint_types where id = new.type_id;
  if not found or not ct.is_active then
    raise exception 'نوعُ الشكوى غير معروف أو معطَّل' using errcode = 'check_violation';
  end if;

  if new.order_id is not null then
    select * into o from orders where id = new.order_id;
    if not found then
      raise exception 'الطلب غير موجود' using errcode = 'check_violation';
    end if;

    if not is_party_to_order(new.order_id, new.submitted_by) then
      raise exception 'لا تشتكي على طلبٍ لست طرفًا فيه'
        using errcode = 'insufficient_privilege';
    end if;

    -- تُملأ من الطلب لا ممّن يكتب.
    new.laundry_id := o.laundry_id;
    new.branch_id  := o.branch_id;
  else
    if not ct.allows_general then
      raise exception 'هذا النوع يحتاج طلبًا' using errcode = 'check_violation';
    end if;
    if new.laundry_id is null then
      raise exception 'التذكرة العامّة تحتاج مغسلة' using errcode = 'check_violation';
    end if;
  end if;

  select * into s from complaint_settings where laundry_id = new.laundry_id;
  if found and not s.is_enabled then
    raise exception 'استقبالُ الشكاوى معطَّل' using errcode = 'check_violation';
  end if;
  if new.order_id is null and found and not s.allow_general_tickets then
    raise exception 'التذاكر العامّة غير مفعّلة' using errcode = 'check_violation';
  end if;

  -- **دورُ الشاكي في هذا الطلب**، لا دورُه في النظام. ثم يُطابَق بنطاق
  -- النوع: العميلُ لا يفتح «العميل لا يردّ»، والسائقُ لا يفتح «بقعةٌ لم تُزل».
  new.submitted_by_role := complainant_role(new.order_id, new.submitted_by);
  if ct.for_role is not null and ct.for_role <> new.submitted_by_role then
    raise exception 'هذا النوع ليس لدورك' using errcode = 'insufficient_privilege';
  end if;

  -- **المهلة تُحسب من التسليم لا من الإنشاء.** طلبٌ استغرق أسبوعًا في
  -- المغسلة لا تُحسب مهلةُ الشكوى عليه من يوم طلبه.
  if new.order_id is not null and o.status in ('delivered', 'cancelled', 'refunded') then
    v_window   := coalesce(s.window_hours, 48);
    v_deadline := coalesce(o.delivered_at, o.updated_at) + make_interval(hours => v_window);
    if now() > v_deadline then
      raise exception 'انتهت مهلة الشكوى على هذا الطلب (% ساعة)', v_window
        using errcode = 'check_violation';
    end if;
  end if;

  -- المشكوُّ منه يُتحقَّق أنّه طرفٌ في الطلب فعلًا: شاكٍ يضع سائقًا لم يمسّ
  -- طلبَه يُلطّخ سجلَّ بريء.
  if new.against_id is not null then
    if new.order_id is null then
      raise exception 'لا شكوى على شخصٍ بلا طلب' using errcode = 'check_violation';
    end if;
    if new.against_id = new.submitted_by then
      raise exception 'لا تشتكي على نفسك' using errcode = 'check_violation';
    end if;
    if new.against_id not in (
         o.customer_id, coalesce(o.pickup_driver_id, o.customer_id),
         coalesce(o.delivery_driver_id, o.customer_id))
       and not auth_has_branch_role(o.branch_id, 'branch_manager', 'laundry_staff') then
      raise exception 'المشكوُّ منه ليس طرفًا في هذا الطلب'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger t_complaints_guard_insert
  before insert on complaints
  for each row execute function guard_complaint_insert();

-- ─────────────────────────────────────────────────────────────────────────
-- حارسُ التعديل
-- ─────────────────────────────────────────────────────────────────────────
-- **RLS تحرس الصفّ لا العمود.** وسياسةُ «الشاكي يرى شكواه» مع منحِ UPDATE
-- تعني أنّ الشاكي يكتب `status = 'closed'` على نفسه، أو أسوأ: يكتب
-- `resolution` فيصنع لنفسه ردًّا من الإدارة. فالانتقالُ كلُّه يمرّ من هنا.
create or replace function guard_complaint_update()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_is_staff boolean;
begin
  if auth_is_service_context() then
    return new;
  end if;

  v_is_staff := auth_is_super_admin()
    or auth_has_role('customer_service')
    or (new.branch_id is not null
        and auth_has_branch_role(new.branch_id, 'branch_manager'));

  -- ما لا يُعدَّل بعد الفتح إطلاقًا — لا من موظّفٍ ولا من شاكٍ.
  if new.id is distinct from old.id
     or new.complaint_number is distinct from old.complaint_number
     or new.laundry_id  is distinct from old.laundry_id
     or new.order_id    is distinct from old.order_id
     or new.submitted_by is distinct from old.submitted_by
     or new.submitted_by_role is distinct from old.submitted_by_role
     or new.created_at  is distinct from old.created_at then
    raise exception 'لا تُعدَّل هويّةُ الشكوى بعد فتحها'
      using errcode = 'insufficient_privilege';
  end if;

  -- **الدوالُّ المعتمَدة تُعرّف نفسها.** `claim_complaint` و`resolve_complaint`
  -- و`confirm_complaint_resolution` و`close_stale_complaints` تفحص الصلاحية
  -- بنفسها ثم ترفع هذه الرايةَ **للمعاملة وحدها**؛ فلا يعيد الحارسُ فحصًا
  -- بمعايير الكتابة المباشرة — وإلّا مُنع صاحبُ الشكوى من الجواب على شكواه.
  --
  -- والرايةُ ليست بابًا خلفيًّا: العميلُ لا يصل إلى `set_config` أصلًا —
  -- PostgREST لا يعرض إلا دوالَّ `public`، وهي في `pg_catalog`. فالحارسُ
  -- هنا يمنع **الكتابة المباشرة على الجدول**، وهي القناةُ الوحيدة للحزمة.
  if coalesce(current_setting('wasl.complaint_flow', true), '') = 'on' then
    return new;
  end if;

  if not v_is_staff then
    -- الشاكي: لا يملك من شكواه إلا وصفَها وصورَها، وما دامت لم تُقرأ بعد.
    if new.submitted_by <> auth.uid() then
      raise exception 'لا تعدّل شكوى غيرك' using errcode = 'insufficient_privilege';
    end if;
    if old.status <> 'open' then
      raise exception 'لا يُعدَّل الوصف بعد أن بدأت مراجعتُها'
        using errcode = 'insufficient_privilege';
    end if;
    if new.status is distinct from old.status
       or new.resolution is distinct from old.resolution
       or new.internal_note is distinct from old.internal_note
       or new.resolved_at is distinct from old.resolved_at
       or new.resolved_by is distinct from old.resolved_by
       or new.closed_at is distinct from old.closed_at
       or new.reopen_count is distinct from old.reopen_count
       or new.against_id is distinct from old.against_id
       or new.type_id is distinct from old.type_id then
      raise exception 'ليس لك من شكواك إلا وصفُها وصورُها'
        using errcode = 'insufficient_privilege';
    end if;
    return new;
  end if;

  -- **الحلُّ والإغلاق لا يُكتبان بـUPDATE مباشر.** لهما دوالُّهما التي تنفّذ
  -- الاسترداد والإنذار في المعاملة نفسها؛ وUPDATE يدويٌّ يقفز فوقها فيترك
  -- شكوى «محلولة» بلا مالٍ صُرف ولا سؤالٍ سُئل.
  if new.status is distinct from old.status
     and not (old.status = 'open' and new.status = 'in_progress') then
    raise exception 'حالةُ الشكوى تُغيَّر بدوالّها لا بتحديثٍ مباشر'
      using errcode = 'insufficient_privilege';
  end if;

  -- أوّلُ لمسةٍ من موظّف تُختم: مهلةُ الردّ تُقاس بها.
  if old.first_response_at is null and new.status <> 'open' then
    new.first_response_at := coalesce(new.first_response_at, now());
  end if;

  return new;
end;
$$;

create trigger t_complaints_guard_update
  before update on complaints
  for each row execute function guard_complaint_update();

-- من يملك التصرّف في هذه الشكوى؟ خدمةُ العملاء ومديرُ فرعها والمالك.
create or replace function complaint_is_staff(c complaints)
returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select auth_is_super_admin()
      or auth_has_role('customer_service')
      or (c.branch_id is not null
          and auth_has_branch_role(c.branch_id, 'branch_manager'));
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- التقاطُ الشكوى: أوّلُ يدٍ تلمسها
-- ─────────────────────────────────────────────────────────────────────────
create or replace function claim_complaint(p_complaint uuid)
returns complaints
language plpgsql security definer set search_path = public, extensions
as $$
declare c complaints%rowtype;
begin
  select * into c from complaints where id = p_complaint for update;
  if not found then
    raise exception 'الشكوى غير موجودة' using errcode = 'no_data_found';
  end if;
  if not complaint_is_staff(c) then
    raise exception 'لست من خدمة العملاء' using errcode = 'insufficient_privilege';
  end if;
  if c.status <> 'open' then
    return c;   -- التقاطٌ مكرَّر ليس خطأً — الصفُّ كما هو.
  end if;

  -- **تُرفع الرايةُ وتُخفض حولَ الكتابة وحدها.** ولو تُركت مرفوعةً بقيت
  -- سارية إلى آخر المعاملة، فصار أيُّ تحديثٍ مباشرٍ بعدها يمرّ بلا حارس.
  perform set_config('wasl.complaint_flow', 'on', true);
  update complaints set status = 'in_progress',
                        first_response_at = coalesce(first_response_at, now())
  where id = p_complaint returning * into c;
  perform set_config('wasl.complaint_flow', 'off', true);
  return c;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- قرارُ الحلّ — معاملةٌ واحدة
-- ─────────────────────────────────────────────────────────────────────────
-- **هنا يخرج المال.** ولذلك كلُّ ما يقع هنا يقع في معاملةٍ واحدة: الاسترداد،
-- وتعويضُ النقاط، والإنذار، وختمُ الشكوى. فإن فشل أيُّها فشل كلُّها، ولا
-- تبقى شكوى «محلولة» بلا مالٍ صُرف، ولا مالٌ صُرف بلا شكوى تفسّره.
--
-- **ولا تُقبل قيمةُ الاسترداد من التطبيق.** تُقبل **نسبةٌ**، ويُقرأ المبلغُ
-- من الطلب لحظة التنفيذ. ولا يتجاوز المقبوض — وذلك يفرضه
-- `enforce_refund_ceiling` في القاعدة، لا حسابٌ في الشاشة.
--
-- **ورسمُ التوصيل لا يُردّ إلا في الاسترداد الكامل**: خدمةٌ أُدّيت فعلًا
-- وسائقٌ قطع الطريق. أمّا الاسترداد الكامل فالطلبُ فيه كأن لم يكن.
create or replace function resolve_complaint(
  p_complaint        uuid,
  p_resolution       text,
  p_refund_percent   numeric default null,
  p_loyalty_points   int     default null,
  p_warn_against     boolean default false,
  p_internal_note    text    default null
)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  c          complaints%rowtype;
  o          orders%rowtype;
  s          complaint_settings%rowtype;
  v_payment  uuid;
  v_captured numeric;
  v_refunded numeric;
  v_base     numeric;
  v_amount   numeric := 0;
  v_points   int := 0;
  v_warned   boolean := false;
  v_warnings int := 0;
  v_actions  text[] := '{}';
begin
  -- **قفلُ الصفّ أوّلًا.** ضغطتان على «تأكيد الحلّ» من جهازين كانتا في
  -- زادقو تصرفان الاسترداد مرّتين — لأنّ الفحص كان قراءةً ثم كتابة. و
  -- `for update` يجعل الثانية تنتظر الأولى ثم ترى نتيجتها.
  select * into c from complaints where id = p_complaint for update;
  if not found then
    raise exception 'الشكوى غير موجودة' using errcode = 'no_data_found';
  end if;
  if not complaint_is_staff(c) then
    raise exception 'لست من خدمة العملاء' using errcode = 'insufficient_privilege';
  end if;
  if c.status in ('resolved', 'closed') then
    raise exception 'هذه الشكوى مُنجَزة — لا يُنفَّذ الحلُّ مرّتين'
      using errcode = 'check_violation';
  end if;

  select * into s from complaint_settings where laundry_id = c.laundry_id;

  -- ── الاسترداد ────────────────────────────────────────────────────────
  if p_refund_percent is not null and p_refund_percent > 0 then
    if p_refund_percent > 100 then
      raise exception 'لا استرداد فوق المئة بالمئة' using errcode = 'check_violation';
    end if;
    if c.order_id is null then
      raise exception 'لا استرداد على تذكرةٍ بلا طلب' using errcode = 'check_violation';
    end if;

    select * into o from orders where id = c.order_id for update;

    select p.id, p.amount into v_payment, v_captured
    from payments p
    where p.order_id = o.id and p.status = 'captured'
    order by p.created_at desc limit 1;

    if v_payment is null then
      -- طلبٌ نقديٌّ لم يُقبض إلكترونيًّا: لا استرداد بطاقة. والتعويضُ
      -- بالنقاط بابُه مفتوح — والفرقُ يُقال صراحةً لا يُبتلع.
      raise exception 'لا دفعةً مقبوضةً على هذا الطلب — عوّض بالنقاط أو استرد نقدًا في الفرع'
        using errcode = 'check_violation';
    end if;

    select coalesce(sum(amount), 0) into v_refunded
    from refunds where payment_id = v_payment and status <> 'failed';

    -- الأساس: قيمةُ الخدمة وحدها، إلا في الاسترداد الكامل فالإجمالي.
    v_base := case when p_refund_percent >= 100 then v_captured
                   else greatest(o.total - o.delivery_fee, 0) end;
    v_amount := round(v_base * (p_refund_percent / 100.0), 2);
    -- ما بقي من المقبوض بعد استردادٍ سابق (شكوى ثانية على الطلب نفسه).
    v_amount := least(v_amount, greatest(v_captured - v_refunded, 0));

    if v_amount <= 0 then
      raise exception 'استُرِدّ هذا الطلب بكامل قيمته مسبقًا — لا شيء فوقه'
        using errcode = 'check_violation';
    end if;

    insert into refunds (payment_id, order_id, amount, reason, requested_by, approved_by)
    values (v_payment, o.id, v_amount,
            format('شكوى #%s', c.complaint_number), auth.uid(), auth.uid());

    v_actions := v_actions || format('استرداد %s%% (%s ر.س)',
                                     round(p_refund_percent), v_amount);
  end if;

  -- ── تعويضٌ بالنقاط ───────────────────────────────────────────────────
  -- بابُ التعويض حين لا يكون هناك ما يُستردّ (طلبٌ نقديّ)، أو حين يكون
  -- الخطأ أصغرَ من أن يُردَّ عليه مالٌ وأكبرَ من أن يُعتذر عنه بكلمة.
  if p_loyalty_points is not null and p_loyalty_points > 0 then
    if c.order_id is null then
      select o.* into o from orders o
      where o.customer_id = c.submitted_by and o.laundry_id = c.laundry_id
      order by o.created_at desc limit 1;
    end if;

    insert into loyalty_transactions (user_id, laundry_id, order_id, kind, points, note)
    values (
      case when c.submitted_by_role = 'customer' then c.submitted_by
           else coalesce(o.customer_id, c.submitted_by) end,
      c.laundry_id, c.order_id, 'adjust', p_loyalty_points,
      format('تعويض — شكوى #%s', c.complaint_number));
    v_points := p_loyalty_points;
    v_actions := v_actions || format('تعويض %s نقطة', p_loyalty_points);
  end if;

  -- ── الإنذار ──────────────────────────────────────────────────────────
  -- **لا يُوقَف سائقٌ في منتصف جولته.** الإنذارُ يُسجَّل ويُمنع صاحبُه من
  -- **قبول جديد**؛ أمّا ما في سيّارته الآن فيُسلَّم أوّلًا. وإيقافٌ فوريّ
  -- يترك ستَّ قطعٍ في صندوقٍ لا يعرف أحدٌ أين هو.
  if p_warn_against and c.against_id is not null and c.against_role = 'driver' then
    insert into driver_warnings (driver_id, laundry_id, complaint_id, reason, issued_by)
    values (c.against_id, c.laundry_id, c.id,
            coalesce(nullif(btrim(p_resolution), ''), 'إنذارٌ على شكوى'), auth.uid());
    v_warned := true;
    v_warnings := driver_active_warnings(c.against_id, c.laundry_id);
    v_actions := v_actions || format('إنذار (%s سارٍ)', v_warnings);
  end if;

  -- ── ختمُ الشكوى ──────────────────────────────────────────────────────
  -- **الحلُّ لا يُغلق.** يفتح مهلةَ تأكيدِ صاحبها — و`resolved_at` أساسُها.
  perform set_config('wasl.complaint_flow', 'on', true);
  update complaints set
    status        = 'resolved',
    resolved_at   = now(),
    resolved_by   = auth.uid(),
    resolution    = nullif(btrim(coalesce(p_resolution, '')), ''),
    internal_note = coalesce(nullif(btrim(coalesce(p_internal_note, '')), ''), internal_note),
    first_response_at = coalesce(first_response_at, now())
  where id = p_complaint;
  perform set_config('wasl.complaint_flow', 'off', true);

  return jsonb_build_object(
    'complaint_id',   c.id,
    'refund_amount',  v_amount,
    'loyalty_points', v_points,
    'warned',         v_warned,
    'active_warnings',v_warnings,
    'actions',        to_jsonb(v_actions),
    'confirm_by',     now() + make_interval(days => coalesce(s.auto_close_days, 3))
  );
end;
$$;

comment on function resolve_complaint(uuid, text, numeric, int, boolean, text) is
  'قرارُ الحلّ كلُّه في معاملةٍ واحدة: استردادٌ وتعويضٌ وإنذارٌ وختم — أو لا شيء.';

-- ─────────────────────────────────────────────────────────────────────────
-- جوابُ الشاكي — وهو الذي يُغلق
-- ─────────────────────────────────────────────────────────────────────────
create or replace function confirm_complaint_resolution(
  p_complaint uuid,
  p_solved    boolean,
  p_note      text default null
)
returns complaints
language plpgsql security definer set search_path = public, extensions
as $$
declare c complaints%rowtype;
begin
  select * into c from complaints where id = p_complaint for update;
  if not found then
    raise exception 'الشكوى غير موجودة' using errcode = 'no_data_found';
  end if;
  if c.submitted_by <> auth.uid() and not auth_is_service_context() then
    raise exception 'هذا جوابُ صاحب الشكوى وحده'
      using errcode = 'insufficient_privilege';
  end if;
  if c.status <> 'resolved' then
    raise exception 'لا يُسأل عن حلٍّ لم يقع بعد' using errcode = 'check_violation';
  end if;

  perform set_config('wasl.complaint_flow', 'on', true);

  if p_solved then
    update complaints set status = 'closed', closed_at = now(),
                          closed_by_timeout = false
    where id = p_complaint returning * into c;
  else
    -- **«لم تُحل» تعيدها إلى الطابور بأولوية**، ولا تمحو ما صُرف: الاسترداد
    -- وقع، والنقاطُ قُيّدت. تعود لتُستكمل لا لتُعاد من الصفر.
    update complaints set status = 'in_progress',
                          reopen_count = reopen_count + 1,
                          resolved_at = null,
                          resolved_by = null
    where id = p_complaint returning * into c;
  end if;

  perform set_config('wasl.complaint_flow', 'off', true);

  if nullif(btrim(coalesce(p_note, '')), '') is not null then
    insert into complaint_messages (complaint_id, sender_id, sender_role, body)
    values (c.id, c.submitted_by, c.submitted_by_role, btrim(p_note));
  end if;

  return c;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الإغلاق التلقائيّ — ولا يُمسح من جهاز
-- ─────────────────────────────────────────────────────────────────────────
-- في زادقو تُستدعى نظيرتُها **من تطبيق المدير**: فإن لم يفتح أحدٌ الشاشة، لم
-- تُغلق شكوى أحد. وقاعدةُ عملٍ تنتظر أن يفتح أحدٌ شاشةً ليست قاعدةَ عمل.
-- هذه تُجدوَل (pg_cron) أو تُستدعى من الخادم، وتعمل ولو نام الجميع.
--
-- **ويُختم أنّ الإغلاق كان بالصمت لا بالرضا** (`closed_by_timeout`) — فلا
-- يُحسب في التقرير نجاحًا. وأكثرُ ما يُغلق بالصمت مؤشّرُ خللٍ لا إنجاز.
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
  'يُجدوَل على الخادم. إغلاقٌ يعتمد على أن يفتح مديرٌ شاشةً ليس إغلاقًا.';

-- ─────────────────────────────────────────────────────────────────────────
-- الطابور كما يُقرأ
-- ─────────────────────────────────────────────────────────────────────────
-- في زادقو تُبَثّ **كلُّ** الشكاوى إلى كلِّ جهازِ مدير، ثم تُرتَّب في الذاكرة.
-- وذلك يعمل عند مئة شكوى ويسقط عند عشرة آلاف — ويُسرّب مع كلِّ صفٍّ اسمَ
-- عميلٍ وهاتفَه إلى جهازٍ قد يُسرَق.
--
-- هنا يُرتَّب في القاعدة: المرتدَّةُ أوّلًا (قال صاحبُها «لم تُحل»)، ثم
-- المتجاوزةُ لمهلة الردّ، ثم الأقدم. و`security_invoker` يُبقي RLS سارية:
-- المنظرُ نافذةٌ على الجدول لا التفافٌ حوله.
create or replace view complaints_queue
with (security_invoker = true) as
select
  c.id,
  c.complaint_number,
  c.laundry_id,
  c.branch_id,
  c.order_id,
  o.order_number,
  ct.code        as type_code,
  ct.label_ar    as type_label,
  c.status,
  c.submitted_by,
  sp.full_name   as submitted_by_name,
  c.submitted_by_role,
  c.against_id,
  ap.full_name   as against_name,
  c.against_role,
  c.description,
  c.reopen_count,
  c.created_at,
  c.first_response_at,
  c.resolved_at,
  -- متى وعدنا بالردّ، وهل تجاوزناه؟
  c.created_at + make_interval(hours => coalesce(s.response_sla_hours, 24))
    as response_due_at,
  (c.first_response_at is null
   and c.status in ('open','in_progress')
   and now() > c.created_at + make_interval(hours => coalesce(s.response_sla_hours, 24)))
    as sla_breached,
  -- ومتى تُغلق تلقائيًّا إن سكت صاحبُها.
  case when c.status = 'resolved' and c.resolved_at is not null
       then c.resolved_at + make_interval(days => coalesce(s.auto_close_days, 3))
  end as auto_close_at
from complaints c
join complaint_types ct on ct.id = c.type_id
left join orders   o  on o.id = c.order_id
left join profiles sp on sp.id = c.submitted_by
left join profiles ap on ap.id = c.against_id
left join complaint_settings s on s.laundry_id = c.laundry_id
order by
  case c.status when 'open' then 0 when 'in_progress' then 1
                when 'resolved' then 2 else 3 end,
  c.reopen_count desc,
  c.created_at;

comment on view complaints_queue is
  'الطابور مرتَّبًا في القاعدة — المرتدَّةُ أوّلًا، فالمتجاوزةُ مهلتَها، فالأقدم.';

-- ─────────────────────────────────────────────────────────────────────────
-- ملخّصٌ للوحة
-- ─────────────────────────────────────────────────────────────────────────
-- **ومقياسُ النجاح فيه سطران يُقرآن معًا**: كم أُغلق بإقرار صاحبه، وكم
-- أُغلق بصمته. والثاني ليس نجاحًا مهما بدا في العدّ الإجماليّ.
create or replace function complaint_summary(
  p_laundry uuid,
  p_from    date default (current_date - 30),
  p_to      date default current_date
)
returns table (
  total            int,
  open_now         int,
  in_progress_now  int,
  sla_breached     int,
  closed_confirmed int,
  closed_by_silence int,
  reopened         int,
  median_response_hours numeric,
  by_type          jsonb
)
language sql stable security invoker set search_path = public, extensions
as $$
  with scoped as (
    select c.*, ct.label_ar as type_label,
           coalesce(s.response_sla_hours, 24) as sla_hours
    from complaints c
    join complaint_types ct on ct.id = c.type_id
    left join complaint_settings s on s.laundry_id = c.laundry_id
    where c.laundry_id = p_laundry
      and c.created_at >= p_from
      and c.created_at < (p_to + 1)
  )
  select
    count(*)::int,
    count(*) filter (where status = 'open')::int,
    count(*) filter (where status = 'in_progress')::int,
    count(*) filter (where first_response_at is null
                       and status in ('open','in_progress')
                       and now() > created_at + make_interval(hours => sla_hours))::int,
    count(*) filter (where status = 'closed' and not closed_by_timeout)::int,
    count(*) filter (where status = 'closed' and closed_by_timeout)::int,
    count(*) filter (where reopen_count > 0)::int,
    round(percentile_cont(0.5) within group (
      order by extract(epoch from (first_response_at - created_at)) / 3600.0
    )::numeric, 2),
    coalesce((
      select jsonb_object_agg(type_label, n)
      from (select type_label, count(*)::int as n from scoped
            group by type_label order by count(*) desc) t
    ), '{}'::jsonb)
  from scoped;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الإنذارُ يمنع الجديد ولا يقطع الجاري
-- ─────────────────────────────────────────────────────────────────────────
-- تُعاد `guard_order_assignment` بشرطٍ إضافيّ: سائقٌ بلغت إنذاراتُه السارية
-- الحدَّ لا يُسنَد إليه **جديد**. وما في سيّارته الآن يُسلَّم — لأنّ إيقافًا
-- فوريًّا يترك قطعَ عميلٍ في صندوقٍ لا يعرف أحدٌ أين هو.
create or replace function driver_is_barred(p_driver uuid, p_branch uuid)
returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select coalesce(
    driver_active_warnings(p_driver, (select laundry_id from branches where id = p_branch))
      >= (select cs.driver_warning_threshold
          from complaint_settings cs
          join branches b on b.laundry_id = cs.laundry_id
          where b.id = p_branch),
    false);
$$;

comment on function driver_is_barred(uuid, uuid) is
  'يمنع الإسناد الجديد لا الجولة الجارية — والفرقُ قطعُ عميلٍ في صندوق سيّارة.';

create or replace function guard_barred_driver_assignment()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if auth_is_service_context() then
    return new;
  end if;

  if new.pickup_driver_id is not null
     and new.pickup_driver_id is distinct from old.pickup_driver_id
     and driver_is_barred(new.pickup_driver_id, new.branch_id) then
    raise exception 'هذا السائق موقوفٌ عن الجديد لبلوغه حدَّ الإنذارات'
      using errcode = 'check_violation';
  end if;

  if new.delivery_driver_id is not null
     and new.delivery_driver_id is distinct from old.delivery_driver_id
     and driver_is_barred(new.delivery_driver_id, new.branch_id) then
    raise exception 'هذا السائق موقوفٌ عن الجديد لبلوغه حدَّ الإنذارات'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

-- الاسمُ بعد `t_orders_guard_assignment` أبجديًّا عمدًا: يُفحص الإسنادُ
-- الأساسيّ أوّلًا (أهو سائقُ الفرع أصلًا؟) ثم يُفحص وقفُه.
create trigger t_orders_guard_barred
  before update of pickup_driver_id, delivery_driver_id on orders
  for each row execute function guard_barred_driver_assignment();

-- ═════════════════════════════════════════════════════════════════════════
-- أمان مستوى الصفّ
-- ═════════════════════════════════════════════════════════════════════════
do $$
declare t text;
begin
  foreach t in array array[
    'complaint_settings','complaint_types','complaints',
    'complaint_messages','driver_warnings'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- ── الإعدادات والأنواع: يقرؤهما كلُّ مسجَّل، ويكتبهما المالكُ ومديرُ المغسلة
create policy complaint_settings_read on complaint_settings
  for select using (auth.uid() is not null);
create policy complaint_settings_write on complaint_settings
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

create policy complaint_types_read on complaint_types
  for select using (auth.uid() is not null);
create policy complaint_types_write on complaint_types
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

-- ── الشكوى نفسها
-- **من يراها**: صاحبُها، وخدمةُ العملاء، ومديرُ فرعها، والمالك.
--
-- **ولا يراها المشكوُّ منه.** وهذا قرارٌ مقصود: سائقٌ يقرأ اسم من اشتكى
-- عليه اليوم يوصل له غدًا. والمواجهةُ بين طرفين تمرّ بالإدارة أو لا تقع.
create or replace function can_see_complaint(p_complaint uuid)
returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select exists (
    select 1 from complaints c
    where c.id = p_complaint
      and (c.submitted_by = auth.uid()
        or auth_is_super_admin()
        or auth_has_role('customer_service')
        or (c.branch_id is not null
            and auth_has_branch_role(c.branch_id, 'branch_manager')))
  );
$$;

create policy complaints_read on complaints
  for select using (
    submitted_by = auth.uid()
    or auth_is_super_admin()
    or auth_has_role('customer_service')
    or (branch_id is not null and auth_has_branch_role(branch_id, 'branch_manager'))
  );

-- الفتحُ باسم النفس وحدها؛ وبقيّةُ الشروط في الحارس (طرفُ الطلب، والمهلة).
create policy complaints_insert on complaints
  for insert with check (submitted_by = auth.uid());

-- السياسةُ تفتح البابَ لمن يراها، والمحفّزُ يقرّر أيَّ عمودٍ يتحرّك.
create policy complaints_update on complaints
  for update using (
    submitted_by = auth.uid()
    or auth_is_super_admin()
    or auth_has_role('customer_service')
    or (branch_id is not null and auth_has_branch_role(branch_id, 'branch_manager'))
  ) with check (
    submitted_by = auth.uid()
    or auth_is_super_admin()
    or auth_has_role('customer_service')
    or (branch_id is not null and auth_has_branch_role(branch_id, 'branch_manager'))
  );

-- **لا تُحذف شكوى.** سجلُّ نزاعٍ يُحذف يعني طرفًا يمحو ما عليه.
create policy complaints_delete on complaints
  for delete using (false);

-- ── المحادثة: يراها من يرى الشكوى — إلا الداخليّة، فللموظّفين وحدهم.
create policy complaint_messages_read on complaint_messages
  for select using (
    can_see_complaint(complaint_id)
    and (not is_internal
         or auth_is_super_admin()
         or auth_has_role('customer_service')
         or exists (select 1 from complaints c
                    where c.id = complaint_id and c.branch_id is not null
                      and auth_has_branch_role(c.branch_id, 'branch_manager')))
  );

create policy complaint_messages_insert on complaint_messages
  for insert with check (sender_id = auth.uid() and can_see_complaint(complaint_id));

-- الرسالةُ المرسَلة لا تُعدَّل ولا تُمحى: محادثةٌ تُحرَّر بعد قراءتها ليست سجلًّا.
create policy complaint_messages_no_edit on complaint_messages
  for update using (false);
create policy complaint_messages_no_delete on complaint_messages
  for delete using (false);

-- ── الإنذارات: يقرؤها صاحبُها والإدارة، ولا تُكتب إلا بدالّة الحلّ.
create policy driver_warnings_read on driver_warnings
  for select using (
    driver_id = auth.uid()
    or auth_is_super_admin()
    or auth_has_role('customer_service')
  );
create policy driver_warnings_admin on driver_warnings
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

-- ═════════════════════════════════════════════════════════════════════════
-- أقلُّ صلاحيةٍ تكفي
-- ═════════════════════════════════════════════════════════════════════════
grant select on complaint_settings, complaint_types, complaints,
                complaint_messages, driver_warnings to authenticated;
grant insert, update on complaints to authenticated;
grant insert on complaint_messages to authenticated;
grant select on complaints_queue to authenticated;

-- **الإنذار لا يُكتب من حزمة**: تكتبه `resolve_complaint` وحدها بصلاحية
-- مالكها. وسائقٌ يمحو إنذارَه بنداءٍ مباشر يُفرغ النظام من معناه.
revoke insert, update, delete, truncate on driver_warnings from anon, authenticated;
revoke insert, update, delete, truncate on complaint_settings, complaint_types
  from anon, authenticated;
revoke delete, truncate on complaints, complaint_messages from anon, authenticated;
revoke update on complaint_messages from anon, authenticated;
revoke insert, update, delete, truncate on complaints, complaint_messages,
  complaint_settings, complaint_types, driver_warnings from anon;

-- الدوالّ: للمسجَّلين لا للزائر ولا لـPUBLIC.
-- ما تناديه الحزمة فعلًا.
do $$
declare f text;
begin
  foreach f in array array[
    'claim_complaint(uuid)',
    'resolve_complaint(uuid, text, numeric, int, boolean, text)',
    'confirm_complaint_resolution(uuid, boolean, text)',
    'complaint_summary(uuid, date, date)',
    -- تُستدعى من داخل سياسة `complaint_messages_read`، والسياسةُ تُقيَّم
    -- بصلاحية المُنادي — فلا بدّ لها من المنح.
    'can_see_complaint(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- **ومساعداتُ الحرّاس لا تُنشر.** هذه تُستدعى من **داخل** دوالَّ
-- `security definer` تعمل بصلاحية مالكها، فلا تحتاج منحًا للحزمة أصلًا.
-- وكشفُها يعطي أيَّ مسجَّلٍ مسبارًا يسأل به عن غيره: «كم إنذارًا على هذا
-- السائق؟» و«أهذا طرفٌ في ذاك الطلب؟» — أسئلةٌ لا تخصّه، وجوابُها يُبنى.
do $$
declare f text;
begin
  foreach f in array array[
    'is_party_to_order(uuid, uuid)',
    'complainant_role(uuid, uuid)',
    'complaint_is_staff(complaints)',
    'driver_active_warnings(uuid, uuid)',
    'driver_is_barred(uuid, uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end $$;

-- **والكنسُ للخادم وحده.** دالّةٌ تُغلق شكاوى الناس لا تُنادى من هاتف.
revoke execute on function close_stale_complaints() from public, anon, authenticated;

-- محفّزاتٌ لا تُنادى مباشرةً.
revoke execute on function guard_complaint_insert() from public, anon, authenticated;
revoke execute on function guard_complaint_update() from public, anon, authenticated;
revoke execute on function guard_barred_driver_assignment() from public, anon, authenticated;

-- ═════════════════════════════════════════════════════════════════════════
-- أنواعٌ افتراضيّة — بلغة الغسيل لا بلغة المطاعم
-- ═════════════════════════════════════════════════════════════════════════
-- **هذه بذرةٌ لا قانون.** تُنشأ لمغسلةٍ جديدة كي لا تبدأ من قائمةٍ فارغة،
-- وللإدارة أن تحذف منها وتضيف — فمغسلةٌ تعطّر الملابس تحتاج «العطر المطلوب
-- لم يُستخدم»، وأخرى لا تعرف العطر أصلًا.
create or replace function seed_complaint_types(p_laundry uuid)
returns int
language plpgsql security definer set search_path = public, extensions
as $$
declare v_count int;
begin
  if not (auth_is_service_context() or auth_is_super_admin()) then
    raise exception 'بذرُ الأنواع للمالك وحده' using errcode = 'insufficient_privilege';
  end if;

  insert into complaint_types
    (laundry_id, code, label_ar, label_en, for_role, suggested_against,
     allows_general, sort_order)
  values
    -- ── ما يشتكي منه العميل ────────────────────────────────────────────
    (p_laundry,'stain_remains','بقعةٌ لم تُزل','Stain not removed',
     'customer','laundry_staff',false,10),
    (p_laundry,'item_missing','قطعةٌ مفقودة','Missing item',
     'customer','laundry_staff',false,20),
    (p_laundry,'item_damaged','قطعةٌ تالفة','Damaged item',
     'customer','laundry_staff',false,30),
    (p_laundry,'color_run','لونٌ نزل على قطعةٍ أخرى','Color bleed',
     'customer','laundry_staff',false,40),
    (p_laundry,'poor_ironing','كيٌّ رديء','Poor ironing',
     'customer','laundry_staff',false,50),
    (p_laundry,'bad_smell','رائحةٌ غير مقبولة','Bad smell',
     'customer','laundry_staff',false,60),
    (p_laundry,'wrong_item','قطعةٌ ليست لي','Item is not mine',
     'customer','laundry_staff',false,70),
    (p_laundry,'late_delivery','تأخّرٌ في التسليم','Late delivery',
     'customer','driver',false,80),
    (p_laundry,'driver_behavior','سلوكُ السائق','Driver behavior',
     'customer','driver',false,90),
    (p_laundry,'billing_unclear','فاتورةٌ غير مفهومة','Unclear billing',
     'customer',null,true,100),

    -- ── وما يشتكي منه السائق ───────────────────────────────────────────
    (p_laundry,'customer_unreachable','العميل لا يردّ','Customer unreachable',
     'driver','customer',false,110),
    (p_laundry,'wrong_address','عنوانٌ خاطئ','Wrong address',
     'driver','customer',false,120),
    (p_laundry,'customer_behavior','سلوكُ العميل','Customer behavior',
     'driver','customer',false,130),
    (p_laundry,'not_ready_at_branch','الطلبُ لم يكن جاهزًا في الفرع',
     'Order not ready at branch','driver','laundry_staff',false,140),

    -- ── وما تشتكي منه المغسلة ──────────────────────────────────────────
    (p_laundry,'count_mismatch','اختلافٌ في عدد القطع','Piece count mismatch',
     'laundry_staff','driver',false,150),
    (p_laundry,'driver_late_pickup','السائق تأخّر في الاستلام',
     'Driver late for pickup','laundry_staff','driver',false,160),

    -- ── وتذاكرُ بلا طلب ────────────────────────────────────────────────
    (p_laundry,'financial_inquiry','استفسارٌ ماليّ','Financial inquiry',
     null,null,true,200),
    (p_laundry,'data_update','تحديثُ بيانات','Data update',
     null,null,true,210),
    (p_laundry,'general_inquiry','استفسارٌ عام','General inquiry',
     null,null,true,220),
    (p_laundry,'other','أخرى','Other',
     null,null,true,999)
  on conflict (laundry_id, code) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- **للمالك وحده.** كانت مكشوفةً لكلّ مسجَّل، وهي تكتب في `complaint_types`
-- لأيّ مغسلةٍ يُمرَّر معرّفُها — أي أن عميلًا يزرع أنواعًا في مغسلةٍ لا يملكها.
-- والفحصُ في الدالّة كما في المنح: `security definer` تتجاوز RLS، فمنحٌ
-- يُوسَّع يومًا بلا فحصٍ داخليّ يفتحها على مصراعيها.
revoke execute on function seed_complaint_types(uuid) from public, anon, authenticated;

-- ولكلِّ مغسلةٍ قائمةٌ وإعداداتٌ منذ اللحظة الأولى: نظامٌ يحتاج تهيئةً يدويّةً
-- قبل أن يعمل هو نظامٌ معطَّلٌ بصمت.
do $$
declare l record;
begin
  for l in select id from laundries loop
    insert into complaint_settings (laundry_id) values (l.id)
      on conflict do nothing;
    perform seed_complaint_types(l.id);
  end loop;
end $$;

create or replace function ensure_complaint_defaults()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  insert into complaint_settings (laundry_id) values (new.id) on conflict do nothing;
  perform seed_complaint_types(new.id);
  return new;
end;
$$;

create trigger t_laundries_complaint_defaults
  after insert on laundries
  for each row execute function ensure_complaint_defaults();

revoke execute on function ensure_complaint_defaults() from public, anon, authenticated;
