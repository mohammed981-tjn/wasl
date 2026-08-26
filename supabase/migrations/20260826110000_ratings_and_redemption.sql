-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | التقييم بعد التسليم، وصرفُ نقاط الولاء
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **التقييم**: رقمٌ بين واحدٍ وخمسة سهلُ الجمع، وقيمتُه ليست في متوسّطه بل في
-- **متى يُقبل ومن أيّ طلب**. فتقييمٌ يُكتب على طلبٍ لم يُسلَّم لا يقول شيئًا،
-- وتقييمٌ يُبدَّل بعد شهرين ليس شهادةً بل مزاجًا متأخّرًا.
--
-- ولذلك ثلاثة قيود في القاعدة لا في الشاشة:
--   ١) لا يُقيَّم إلا طلبٌ **سُلّم**.
--   ٢) ولا يقيّمه إلا **صاحبُه**.
--   ٣) وفي **نافذةٍ زمنيّةٍ تحدّدها الإدارة** — بعدها يُقفل ويبقى شهادة.
--
-- **وصرفُ النقاط**: المحرّك مبنيٌّ من قبل (`quote_loyalty_redemption`)، وما
-- ينقص هو الصرف نفسه. وهو حركةُ مالٍ فعليّة: نقطةٌ تُصرف تُنقص فاتورة. فلا
-- تُقبل قيمتُها من التطبيق أبدًا — تُعاد قراءتها من القاعدة لحظة الصرف.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- إعدادات التقييم
-- ─────────────────────────────────────────────────────────────────────────
create table feedback_settings (
  laundry_id  uuid primary key references laundries(id) on delete cascade,
  is_enabled  boolean not null default true,

  -- كم يومًا يبقى الطلب قابلًا للتقييم بعد تسليمه؟
  window_days int not null default 14 check (window_days between 1 and 365),

  -- ما دون هذا يُعدّ شكوى تُراجَع لا رأيًا يُجمَع في متوسّط.
  low_star_at smallint not null default 3 check (low_star_at between 1 and 5),

  updated_at  timestamptz not null default now()
);

comment on column feedback_settings.low_star_at is
  'حدُّ الشكوى. المتوسّط وحده يُخفي عشرَ نجماتٍ واحدة تحت مئةِ خمسات.';

