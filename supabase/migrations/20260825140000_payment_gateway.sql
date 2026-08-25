-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | بوّابة الدفع: الجلسة، والإشعار الوارد، وتطبيق النتيجة
-- ═══════════════════════════════════════════════════════════════════════════
--
-- جداول الدفع مبنيّةٌ من قبل (`payments` و`refunds` و`payment_providers`).
-- وما ينقص هو **الطريق بين المزوّد وبينها** — وهو أخطر طريقٍ في النظام، لأن
-- ما يمرّ فيه مال.
--
-- وأربع حقائق عن بوّابات الدفع تُبنى لها القاعدة هنا، لا يُكتشف غيابُها إلا
-- بعد أن يصير في الدفاتر خطأ:
--
--   ١) **الإشعار يتكرّر.** البوّابة تعيد الإرسال حتى تتلقّى إقرارًا، فالإشعار
--      الواحد قد يصل ثلاثًا. وتسجيلُه ثلاثًا يضاعف الإيراد في التقارير.
--      فالمعالجة تُقيَّد بمعرّف الحدث لا بمضمونه.
--
--   ٢) **الإشعار يصل بغير ترتيبه.** `paid` قد يسبق `initiated` في الوصول.
--      فالحالة لا تتراجع: مقبوضٌ لا يعود «معلَّقًا» لأن إشعارًا قديمًا تأخّر.
--
--   ٣) **المبلغ يجب أن يُتحقَّق منه لا أن يُصدَّق.** بوّابةٌ تقول «دُفع ٥ ريال»
--      لطلبٍ إجماليّه ٥٠٠ ليست بوّابةً تُطاع: إمّا خطأُ إعدادٍ أو عبثٌ، وفي
--      الحالتين لا يُعلَن الطلب مدفوعًا.
--
--   ٤) **مفتاح السرّ لا يلمس القاعدة ولا الحزمة.** يسكن أسرارَ دالّة Edge،
--      وهي وحدها من يكلّم المزوّد. والقاعدة تستقبل **نتيجةً** لا تُجريها.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- الإشعارات الواردة من البوّابة
-- ─────────────────────────────────────────────────────────────────────────
-- يُسجَّل كلُّ إشعارٍ ولو رُفض: «وصل إشعارٌ بتوقيعٍ خاطئ» معلومةٌ أمنية، وحذفُها
-- يجعل المحاولة الأولى للاختراق غير مرئيّة.
create table payment_webhook_events (
  id           uuid primary key default uuid_generate_v4(),

  -- معرّف الحدث عند المزوّد. **فريدٌ** — وهو كلُّ ما يمنع المعالجة المكرّرة.
  provider_code text not null,
  event_id     text not null,
  event_type   text,
  provider_ref text,
  payload      jsonb not null,
  accepted     boolean not null default false,
  reject_reason text,
  received_at  timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider_code, event_id)
);

create index on payment_webhook_events (provider_ref);
create index on payment_webhook_events (received_at desc);

comment on table payment_webhook_events is
  'سجلُّ الوارد من البوّابة. التفرّد على (المزوّد، الحدث) هو ما يمنع مضاعفة الإيراد حين تعيد البوّابة الإرسال.';

-- ─────────────────────────────────────────────────────────────────────────
-- الحالة لا تتراجع
-- ─────────────────────────────────────────────────────────────────────────
-- إشعارٌ متأخّرٌ يحمل حالةً قديمة يجب أن يُهمَل لا أن يُطبَّق. ولولا هذا لَعاد
-- طلبٌ مقبوضٌ «معلَّقًا» بعد دقيقةٍ من دفعه، ولانقلبت حالة الدفع على الطلب.
create or replace function guard_payment_status_regression()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  rank_old int;
  rank_new int;
begin
  if new.status = old.status then
    return new;
  end if;

  rank_old := case old.status
    when 'pending' then 0 when 'failed' then 1 when 'cancelled' then 1
    when 'authorized' then 2 when 'captured' then 3 end;
  rank_new := case new.status
    when 'pending' then 0 when 'failed' then 1 when 'cancelled' then 1
    when 'authorized' then 2 when 'captured' then 3 end;

  -- المقبوض لا يصير معلَّقًا ولا فاشلًا. والإلغاء الحقيقيّ بعد القبض
  -- **استردادٌ** يُسجَّل في `refunds`، لا تراجعٌ في حالة الدفعة.
  if rank_new < rank_old then
    raise exception 'لا تتراجع حالة الدفعة من % إلى %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger t_payments_no_regression
  before update of status on payments
  for each row execute function guard_payment_status_regression();

