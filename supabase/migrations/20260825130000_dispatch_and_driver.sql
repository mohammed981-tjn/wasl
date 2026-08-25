-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | الإسناد، ورمز التسليم، وموقع السائق
-- ═══════════════════════════════════════════════════════════════════════════
--
-- طرفُ السائق هو الحلقة التي بلا وصلٍ لا يصل شيء: العميل يطلب، والمغسلة
-- تغسل، والإدارة تدير — ولا أحد يستلم ويوصّل.
--
-- وثلاثة أسئلةٍ تُحسم هنا في القاعدة لا في الشاشة:
--
--   ١) **من يُسنِد ولمن؟** الإسناد فعلُ إدارةٍ لا فعلُ سائق. ولولا حارسٌ
--      صريح لَاستطاع كلُّ من يرى الطلب أن يكتب `delivery_driver_id` —
--      والسياسة تحرس الصفّ لا العمود. والمسنَد إليه يجب أن يكون **سائقًا في
--      فرع الطلب** فعلًا: إسنادٌ إلى من لا دور له يُنتج طلبًا لا يراه أحد.
--
--   ٢) **بمَ يُثبت التسليم؟** رمزٌ يعرفه العميل وحده. ويُخزَّن مُجزَّأً
--      فلا يقرؤه من يقرأ الجدول، ويُقارَن في دالّةٍ لا تُعيده، وله صلاحيةٌ
--      وسقفُ محاولات — وإلّا صار تخمينُ أربعة أرقام مسألةَ وقت.
--
--   ٣) **أين السائق؟** صفٌّ واحدٌ يُحدَّث لا سجلٌّ يتراكم: خريطة التشغيل
--      تريد «أين هو الآن»، وتاريخُ المسار سؤالٌ آخر لا يُدفع ثمنه في كل
--      نبضة موقع.
--
-- وكلُّ رقمٍ هنا إعدادٌ تعدّله الإدارة: طول الرمز، ومدّته، وعدد محاولاته،
-- وسقفُ مهامّ السائق الواحد، وتواترُ نبض الموقع.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- إعدادات التوصيل والسائقين لكل فرع
-- ─────────────────────────────────────────────────────────────────────────
create table driver_settings (
  branch_id            uuid primary key references branches(id) on delete cascade,

  -- هل يُشترط رمزٌ لإتمام التسليم؟ مغسلةٌ صغيرةٌ في حيٍّ قد تراه تعقيدًا،
  -- وأخرى تسلّم في فندقٍ لا تسلّم بغيره.
  require_delivery_code boolean not null default true,

  -- أربعةُ أرقامٍ تُقرأ في رسالة وتُملى على الباب. وثمانيةٌ لمن أراد.
  delivery_code_length  smallint not null default 4
    check (delivery_code_length between 4 and 8),

  -- الرمز يموت. رمزٌ بلا انتهاءٍ يصير مفتاحًا دائمًا لطلبٍ عَلِق.
  delivery_code_ttl_minutes int not null default 180
    check (delivery_code_ttl_minutes between 5 and 1440),

  -- سقفُ المحاولات: بلا سقفٍ يُخمَّن رمزٌ من أربعة أرقام في دقائق.
  delivery_code_max_attempts smallint not null default 5
    check (delivery_code_max_attempts between 1 and 20),

  -- كم مهمّةً نشطةً يحمل السائق الواحد؟ صفر = بلا سقف.
  max_active_jobs      smallint not null default 0 check (max_active_jobs >= 0),

  -- تواتر نبض الموقع بالثواني. نبضةٌ كل ثانية تستنزف البطارية والباقة،
  -- وكلَّ عشر دقائق تجعل الخريطة كذبًا.
  location_ping_seconds int not null default 60
    check (location_ping_seconds between 15 and 900),

  updated_at           timestamptz not null default now()
);

comment on table driver_settings is
  'قواعد التوصيل لكل فرع — رقمٌ واحدٌ منها ليس في الشيفرة.';
