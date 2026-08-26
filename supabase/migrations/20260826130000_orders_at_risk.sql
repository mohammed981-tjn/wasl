-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | الطلبات المعرَّضة للتأخير
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **«متأخّر» معلومةٌ متأخّرة.** حين يتجاوز الطلبُ وعدَه يكون العميل قد انتظر
-- بالفعل، وكلُّ ما بقي اعتذار. والسؤال النافع أسبقُ من ذلك: **أيُّ طلبٍ لم
-- يتأخّر بعدُ وسيتأخّر؟**
--
-- وجوابُه في القاعدة منذ اليوم الأول ولا يحتاج نموذجًا ولا خدمةً خارجية: كلُّ
-- انتقالٍ سُجِّل بوقته في `order_events`. فيُعرف **كم يستغرق كلُّ طورٍ في هذا
-- الفرع فعلًا** — لا كم يُفترض أن يستغرق — ويُجمَع ما بقي من أطوارٍ أمام
-- الطلب، ويُقارَن بما بقي من وقتٍ قبل وعده.
--
-- ثلاثةُ قراراتٍ في هذا الحساب تستحقّ أن تُقال:
--
--   ١) **الوسيط لا المتوسّط.** طلبٌ واحدٌ نُسي في الغسّالة يومين يرفع المتوسّط
--      فيجعل كلَّ طلبٍ يبدو معرَّضًا للتأخير. والوسيط لا يتأثّر به.
--
--   ٢) **يُعلَن عددُ العيّنات، ولا يُخفى قِلّتُها.** تقديرٌ مبنيٌّ على طلبين
--      ليس تقديرًا. فيُعاد `confident` صريحًا، والشاشة تقول «تقديرٌ ضعيف»
--      بدل أن تعرض رقمًا يُصدَّق.
--
--   ٣) **التقدير متحفّظ عمدًا.** يُجمَع الكيّ في المسار وإن كان بعضُ الطلبات
--      يتخطّاه — فالخطأ في جهة الإنذار المبكر أرحمُ من الخطأ في جهة الصمت.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- ترتيبُ الأطوار حتى الجاهزية
-- ─────────────────────────────────────────────────────────────────────────
-- دالّةٌ لا جدول: هذا **ترتيبُ قراءةٍ للتحليل** لا قاعدةُ عملٍ تُعدَّل. وقاعدة
-- العمل (أيُّ انتقالٍ مسموح ولمن) في `order_transitions` وحدها.
create or replace function stage_sequence()
returns table (stage order_status, ord int)
language sql immutable set search_path = public, extensions
as $$
  values
    ('placed'::order_status, 1),
    ('accepted', 2),
    ('pickup_assigned', 3),
    ('pickup_en_route', 4),
    ('picked_up', 5),
    ('at_laundry', 6),
    ('sorting', 7),
    ('washing', 8),
    ('drying', 9),
    ('ironing', 10),
    ('packaging', 11);
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الطلبات المعرَّضة
-- ─────────────────────────────────────────────────────────────────────────
create or replace function orders_at_risk(
  p_branch        uuid,
  p_history_days  int default 30,
  p_min_samples   int default 5
)
returns table (
  order_id          uuid,
  order_number      bigint,
  customer_name     text,
  status            order_status,
  is_express        boolean,
  promised_ready_at timestamptz,
  expected_ready_at timestamptz,
  late_by_minutes   int,
  minutes_in_stage  int,
  samples           int,
  confident         boolean,
  already_late      boolean
)
language sql stable security invoker set search_path = public, extensions
as $$
  with seq as (
    select * from stage_sequence()
  ),
  -- مدّةُ كلِّ طورٍ كما وقعت: من دخول الطور إلى دخول ما بعده.
  spans as (
    select
      e.to_status as stage,
      extract(epoch from (
        lead(e.created_at) over (partition by e.order_id order by e.created_at)
        - e.created_at
      )) / 60.0 as minutes
    from order_events e
    join orders o on o.id = e.order_id
    where o.branch_id = p_branch
      and e.created_at >= now() - make_interval(days => p_history_days)
  ),
  medians as (
    select
      stage,
      count(*)::int as samples,
      percentile_cont(0.5) within group (order by minutes) as median_minutes
    from spans
    -- الطور الجاري بلا انتقالٍ بعده يعطي NULL، والسالب يعني ساعةً رجعت.
    where minutes is not null and minutes >= 0
    group by stage
  ),
  open_orders as (
    select
      o.id, o.order_number, o.status, o.is_express, o.promised_ready_at,
      o.created_at, s.ord,
      coalesce(
        (select max(e.created_at) from order_events e
         where e.order_id = o.id and e.to_status = o.status),
        o.created_at) as entered_at
    from orders o
    join seq s on s.stage = o.status
    where o.branch_id = p_branch
      and o.promised_ready_at is not null
  ),
  est as (
    select
      oo.*,
      -- ما بقي من أطوارٍ **بعد** الطور الحاليّ.
      coalesce((
        select sum(coalesce(m.median_minutes, 0))
        from seq s2 left join medians m on m.stage = s2.stage
        where s2.ord > oo.ord), 0) as after_minutes,
      -- والطور الحاليّ نفسه: يُحسب من لحظة دخوله لا من الآن.
      coalesce((
        select m.median_minutes from medians m where m.stage = oo.status), 0)
        as this_minutes,
      -- أضعفُ حلقةٍ في السلسلة: طورٌ بلا تاريخٍ يجعل التقدير كلَّه ضعيفًا.
      coalesce((
        select min(coalesce(m.samples, 0))
        from seq s2 left join medians m on m.stage = s2.stage
        where s2.ord >= oo.ord), 0) as min_samples
    from open_orders oo
  ),
  scored as (
    select
      e.*,
      -- **لا يُتوقَّع ماضٍ**: طلبٌ تجاوز وسيطَ طوره الحاليّ لا يزال فيه،
      -- فأقربُ ما يمكن أن يخرج منه هو الآن.
      greatest(
        e.entered_at + make_interval(mins => e.this_minutes::int),
        now()
      ) + make_interval(mins => e.after_minutes::int) as expected
    from est e
  )
  select
    s.id,
    s.order_number,
    (select p.full_name from profiles p
     join orders o2 on o2.customer_id = p.id where o2.id = s.id),
    s.status,
    s.is_express,
    s.promised_ready_at,
    s.expected,
    (extract(epoch from (s.expected - s.promised_ready_at)) / 60)::int,
    (extract(epoch from (now() - s.entered_at)) / 60)::int,
    s.min_samples,
    s.min_samples >= p_min_samples,
    s.promised_ready_at < now()
  from scored s
  where s.expected > s.promised_ready_at
  order by (s.expected - s.promised_ready_at) desc;
$$;

comment on function orders_at_risk(uuid, int, int) is
  'أيُّ طلبٍ سيتأخّر قبل أن يتأخّر — من مُدد الأطوار كما وقعت في هذا الفرع، لا من تقدير.';

revoke execute on function orders_at_risk(uuid, int, int) from public, anon;
grant execute on function orders_at_risk(uuid, int, int) to authenticated;
revoke execute on function stage_sequence() from public, anon;
grant execute on function stage_sequence() to authenticated;
