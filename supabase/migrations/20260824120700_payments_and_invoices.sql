-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | المدفوعات والفواتير والاسترداد
-- ═══════════════════════════════════════════════════════════════════════════
--
-- طلبتَ «معمارية دفع لا زرّ دفع». والفرق العمليّ بينهما ثلاثة أشياء:
--
--   ١) **طبقة تجريد للمزوّد**: البوّابة صفٌّ في جدول لا شرطٌ في الشيفرة. تبديل
--      «ميسر» بغيرها غدًا تغييرُ صفّ، لا مطاردةُ اسمها في مئة ملفّ.
--   ٢) **المحاولة كيانٌ لا نتيجة**: الدفعة تُنشأ `pending`، ثم تنجح أو تفشل.
--      من يسجّل الناجحة وحدها لا يعرف كم عميلًا حاول ولم يستطع — وهو أهمّ
--      رقمٍ في قمع الشراء.
--   ٣) **الاسترداد حركةٌ مستقلّة**: لا حقلٌ في الدفعة. جزئيًّا مرّتين ممكنٌ،
--      ومجموعُه لا يتجاوز الأصل — قيدٌ لا مراجعة.

create schema if not exists wasl;
set search_path = wasl, public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- مزوّدو الدفع
-- ─────────────────────────────────────────────────────────────────────────
create table payment_providers (
  id           uuid primary key default uuid_generate_v4(),
  laundry_id   uuid not null references laundries(id) on delete cascade,
  code         text not null,                -- 'moyasar' · 'tap' · 'cash'
  display_name_ar text not null,
  -- الوسائل التي تُعرض للعميل عبر هذا المزوّد.
  methods      payment_method[] not null default '{}',
  is_active    boolean not null default true,
  is_default   boolean not null default false,
  -- **لا مفتاح سرّيّ هنا.** المفتاح المنشور غير سرّيّ ويُمرَّر للتطبيق؛ ومفتاح
  -- السرّ يسكن أسرار دوالّ Edge ولا يلمس قاعدةً ولا حزمةً إطلاقًا.
  publishable_key text,
  config       jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (laundry_id, code)
);

comment on column payment_providers.publishable_key is
  'المفتاح المنشور فقط. مفتاح السرّ في أسرار دوالّ Edge — لا في قاعدة ولا في حزمة.';

-- مزوّدٌ افتراضيّ واحد لكل مغسلة: اثنان يجعلان «أيّهما يُستعمل؟» سؤالًا بلا جواب.
create unique index payment_providers_one_default
  on payment_providers (laundry_id) where is_default;

-- ─────────────────────────────────────────────────────────────────────────
-- الدفعات
-- ─────────────────────────────────────────────────────────────────────────
create type payment_txn_status as enum (
  'pending',      -- أُنشئت وتنتظر العميل
  'authorized',   -- حُجز المبلغ ولم يُقبض (الدفع عند التسليم بالبطاقة)
  'captured',     -- قُبض
  'failed',
  'cancelled'
);