comment on column driver_settings.delivery_code_max_attempts is
  'بلا سقفٍ يصير تخمين أربعة أرقام مسألة وقت لا مسألة معرفة.';

create trigger t_driver_settings_updated
  before update on driver_settings
  for each row execute function touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────
-- موقع السائق — الآن، لا تاريخًا
-- ─────────────────────────────────────────────────────────────────────────
-- صفٌّ لكل سائقٍ يُحدَّث في مكانه. وسجلُّ المسار الكامل حاجةٌ أخرى (تدقيقٌ
-- ونزاع) تُبنى بجدولٍ آخر حين تُطلب — لا بأن يتضخّم هذا فيبطئ الخريطة.
create table driver_locations (
  driver_id   uuid primary key references profiles(id) on delete cascade,
  location    geography(point, 4326) not null,

  -- ولنفس السبب في `addresses`: عمود geography يصل نصًّا سداسيًّا، والقراءة
  -- منه مباشرةً تعطي صفرًا صامتًا. فالإحداثيّات عمودان مشتقّان.
  lat         double precision generated always as (st_y(location::geometry)) stored,
  lng         double precision generated always as (st_x(location::geometry)) stored,

  accuracy_m  double precision check (accuracy_m is null or accuracy_m >= 0),
  is_online   boolean not null default true,
  updated_at  timestamptz not null default now()
);

create index on driver_locations using gist (location);
create index on driver_locations (updated_at desc) where is_online;

comment on table driver_locations is
  'الموقع الحاليّ لا المسار. «أين هو الآن» سؤالُ الخريطة، وتاريخُ المسار سؤالٌ آخر لا يُدفع ثمنه في كل نبضة.';

-- ─────────────────────────────────────────────────────────────────────────
-- دفتر الفرع ليس للسائق
-- ─────────────────────────────────────────────────────────────────────────
-- `auth_branch_ids()` تُعيد فروعَ من له فيها **أيّ** دور، و`can_see_order`
-- تفتح بها الطلب. فكان كلُّ سائقٍ يقرأ كلَّ طلبات فرعه — بأسماء أصحابها
-- وعناوينهم وهواتفهم، لا المسنَدَ إليه وحده. تسريبٌ صامتٌ لا يظهر في شاشة:
-- التطبيق يرشّح بـ`driver_id` فتبدو القائمة صحيحة، والقاعدة تعطي الكلّ لمن
-- سأل بغير التطبيق.
--
-- وحقُّ السائق مذكورٌ صراحةً في كل سياسة تخصّه
-- (`pickup_driver_id = auth.uid()`)، فاستثناءُ دوره هنا لا ينقص شيئًا يحتاجه
-- ويمنع ما لا يحتاجه.
create or replace function auth_branch_ids()
returns setof uuid
language sql stable security definer set search_path = public, extensions
as $$
  select branch_id from user_roles
  where user_id = auth.uid() and branch_id is not null and role <> 'driver';
$$;

comment on function auth_branch_ids() is
  'فروعُ من يشغّلها. ودورُ السائق مستثنًى: حقُّه في طلبٍ يأتي من إسناده إليه لا من فرعه.';

-- ─────────────────────────────────────────────────────────────────────────
-- حارس الإسناد
-- ─────────────────────────────────────────────────────────────────────────
-- `orders_update` تسمح لكل من يرى الطلب بتحديثه، والمحفّزات تحرس الحالة
-- والمبالغ — ولا شيء كان يحرس **من الذي يوصّل**. فالعميل يستطيع أن يكتب
-- سائقًا في طلبه، والسائق أن يفكّ إسناده عن نفسه، والإدارة أن تُسنِد إلى من
-- لا دور له فيصير الطلب في عهدة من لا يراه.
create or replace function guard_order_assignment()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_old_pickup   uuid := case when tg_op = 'UPDATE' then old.pickup_driver_id   end;
  v_old_delivery uuid := case when tg_op = 'UPDATE' then old.delivery_driver_id end;
  v_cap smallint;
  v_active int;