-- ─────────────────────────────────────────────────────────────────────────
-- تطبيق نتيجة الدفع
-- ─────────────────────────────────────────────────────────────────────────
-- تُنادى من دالّة Edge بمفتاح `service_role` وحدها. و`security definer` هنا
-- ليست تسهيلًا: سياسة `payments` تمنع الكتابة على كل من دون محاسبٍ أو مالك —
-- **وهذا صحيح**، فمن يكتب دفعةً `captured` يدفع طلبه بجملة SQL.
--
-- والحارس صريحٌ في أوّل سطر: بلا جلسةٍ فقط. أيّ مستخدمٍ مسجَّل — ولو كان
-- المالك — لا يمرّ من هنا، لأن هذا الطريق للآلة لا لليد.
create or replace function apply_payment_result(
  p_provider_ref  text,
  p_status        payment_txn_status,
  p_amount        numeric,
  p_order         uuid default null,
  p_method        payment_method default 'card',
  p_card_brand    text default null,
  p_card_last4    text default null,
  p_failure_code  text default null,
  p_failure_message text default null,
  p_raw           jsonb default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  p payments%rowtype;
  v_order uuid;
  v_total numeric;
begin
  if not auth_is_service_context() then
    raise exception 'تطبيق نتيجة الدفع من الخادم وحده'
      using errcode = 'insufficient_privilege';
  end if;

  if p_provider_ref is null or length(trim(p_provider_ref)) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'لا معرّف عملية');
  end if;

  select * into p from payments where provider_ref = p_provider_ref;
  v_order := coalesce(p.order_id, p_order);

  if v_order is null then
    return jsonb_build_object('ok', false, 'reason', 'لا طلب لهذه العملية');
  end if;

  select total into v_total from orders where id = v_order;
  if v_total is null then
    return jsonb_build_object('ok', false, 'reason', 'الطلب غير موجود');
  end if;

  -- المبلغ يُتحقَّق منه لا يُصدَّق. والفرق يُسجَّل ولا يُطبَّق: نصفُ ريالٍ
  -- خطأُ تقريبٍ في التحويل إلى هللات، وخمسُ مئةٍ عبث — وكلاهما يُوقف الإعلان.
  if p_status = 'captured' and round(p_amount, 2) <> round(v_total, 2) then
    return jsonb_build_object(
      'ok', false,
      'reason', 'المبلغ لا يطابق إجمالي الطلب',
      'expected', v_total, 'received', p_amount);
  end if;

  if p.id is null then
    insert into payments (order_id, method, status, amount, provider_ref,
                          card_brand, card_last4, failure_code, failure_message,
                          raw_response,
                          captured_at, authorized_at)
    values (v_order, p_method, p_status, p_amount, p_provider_ref,
            p_card_brand, nullif(p_card_last4, ''), p_failure_code, p_failure_message,
            p_raw,
            case when p_status = 'captured'  then now() end,
            case when p_status = 'authorized' then now() end);
    return jsonb_build_object('ok', true, 'created', true);
  end if;

  if p.status = p_status then
    return jsonb_build_object('ok', true, 'unchanged', true);
  end if;

  update payments set
    status = p_status,
    card_brand = coalesce(p_card_brand, card_brand),
    card_last4 = coalesce(nullif(p_card_last4, ''), card_last4),
    failure_code = coalesce(p_failure_code, failure_code),
    failure_message = coalesce(p_failure_message, failure_message),
    raw_response = coalesce(p_raw, raw_response),
    captured_at = case when p_status = 'captured' then now() else captured_at end,
    authorized_at = case when p_status = 'authorized' then now() else authorized_at end
  where id = p.id;

  return jsonb_build_object('ok', true, 'updated', true);
exception
  -- التراجع في الحالة ليس خطأً يُوقف المعالجة بل إشعارٌ متأخّر يُهمَل.
  when check_violation then
    return jsonb_build_object('ok', true, 'ignored', true, 'reason', sqlerrm);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- فتحُ جلسة دفع