create table payments (
  id             uuid primary key default uuid_generate_v4(),
  order_id       uuid not null references orders(id) on delete cascade,
  provider_id    uuid references payment_providers(id) on delete set null,
  method         payment_method not null,
  status         payment_txn_status not null default 'pending',
  amount         numeric(10,2) not null check (amount > 0),
  currency       char(3) not null default 'SAR',

  -- معرّف العملية عند المزوّد. فريدٌ كي لا يُسجَّل webhook مرّتين: البوّابات
  -- تعيد الإرسال عند غياب الإقرار، والتسجيل المكرّر يضاعف الإيراد في التقارير.
  provider_ref   text,

  failure_code   text,
  failure_message text,
  -- آخر أربعة أرقام ونوع البطاقة فقط. لا رقم بطاقة ولا CVV يُخزَّن أبدًا،
  -- ولا في عمود مشفَّر: ما لا يُخزَّن لا يُسرَّب.
  card_brand     text,
  card_last4     char(4),

  raw_response   jsonb,
  authorized_at  timestamptz,
  captured_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create unique index payments_provider_ref_uniq on payments (provider_ref)
  where provider_ref is not null;
create index on payments (order_id);
create index on payments (status, created_at);

comment on index payments_provider_ref_uniq is
  'يمنع تسجيل webhook مرّتين — البوّابات تعيد الإرسال، والتكرار يضاعف الإيراد.';

-- ─────────────────────────────────────────────────────────────────────────
-- الاسترداد
-- ─────────────────────────────────────────────────────────────────────────
create type refund_status as enum ('pending', 'completed', 'failed');

create table refunds (
  id           uuid primary key default uuid_generate_v4(),
  payment_id   uuid not null references payments(id) on delete cascade,
  order_id     uuid not null references orders(id) on delete cascade,
  amount       numeric(10,2) not null check (amount > 0),
  reason       text not null,
  status       refund_status not null default 'pending',
  provider_ref text,
  requested_by uuid references profiles(id),
  approved_by  uuid references profiles(id),
  created_at   timestamptz not null default now(),
  completed_at timestamptz
);

create unique index refunds_provider_ref_uniq on refunds (provider_ref)
  where provider_ref is not null;
create index on refunds (payment_id);

-- مجموع المستردّ لا يتجاوز المقبوض. قيدٌ في القاعدة لا مراجعةٌ بشرية: خطأٌ
-- هنا يخرج مالًا لا يعود.
create or replace function enforce_refund_ceiling()
returns trigger
language plpgsql security definer set search_path = wasl, public, extensions
as $$
declare
  v_paid     numeric;
  v_refunded numeric;
begin
  select amount into v_paid from payments
  where id = new.payment_id and status = 'captured';

  if v_paid is null then
    raise exception 'لا استرداد من دفعةٍ لم تُقبض' using errcode = 'check_violation';
  end if;

  select coalesce(sum(amount), 0) into v_refunded
  from refunds
  where payment_id = new.payment_id
    and status <> 'failed'
    and id is distinct from new.id;

  if v_refunded + new.amount > v_paid then
    raise exception 'الاسترداد (% + %) يتجاوز المقبوض (%)',
      v_refunded, new.amount, v_paid using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger t_refunds_ceiling
  before insert or update on refunds
  for each row execute function enforce_refund_ceiling();

-- ─────────────────────────────────────────────────────────────────────────
-- حالة الدفع على الطلب — مشتقّة لا مكتوبة
-- ─────────────────────────────────────────────────────────────────────────
-- `orders.payment_status` حقلٌ يقرأه التطبيق كثيرًا، فيبقى — لكن لا تكتبه يد.
-- يُشتقّ من الدفعات والاستردادات عند كل تغيّر، فلا ينحرف عن الحقيقة.
create or replace function sync_order_payment_status()
returns trigger
language plpgsql security definer set search_path = wasl, public, extensions
as $$
declare
  v_order     uuid;
  v_total     numeric;
  v_captured  numeric;
  v_refunded  numeric;
  v_authorized numeric;
  v_status    payment_status;
begin
  v_order := coalesce(new.order_id, old.order_id);

  select total into v_total from orders where id = v_order;

  select coalesce(sum(amount) filter (where status = 'captured'), 0),
         coalesce(sum(amount) filter (where status = 'authorized'), 0)
    into v_captured, v_authorized
  from payments where order_id = v_order;

  select coalesce(sum(amount), 0) into v_refunded
  from refunds where order_id = v_order and status = 'completed';

  v_status := case
    when v_captured = 0 and v_authorized > 0 then 'authorized'
    when v_captured = 0                       then 'unpaid'
    when v_refunded >= v_captured             then 'refunded'
    when v_refunded > 0                       then 'partially_refunded'
    when v_captured >= coalesce(v_total, 0)   then 'paid'
    else 'unpaid'   -- قُبض بعضٌ ولم يكتمل: ليس مدفوعًا
  end;

  update orders set payment_status = v_status where id = v_order;
  return null;
end;
$$;

create trigger t_payments_sync_status
  after insert or update or delete on payments
  for each row execute function sync_order_payment_status();

create trigger t_refunds_sync_status
  after insert or update or delete on refunds
  for each row execute function sync_order_payment_status();

-- ─────────────────────────────────────────────────────────────────────────
-- الفواتير وضريبة القيمة المضافة
-- ─────────────────────────────────────────────────────────────────────────
-- النسبة إعدادٌ لا ثابت: تغيّرت في السعودية من ٥٪ إلى ١٥٪، ومن يكتبها في
-- الشيفرة يُعيد الإصدار يوم تتغيّر.
create table tax_settings (
  laundry_id     uuid primary key references laundries(id) on delete cascade,
  vat_percent    numeric(5,2) not null default 15 check (vat_percent between 0 and 100),
  -- هل الأسعار المعروضة شاملةٌ للضريبة؟ خطأٌ هنا يغيّر كل فاتورة.
  prices_include_vat boolean not null default true,
  updated_at     timestamptz not null default now()
);

create table invoices (
  id             uuid primary key default uuid_generate_v4(),
  order_id       uuid not null unique references orders(id) on delete cascade,
  invoice_number bigint generated always as identity (start with 1000),
  -- كل المبالغ منسوخةٌ لا محسوبة: الفاتورة وثيقةٌ لا تتغيّر بتغيّر مصادرها.
  subtotal       numeric(10,2) not null,
  delivery_fee   numeric(10,2) not null,
  discount_amount numeric(10,2) not null,
  vat_percent    numeric(5,2) not null,
  vat_amount     numeric(10,2) not null,
  total          numeric(10,2) not null,
  -- بيانات البائع لحظة الإصدار: تغيّر الرقم الضريبي غدًا لا يمسّ فاتورة أمس.
  seller_name    text not null,
  seller_vat     text,
  issued_at      timestamptz not null default now(),
  pdf_url        text
);

create unique index on invoices (invoice_number);

-- حساب الضريبة من الإجمالي أو فوقه بحسب الإعداد.
create or replace function compute_vat(p_laundry uuid, p_taxable numeric)
returns table (vat_amount numeric, vat_percent numeric, total numeric)
language plpgsql stable
as $$
declare t tax_settings%rowtype;
begin
  select * into t from tax_settings where laundry_id = p_laundry;
  if not found then
    t.vat_percent := 15;
    t.prices_include_vat := true;
  end if;

  if t.prices_include_vat then
    -- السعر شاملٌ: الضريبة مستخرجةٌ منه، والإجمالي هو هو.
    return query select
      round(p_taxable * t.vat_percent / (100 + t.vat_percent), 2),
      t.vat_percent,
      round(p_taxable, 2);
  else
    return query select
      round(p_taxable * t.vat_percent / 100, 2),
      t.vat_percent,
      round(p_taxable * (100 + t.vat_percent) / 100, 2);
  end if;
end;
$$;

comment on function compute_vat is
  'شاملة أم مضافة — الفرق ليس تفصيلًا: على ١١٥ ريالًا يعطي الأوّل ١٥ والثاني ١٧.٢٥.';

create trigger t_payment_providers_touch before update on payment_providers
  for each row execute function touch_updated_at();
create trigger t_payments_touch before update on payments
  for each row execute function touch_updated_at();
create trigger t_tax_settings_touch before update on tax_settings
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحيات
-- ─────────────────────────────────────────────────────────────────────────
grant select, insert, update, delete
  on payment_providers, payments, refunds, tax_settings, invoices to authenticated;
grant select on payment_providers, tax_settings to anon;
grant usage, select on all sequences in schema wasl to authenticated;

do $$
declare t text;
begin
  foreach t in array array['payment_providers','payments','refunds','tax_settings','invoices'] loop
    execute format('alter table wasl.%I enable row level security', t);
    execute format('alter table wasl.%I force row level security', t);
  end loop;
end $$;

create policy payment_providers_read on payment_providers
  for select using (is_active or auth_is_super_admin());
create policy payment_providers_write on payment_providers
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

-- الدفعة يراها صاحب الطلب والإدارة. **ولا يكتبها العميل**: من يكتب دفعةً
-- `captured` يدفع طلبه بجملة SQL.
create policy payments_read on payments for select using (can_see_order(order_id));
create policy payments_write on payments
  for all using (auth_is_super_admin() or auth_has_role('accountant'))
  with check (auth_is_super_admin() or auth_has_role('accountant'));

-- والاسترداد قرارٌ ماليّ: المحاسب والمالك وحدهما.
create policy refunds_read on refunds for select using (can_see_order(order_id));
create policy refunds_write on refunds
  for all using (auth_is_super_admin() or auth_has_role('accountant'))
  with check (auth_is_super_admin() or auth_has_role('accountant'));

create policy tax_settings_read on tax_settings for select using (true);
create policy tax_settings_write on tax_settings
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

create policy invoices_read on invoices for select using (can_see_order(order_id));
create policy invoices_write on invoices
  for all using (auth_is_super_admin() or auth_has_role('accountant'))
  with check (auth_is_super_admin() or auth_has_role('accountant'));
