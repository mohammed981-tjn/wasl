-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | محرّك الطلبات وخطّ تشغيل المغسلة
-- ═══════════════════════════════════════════════════════════════════════════
--
-- ما يميّز مغسلةً عن مطعم أنّ الطلب لا «يُحضَّر» ثم يخرج: يدخل، ويُفرز، ويُغسل،
-- ويُجفَّف، ويُكوى، ويُغلَّف — وفي كل مرحلة يجب أن تعرف الإدارة أين هو، وأين كل
-- قطعة فيه. ولذلك لا يكفي عمود `status` واحد؛ هنا ثلاث طبقات:
--
--   orders            الطلب وحالته الجارية        — «أين هو الآن؟»
--   order_events      سجلّ كل انتقال ومن نفّذه    — «كيف وصل إلى هنا؟»
--   order_garments    القطعة الواحدة بباركودها     — «أين ثوبي أنا؟»

-- ─────────────────────────────────────────────────────────────────────────
-- العناوين — بما فيها وضع الزائر
-- ─────────────────────────────────────────────────────────────────────────
-- المدينة المنورة ليست مدينة سكّان فحسب. الحاجّ والمعتمر ونزيل الفندق لا يعرف
-- عنوانًا وطنيًّا ولا اسم شارع — يعرف اسم فندقه ورقم غرفته وموعد مغادرته.
-- فالنظام يسأله ما يعرف، ويحفظ موعد المغادرة لأنه **قيدٌ على وعد التسليم**:
-- لا يجوز أن يَعِد النظام بتسليمٍ بعد أن يغادر صاحبه المدينة.
-- ═══ عزل المخطّط ═══════════════════════════════════════════════════════════
-- وصل يسكن schema باسمه لا `public`. والسبب أن المشروع مشترك مع تطبيق آخر
-- (AdCraft) على الخطّة نفسها: فـ`public` أرضٌ مشاعة تتصادم فيها الأسماء، و
-- schema مستقلّ يعطي فضاء أسماء خاصًّا، وسياسات خاصّة، وحذفًا نظيفًا بأمر
-- واحد (`drop schema wasl cascade`) لا يمسّ جدولًا لغيرنا.
--
-- ملاحظة نشر: PostgREST لا يكشف إلا `public` افتراضًا. فليُضَف `wasl` إلى
-- Exposed schemas في إعدادات API، وإلا فالجداول موجودة ولا تراها الواجهة.
create schema if not exists wasl;
set search_path = wasl, public, extensions;

create type address_kind as enum ('home', 'work', 'hotel', 'other');

create table addresses (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references profiles(id) on delete cascade,
  kind         address_kind not null default 'home',
  label        text,
  location     geography(point, 4326) not null,
  street       text,
  district     text,
  city         text not null default 'المدينة المنورة',
  building     text,
  notes        text,                          -- «الدور الثاني، الباب الأزرق»

  -- حقول الفندق — تُملأ حين kind = 'hotel'
  hotel_name   text,
  room_number  text,
  checkout_date date,

  is_default   boolean not null default false,
  created_at   timestamptz not null default now()
);

create index on addresses (user_id);
create index on addresses using gist (location);

-- عنوان فندق بلا اسم فندق عنوانٌ لا يُوصَل إليه. القيد يمسك ذلك عند الإدخال
-- لا عند وصول السائق.
alter table addresses add constraint hotel_fields_present check (
  kind <> 'hotel' or (hotel_name is not null and room_number is not null)
);

-- ─────────────────────────────────────────────────────────────────────────
-- حالات الطلب
-- ─────────────────────────────────────────────────────────────────────────
-- الترتيب هنا هو نفسه الخطّ الزمني الذي يراه العميل. وكونها enum لا نصًّا يعني
-- أن حالةً غير معرَّفة تفشل عند الكتابة، لا بعد أسبوع في تقرير.
create type order_status as enum (
  'draft',             -- سلّة لم تُرسل بعد
  'placed',            -- تم الطلب
  'accepted',          -- تم قبول الطلب
  'pickup_assigned',   -- أُسند لسائق استلام
  'pickup_en_route',   -- السائق في الطريق
  'picked_up',         -- تم الاستلام
  'at_laundry',        -- وصلت للمغسلة
  'sorting',           -- جاري الفرز
  'washing',           -- جاري الغسيل
  'drying',            -- جاري التجفيف
  'ironing',           -- جاري الكوي
  'packaging',         -- جاري التغليف
  'ready',             -- جاهز للتسليم
  'delivery_assigned', -- أُسند لسائق تسليم
  'out_for_delivery',  -- خرج للتوصيل
  'delivered',         -- تم التسليم
  'on_hold',           -- موقوف: بقعة تحتاج قرار العميل، تعذّر الوصول…
  'cancelled',
  'refunded'
);

