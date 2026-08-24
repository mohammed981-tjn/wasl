-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | الكوبونات ونقاط الولاء
-- ═══════════════════════════════════════════════════════════════════════════
--
-- الخصم مالٌ يخرج، فقواعده تُحرَس كما تُحرَس الأسعار. وأخطر ما في الكوبونات
-- ليس حسابُ النسبة بل **الحدود**: كوبونٌ بلا سقف استخدام يُنشر في مجموعة
-- واتساب فيُستهلك آلاف المرّات في ساعة، وكوبونٌ بلا «مرّة لكل عميل» يُعاد
-- استعماله كل طلب. ولذلك جدول استخداماتٍ منفصل وقيدٌ فريد عليه — لا عدّاد.

set search_path = public, extensions;

create type coupon_kind as enum ('percentage', 'fixed', 'free_delivery');

-- ─────────────────────────────────────────────────────────────────────────
-- الكوبونات
-- ─────────────────────────────────────────────────────────────────────────
create table coupons (
  id             uuid primary key default uuid_generate_v4(),
  laundry_id     uuid not null references laundries(id) on delete cascade,
  code           text not null,
  kind           coupon_kind not null,

  -- النسبة (٪) أو المبلغ (ريال). free_delivery يتجاهلهما.
  value          numeric(10,2) not null default 0 check (value >= 0),

  -- سقف الخصم في كوبون النسبة: «٥٠٪ بحدّ أقصى ٣٠ ريال». بدونه يبتلع
  -- كوبونُ نصفٍ فاتورةَ سجّادٍ بألف ريال.
  max_discount   numeric(10,2) check (max_discount > 0),

  min_subtotal   numeric(10,2) not null default 0 check (min_subtotal >= 0),

  starts_at      timestamptz not null default now(),
  ends_at        timestamptz,

  -- الحدود. صفر = بلا حدّ.
  max_uses_total     int not null default 0 check (max_uses_total >= 0),
  max_uses_per_user  int not null default 1 check (max_uses_per_user >= 0),

  -- نطاق التطبيق: فرعٌ بعينه، أو خدماتٌ بعينها. NULL/فارغ = الكلّ.
  branch_id      uuid references branches(id) on delete cascade,
  service_ids    uuid[] not null default '{}',

  -- كوبون أوّل طلب: أكثر أنواع الحملات استعمالًا وأخطرها بلا حارس.
  first_order_only boolean not null default false,

  is_active      boolean not null default true,
  created_by     uuid references profiles(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- الرمز فريدٌ داخل المغسلة لا عالميًّا: مغسلتان قد تستعملان WELCOME10.
create unique index coupons_code_uniq on coupons (laundry_id, upper(code));
create index on coupons (laundry_id) where is_active;

comment on column coupons.max_discount is
  'سقف خصم النسبة. بدونه يبتلع كوبونُ نصفٍ فاتورةَ سجّادٍ بألف ريال.';

-- ─────────────────────────────────────────────────────────────────────────
-- الاستخدامات
-- ─────────────────────────────────────────────────────────────────────────
-- جدولٌ لا عدّاد. العدّاد يُقرأ ويُزاد في خطوتين، وبينهما يتّسع سباقٌ يستهلك
-- كوبونًا مرّتين. والصفّ بقيدٍ فريد يحسم السباق في القاعدة.
create table coupon_redemptions (
  id          uuid primary key default uuid_generate_v4(),
  coupon_id   uuid not null references coupons(id) on delete cascade,
  user_id     uuid not null references profiles(id) on delete cascade,
  order_id    uuid not null references orders(id) on delete cascade,
  amount      numeric(10,2) not null check (amount >= 0),
  redeemed_at timestamptz not null default now(),
  unique (coupon_id, order_id)
);

create index on coupon_redemptions (coupon_id);
create index on coupon_redemptions (user_id);

alter table orders
  add constraint orders_coupon_fk foreign key (coupon_id) references coupons(id) on delete set null;

-- ─────────────────────────────────────────────────────────────────────────
-- التحقّق من الكوبون
-- ─────────────────────────────────────────────────────────────────────────
-- تُعيد الخصم وسببَ الرفض. والسبب مهمّ: «الكوبون غير صالح» تجعل العميل يعيد
-- الكتابة ظنًّا أنه أخطأ، و«انتهت صلاحيته» تُنهي المحاولة.
create or replace function quote_coupon(
  p_code      text,
  p_laundry   uuid,
  p_branch    uuid,
  p_user      uuid,
  p_subtotal  numeric,
  p_delivery_fee numeric default 0
)
returns table (
  coupon_id   uuid,
  discount    numeric,
  valid       boolean,
  reason      text
)
language plpgsql stable
as $$
declare
  c coupons%rowtype;
  v_uses_total int;
  v_uses_user  int;
  v_discount   numeric := 0;
begin
  select * into c from coupons
  where laundry_id = p_laundry and upper(code) = upper(trim(p_code));

  if not found then
    return query select null::uuid, 0::numeric, false, 'الرمز غير موجود'::text; return;
  end if;
  if not c.is_active then
    return query select c.id, 0::numeric, false, 'الكوبون موقوف'::text; return;
  end if;
  if now() < c.starts_at then
    return query select c.id, 0::numeric, false, 'الكوبون لم يبدأ بعد'::text; return;
  end if;
  if c.ends_at is not null and now() > c.ends_at then
    return query select c.id, 0::numeric, false, 'انتهت صلاحية الكوبون'::text; return;
  end if;
  if c.branch_id is not null and c.branch_id <> p_branch then
    return query select c.id, 0::numeric, false, 'الكوبون لا يشمل هذا الفرع'::text; return;
  end if;
  if p_subtotal < c.min_subtotal then
    return query select c.id, 0::numeric, false,
      format('الكوبون يبدأ من %s ريال', c.min_subtotal)::text; return;
  end if;

  if c.max_uses_total > 0 then
    select count(*) into v_uses_total from coupon_redemptions where coupon_redemptions.coupon_id = c.id;
    if v_uses_total >= c.max_uses_total then
      return query select c.id, 0::numeric, false, 'استُهلك الكوبون بالكامل'::text; return;
    end if;
  end if;

  if c.max_uses_per_user > 0 then
    select count(*) into v_uses_user
    from coupon_redemptions r where r.coupon_id = c.id and r.user_id = p_user;
    if v_uses_user >= c.max_uses_per_user then
      return query select c.id, 0::numeric, false, 'استعملت هذا الكوبون من قبل'::text; return;
    end if;
  end if;

  if c.first_order_only and exists (
    select 1 from orders o
    where o.customer_id = p_user and o.status not in ('draft','cancelled')
  ) then
    return query select c.id, 0::numeric, false, 'الكوبون لأول طلب فقط'::text; return;
  end if;

  v_discount := case c.kind
    when 'percentage'    then round(p_subtotal * c.value / 100.0, 2)
    when 'fixed'         then c.value
    when 'free_delivery' then p_delivery_fee
  end;

  if c.max_discount is not null then
    v_discount := least(v_discount, c.max_discount);
  end if;

  -- الخصم لا يتجاوز ما يُخصم منه: كوبون ٥٠ ريال على طلب ٣٠ يخصم ٣٠ لا ٥٠،
  -- وإلا صار الإجمالي سالبًا — أي أن المغسلة تدفع للعميل.
  v_discount := least(v_discount,
    case when c.kind = 'free_delivery' then p_delivery_fee else p_subtotal end);

  return query select c.id, v_discount, true,
    case c.kind
      when 'percentage'    then format('خصم %s%%', c.value)
      when 'fixed'         then format('خصم %s ريال', c.value)
      when 'free_delivery' then 'توصيل مجاني'
    end::text;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- نقاط الولاء
-- ─────────────────────────────────────────────────────────────────────────
-- القواعد إعدادٌ لكل مغسلة لا ثابتٌ في الشيفرة: «ريالٌ = نقطة» و«مئة نقطة =
-- عشرة ريالات» قراران تجاريّان يتغيّران بحملة.
create table loyalty_settings (
  laundry_id        uuid primary key references laundries(id) on delete cascade,
  is_enabled        boolean not null default true,
  points_per_riyal  numeric(6,2) not null default 1 check (points_per_riyal >= 0),
  riyal_per_point   numeric(6,4) not null default 0.10 check (riyal_per_point >= 0),
  min_points_to_redeem int not null default 100 check (min_points_to_redeem >= 0),
  -- أقصى نسبةٍ من الفاتورة تُدفع بالنقاط. بلا سقفٍ يُدفع طلبٌ كاملٌ بنقاطٍ
  -- كُسبت من طلباتٍ مخفَّضة — دورةٌ تأكل نفسها.
  max_redeem_percent numeric(5,2) not null default 50
    check (max_redeem_percent between 0 and 100),
  points_expire_days int not null default 0 check (points_expire_days >= 0),
  updated_at        timestamptz not null default now()
);

create type loyalty_txn_kind as enum ('earn', 'redeem', 'expire', 'adjust');

-- الرصيد مشتقٌّ من الحركات لا حقلٌ يُكتب. حقلٌ يُكتب من عدّة أمكنة ينحرف،
-- والانحراف في نقاطٍ تُصرف مالًا خلافٌ مع العميل لا يُحسم.
create table loyalty_transactions (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references profiles(id) on delete cascade,
  laundry_id  uuid not null references laundries(id) on delete cascade,
  order_id    uuid references orders(id) on delete set null,
  kind        loyalty_txn_kind not null,
  points      int not null,          -- موجبٌ للكسب، سالبٌ للصرف
  note        text,
  expires_at  timestamptz,
  created_at  timestamptz not null default now(),
  check (
    (kind = 'earn'   and points > 0) or
    (kind = 'redeem' and points < 0) or
    (kind = 'expire' and points < 0) or
    (kind = 'adjust')
  )
);

create index on loyalty_transactions (user_id, laundry_id);
create index on loyalty_transactions (order_id);

create or replace function loyalty_balance(p_user uuid, p_laundry uuid)
returns int
language sql stable
as $$
  select coalesce(sum(points), 0)::int
  from loyalty_transactions
  where user_id = p_user and laundry_id = p_laundry
    and (expires_at is null or expires_at > now());
$$;

-- كم ريالًا يستطيع هذا العميل أن يدفع بنقاطه في هذه الفاتورة؟
create or replace function quote_loyalty_redemption(
  p_user uuid, p_laundry uuid, p_subtotal numeric
)
returns table (points_to_spend int, riyal_value numeric, reason text)
language plpgsql stable
as $$
declare
  s loyalty_settings%rowtype;
  v_balance int;
  v_cap_riyal numeric;
  v_riyal numeric;
  v_points int;
begin
  select * into s from loyalty_settings where laundry_id = p_laundry;
  if not found or not s.is_enabled then
    return query select 0, 0::numeric, 'نظام النقاط غير مفعّل'::text; return;
  end if;

  v_balance := loyalty_balance(p_user, p_laundry);
  if v_balance < s.min_points_to_redeem then
    return query select 0, 0::numeric,
      format('تحتاج %s نقطة على الأقل، ولديك %s', s.min_points_to_redeem, v_balance)::text;
    return;
  end if;

  v_cap_riyal := round(p_subtotal * s.max_redeem_percent / 100.0, 2);
  v_riyal := least(round(v_balance * s.riyal_per_point, 2), v_cap_riyal);
  v_points := case when s.riyal_per_point = 0 then 0
                   else ceil(v_riyal / s.riyal_per_point)::int end;
  v_points := least(v_points, v_balance);

  return query select v_points, v_riyal,
    format('%s نقطة = %s ريال', v_points, v_riyal)::text;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الكسب عند التسليم — لا عند الطلب
-- ─────────────────────────────────────────────────────────────────────────
-- نقاطٌ تُمنح عند الطلب تُمنح على طلبٍ يُلغى. والكسب على المبلغ بعد الخصم:
-- كسبُ نقاطٍ على خصمٍ لم يُدفع يصنع دورةً تُموّل نفسها.
create or replace function award_loyalty_on_delivery()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  s loyalty_settings%rowtype;
  v_points int;
begin
  if new.status <> 'delivered' or old.status = 'delivered' then
    return new;
  end if;

  select * into s from loyalty_settings where laundry_id = new.laundry_id;
  if not found or not s.is_enabled or s.points_per_riyal = 0 then
    return new;
  end if;

  v_points := floor(greatest(new.subtotal - new.discount_amount, 0) * s.points_per_riyal)::int;
  if v_points <= 0 then
    return new;
  end if;

  insert into loyalty_transactions (user_id, laundry_id, order_id, kind, points, note, expires_at)
  values (new.customer_id, new.laundry_id, new.id, 'earn', v_points,
          format('طلب #%s', new.order_number),
          case when s.points_expire_days > 0
               then now() + make_interval(days => s.points_expire_days) end);

  new.loyalty_points_earned := v_points;
  return new;
end;
$$;

create trigger t_orders_award_loyalty
  before update of status on orders
  for each row execute function award_loyalty_on_delivery();

create trigger t_coupons_touch before update on coupons
  for each row execute function touch_updated_at();
create trigger t_loyalty_settings_touch before update on loyalty_settings
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحيات
-- ─────────────────────────────────────────────────────────────────────────
grant select, insert, update, delete
  on coupons, coupon_redemptions, loyalty_settings, loyalty_transactions to authenticated;
grant select on coupons, loyalty_settings to anon;

do $$
declare t text;
begin
  foreach t in array array['coupons','coupon_redemptions','loyalty_settings','loyalty_transactions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- الكوبون يُقرأ ليُعرض في الحملات؛ ويُكتب من مدير الفرع فأعلى.
create policy coupons_read on coupons for select using (true);
create policy coupons_write on coupons
  for all using (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = coupons.laundry_id))
  with check (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = coupons.laundry_id));

-- الاستخدام يراه صاحبه والإدارة. ولا يُحذف: حذفُ صفٍّ يعيد كوبونًا استُهلك.
create policy redemptions_read on coupon_redemptions
  for select using (user_id = auth.uid() or auth_is_super_admin()
                    or auth_has_role('customer_service') or auth_has_role('accountant'));
create policy redemptions_insert on coupon_redemptions
  for insert with check (user_id = auth.uid() or auth_is_super_admin());

create policy loyalty_settings_read on loyalty_settings for select using (true);
create policy loyalty_settings_write on loyalty_settings
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

-- الحركات تُقرأ من صاحبها، **ولا تُكتب منه إطلاقًا**: من يكتب نقاطه يكتب مالًا.
create policy loyalty_txn_read on loyalty_transactions
  for select using (user_id = auth.uid() or auth_is_super_admin()
                    or auth_has_role('accountant') or auth_has_role('customer_service'));
create policy loyalty_txn_write on loyalty_transactions
  for insert with check (auth_is_super_admin() or auth_has_role('accountant'));