create trigger t_feedback_settings_updated
  before update on feedback_settings
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- التقييم
-- ─────────────────────────────────────────────────────────────────────────
-- تقييمٌ واحدٌ لكل طلب (مفتاحٌ أساسيّ على `order_id`) — لا سجلُّ محاولات.
create table order_ratings (
  order_id    uuid primary key references orders(id) on delete cascade,
  customer_id uuid not null references profiles(id) on delete cascade,
  branch_id   uuid not null references branches(id) on delete cascade,

  stars       smallint not null check (stars between 1 and 5),

  -- تقييمُ التوصيل منفصل: مغسلةٌ تغسل جيّدًا وسائقٌ يتأخّر مشكلتان مختلفتان،
  -- وجمعُهما في رقمٍ واحد يُخفي أيَّهما يجب إصلاحه.
  delivery_stars smallint check (delivery_stars between 1 and 5),

  -- من سلّم؟ **يُجمَّد لحظة التقييم**: تغييرُ إسناد الطلب لاحقًا يجب ألّا
  -- ينقل شكوى عميلٍ من سائقٍ إلى آخر.
  driver_id   uuid references profiles(id),

  -- أسبابٌ جاهزة («تأخّر»، «بقعة لم تُزل») — تُجمَع وتُعدّ، والنصّ الحرّ يُقرأ.
  tags        text[] not null default '{}',
  comment     text,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index on order_ratings (branch_id, created_at desc);
-- «ماذا قال هذا العميل عن طلباته؟» سؤالُ خدمةِ العملاء حين يتّصل.
create index on order_ratings (customer_id);
create index on order_ratings (driver_id) where driver_id is not null;
create index on order_ratings (stars);

create trigger t_order_ratings_updated
  before update on order_ratings
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- حارس التقييم
-- ─────────────────────────────────────────────────────────────────────────
create or replace function guard_order_rating()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  o orders%rowtype;
  s feedback_settings%rowtype;
  v_window int;
  v_since timestamptz;
begin
  select * into o from orders where id = new.order_id;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'check_violation';
  end if;

  -- الفرعُ والعميلُ والسائق تُملأ من الطلب لا ممّن يكتب: عميلٌ يرسل فرعًا
  -- غير فرعه يُفسد متوسّط فرعٍ لم يخدمه.
  new.customer_id := o.customer_id;
  new.branch_id   := o.branch_id;
  if tg_op = 'INSERT' then
    new.driver_id := o.delivery_driver_id;
  end if;

  if auth_is_service_context() then
    return new;
  end if;

  if o.customer_id <> auth.uid() then
    raise exception 'لا تقيّم طلبًا ليس لك' using errcode = 'insufficient_privilege';
  end if;

  if o.status <> 'delivered' then
    raise exception 'لا يُقيَّم إلا طلبٌ سُلّم' using errcode = 'check_violation';
  end if;

  select * into s from feedback_settings where laundry_id = o.laundry_id;
  if found and not s.is_enabled then
    raise exception 'التقييم غير مفعّل' using errcode = 'check_violation';
  end if;
  v_window := coalesce(s.window_days, 14);

  -- النافذة تُقاس من التسليم لا من الإنشاء: طلبٌ سُلّم أمس يُقيَّم اليوم ولو
  -- كان قد وُضع قبل شهر.
  v_since := coalesce(o.delivered_at, o.updated_at);
  if v_since + make_interval(days => v_window) < now() then
    raise exception 'انتهت مهلة التقييم (% يومًا)', v_window
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger t_order_ratings_guard
  before insert or update on order_ratings
  for each row execute function guard_order_rating();

-- ─────────────────────────────────────────────────────────────────────────
-- ملخّص التقييم للوحة
-- ─────────────────────────────────────────────────────────────────────────
-- **المتوسّط وحده يكذب**: أربعُ نجماتٍ ونصف قد تُخفي عشرَ شكاوى تحت مئةِ
-- رضًا. فيُعاد التوزيعُ كاملًا وعددُ ما دون الحدّ.
create or replace function rating_summary(
  p_branch uuid,
  p_from   date default (current_date - 30),
  p_to     date default current_date
)
returns table (
  ratings_count   int,
  avg_stars       numeric,
  avg_delivery    numeric,
  low_count       int,
  stars_1 int, stars_2 int, stars_3 int, stars_4 int, stars_5 int
)
language sql stable security invoker set search_path = public, extensions
as $$
  with scoped as (
    select r.*
    from order_ratings r
    join branches b on b.id = r.branch_id
    left join feedback_settings f on f.laundry_id = b.laundry_id
    where r.branch_id = p_branch
      and r.created_at >= p_from
      and r.created_at < (p_to + 1)
  )
  select
    count(*)::int,
    round(avg(stars)::numeric, 2),
    round(avg(delivery_stars)::numeric, 2),
    count(*) filter (where stars <= coalesce(
      (select low_star_at from feedback_settings f
       join branches b on b.laundry_id = f.laundry_id
       where b.id = p_branch), 3))::int,
    count(*) filter (where stars = 1)::int,
    count(*) filter (where stars = 2)::int,
    count(*) filter (where stars = 3)::int,
    count(*) filter (where stars = 4)::int,
    count(*) filter (where stars = 5)::int
  from scoped;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- صرفُ نقاط الولاء على طلب
-- ─────────────────────────────────────────────────────────────────────────
-- **القيمة تُعاد قراءتها هنا ولا تُقبل من التطبيق**: حزمةٌ معدَّلة ترسل
-- «صرفتُ ١٠ نقاطٍ بمئة ريال»، والقاعدة وحدها تعرف كم تساوي النقطة وما سقفُها.
--
-- ويقع على المسوّدة قبل الإرسال: بعد الإرسال تُجمَّد المبالغ (`guard_order_amounts`)
-- ولا يُخصم منها شيء.
create or replace function redeem_loyalty_on_order(p_order uuid, p_points int)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  o orders%rowtype;
  q record;
  v_points int;
  v_riyal  numeric;
begin
  select * into o from orders where id = p_order;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'الطلب غير موجود');
  end if;

  if not auth_is_service_context() and o.customer_id <> auth.uid() then
    raise exception 'الطلب ليس لك' using errcode = 'insufficient_privilege';
  end if;

  if o.status <> 'draft' then
    return jsonb_build_object('ok', false, 'reason', 'لا تُصرف النقاط بعد إرسال الطلب');
  end if;

  if o.loyalty_points_spent <> 0 then
    return jsonb_build_object('ok', false, 'reason', 'صُرفت نقاطٌ على هذا الطلب');
  end if;

  if coalesce(p_points, 0) <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'لا نقاط للصرف');
  end if;

  select * into q from quote_loyalty_redemption(o.customer_id, o.laundry_id, o.subtotal);

  if q.points_to_spend <= 0 then
    return jsonb_build_object('ok', false, 'reason', q.reason);
  end if;

  -- ما طلبه العميل أو ما يسمح به النظام — أيّهما أقلّ. وطلبُ أكثر ليس خطأً
  -- يُرفض بل رغبةٌ تُقصّ إلى حدّها.
  v_points := least(p_points, q.points_to_spend);
  v_riyal  := round(v_points * (
    select riyal_per_point from loyalty_settings where laundry_id = o.laundry_id
  ), 2);

  -- ولا يتجاوز الخصمُ ما بقي على الطلب: خصمٌ أكبر من الإجماليّ يعطي مبلغًا
  -- سالبًا يرفضه القيد — بعد أن تكون النقاط قد خُصمت.
  v_riyal := least(v_riyal, o.total);
  if v_riyal <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'لا قيمة لهذه النقاط');
  end if;

  insert into loyalty_transactions (user_id, laundry_id, order_id, kind, points, note)
  values (o.customer_id, o.laundry_id, p_order, 'redeem', -v_points,
          format('صُرفت على الطلب %s', o.order_number));

  update orders set
    loyalty_points_spent = v_points,
    discount_amount = discount_amount + v_riyal,
    total = greatest(total - v_riyal, 0)
  where id = p_order;

  return jsonb_build_object('ok', true, 'points', v_points, 'riyal', v_riyal);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحيات
-- ─────────────────────────────────────────────────────────────────────────
grant select, insert, update, delete on feedback_settings to authenticated;
grant select on feedback_settings to anon;
grant select, insert, update on order_ratings to authenticated;

alter table feedback_settings enable row level security;
alter table feedback_settings force row level security;
alter table order_ratings enable row level security;
alter table order_ratings force row level security;

create policy feedback_settings_read on feedback_settings for select using (true);
create policy feedback_settings_write on feedback_settings
  for all using (auth_is_super_admin() or auth_has_role('branch_manager'))
  with check (auth_is_super_admin() or auth_has_role('branch_manager'));

-- يقرأ التقييمَ من يرى الطلب. ولا يُفتح للعامّة: تقييمُ عميلٍ باسمه ليس
-- بيانًا عامًّا، والعرضُ العامّ (لو أُريد) يكون بملخّصٍ مجهول الهويّة.
create policy order_ratings_read on order_ratings
  for select using (can_see_order(order_id));

create policy order_ratings_insert on order_ratings
  for insert with check (
    exists (select 1 from orders o
            where o.id = order_ratings.order_id and o.customer_id = (select auth.uid()))
    or auth_is_super_admin()
  );

-- التعديل لصاحبه داخل النافذة — والحارس هو من يقيس النافذة.
create policy order_ratings_update on order_ratings
  for update using (
    exists (select 1 from orders o
            where o.id = order_ratings.order_id and o.customer_id = (select auth.uid()))
    or auth_is_super_admin()
  ) with check (
    exists (select 1 from orders o
            where o.id = order_ratings.order_id and o.customer_id = (select auth.uid()))
    or auth_is_super_admin()
  );

revoke execute on function guard_order_rating() from public, anon, authenticated;
revoke execute on function redeem_loyalty_on_order(uuid, int) from public, anon;
grant execute on function redeem_loyalty_on_order(uuid, int) to authenticated;
