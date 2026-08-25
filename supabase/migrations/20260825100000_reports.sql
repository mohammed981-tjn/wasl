-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | التقارير
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **لماذا في القاعدة لا في التطبيق**: تقريرُ شهرٍ يمسح آلاف الطلبات. وجلبُها
-- كلّها إلى الجوّال ليجمعها هناك يدفع ثمن نقلها، ويعطي رقمًا يختلف بين جهازٍ
-- وآخر إن اختلفت المنطقة الزمنية أو نسخة التطبيق. والتجميع هنا يعطي رقمًا
-- واحدًا للجميع.
--
-- وأثمنُ ما في هذا الملفّ `report_stage_durations`: **كم يستغرق الغسيل فعلًا؟**
-- سؤالٌ لا يُجاب بالتقدير، وجوابُه في `order_events` منذ اليوم الأول — لأن كل
-- انتقالٍ سُجِّل بوقته.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- الملخّص
-- ─────────────────────────────────────────────────────────────────────────
create or replace function report_summary(
  p_branch uuid, p_from date, p_to date
)
returns table (
  orders_count      int,
  revenue           numeric,
  avg_order_value   numeric,
  delivery_revenue  numeric,
  discounts_given   numeric,
  cancelled_count   int,
  late_count        int,
  pieces_processed  numeric
)
language sql stable security invoker set search_path = public, extensions
as $$
  with scoped as (
    select o.*
    from orders o
    where o.branch_id = p_branch
      and o.status <> 'draft'
      and o.created_at >= p_from
      and o.created_at < (p_to + 1)
  ),
  -- الإيراد لا يشمل الملغى ولا المسترَدّ: رقمٌ يسرّ ولا يصدق أسوأ من لا رقم.
  earning as (
    select * from scoped where status not in ('cancelled','refunded')
  )
  select
    (select count(*) from scoped)::int,
    coalesce((select sum(total) from earning), 0),
    coalesce((select avg(total) from earning), 0),
    coalesce((select sum(delivery_fee) from earning), 0),
    coalesce((select sum(discount_amount) from scoped), 0),
    (select count(*) from scoped where status = 'cancelled')::int,
    (select count(*) from scoped
      where promised_ready_at is not null
        and status not in ('delivered','cancelled','refunded')
        and promised_ready_at < now())::int,
    coalesce((select sum(order_piece_load(id)) from earning), 0);
$$;

comment on function report_summary is
  'ملخّص فترة. الإيراد لا يشمل الملغى ولا المسترَدّ — رقمٌ يسرّ ولا يصدق أسوأ من لا رقم.';

-- ─────────────────────────────────────────────────────────────────────────
-- الإيراد اليوميّ
-- ─────────────────────────────────────────────────────────────────────────
-- **بسلسلةٍ زمنية كاملة**: اليوم الذي لا طلب فيه يجب أن يظهر صفرًا لا أن
-- يُحذف. فرسمٌ يقفز فوق الأيام الفارغة يُخفي ركودًا، ويجعل الأسبوع يبدو
-- متّصلًا وهو ليس كذلك.
create or replace function report_daily(
  p_branch uuid, p_from date, p_to date
)
returns table (day date, orders_count int, revenue numeric)
language sql stable security invoker set search_path = public, extensions
as $$
  select
    d::date,
    coalesce(count(o.id) filter (where o.id is not null), 0)::int,
    coalesce(sum(o.total), 0)
  from generate_series(p_from, p_to, interval '1 day') d
  left join orders o
    on o.branch_id = p_branch
   and o.status not in ('draft','cancelled','refunded')
   and o.created_at >= d
   and o.created_at < d + interval '1 day'
  group by d
  order by d;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- مزيج الخدمات
-- ─────────────────────────────────────────────────────────────────────────
-- يُجمَّع على **الاسم المنسوخ في البند** لا على `service_id`: الخدمة قد تُحذف
-- من الكتالوج، والفاتورة تبقى. والتجميع على المعرّف يُسقط صفوفها من التقرير.
create or replace function report_service_mix(
  p_branch uuid, p_from date, p_to date
)
returns table (
  service_name  text,
  unit          pricing_unit,
  orders_count  int,
  quantity      numeric,
  revenue       numeric
)
language sql stable security invoker set search_path = public, extensions
as $$
  select
    oi.service_name_ar,
    oi.unit,
    count(distinct oi.order_id)::int,
    sum(oi.quantity),
    sum(oi.line_total)
  from order_items oi
  join orders o on o.id = oi.order_id
  where o.branch_id = p_branch
    and o.status not in ('draft','cancelled','refunded')
    and o.created_at >= p_from
    and o.created_at < (p_to + 1)
  group by oi.service_name_ar, oi.unit
  order by sum(oi.line_total) desc;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- أزمنة المراحل — أثمن ما هنا
-- ─────────────────────────────────────────────────────────────────────────
-- «كم يستغرق الكوي فعلًا؟» سؤالٌ تشغيليّ لا يُجاب بالتقدير. وجوابه محفوظٌ منذ
-- اليوم الأول في `order_events`: زمنُ المرحلة هو الفارق بين دخولها والانتقال
-- منها.
--
-- والوسيط (median) يُعرض مع المتوسّط عمدًا: طلبٌ واحدٌ نُسي في آلة الغسيل
-- أسبوعًا يرفع المتوسّط ولا يمسّ الوسيط — فاختلافهما الكبير هو نفسه الإشارة.
create or replace function report_stage_durations(
  p_branch uuid, p_from date, p_to date
)
returns table (
  stage        order_status,
  samples      int,
  avg_hours    numeric,
  median_hours numeric,
  max_hours    numeric
)
language sql stable security invoker set search_path = public, extensions
as $$
  with spans as (
    select
      e.to_status as stage,
      extract(epoch from (
        lead(e.created_at) over (partition by e.order_id order by e.created_at)
        - e.created_at
      )) / 3600.0 as hours
    from order_events e
    join orders o on o.id = e.order_id
    where o.branch_id = p_branch
      and e.created_at >= p_from
      and e.created_at < (p_to + 1)
  )
  select
    stage,
    count(*)::int,
    round(avg(hours)::numeric, 2),
    round(
      percentile_cont(0.5) within group (order by hours)::numeric, 2),
    round(max(hours)::numeric, 2)
  from spans
  where hours is not null      -- المرحلة الجارية بلا انتقالٍ بعدها
  group by stage
  order by avg(hours) desc nulls last;
$$;

comment on function report_stage_durations is
  'زمن كل مرحلة من سجلّ الأحداث. الوسيط مع المتوسّط: طلبٌ نُسي أسبوعًا يرفع الثاني ولا يمسّ الأول.';

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحية
-- ─────────────────────────────────────────────────────────────────────────
-- `security invoker` لا `definer`: التقارير تُبنى على `orders` و`order_items`
-- و`order_events`، وسياسات RLS عليها ترشّح بالفعل. فتقريرُ مديرِ فرعٍ يشمل
-- فرعه وحده **دون شرطٍ إضافيّ نكتبه** — والقاعدة تحرس، لا الدالّة.
grant execute on function report_summary(uuid, date, date) to authenticated;
grant execute on function report_daily(uuid, date, date) to authenticated;
grant execute on function report_service_mix(uuid, date, date) to authenticated;
grant execute on function report_stage_durations(uuid, date, date) to authenticated;

revoke execute on function report_summary(uuid, date, date) from public, anon;
revoke execute on function report_daily(uuid, date, date) from public, anon;
revoke execute on function report_service_mix(uuid, date, date) from public, anon;
revoke execute on function report_stage_durations(uuid, date, date) from public, anon;
