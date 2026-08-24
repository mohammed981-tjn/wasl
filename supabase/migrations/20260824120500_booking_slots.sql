-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | محرّك المواعيد والطاقة الاستيعابية
-- ═══════════════════════════════════════════════════════════════════════════
--
-- «متى تريد استلام الملابس؟» سؤالٌ لا يُجاب بقائمة أوقاتٍ ثابتة. الفتحة التي
-- تُعرض ولا تُنفَّذ أسوأ من فتحةٍ لا تُعرض: العميل انتظر، والفرع تجاوز طاقته،
-- والوعد الذي قُطع لم يُوفَ.
--
-- فالفتحة هنا محسوبةٌ من خمسة قيود مجتمعة:
--   ١) ساعات عمل الفرع في ذلك اليوم        (branch_hours)
--   ٢) الطاقة اليومية بالقطع                (branches.daily_capacity_pieces)
--   ٣) سقف الفتحة الواحدة طلبًا وقطعةً      (booking_settings)
--   ٤) مهلةٌ من الآن — لا موعد بعد دقيقتين  (lead_time_minutes)
--   ٥) أيام التعطيل والإغلاق الطارئ         (slot_blackouts)

create schema if not exists wasl;
set search_path = wasl, public, extensions;

create type slot_kind as enum ('pickup', 'delivery');

-- ─────────────────────────────────────────────────────────────────────────
-- إعدادات الحجز لكل فرع
-- ─────────────────────────────────────────────────────────────────────────
create table booking_settings (
  branch_id            uuid primary key references branches(id) on delete cascade,

  -- طول الفتحة بالدقائق. ٦٠ يعطي «٥:٠٠–٦:٠٠»، و١٢٠ يعطي «٥:٠٠–٧:٠٠».
  slot_minutes         int not null default 60 check (slot_minutes between 15 and 480),

  -- أقرب موعد من الآن. صفرٌ يعني أن العميل يحجز فتحةً بدأت قبل دقيقة.
  lead_time_minutes    int not null default 120 check (lead_time_minutes >= 0),

  -- إلى أيّ مدى يرى العميل مواعيد؟ أسبوعٌ افتراضًا.
  horizon_days         int not null default 7 check (horizon_days between 1 and 60),

  -- سقف الفتحة الواحدة. صفر = بلا سقف.
  max_orders_per_slot  int not null default 0 check (max_orders_per_slot >= 0),
  max_pieces_per_slot  int not null default 0 check (max_pieces_per_slot >= 0),

  -- آخر فتحة تُفتح قبل الإغلاق: سائقٌ يخرج قبل الإغلاق بعشر دقائق لا يعود.
  cutoff_before_close_minutes int not null default 30 check (cutoff_before_close_minutes >= 0),

  updated_at           timestamptz not null default now()
);

comment on column booking_settings.lead_time_minutes is
  'أقرب موعد من الآن. صفرٌ يعني فتحةً بدأت قبل دقيقة — وهو عطلٌ لا إعداد.';