begin
  if new.pickup_driver_id   is not distinct from v_old_pickup
     and new.delivery_driver_id is not distinct from v_old_delivery then
    return new;
  end if;

  -- السياق الخادميّ يمرّ: الإصلاح اليدويّ والبذر يجب أن يبقيا ممكنين.
  if auth_is_service_context() then
    return new;
  end if;

  if not (auth_is_super_admin()
          or auth_has_branch_role(new.branch_id, 'branch_manager', 'customer_service')) then
    raise exception 'الإسناد من الإدارة لا من التطبيق'
      using errcode = 'insufficient_privilege';
  end if;

  -- المسنَد إليه سائقٌ في هذا الفرع، وإلّا فطلبٌ في عهدة من لا يراه.
  if new.pickup_driver_id is not null
     and new.pickup_driver_id is distinct from v_old_pickup
     and not exists (select 1 from user_roles
                     where user_id = new.pickup_driver_id
                       and role = 'driver' and branch_id = new.branch_id) then
    raise exception 'من تُسنِد إليه الاستلام ليس سائقًا في هذا الفرع'
      using errcode = 'check_violation';
  end if;

  if new.delivery_driver_id is not null
     and new.delivery_driver_id is distinct from v_old_delivery
     and not exists (select 1 from user_roles
                     where user_id = new.delivery_driver_id
                       and role = 'driver' and branch_id = new.branch_id) then
    raise exception 'من تُسنِد إليه التسليم ليس سائقًا في هذا الفرع'
      using errcode = 'check_violation';
  end if;

  -- سقفُ المهامّ النشطة: إسنادُ عشرين طلبًا لسائقٍ واحد ليس تنظيمًا بل
  -- تأجيلٌ للفشل إلى ساعةٍ متأخّرة.
  select max_active_jobs into v_cap from driver_settings where branch_id = new.branch_id;
  if coalesce(v_cap, 0) > 0 then
    if new.pickup_driver_id is not null
       and new.pickup_driver_id is distinct from v_old_pickup then
      select count(*) into v_active from orders
      where id <> new.id
        and (pickup_driver_id = new.pickup_driver_id or delivery_driver_id = new.pickup_driver_id)
        and status in ('pickup_assigned','pickup_en_route','delivery_assigned','out_for_delivery');
      if v_active >= v_cap then
        raise exception 'السائق بلغ سقف المهامّ النشطة (%)', v_cap
          using errcode = 'check_violation';
      end if;
    end if;

    if new.delivery_driver_id is not null
       and new.delivery_driver_id is distinct from v_old_delivery then
      select count(*) into v_active from orders
      where id <> new.id
        and (pickup_driver_id = new.delivery_driver_id or delivery_driver_id = new.delivery_driver_id)
        and status in ('pickup_assigned','pickup_en_route','delivery_assigned','out_for_delivery');
      if v_active >= v_cap then
        raise exception 'السائق بلغ سقف المهامّ النشطة (%)', v_cap
          using errcode = 'check_violation';
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger t_orders_guard_assignment
  before insert or update on orders
  for each row execute function guard_order_assignment();

-- ─────────────────────────────────────────────────────────────────────────
-- رمز التسليم
-- ─────────────────────────────────────────────────────────────────────────
-- التجزئة بـsha256 المدمجة في القاعدة، ومِلحُها معرّفُ الطلب: رمزٌ من أربعة
-- أرقام بلا مِلحٍ يُفكّ بجدولٍ من عشرة آلاف صفّ، وبمِلحٍ لكل طلبٍ لا يُعاد
-- استعمال الجدول مرّتين.
create or replace function hash_delivery_code(p_order uuid, p_code text)
returns text
language sql immutable set search_path = public, extensions
as $$
  select encode(sha256(convert_to(p_order::text || ':' || p_code, 'utf8')), 'hex');
$$;

