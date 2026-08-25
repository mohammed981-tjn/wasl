-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | الباركود
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **لماذا يُولَّد في القاعدة لا في التطبيق**: التفرّد. جهازان في المغسلة
-- يفرزان طلبين في اللحظة نفسها، وكلٌّ يولّد باركودًا من عدّادٍ محلّيّ — فيتكرّر
-- الرقم، ويُمسح كيسٌ فيظهر طلبُ غيره. والقاعدة تملك المتسلسلة وحدها.
--
-- والصيغة مقروءةٌ عمدًا: `WSL-10042` يُملى في الهاتف ويُقرأ من ملصقٍ اتّسخ.
-- ومعرّف UUID لا يصلح لواحدٍ منهما.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- باركود الطلب — عند الإرسال لا عند الإنشاء
-- ─────────────────────────────────────────────────────────────────────────
-- المسوّدة قد تُهجر، وباركودٌ لها يستهلك رقمًا ويُطبع ملصقًا لطلبٍ لم يوجد.
create or replace function assign_order_barcode()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if new.status = 'placed' and old.status = 'draft' and new.barcode is null then
    new.barcode := 'WSL-' || new.order_number::text;
  end if;
  return new;
end;
$$;

create trigger t_orders_barcode
  before update of status on orders
  for each row execute function assign_order_barcode();

-- ─────────────────────────────────────────────────────────────────────────
-- باركود القطعة
-- ─────────────────────────────────────────────────────────────────────────
-- مشتقٌّ من باركود الطلب برقمٍ تسلسليّ داخله: `WSL-10042-03`. والفائدة أن
-- القطعة الضائعة تُنسب إلى طلبها بالنظر — قبل أن يُفتح أيّ نظام.
create or replace function assign_garment_barcode()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_order_barcode text;
  v_seq int;
begin
  if new.barcode is not null and new.barcode <> '' then
    return new;   -- باركودٌ مطبوعٌ مسبقًا (ملصقات جاهزة) يُحترم
  end if;

  select coalesce(o.barcode, 'WSL-' || o.order_number::text)
    into v_order_barcode
  from orders o where o.id = new.order_id;

  -- العدّ من القطع الموجودة **في هذا الطلب** لا من متسلسلة عامّة: الترقيم
  -- داخل الكيس هو ما يفيد الفارز.
  select count(*) + 1 into v_seq
  from order_garments g where g.order_id = new.order_id;

  new.barcode := v_order_barcode || '-' || lpad(v_seq::text, 2, '0');
  return new;
end;
$$;

create trigger t_garments_barcode
  before insert on order_garments
  for each row execute function assign_garment_barcode();

-- ─────────────────────────────────────────────────────────────────────────
-- البحث بالمسح
-- ─────────────────────────────────────────────────────────────────────────
-- المسح يعطي نصًّا واحدًا: قد يكون باركود طلبٍ أو باركود قطعة. والموظّف لا
-- يعرف أيّهما مسح — ولا ينبغي أن يُسأل. فالدالّة تجيب بالطلب في الحالتين،
-- وتقول أيّهما كان.
create or replace function resolve_barcode(p_code text)
returns table (
  order_id     uuid,
  order_number bigint,
  status       order_status,
  kind         text,
  garment_id   uuid,
  garment_label text
)
language sql stable security invoker set search_path = public, extensions
as $$
  select o.id, o.order_number, o.status, 'order'::text, null::uuid, null::text
  from orders o
  where o.barcode = upper(trim(p_code))
  union all
  select o.id, o.order_number, o.status, 'garment'::text, g.id, g.label_ar
  from order_garments g
  join orders o on o.id = g.order_id
  where g.barcode = upper(trim(p_code))
  limit 1;
$$;

comment on function resolve_barcode is
  'يجيب بالطلب سواء مُسح ملصقُ الكيس أو ملصقُ قطعةٍ فيه — والموظّف لا يُسأل أيّهما مسح.';

grant execute on function resolve_barcode(text) to authenticated;
revoke execute on function resolve_barcode(text) from public, anon;

-- ─────────────────────────────────────────────────────────────────────────
-- نقل مرحلة القطع مع الطلب
-- ─────────────────────────────────────────────────────────────────────────
-- `order_garments.current_stage` كان يُترك عند `sorting` أبدًا. وقيمةٌ لا
-- تُحدَّث أسوأ من غيابها: تبدو معلومةً وهي قديمة، فيبحث الموظّف عن قطعةٍ في
-- مرحلةٍ غادرتها.
create or replace function sync_garment_stages()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if new.status = old.status then
    return new;
  end if;
  -- المراحل الداخلية وحدها: القطعة لا تكون «خرجت للتوصيل» — الكيس هو الذي خرج.
  if new.status in ('sorting','washing','drying','ironing','packaging') then
    update order_garments
       set current_stage = new.status
     where order_id = new.id;
  end if;
  return new;
end;
$$;

create trigger t_orders_sync_garments
  after update of status on orders
  for each row execute function sync_garment_stages();

-- ─────────────────────────────────────────────────────────────────────────
-- سحب التنفيذ من دوالّ المحفّزات الجديدة
-- ─────────────────────────────────────────────────────────────────────────
-- **خطوةٌ تلزم كلَّ مهاجرةٍ تضيف محفّزًا.** `grant execute on all functions`
-- الذي مضى لا يشمل ما يُضاف بعده، لكنّ Postgres يمنح كل دالّة جديدة لـPUBLIC
-- تلقائيًّا — فتظهر على `/rest/v1/rpc/` بلا قصد.
--
-- وقد أمسك ذلك اختبارُ النظافة قبل أن يصل الإنتاج. والسحب من `public` أوّلًا
-- لأن السحب من الدورين وحدهما لا يمسّ المنح الموروث.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;