create type payment_method as enum ('cash_on_pickup', 'cash_on_delivery', 'card', 'apple_pay', 'wallet');
create type payment_status as enum ('unpaid', 'authorized', 'paid', 'partially_refunded', 'refunded', 'failed');

-- ─────────────────────────────────────────────────────────────────────────
-- الطلبات
-- ─────────────────────────────────────────────────────────────────────────
create table orders (
  id              uuid primary key default uuid_generate_v4(),
  -- رقم بشريّ قصير يُقال في الهاتف ويُطبع على الكيس. UUID لا يُملى على عميل.
  order_number    bigint generated always as identity (start with 10000),

  laundry_id      uuid not null references laundries(id),
  branch_id       uuid not null references branches(id),
  customer_id     uuid not null references profiles(id),

  status          order_status not null default 'draft',
  payment_method  payment_method not null default 'cash_on_delivery',
  payment_status  payment_status not null default 'unpaid',

  -- العناوين والمواعيد
  pickup_address_id   uuid references addresses(id),
  delivery_address_id uuid references addresses(id),
  pickup_slot_start   timestamptz,
  pickup_slot_end     timestamptz,
  delivery_slot_start timestamptz,
  delivery_slot_end   timestamptz,
  promised_ready_at   timestamptz,   -- وعد الجاهزية المحسوب من turnaround

  is_express      boolean not null default false,
  customer_notes  text,

  -- المبالغ. تُجمَّد على الطلب لحظة إرساله: تغيير سعر خدمة غدًا يجب ألّا
  -- يغيّر فاتورة أُصدرت أمس. ولهذا نُخزّن ولا نحسب من الكتالوج عند العرض.
  subtotal        numeric(10,2) not null default 0 check (subtotal >= 0),
  delivery_fee    numeric(10,2) not null default 0 check (delivery_fee >= 0),
  discount_amount numeric(10,2) not null default 0 check (discount_amount >= 0),
  vat_amount      numeric(10,2) not null default 0 check (vat_amount >= 0),
  total           numeric(10,2) not null default 0 check (total >= 0),
  delivery_fee_reason text,          -- سبب الرسم كما أعادته quote_delivery_fee

  coupon_id       uuid,              -- مرجع يُضاف في مهاجرة الكوبونات
  loyalty_points_earned int not null default 0,
  loyalty_points_spent  int not null default 0,

  -- الأطراف المسندة
  pickup_driver_id   uuid references profiles(id),
  delivery_driver_id uuid references profiles(id),

  -- الباركود على مستوى الطلب: ملصق الكيس.
  barcode         text unique,

  cancelled_reason text,
  cancelled_by     uuid references profiles(id),

  placed_at       timestamptz,
  delivered_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index on orders (branch_id, status);
create index on orders (customer_id, created_at desc);
create index on orders (pickup_driver_id) where status in ('pickup_assigned','pickup_en_route');
create index on orders (delivery_driver_id) where status in ('delivery_assigned','out_for_delivery');
create index on orders (barcode);
create unique index on orders (order_number);

comment on column orders.subtotal is
  'مجمَّد لحظة الإرسال. تغيير سعر الكتالوج لا يمسّ فاتورة صدرت.';

-- ─────────────────────────────────────────────────────────────────────────
-- بنود الطلب
-- ─────────────────────────────────────────────────────────────────────────
-- السعر والاسم منسوخان لا مرجعان — للسبب نفسه: الفاتورة وثيقة، والوثيقة لا
-- تتغيّر بتغيّر ما تشير إليه. حذف خدمة من الكتالوج غدًا يجب ألّا يُفرغ فاتورة.
create table order_items (
  id            uuid primary key default uuid_generate_v4(),
  order_id      uuid not null references orders(id) on delete cascade,
  service_id    uuid references services(id) on delete set null,
  service_name_ar text not null,
  unit          pricing_unit not null,
  quantity      numeric(10,2) not null check (quantity > 0),
  unit_price    numeric(10,2) not null check (unit_price >= 0),
  line_total    numeric(10,2) not null check (line_total >= 0),
  notes         text,
  created_at    timestamptz not null default now()
);

create index on order_items (order_id);

-- ─────────────────────────────────────────────────────────────────────────
-- القطع — الجرد الفعليّ بعد الفرز
-- ─────────────────────────────────────────────────────────────────────────
-- ما يطلبه العميل تقديرٌ؛ وما يجده الفارز هو الحقيقة. الفصل بين الاثنين يجعل
-- الفرق مرئيًّا («طلب ٣ ثياب ووصل ٤») بدل أن يُطمس بتعديل البند.
-- ولكل قطعة باركودها — فتُعرف القطعة الضائعة باسمها لا بالطلب كلّه.
create table order_garments (
  id            uuid primary key default uuid_generate_v4(),
  order_id      uuid not null references orders(id) on delete cascade,
  order_item_id uuid references order_items(id) on delete set null,
  barcode       text not null unique,
  label_ar      text not null,                 -- «ثوب أبيض»، «شماغ»
  color         text,
  brand         text,
  -- ملاحظات الفحص: بقعة، تمزّق، لون يسيل. تُوثَّق قبل الغسيل لا بعده.
  defect_notes  text,
  photo_urls    text[] not null default '{}',
  current_stage order_status not null default 'sorting',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index on order_garments (order_id);
create index on order_garments (barcode);

comment on table order_garments is
  'القطعة الواحدة بباركودها. تجيب سؤال العميل «أين ثوبي؟» لا «أين طلبي؟».';

-- ─────────────────────────────────────────────────────────────────────────
-- سجلّ الأحداث
-- ─────────────────────────────────────────────────────────────────────────
-- كل انتقال حالة صفٌّ هنا: مَن، ومتى، ومن أين إلى أين. وهذا ما يجعل «متوسط زمن
-- الكوي» و«الطلبات المتأخّرة» استعلامًا لا تخمينًا — ويجعل الخلاف مع العميل
-- يُحسم بسجلّ لا بذاكرة.
create table order_events (
  id           uuid primary key default uuid_generate_v4(),
  order_id     uuid not null references orders(id) on delete cascade,
  from_status  order_status,
  to_status    order_status not null,
  actor_id     uuid references profiles(id),
  actor_role   app_role,
  note         text,
  -- موقع من نفّذ الحدث: إثبات أن السائق كان عند الباب حين ضغط «سلّمت».
  location     geography(point, 4326),
  created_at   timestamptz not null default now()
);

create index on order_events (order_id, created_at);
create index on order_events (to_status, created_at);

-- ─────────────────────────────────────────────────────────────────────────
-- إثبات الاستلام والتسليم
-- ─────────────────────────────────────────────────────────────────────────
create type proof_kind as enum ('pickup', 'delivery');

create table order_proofs (
  id           uuid primary key default uuid_generate_v4(),
  order_id     uuid not null references orders(id) on delete cascade,
  kind         proof_kind not null,
  driver_id    uuid references profiles(id),
  photo_urls   text[] not null default '{}',
  signature_url text,
  otp_verified boolean not null default false,
  location     geography(point, 4326),
  created_at   timestamptz not null default now(),
  unique (order_id, kind)
);

-- رمز تسليم لمرة واحدة. يُخزَّن مجزّأً لا نصًّا صريحًا: من يقرأ الجدول لا
-- يجوز أن يستطيع استلام طلب غيره.
create table order_delivery_codes (
  order_id     uuid primary key references orders(id) on delete cascade,
  code_hash    text not null,
  expires_at   timestamptz not null,
  consumed_at  timestamptz,
  attempts     smallint not null default 0
);

-- ─────────────────────────────────────────────────────────────────────────
-- آلة الحالات — الانتقالات المسموحة
-- ─────────────────────────────────────────────────────────────────────────
-- بلا هذا يستطيع أي عميلٍ مُعدَّل أن يقفز بطلبه من 'placed' إلى 'delivered'.
-- الجدول بيانات لا شيفرة، فتعديل مسار التشغيل مستقبلًا صفٌّ يُضاف.
create table order_transitions (
  from_status  order_status not null,
  to_status    order_status not null,
  allowed_roles app_role[] not null,
  primary key (from_status, to_status)
);

insert into order_transitions (from_status, to_status, allowed_roles) values
  ('draft','placed',                  '{customer}'),
  ('placed','accepted',               '{super_admin,branch_manager,customer_service}'),
  ('placed','cancelled',              '{customer,super_admin,branch_manager,customer_service}'),
  ('accepted','pickup_assigned',      '{super_admin,branch_manager,customer_service}'),
  ('accepted','cancelled',            '{customer,super_admin,branch_manager,customer_service}'),
  ('pickup_assigned','pickup_en_route','{driver,super_admin,branch_manager}'),
  ('pickup_assigned','cancelled',     '{super_admin,branch_manager,customer_service}'),
  ('pickup_en_route','picked_up',     '{driver,super_admin,branch_manager}'),
  ('picked_up','at_laundry',          '{driver,laundry_staff,super_admin,branch_manager}'),
  ('at_laundry','sorting',            '{laundry_staff,super_admin,branch_manager}'),
  ('sorting','washing',               '{laundry_staff,super_admin,branch_manager}'),
  ('sorting','on_hold',               '{laundry_staff,super_admin,branch_manager}'),
  ('washing','drying',                '{laundry_staff,super_admin,branch_manager}'),
  ('drying','ironing',                '{laundry_staff,super_admin,branch_manager}'),
  ('drying','packaging',              '{laundry_staff,super_admin,branch_manager}'),
  ('ironing','packaging',             '{laundry_staff,super_admin,branch_manager}'),
  ('packaging','ready',               '{laundry_staff,super_admin,branch_manager}'),
  ('ready','delivery_assigned',       '{super_admin,branch_manager,customer_service}'),
  ('delivery_assigned','out_for_delivery','{driver,super_admin,branch_manager}'),
  ('out_for_delivery','delivered',    '{driver,super_admin,branch_manager}'),
  ('out_for_delivery','on_hold',      '{driver,super_admin,branch_manager,customer_service}'),
  ('on_hold','sorting',               '{laundry_staff,super_admin,branch_manager}'),
  ('on_hold','out_for_delivery',      '{super_admin,branch_manager,customer_service}'),
  ('on_hold','cancelled',             '{super_admin,branch_manager,customer_service}'),
  ('delivered','refunded',            '{super_admin,accountant}'),
  ('cancelled','refunded',            '{super_admin,accountant}');

-- الحارس: يرفض الانتقال غير المسموح، ويكتب سجلّ الحدث في المعاملة نفسها.
-- كتابة السجلّ من التطبيق تعني أن أول استثناء يترك طلبًا انتقل بلا أثر.
create or replace function enforce_order_transition()
returns trigger
language plpgsql security definer set search_path = wasl, public, extensions
as $$
declare
  v_role app_role;
  v_allowed app_role[];
begin
  if new.status = old.status then
    return new;
  end if;

  -- السياق الخادميّ (مفتاح service_role أو محرّر SQL) يمرّ: الإصلاح اليدويّ
  -- لطلبٍ عَلِق يجب أن يبقى ممكنًا. ويُسجَّل بمنفّذٍ NULL — أي «النظام»، لا
  -- انتحالًا لشخص.
  if auth.uid() is null then
    insert into order_events (order_id, from_status, to_status, note)
    values (new.id, old.status, new.status, 'من السياق الخادميّ');
    if new.status = 'placed'    and new.placed_at    is null then new.placed_at    := now(); end if;
    if new.status = 'delivered' and new.delivered_at is null then new.delivered_at := now(); end if;
    return new;
  end if;

  select allowed_roles into v_allowed
  from order_transitions
  where from_status = old.status and to_status = new.status;

  if v_allowed is null then
    raise exception 'انتقال غير مسموح: % ← %', old.status, new.status
      using errcode = 'check_violation';
  end if;

  -- أعلى دور يملكه المنفّذ في هذا الفرع، أو super_admin.
  select ur.role into v_role
  from user_roles ur
  where ur.user_id = auth.uid()
    and (ur.role = 'super_admin' or ur.branch_id = new.branch_id or ur.role = 'customer')
    and ur.role = any(v_allowed)
  limit 1;

  if v_role is null then
    raise exception 'دورك لا يخوّل الانتقال % ← %', old.status, new.status
      using errcode = 'insufficient_privilege';
  end if;

  -- العميل لا ينقل إلا طلبه هو.
  if v_role = 'customer' and new.customer_id <> auth.uid() then
    raise exception 'لا تملك هذا الطلب' using errcode = 'insufficient_privilege';
  end if;

  insert into order_events (order_id, from_status, to_status, actor_id, actor_role)
  values (new.id, old.status, new.status, auth.uid(), v_role);

  if new.status = 'placed'    and new.placed_at    is null then new.placed_at    := now(); end if;
  if new.status = 'delivered' and new.delivered_at is null then new.delivered_at := now(); end if;

  return new;
end;
$$;

create trigger t_orders_transition
  before update of status on orders
  for each row execute function enforce_order_transition();

create trigger t_orders_touch before update on orders
  for each row execute function touch_updated_at();
create trigger t_order_garments_touch before update on order_garments
  for each row execute function touch_updated_at();