-- توليدُ الرمز عند الخروج للتسليم.
--
-- ولماذا محفّزٌ لا نداءٌ من التطبيق: الرمز يجب أن يوجد **كلّما** خرج الطلب،
-- من أيّ حزمةٍ خرج ومن أيّ شاشة. ونداءُ التطبيق يعني طلبًا خرج بلا رمزٍ لأن
-- شاشةً نسيت النداء، فيقف السائق عند الباب بلا ما يُدخِله.
create or replace function issue_delivery_code()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  s driver_settings%rowtype;
  v_len smallint;
  v_ttl int;
  v_code text;
begin
  if new.status <> 'out_for_delivery' or old.status = 'out_for_delivery' then
    return new;
  end if;

  select * into s from driver_settings where branch_id = new.branch_id;

  -- غياب الإعدادات يعني الافتراضَ لا التعطيل: فرعٌ لم يُضبط بعدُ يجب أن
  -- يسلّم بأمانٍ لا بلا رمز.
  if found and not s.require_delivery_code then
    return new;
  end if;
  v_len := coalesce(s.delivery_code_length, 4);
  v_ttl := coalesce(s.delivery_code_ttl_minutes, 180);

  v_code := lpad((floor(random() * (10::numeric ^ v_len)))::bigint::text, v_len, '0');

  insert into order_delivery_codes (order_id, code_hash, expires_at, consumed_at, attempts)
  values (new.id, hash_delivery_code(new.id, v_code),
          now() + make_interval(mins => v_ttl), null, 0)
  on conflict (order_id) do update
    set code_hash = excluded.code_hash,
        expires_at = excluded.expires_at,
        consumed_at = null,
        attempts = 0;

  -- الرمز الصريح لا يُخزَّن ولا يُعاد: يُمرَّر إلى محفّز الإشعارات في
  -- إعدادٍ **محلّيٍّ للمعاملة** ينتهي بانتهائها، فلا يبقى منه أثرٌ في قرص.
  perform set_config('wasl.delivery_code', v_code, true);
  return new;
end;
$$;

-- ترتيبُه قبل محفّز الإشعارات مضمونٌ بنوعه لا باسمه: هذا BEFORE وذاك AFTER،
-- فالرمز يوجد قبل أن تُصفّ الرسالة التي تحمله.
create trigger t_orders_issue_delivery_code
  before update of status on orders
  for each row execute function issue_delivery_code();

-- التحقّق والاستهلاك.
--
-- لا يُرفع استثناءٌ عند رمزٍ خاطئ **عمدًا**: الاستثناء يتراجع بالمعاملة،
-- فيتراجع معه عدّادُ المحاولات — ويصير السقف الذي يحمي من التخمين وهمًا.
-- فالخطأ يُعاد قيمةً لا استثناءً.
create or replace function verify_delivery_code(p_order uuid, p_code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  o orders%rowtype;
  c order_delivery_codes%rowtype;
  v_max smallint;
begin
  select * into o from orders where id = p_order;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'الطلب غير موجود');
  end if;

  -- الدالّة definer فتتجاوز السياسات: الصلاحية تُفحص هنا صراحةً.
  if not (auth_is_service_context()
          or o.delivery_driver_id = auth.uid()
          or auth_has_branch_role(o.branch_id, 'branch_manager', 'customer_service')) then
    raise exception 'لا تملك تسليم هذا الطلب' using errcode = 'insufficient_privilege';
  end if;

  select * into c from order_delivery_codes where order_id = p_order;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'لا رمز لهذا الطلب');
  end if;
  if c.consumed_at is not null then
    return jsonb_build_object('ok', false, 'reason', 'الرمز استُهلك');
  end if;
  if c.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'انتهت صلاحية الرمز');
  end if;

  select coalesce(ds.delivery_code_max_attempts, 5) into v_max
  from (select 1) x
  left join driver_settings ds on ds.branch_id = o.branch_id;

  if c.attempts >= v_max then
    return jsonb_build_object('ok', false, 'reason', 'تجاوزتَ عدد المحاولات');
  end if;

  if c.code_hash <> hash_delivery_code(p_order, coalesce(trim(p_code), '')) then
    update order_delivery_codes set attempts = attempts + 1 where order_id = p_order;
    return jsonb_build_object(
      'ok', false,
      'reason', 'الرمز غير صحيح',
      'attempts_left', greatest(v_max - (c.attempts + 1), 0));
  end if;

  update order_delivery_codes set consumed_at = now() where order_id = p_order;
  return jsonb_build_object('ok', true);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- ملاحظة المنفّذ تُكتب مع الحدث لا بعده