-- ─────────────────────────────────────────────────────────────────────────
-- يناديها الخادم قبل مخاطبة المزوّد: تتحقّق أن الطلب قابلٌ للدفع، وتُعيد
-- **المبلغ من القاعدة لا من العميل**. وهذا هو الفرق كلُّه: عميلٌ يرسل مبلغه
-- يدفع مئة ريالٍ لطلبٍ بخمس مئة.
create or replace function open_payment_session(p_order uuid, p_customer uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  o orders%rowtype;
  v_laundry text;
  v_paid numeric;
begin
  if not auth_is_service_context() then
    raise exception 'فتح جلسة الدفع من الخادم وحده'
      using errcode = 'insufficient_privilege';
  end if;

  select * into o from orders where id = p_order;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'الطلب غير موجود');
  end if;

  -- الدفع لصاحب الطلب: من يعرف معرّف طلبٍ غيره لا يدفعه (ولا يراه).
  if o.customer_id <> p_customer then
    return jsonb_build_object('ok', false, 'reason', 'الطلب ليس لك');
  end if;

  if o.status = 'draft' then
    return jsonb_build_object('ok', false, 'reason', 'الطلب لم يُرسل بعد');
  end if;
  if o.status in ('cancelled', 'refunded') then
    return jsonb_build_object('ok', false, 'reason', 'الطلب ملغًى');
  end if;
  if o.total <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'لا مبلغ على هذا الطلب');
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from payments where order_id = p_order and status in ('captured', 'authorized');
  if v_paid >= o.total then
    return jsonb_build_object('ok', false, 'reason', 'الطلب مدفوع');
  end if;

  select name_ar into v_laundry from laundries where id = o.laundry_id;

  return jsonb_build_object(
    'ok', true,
    'order_id', o.id,
    'order_number', o.order_number,
    'laundry_id', o.laundry_id,
    'laundry_name', coalesce(v_laundry, 'وصل'),
    'amount', o.total,
    'currency', 'SAR');
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- تسجيل الإشعار الوارد
-- ─────────────────────────────────────────────────────────────────────────
-- يُسجَّل أوّلًا ويُعالَج بعده. و`ok=false` مع `duplicate` تعني «رأيتُه من قبل»
-- لا «فشل»: على الخادم أن يجيب البوّابة بنجاحٍ كي تكفّ عن الإعادة.
create or replace function record_webhook_event(
  p_provider  text,
  p_event_id  text,
  p_event_type text,
  p_provider_ref text,
  p_payload   jsonb,
  p_accepted  boolean default true,
  p_reject_reason text default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare v_id uuid;
begin
  if not auth_is_service_context() then
    raise exception 'تسجيل الإشعار من الخادم وحده'
      using errcode = 'insufficient_privilege';
  end if;

  insert into payment_webhook_events
    (provider_code, event_id, event_type, provider_ref, payload, accepted, reject_reason,
     processed_at)
  values (p_provider, p_event_id, p_event_type, p_provider_ref, p_payload,
          p_accepted, p_reject_reason, case when p_accepted then now() end)
  on conflict (provider_code, event_id) do nothing
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'duplicate', true);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحيات
-- ─────────────────────────────────────────────────────────────────────────
alter table payment_webhook_events enable row level security;
alter table payment_webhook_events force row level security;

-- سياسةُ منعٍ **صريحة** لا غيابُ سياسة: جدولٌ بـRLS وبلا سياسة يعطي صفر صفوف
-- بلا خطأ، فيبدو فارغًا لا ممنوعًا — ولا يُعرف أهو مقصودٌ أم نُسي. والمنع هنا
-- مقصود: الوارد الخام فيه ردُّ المزوّد كاملًا، ولا يمرّ على واجهة.
create policy webhook_events_no_read on payment_webhook_events
  for select using (false);

grant select, insert on payment_webhook_events to service_role;

revoke execute on function guard_payment_status_regression() from public, anon, authenticated;
revoke execute on function apply_payment_result(text, payment_txn_status, numeric, uuid,
  payment_method, text, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function open_payment_session(uuid, uuid) from public, anon, authenticated;
revoke execute on function record_webhook_event(text, text, text, text, jsonb, boolean, text)
  from public, anon, authenticated;
