-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | محرّك التوصيل: المناطق والرسوم
-- ═══════════════════════════════════════════════════════════════════════════
--
-- المطلوب أن تُعبَّر كلُّ هذه السياسات من لوحة الإدارة، بلا إصدار تطبيق جديد:
--
--   • رسم ثابت                     → 10 ريال
--   • شرائح مسافة                  → 0–3 كم = 5، 3–7 = 10، 7–12 = 15
--   • رسم حسب المنطقة              → لكل حيّ سعره
--   • فصل الاستلام عن التسليم      → استلام 8، تسليم 8
--   • خصم الرحلتين معًا            → الاثنان = 15 لا 16
--   • توصيل مجاني فوق مبلغ         → أكثر من 100 ريال
--
-- ولذلك ثلاثة جداول لا واحد: إعداداتٌ لكل فرع تختار **الاستراتيجية**، وجدولا
-- شرائح ومناطق يغذّيان الاستراتيجيتين اللتين تحتاجان تفصيلًا. والدالّة في آخر
-- الملف هي المرجع الوحيد لحساب الرسم — التطبيق يسألها ولا يحسب.

create type delivery_strategy as enum ('flat', 'distance', 'zone');

-- ─────────────────────────────────────────────────────────────────────────
-- إعدادات التوصيل لكل فرع
-- ─────────────────────────────────────────────────────────────────────────
create table delivery_settings (
  branch_id   uuid primary key references branches(id) on delete cascade,
  strategy    delivery_strategy not null default 'flat',

  -- تُستعمل حين strategy = 'flat'
  flat_pickup_fee   numeric(10,2) not null default 0 check (flat_pickup_fee >= 0),
  flat_delivery_fee numeric(10,2) not null default 0 check (flat_delivery_fee >= 0),

  -- رسم الرحلتين معًا. NULL = اجمع الرسمين كما هما.
  -- هذا ما يجعل «الاستلام 8، التسليم 8، والاثنان 15» ممكنًا بلا شيفرة.
  combined_fee numeric(10,2) check (combined_fee >= 0),

  -- توصيل مجاني فوق هذا المجموع. NULL = لا إعفاء.
  free_above_subtotal numeric(10,2) check (free_above_subtotal >= 0),

  -- أبعد مسافة يقبلها الفرع. خارجها لا يُعرض على العميل أصلًا.
  max_radius_km numeric(6,2) not null default 15 check (max_radius_km > 0),

  -- حدّ أدنى لقيمة الطلب قبل الرسوم.
  min_order_subtotal numeric(10,2) not null default 0 check (min_order_subtotal >= 0),

  updated_at  timestamptz not null default now()
);

comment on column delivery_settings.combined_fee is
  'رسم الاستلام والتسليم معًا. NULL = اجمع الرسمين. هنا يسكن «الاثنان بـ15 لا 16».';

-- ─────────────────────────────────────────────────────────────────────────
-- شرائح المسافة — حين strategy = 'distance'
-- ─────────────────────────────────────────────────────────────────────────
-- الحدّ الأدنى شامل والأعلى غير شامل [from, to) — كي لا تقع 3.0 كم في شريحتين.
create table delivery_distance_tiers (
  id          uuid primary key default uuid_generate_v4(),
  branch_id   uuid not null references branches(id) on delete cascade,
  from_km     numeric(6,2) not null check (from_km >= 0),
  to_km       numeric(6,2) not null,
  pickup_fee  numeric(10,2) not null default 0 check (pickup_fee >= 0),
  delivery_fee numeric(10,2) not null default 0 check (delivery_fee >= 0),
  check (to_km > from_km)
);

create index on delivery_distance_tiers (branch_id, from_km);

-- شريحتان متداخلتان تجعلان الرسم يعتمد على ترتيب الصفوف — وهو غير مضمون.
-- الاستبعاد يمنع التداخل في القاعدة لا في مراجعة بشرية.
alter table delivery_distance_tiers
  add constraint no_overlapping_tiers
  exclude using gist (
    branch_id with =,
    numrange(from_km, to_km, '[)') with &&
  );