-- ─────────────────────────────────────────────────────────────────────────
-- «العميل لم يفتح» و«سُلّم للحارس» ملاحظاتٌ تُكتب لحظة الانتقال. وكانت
-- تُكتب بتحديثٍ لاحقٍ على `order_events` — وهو خطأٌ من وجهين:
--
--   ١) السجلّ **لا يُحدَّث**: لا سياسة update عليه، فالتحديث يمسّ صفرَ صفوف
--      و**ينجح** بلا خطأ. الملاحظة تضيع بصمت.
--   ٢) ولو سُمح به لَصار سجلًّا يُعاد تحريره — وسجلٌّ يُحرَّر ليس سجلًّا.
--
-- فالملاحظة تُمرَّر في إعدادٍ محلّيٍّ للمعاملة، ويقرؤها المحفّز فيكتبها في
-- صفّ الحدث نفسه. وهي محلّيّةٌ فتُمحى بانتهاء المعاملة، وتُصفَّر بعد
-- استعمالها فلا تلتصق بانتقالٍ تالٍ في المعاملة نفسها.
create or replace function enforce_order_transition()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_role app_role;
  v_allowed app_role[];
  v_note text := nullif(current_setting('wasl.event_note', true), '');
begin
  if new.status = old.status then
    return new;
  end if;

  if auth.uid() is null then
    insert into order_events (order_id, from_status, to_status, note)
    values (new.id, old.status, new.status, coalesce(v_note, 'من السياق الخادميّ'));
    perform set_config('wasl.event_note', '', true);
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

  if v_role = 'customer' and new.customer_id <> auth.uid() then
    raise exception 'لا تملك هذا الطلب' using errcode = 'insufficient_privilege';
  end if;

  insert into order_events (order_id, from_status, to_status, actor_id, actor_role, note)
  values (new.id, old.status, new.status, auth.uid(), v_role, v_note);
  perform set_config('wasl.event_note', '', true);

  if new.status = 'placed'    and new.placed_at    is null then new.placed_at    := now(); end if;
  if new.status = 'delivered' and new.delivered_at is null then new.delivered_at := now(); end if;

  return new;
end;
$$;

revoke execute on function enforce_order_transition() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- إتمام الاستلام والتسليم
-- ─────────────────────────────────────────────────────────────────────────
-- الإثبات والانتقال في نداءٍ واحد. ولماذا: نداءان من التطبيق يعنيان طلبًا
-- انتقل إلى «سُلّم» ثم انقطعت الشبكة قبل الإثبات — فيصير التسليم بلا سندٍ
-- ولا يُعرف أوقع أم لا.
create or replace function complete_pickup(
  p_order uuid,
  p_lat   double precision default null,
  p_lng   double precision default null,
  p_note  text default null
) returns jsonb
language plpgsql security invoker set search_path = public, extensions
as $$
declare
  v_point geography;
begin
  if p_lat is not null and p_lng is not null then
    v_point := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  end if;

  insert into order_proofs (order_id, kind, driver_id, location, otp_verified)
  values (p_order, 'pickup', auth.uid(), v_point, false)
  on conflict (order_id, kind) do update
    set driver_id = excluded.driver_id,
        location  = coalesce(excluded.location, order_proofs.location);

  perform set_config('wasl.event_note', coalesce(trim(p_note), ''), true);

  -- الانتقال بعد الإثبات: RLS ومحفّز الانتقالات هما الحَكَم، ورفضُ أيٍّ
  -- منهما يتراجع بالإثبات معه.
  update orders set status = 'picked_up' where id = p_order;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function complete_delivery(
  p_order uuid,
  p_code  text default null,
  p_lat   double precision default null,
  p_lng   double precision default null,
  p_note  text default null
) returns jsonb
language plpgsql security invoker set search_path = public, extensions
as $$
declare
  v_required boolean;
  v_branch uuid;
  v_check jsonb;
  v_point geography;
