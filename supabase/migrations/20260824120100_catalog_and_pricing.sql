-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | كتالوج الخدمات ومحرّك التسعير
-- ═══════════════════════════════════════════════════════════════════════════
--
-- الشرط الذي يحكم هذا الملف كلّه: **لا سعر واحد في شيفرة التطبيق.**
-- «ثوب غسيل = ٨ ريال» صفٌّ في جدول تعدّله الإدارة، لا ثابتٌ يحتاج إصدارًا
-- جديدًا على المتجر. وكل ما يمكن أن تريد الإدارة تغييره — السعر، المدّة،
-- الحدّ الأدنى، وحدة القياس، توفّر الخدمة في منطقة — عمودٌ هنا لا شرطٌ هناك.

-- وحدة القياس: القطعة أم الوزن أم السلّة. تحدّد شكل شاشة الطلب نفسها:
-- «كم قطعة؟» أو «كم كيلو؟» أو «سلّة واحدة».
-- المشروع مخصَّص لوصل وحده، فالجداول تسكن `public` — وهو ما تفترضه أدوات
-- Supabase كلّها: توليد الأنواع، وPostgREST، وعميل Flutter الذي يكتب
-- `from('orders')` بلا وسيط. والامتدادات وحدها تُنحّى إلى `extensions`.
set search_path = public, extensions;

create type pricing_unit as enum ('piece', 'kilogram', 'basket');

-- ─────────────────────────────────────────────────────────────────────────
-- أقسام الخدمات
-- ─────────────────────────────────────────────────────────────────────────
create table service_categories (
  id           uuid primary key default uuid_generate_v4(),
  laundry_id   uuid not null references laundries(id) on delete cascade,
  name_ar      text not null,
  name_en      text,
  icon         text,                        -- اسم أيقونة، لا مسار صورة
  sort_order   int  not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index on service_categories (laundry_id, sort_order);

-- ─────────────────────────────────────────────────────────────────────────
-- الخدمات
-- ─────────────────────────────────────────────────────────────────────────
-- غسيل · غسيل وكوي · كوي فقط · تنظيف جاف · بطانيات · مفارش · سجاد · أحذية…
-- الخدمة تُعرَّف على مستوى المغسلة، ويُسعّر الفرع منها ما يقدّمه (انظر
-- branch_services) — لأن فرع قد لا يملك آلة تنظيف جاف.
create table services (
  id             uuid primary key default uuid_generate_v4(),
  laundry_id     uuid not null references laundries(id) on delete cascade,
  category_id    uuid references service_categories(id) on delete set null,
  name_ar        text not null,
  name_en        text,
  description_ar text,
  image_url      text,

  -- التسعير
  unit           pricing_unit not null default 'piece',
  base_price     numeric(10,2) not null check (base_price >= 0),

  -- المدّة المتوقّعة للتنفيذ داخل المغسلة، بالساعات. يغذّي وعد التسليم
  -- للعميل ومحرّك المواعيد — لا يُعرض رقمًا فحسب.
  turnaround_hours int not null default 24 check (turnaround_hours > 0),

  -- الحدّ الأدنى للكمّية في هذه الخدمة (٣ قطع، ٥ كجم…). صفر = بلا حدّ.
  min_quantity   numeric(10,2) not null default 0 check (min_quantity >= 0),

  -- خدمة عاجلة: مضاعِف يُطبَّق على السعر حين يختار العميل الاستعجال.
  -- 1.0 يعني «لا استعجال في هذه الخدمة».
  express_multiplier numeric(4,2) not null default 1.0 check (express_multiplier >= 1.0),
  express_turnaround_hours int check (express_turnaround_hours > 0),

  is_active      boolean not null default true,
  sort_order     int not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index on services (laundry_id) where is_active;
create index on services (category_id);

comment on column services.unit is
  'يحدّد شكل الإدخال في تطبيق العميل: عدد قطع، أو وزن بالكيلو، أو سلّة.';
comment on column services.express_multiplier is
  'مضاعِف الاستعجال. 1.0 = الخدمة لا تقبل الاستعجال.';

-- ─────────────────────────────────────────────────────────────────────────
-- تسعير الفرع: التجاوز الاختياري
-- ─────────────────────────────────────────────────────────────────────────
-- الفرع يرث سعر المغسلة ما لم يُدرَج هنا. وهذا يحلّ حالتين بجدول واحد:
-- «هذا الفرع لا يقدّم الخدمة» (is_offered = false) و«يقدّمها بسعر مختلف».
create table branch_services (
  id            uuid primary key default uuid_generate_v4(),
  branch_id     uuid not null references branches(id) on delete cascade,
  service_id    uuid not null references services(id) on delete cascade,
  is_offered    boolean not null default true,
  price_override numeric(10,2) check (price_override >= 0),
  turnaround_hours_override int check (turnaround_hours_override > 0),
  updated_at    timestamptz not null default now(),
  unique (branch_id, service_id)
);

create index on branch_services (branch_id) where is_offered;

-- السعر النافذ: تجاوز الفرع إن وُجد، وإلا سعر المغسلة.
-- دالّةٌ واحدة يستدعيها التطبيق والتقارير ومحرّك الطلب — كي لا يُعاد حساب
-- القاعدة نفسها في ثلاثة أمكنة فتفترق ثلاث نتائج.
create or replace function effective_service_price(p_branch uuid, p_service uuid)
returns numeric
language sql stable
as $$
  select coalesce(bs.price_override, s.base_price)
  from services s
  left join branch_services bs
    on bs.service_id = s.id and bs.branch_id = p_branch
  where s.id = p_service
    and s.is_active
    and coalesce(bs.is_offered, true);
$$;

create or replace function effective_turnaround_hours(p_branch uuid, p_service uuid)
returns int
language sql stable
as $$
  select coalesce(bs.turnaround_hours_override, s.turnaround_hours)
  from services s
  left join branch_services bs
    on bs.service_id = s.id and bs.branch_id = p_branch
  where s.id = p_service;
$$;

create trigger t_service_categories_touch before update on service_categories
  for each row execute function touch_updated_at();
create trigger t_services_touch before update on services
  for each row execute function touch_updated_at();
create trigger t_branch_services_touch before update on branch_services
  for each row execute function touch_updated_at();