-- ─────────────────────────────────────────────────────────────────────────
-- المناطق الجغرافية — حين strategy = 'zone'، وللـGeoFencing دائمًا
-- ─────────────────────────────────────────────────────────────────────────
-- المنطقة تخدم غرضين: تسعيرًا حين تكون الاستراتيجية 'zone'، وتحديدَ نطاق
-- الخدمة في كل الحالات — «هذا الحيّ لا نخدمه» جوابٌ يُعطى قبل أن يملأ العميل
-- طلبًا كاملًا.
create table delivery_zones (
  id          uuid primary key default uuid_generate_v4(),
  branch_id   uuid not null references branches(id) on delete cascade,
  name_ar     text not null,
  name_en     text,
  area        geography(polygon, 4326) not null,
  pickup_fee   numeric(10,2) not null default 0 check (pickup_fee >= 0),
  delivery_fee numeric(10,2) not null default 0 check (delivery_fee >= 0),
  combined_fee numeric(10,2) check (combined_fee >= 0),
  -- عند تداخل منطقتين تفوز الأعلى أولوية. التداخل مقصود أحيانًا:
  -- «وسط المدينة» داخل «المدينة» بسعر مختلف.
  priority    int not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create index on delivery_zones using gist (area);
create index on delivery_zones (branch_id, priority desc) where is_active;

-- توفّر الخدمة في منطقة بعينها — «التنظيف الجاف في هذا الحيّ فقط».
-- غياب الصفّ يعني «متاحة»، فلا يحتاج الوضع الطبيعي صفوفًا.
create table zone_service_rules (
  id          uuid primary key default uuid_generate_v4(),
  zone_id     uuid not null references delivery_zones(id) on delete cascade,
  service_id  uuid not null references services(id) on delete cascade,
  is_offered  boolean not null default true,
  unique (zone_id, service_id)
);

-- ─────────────────────────────────────────────────────────────────────────
-- الدالّة المرجعية: كم يدفع هذا العميل مقابل التوصيل؟
-- ─────────────────────────────────────────────────────────────────────────
-- تُرجع صفًّا واحدًا فيه الرسم وسببه. «السبب» ليس زينةً: العميل الذي يرى رسمًا
-- لا يفهمه يترك السلّة، والدعم الذي لا يعرف من أين جاء الرقم لا يجيب.
create or replace function quote_delivery_fee(
  p_branch     uuid,
  p_point      geography,
  p_subtotal   numeric,
  p_wants_pickup   boolean default true,
  p_wants_delivery boolean default true
)
returns table (
  fee          numeric,
  distance_km  numeric,
  zone_id      uuid,
  reason       text,
  serviceable  boolean
)
language plpgsql stable
as $$
declare
  v            delivery_settings%rowtype;
  v_distance   numeric;
  v_zone       delivery_zones%rowtype;
  v_pickup     numeric := 0;
  v_delivery   numeric := 0;
  v_combined   numeric;
  v_fee        numeric := 0;
  v_reason     text;
begin
  select * into v from delivery_settings where branch_id = p_branch;
  if not found then
    return query select 0::numeric, null::numeric, null::uuid,
                        'لا إعدادات توصيل لهذا الفرع'::text, false;
    return;
  end if;

  select round((st_distance(b.location, p_point) / 1000.0)::numeric, 2)
    into v_distance
  from branches b where b.id = p_branch;

  if v_distance is null then
    return query select 0::numeric, null::numeric, null::uuid,
                        'موقع الفرع غير محدَّد'::text, false;
    return;
  end if;

  if v_distance > v.max_radius_km then
    return query select 0::numeric, v_distance, null::uuid,
                        'خارج نطاق خدمة الفرع'::text, false;
    return;
  end if;

  -- المنطقة تُحسب دائمًا: تسعّر حين تكون الاستراتيجية 'zone'، وتقيّد الخدمة
  -- في كل الحالات.
  select * into v_zone
  from delivery_zones z
  where z.branch_id = p_branch and z.is_active
    and st_covers(z.area, p_point)
  order by z.priority desc
  limit 1;

  case v.strategy
    when 'flat' then
      v_pickup   := v.flat_pickup_fee;
      v_delivery := v.flat_delivery_fee;
      v_combined := v.combined_fee;
      v_reason   := 'رسم ثابت';

    when 'distance' then
      select t.pickup_fee, t.delivery_fee into v_pickup, v_delivery
      from delivery_distance_tiers t
      where t.branch_id = p_branch
        and v_distance >= t.from_km and v_distance < t.to_km
      limit 1;

      if v_pickup is null then
        -- مسافة داخل النطاق ولا شريحة تغطّيها = ثغرة في إعداد الإدارة.
        -- الصمت هنا يعني توصيلًا مجانيًا بالخطأ، فيُصرَّح بالسبب.
        return query select 0::numeric, v_distance, v_zone.id,
                            format('لا شريحة مسافة تغطّي %s كم', v_distance)::text, false;
        return;
      end if;
      v_combined := v.combined_fee;
      v_reason   := format('شريحة المسافة (%s كم)', v_distance);

    when 'zone' then
      if v_zone.id is null then
        return query select 0::numeric, v_distance, null::uuid,
                            'الموقع خارج مناطق التوصيل المعرَّفة'::text, false;
        return;
      end if;
      v_pickup   := v_zone.pickup_fee;
      v_delivery := v_zone.delivery_fee;
      v_combined := coalesce(v_zone.combined_fee, v.combined_fee);
      v_reason   := format('منطقة: %s', v_zone.name_ar);
  end case;

  -- الجمع، مع احترام رسم الرحلتين معًا إن عُرِّف.
  if p_wants_pickup and p_wants_delivery then
    v_fee := coalesce(v_combined, v_pickup + v_delivery);
    if v_combined is not null then
      v_reason := v_reason || ' — استلام وتسليم';
    end if;
  elsif p_wants_pickup then
    v_fee := v_pickup;
    v_reason := v_reason || ' — استلام فقط';
  elsif p_wants_delivery then
    v_fee := v_delivery;
    v_reason := v_reason || ' — تسليم فقط';
  end if;

  -- الإعفاء يأتي أخيرًا: يلغي ما سبق مهما كانت الاستراتيجية.
  if v.free_above_subtotal is not null and p_subtotal >= v.free_above_subtotal then
    return query select 0::numeric, v_distance, v_zone.id,
                        format('توصيل مجاني لتجاوز الطلب %s ريال', v.free_above_subtotal)::text,
                        true;
    return;
  end if;

  return query select v_fee, v_distance, v_zone.id, v_reason, true;
end;
$$;

comment on function quote_delivery_fee is
  'المرجع الوحيد لرسم التوصيل. التطبيق ولوحة الإدارة والتقارير تسألها ولا تحسب.';

create trigger t_delivery_settings_touch before update on delivery_settings
  for each row execute function touch_updated_at();