begin
  select branch_id into v_branch from orders where id = p_order;
  if v_branch is null then
    return jsonb_build_object('ok', false, 'reason', 'الطلب غير موجود');
  end if;

  select coalesce(ds.require_delivery_code, true) into v_required
  from (select 1) x
  left join driver_settings ds on ds.branch_id = v_branch;

  if v_required then
    v_check := verify_delivery_code(p_order, coalesce(p_code, ''));
    if not (v_check ->> 'ok')::boolean then
      return v_check;
    end if;
  end if;

  if p_lat is not null and p_lng is not null then
    v_point := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  end if;

  insert into order_proofs (order_id, kind, driver_id, location, otp_verified)
  values (p_order, 'delivery', auth.uid(), v_point, v_required)
  on conflict (order_id, kind) do update
    set driver_id = excluded.driver_id,
        location  = coalesce(excluded.location, order_proofs.location),
        otp_verified = excluded.otp_verified;

  perform set_config('wasl.event_note', coalesce(trim(p_note), ''), true);
  update orders set status = 'delivered' where id = p_order;

  return jsonb_build_object('ok', true);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- نبض الموقع
-- ─────────────────────────────────────────────────────────────────────────
-- إحداثيّتان لا نصُّ geography: بناءُ النقطة في القاعدة يمنع صيغةً خاطئة
-- تُكتب من عميلٍ ولا تُكتشف إلا على خريطةٍ فارغة.
create or replace function ping_driver_location(
  p_lat double precision,
  p_lng double precision,
  p_accuracy_m double precision default null,
  p_online boolean default true
) returns void
language plpgsql security invoker set search_path = public, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'لا جلسة' using errcode = 'insufficient_privilege';
  end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'إحداثيّات غير صالحة' using errcode = 'check_violation';
  end if;

  insert into driver_locations (driver_id, location, accuracy_m, is_online, updated_at)
  values (auth.uid(),
          st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
          p_accuracy_m, p_online, now())
  on conflict (driver_id) do update
    set location   = excluded.location,
        accuracy_m = excluded.accuracy_m,
        is_online  = excluded.is_online,
        updated_at = now();
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الرمز في رسالة العميل
-- ─────────────────────────────────────────────────────────────────────────
-- يُعاد تعريف محفّز الإشعارات ليحمل `{رمز_التسليم}`.
--
-- **وللعميل وحده**: قالبٌ جمهورُه السائق لو حمل المتغيّر لَوصل الرمزُ إلى من
-- يُفترض أن يُتحقَّق منه — فيصير الإثبات توقيعَ المرء على نفسه.
create or replace function queue_status_notifications()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  t     notification_templates%rowtype;
  prefs notification_preferences%rowtype;
  v_vars jsonb;
  v_target uuid;
  v_branch text;
  v_allowed boolean;
  v_code text := nullif(current_setting('wasl.delivery_code', true), '');
  v_body_vars jsonb;