-- ─────────────────────────────────────────────────────────────────────────
-- التعطيل
-- ─────────────────────────────────────────────────────────────────────────
-- عيدٌ، أو عطلٌ في آلة، أو إغلاقُ ساعتين لسببٍ طارئ. مدًى زمنيّ لا يومٌ كامل:
-- «مغلق من ٢ إلى ٤ اليوم» حاجةٌ حقيقية لا تُعبَّر بيوم.
create table slot_blackouts (
  id         uuid primary key default uuid_generate_v4(),
  branch_id  uuid not null references branches(id) on delete cascade,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  kind       slot_kind,          -- NULL = يشمل الاستلام والتسليم معًا
  reason     text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index on slot_blackouts (branch_id, starts_at);

-- ─────────────────────────────────────────────────────────────────────────
-- عدد قطع الطلب — يُستعمل في حساب الطاقة
-- ─────────────────────────────────────────────────────────────────────────
-- ما يُحجز على الطاقة هو الكمّية المطلوبة (تقدير العميل) لا القطع المجرودة،
-- لأن الجرد لا يقع إلا بعد أن تصل الملابس — والحجز يقع قبله بأيام.
-- والوزن يُحوَّل بمعامل: كيلو الغسيل ليس قطعةً واحدة.
create or replace function order_piece_load(p_order uuid)
returns numeric
language sql stable
as $$
  select coalesce(sum(
    case oi.unit
      when 'piece'     then oi.quantity
      when 'kilogram'  then oi.quantity * 4     -- الكيلو ≈ أربع قطع
      when 'basket'    then oi.quantity * 15    -- السلّة ≈ خمس عشرة قطعة
    end
  ), 0)
  from order_items oi where oi.order_id = p_order;
$$;

comment on function order_piece_load is
  'حِمل الطلب بالقطع المكافئة. الوزن والسلّة يُحوَّلان — وإلا بدا طلبُ عشرين كيلو أخفَّ من قميص.';

-- ─────────────────────────────────────────────────────────────────────────
-- الفتحات المتاحة
-- ─────────────────────────────────────────────────────────────────────────
-- تُعيد الفتحات مع ما تبقّى فيها، وسببَ إغلاق المغلقة. والسبب ليس زينةً:
-- «لا مواعيد» شاشةٌ يائسة، و«ممتلئ اليوم — جرّب الغد» شاشةٌ تبيع.
create or replace function available_slots(
  p_branch      uuid,
  p_kind        slot_kind default 'pickup',
  p_from        date default null,
  p_days        int  default null,
  p_piece_load  numeric default 0
)
returns table (
  slot_start      timestamptz,
  slot_end        timestamptz,
  is_available    boolean,
  orders_booked   int,
  pieces_booked   numeric,
  blocked_reason  text
)
language plpgsql stable
as $$
declare
  v_cfg    booking_settings%rowtype;
  v_branch branches%rowtype;
  v_from   date;
  v_days   int;
begin
  select * into v_branch from branches where id = p_branch;
  if not found or not v_branch.is_active then
    return;
  end if;

  select * into v_cfg from booking_settings where branch_id = p_branch;
  if not found then
    -- إعداداتٌ افتراضية بدل الصمت: فرعٌ بلا إعدادات يجب أن يقبل الحجز
    -- بقيمٍ محافظة، لا أن يبدو مغلقًا للأبد.
    v_cfg.slot_minutes := 60;
    v_cfg.lead_time_minutes := 120;
    v_cfg.horizon_days := 7;
    v_cfg.max_orders_per_slot := 0;
    v_cfg.max_pieces_per_slot := 0;
    v_cfg.cutoff_before_close_minutes := 30;
  end if;

  v_from := coalesce(p_from, current_date);
  v_days := least(coalesce(p_days, v_cfg.horizon_days), v_cfg.horizon_days);

  return query
  with days as (
    select (v_from + i)::date as d
    from generate_series(0, v_days - 1) as i
  ),
  -- فتحات اليوم: سلسلةٌ من الفتح إلى الإغلاق بخطوة طول الفتحة، ثم تُقصّ
  -- كلُّ فتحةٍ تنتهي بعد آخر خروجٍ مسموح (الإغلاق ناقصَ مهلة العودة).
  slots as (
    select
      gs as s_start,
      gs + make_interval(mins => v_cfg.slot_minutes) as s_end
    from days d
    join branch_hours h
      on h.branch_id = p_branch
     and h.weekday = extract(dow from d.d)::smallint
     and not h.is_closed
    cross join lateral generate_series(
      (d.d + h.opens_at)::timestamptz,
      (d.d + h.closes_at)::timestamptz - make_interval(mins => v_cfg.slot_minutes),
      make_interval(mins => v_cfg.slot_minutes)
    ) as gs
    where gs + make_interval(mins => v_cfg.slot_minutes)
          <= (d.d + h.closes_at)::timestamptz
             - make_interval(mins => v_cfg.cutoff_before_close_minutes)
  ),
  booked as (
    select
      s.s_start,
      count(o.id)::int as n_orders,
      coalesce(sum(order_piece_load(o.id)), 0)::numeric as n_pieces
    from slots s
    left join orders o
      on o.branch_id = p_branch
     and o.status not in ('draft','cancelled','refunded')
     and ((p_kind = 'pickup'   and o.pickup_slot_start   = s.s_start)
       or (p_kind = 'delivery' and o.delivery_slot_start = s.s_start))
    group by s.s_start
  ),
  daily as (
    select
      s.s_start::date as d,
      coalesce(sum(order_piece_load(o.id)), 0)::numeric as day_pieces
    from slots s
    left join orders o
      on o.branch_id = p_branch
     and o.status not in ('draft','cancelled','refunded')
     and ((p_kind = 'pickup'   and o.pickup_slot_start::date   = s.s_start::date)
       or (p_kind = 'delivery' and o.delivery_slot_start::date = s.s_start::date))
    group by s.s_start::date
  )
  select
    s.s_start,
    s.s_end,
    reason.txt is null as is_available,
    b.n_orders,
    b.n_pieces,
    reason.txt
  from slots s
  join booked b on b.s_start = s.s_start
  join daily  dl on dl.d = s.s_start::date
  cross join lateral (
    select case
      when s.s_start < now() + make_interval(mins => v_cfg.lead_time_minutes)
        then 'أقرب من مهلة التجهيز'
      when exists (
        select 1 from slot_blackouts bl
        where bl.branch_id = p_branch
          and (bl.kind is null or bl.kind = p_kind)
          and bl.starts_at < s.s_end and bl.ends_at > s.s_start
      ) then coalesce((
        select bl.reason from slot_blackouts bl
        where bl.branch_id = p_branch
          and (bl.kind is null or bl.kind = p_kind)
          and bl.starts_at < s.s_end and bl.ends_at > s.s_start
        limit 1), 'مغلق')
      when v_cfg.max_orders_per_slot > 0 and b.n_orders >= v_cfg.max_orders_per_slot
        then 'الفتحة ممتلئة'
      when v_cfg.max_pieces_per_slot > 0
           and b.n_pieces + p_piece_load > v_cfg.max_pieces_per_slot
        then 'طاقة الفتحة لا تتّسع لهذا الطلب'
      when v_branch.daily_capacity_pieces > 0
           and dl.day_pieces + p_piece_load > v_branch.daily_capacity_pieces
        then 'طاقة اليوم مكتملة'
      else null
    end as txt
  ) reason
  order by s.s_start;
end;
$$;

comment on function available_slots is
  'الفتحات المتاحة محسوبةً من ساعات العمل والطاقة والسقوف والمهلة والتعطيل. تُعيد سبب إغلاق المغلقة — «ممتلئ اليوم» يبيع، و«لا مواعيد» لا.';

-- أقرب فتحةٍ متاحة فعلًا — الجواب المباشر لسؤال العميل.
create or replace function earliest_slot(
  p_branch uuid,
  p_kind slot_kind default 'pickup',
  p_piece_load numeric default 0
)
returns timestamptz
language sql stable
as $$
  select slot_start from available_slots(p_branch, p_kind, null, null, p_piece_load)
  where is_available
  order by slot_start
  limit 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الحارس: لا يُحجز موعدٌ غيرُ متاح
-- ─────────────────────────────────────────────────────────────────────────
-- عرضُ الفتحات في التطبيق لا يمنع من ينادي الواجهة بموعدٍ ملفَّق. والسباق
-- حقيقيّ أيضًا: عميلان يريان الفتحة نفسها متاحةً ويحجزان معًا.
create or replace function enforce_slot_availability()
returns trigger
language plpgsql security definer set search_path = wasl, public, extensions
as $$
declare
  v_ok boolean;
begin
  if auth.uid() is null then
    return new;   -- السياق الخادميّ يحجز يدويًّا
  end if;

  if new.pickup_slot_start is not null
     and new.pickup_slot_start is distinct from coalesce(old.pickup_slot_start, null) then
    select is_available into v_ok
    from available_slots(new.branch_id, 'pickup', new.pickup_slot_start::date, 1,
                         order_piece_load(new.id))
    where slot_start = new.pickup_slot_start;
    if not coalesce(v_ok, false) then
      raise exception 'موعد الاستلام غير متاح' using errcode = 'check_violation';
    end if;
  end if;

  if new.delivery_slot_start is not null
     and new.delivery_slot_start is distinct from coalesce(old.delivery_slot_start, null) then
    select is_available into v_ok
    from available_slots(new.branch_id, 'delivery', new.delivery_slot_start::date, 1,
                         order_piece_load(new.id))
    where slot_start = new.delivery_slot_start;
    if not coalesce(v_ok, false) then
      raise exception 'موعد التسليم غير متاح' using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

create trigger t_orders_slot_guard
  before update of pickup_slot_start, delivery_slot_start on orders
  for each row execute function enforce_slot_availability();

create trigger t_booking_settings_touch before update on booking_settings
  for each row execute function touch_updated_at();

-- الصلاحيات وRLS للجداول الجديدة
grant select, insert, update, delete on booking_settings, slot_blackouts to authenticated;
grant select on booking_settings, slot_blackouts to anon;

alter table booking_settings enable row level security;
alter table booking_settings force row level security;
alter table slot_blackouts   enable row level security;
alter table slot_blackouts   force row level security;

create policy booking_settings_read on booking_settings for select using (true);
create policy booking_settings_write on booking_settings
  for all using (auth_has_branch_role(branch_id, 'branch_manager'))
  with check (auth_has_branch_role(branch_id, 'branch_manager'));

create policy slot_blackouts_read on slot_blackouts for select using (true);
create policy slot_blackouts_write on slot_blackouts
  for all using (auth_has_branch_role(branch_id, 'branch_manager', 'laundry_staff'))
  with check (auth_has_branch_role(branch_id, 'branch_manager', 'laundry_staff'));