begin
  if new.status = old.status then
    return new;
  end if;

  select name_ar into v_branch from branches where id = new.branch_id;

  v_vars := jsonb_build_object(
    'رقم_الطلب', new.order_number::text,
    'الفرع',     coalesce(v_branch, ''),
    'الإجمالي',  new.total::text
  );

  for t in
    select * from notification_templates
    where laundry_id = new.laundry_id
      and trigger_status = new.status
      and is_active
  loop
    v_target := case t.audience
      when 'customer' then new.customer_id
      when 'driver'   then coalesce(new.delivery_driver_id, new.pickup_driver_id)
      else null
    end;

    if v_target is null then
      continue;
    end if;

    v_body_vars := case
      when t.audience = 'customer' and v_code is not null
        then v_vars || jsonb_build_object('رمز_التسليم', v_code)
      else v_vars
    end;

    select * into prefs from notification_preferences where user_id = v_target;

    v_allowed := true;
    if found then
      v_allowed := case t.channel
        when 'push'     then prefs.push_enabled
        when 'sms'      then prefs.sms_enabled
        when 'whatsapp' then prefs.whatsapp_enabled
        when 'email'    then prefs.email_enabled
        else true
      end;
    end if;

    if not v_allowed then
      insert into notifications (user_id, order_id, template_id, channel, title, body, status)
      values (v_target, new.id, t.id, t.channel,
              render_template(coalesce(t.title_ar,''), v_body_vars),
              render_template(t.body_ar, v_body_vars), 'skipped');
      continue;
    end if;

    insert into notifications (user_id, order_id, template_id, channel, title, body)
    values (v_target, new.id, t.id, t.channel,
            render_template(coalesce(t.title_ar,''), v_body_vars),
            render_template(t.body_ar, v_body_vars));
  end loop;

  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحيات
-- ─────────────────────────────────────────────────────────────────────────
grant select, insert, update, delete on driver_settings  to authenticated;
grant select, insert, update, delete on driver_locations to authenticated;

alter table driver_settings  enable row level security;
alter table driver_settings  force row level security;
alter table driver_locations enable row level security;
alter table driver_locations force row level security;

-- الإعدادات تُقرأ من التطبيق (السائق يحتاج تواتر النبض)، وتُكتب من الإدارة.
create policy driver_settings_read on driver_settings for select using (true);
create policy driver_settings_write on driver_settings
  for all using (auth_has_branch_role(branch_id, 'branch_manager'))
  with check (auth_has_branch_role(branch_id, 'branch_manager'));

-- الموقع: يكتبه صاحبه وحده. ولو سُمح لغيره لَاستطاع سائقٌ أن يضع زميله في
-- حيٍّ آخر ويأخذ مهمّته.
create policy driver_locations_write on driver_locations
  for all using (driver_id = (select auth.uid()))
  with check (driver_id = (select auth.uid()));

-- ويقرؤه من يشغّل الفرع الذي يعمل فيه — لا كل حامل رمز: مواقع الناس
-- اللحظيّة ليست بياناتٍ عامّة.
create policy driver_locations_read on driver_locations
  for select using (
    driver_id = (select auth.uid())
    or auth_is_super_admin()
    or exists (
      select 1 from user_roles ur
      where ur.user_id = driver_locations.driver_id
        and ur.branch_id in (select auth_branch_ids())
    )
  );

-- الدوالّ التي تُنادى من التطبيق تُفتح، ودوالّ المحفّزات تُغلق: كلُّ دالّةٍ
-- تُنشأ تُمنح EXECUTE لـPUBLIC افتراضًا، فتظهر على `/rest/v1/rpc/`.
revoke execute on function issue_delivery_code()    from public, anon, authenticated;
revoke execute on function guard_order_assignment() from public, anon, authenticated;
revoke execute on function queue_status_notifications() from public, anon, authenticated;
revoke execute on function hash_delivery_code(uuid, text) from public, anon, authenticated;

revoke execute on function verify_delivery_code(uuid, text) from public, anon;
revoke execute on function complete_pickup(uuid, double precision, double precision, text) from public, anon;
revoke execute on function complete_delivery(uuid, text, double precision, double precision, text) from public, anon;
revoke execute on function ping_driver_location(double precision, double precision, double precision, boolean) from public, anon;

grant execute on function verify_delivery_code(uuid, text) to authenticated;
grant execute on function complete_pickup(uuid, double precision, double precision, text) to authenticated;
grant execute on function complete_delivery(uuid, text, double precision, double precision, text) to authenticated;
grant execute on function ping_driver_location(double precision, double precision, double precision, boolean) to authenticated;
