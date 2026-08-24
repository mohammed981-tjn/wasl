-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | أمان مستوى الصفّ
-- ═══════════════════════════════════════════════════════════════════════════
--
-- هنا يصير الدور حقيقةً بدل أن يكون تسميةً. قبل هذا الملف، أيّ حاملِ رمزٍ صالح
-- يقرأ كل طلب في المنصّة ويكتب كل سعر — والشاشة التي تُخفي الزرّ لا تمنع من
-- ينادي الواجهة مباشرةً.
--
-- **مصيدةٌ يجب التصريح بها**: سياسة RLS تحرس الصفّ لا العمود. فسياسةُ «عدّل
-- ملفّك» تمنح العمودَ `blocked_at` أيضًا — أي أن المحظور يرفع الحظر عن نفسه.
-- ولذلك ما لا يُحرَس بالصفّ يُحرَس بمحفّز، في آخر هذا الملف.

-- ─────────────────────────────────────────────────────────────────────────
-- الصلاحيات الأساسية
-- ─────────────────────────────────────────────────────────────────────────
-- RLS ترشّح ما يُرى؛ وGRANT تقرّر ما يُمكن أصلًا. بلا المنح لا تصل السياسة.
-- المشروع مخصَّص لوصل وحده، فالجداول تسكن `public` — وهو ما تفترضه أدوات
-- Supabase كلّها: توليد الأنواع، وPostgREST، وعميل Flutter الذي يكتب
-- `from('orders')` بلا وسيط. والامتدادات وحدها تُنحّى إلى `extensions`.
set search_path = public, extensions;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
grant execute on all functions in schema public to anon, authenticated;

-- المتسلسلات تحتاج منحًا مستقلًا: عمود identity في orders يقرأ متسلسلة، ومن
-- لا يملكها يفشل عند الإدراج برسالةٍ لا تذكر المتسلسلة إطلاقًا.
grant usage, select on all sequences in schema public to authenticated;

alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- تفعيل RLS على كل جدول
-- ─────────────────────────────────────────────────────────────────────────
-- الحصر بقائمة صريحة لا `for all tables`: جدولٌ جديد يُنسى تفعيلُه عليه هو
-- بالضبط شكل الثغرة التي لا يلحظها أحد. والقائمة تُراجَع عند كل مهاجرة.
do $$
declare t text;
begin
  foreach t in array array[
    'laundries','branches','branch_hours','profiles','user_roles',
    'service_categories','services','branch_services',
    'delivery_settings','delivery_distance_tiers','delivery_zones','zone_service_rules',
    'addresses','orders','order_items','order_garments','order_events',
    'order_proofs','order_delivery_codes','order_transitions'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    -- force كي تنطبق السياسة على مالك الجدول أيضًا. بدونها يتجاوزها المالك
    -- بصمت، فيبدو الاختبار ناجحًا وهو لم يمرّ بسياسة أصلًا.
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- ═════════════════════════════════════════════════════════════════════════
-- الكتالوج العام: يُقرأ من الجميع، ويُكتب من الإدارة
-- ═════════════════════════════════════════════════════════════════════════
-- العميل يحتاج أن يرى الخدمات وأسعارها ومناطق التوصيل **قبل** أن يسجّل — وإلا
-- فلا يعرف ما يشتري. فالقراءة عامة، والكتابة محكومة.

create policy laundries_read on laundries
  for select using (is_active or auth_is_super_admin());
create policy laundries_write on laundries
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

create policy branches_read on branches
  for select using (is_active or auth_has_branch_role(id, 'branch_manager'));
create policy branches_insert on branches
  for insert with check (auth_is_super_admin());
create policy branches_update on branches
  for update using (auth_has_branch_role(id, 'branch_manager'))
  with check (auth_has_branch_role(id, 'branch_manager'));
create policy branches_delete on branches
  for delete using (auth_is_super_admin());

create policy branch_hours_read on branch_hours for select using (true);
create policy branch_hours_write on branch_hours
  for all using (auth_has_branch_role(branch_id, 'branch_manager'))
  with check (auth_has_branch_role(branch_id, 'branch_manager'));

-- الخدمات والأسعار: تُقرأ من الجميع. وتعديلها لمدير الفرع فأعلى — وموظّف
-- المغسلة **لا** يغيّر سعرًا، وهذا شرطٌ صريح في التصميم.
create policy service_categories_read on service_categories for select using (true);
create policy service_categories_write on service_categories
  for all using (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = service_categories.laundry_id))
  with check (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = service_categories.laundry_id));

create policy services_read on services for select using (true);
create policy services_write on services
  for all using (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = services.laundry_id))
  with check (auth_is_super_admin() or exists (
    select 1 from user_roles ur where ur.user_id = auth.uid()
      and ur.role = 'branch_manager' and ur.laundry_id = services.laundry_id));

create policy branch_services_read on branch_services for select using (true);
create policy branch_services_write on branch_services
  for all using (auth_has_branch_role(branch_id, 'branch_manager'))
  with check (auth_has_branch_role(branch_id, 'branch_manager'));

create policy delivery_settings_read on delivery_settings for select using (true);
create policy delivery_settings_write on delivery_settings
  for all using (auth_has_branch_role(branch_id, 'branch_manager'))
  with check (auth_has_branch_role(branch_id, 'branch_manager'));

create policy delivery_tiers_read on delivery_distance_tiers for select using (true);
create policy delivery_tiers_write on delivery_distance_tiers
  for all using (auth_has_branch_role(branch_id, 'branch_manager'))
  with check (auth_has_branch_role(branch_id, 'branch_manager'));

create policy delivery_zones_read on delivery_zones for select using (true);
create policy delivery_zones_write on delivery_zones
  for all using (auth_has_branch_role(branch_id, 'branch_manager'))
  with check (auth_has_branch_role(branch_id, 'branch_manager'));

create policy zone_rules_read on zone_service_rules for select using (true);
create policy zone_rules_write on zone_service_rules
  for all using (exists (
    select 1 from delivery_zones z
    where z.id = zone_service_rules.zone_id
      and auth_has_branch_role(z.branch_id, 'branch_manager')))
  with check (exists (
    select 1 from delivery_zones z
    where z.id = zone_service_rules.zone_id
      and auth_has_branch_role(z.branch_id, 'branch_manager')));

-- جدول الانتقالات يُقرأ ليعرف التطبيق أيّ زرٍّ يعرض؛ ولا يُكتب إلا من المالك.
create policy order_transitions_read on order_transitions for select using (true);
create policy order_transitions_write on order_transitions
  for all using (auth_is_super_admin()) with check (auth_is_super_admin());

-- ═════════════════════════════════════════════════════════════════════════
-- الملفّات الشخصية والأدوار
-- ═════════════════════════════════════════════════════════════════════════
-- من يرى ملفّ العميل؟ هو نفسه، وخدمة العملاء والإدارة، **والسائق المسنَد إلى
-- طلبه** — لأنه يحتاج اسمًا ورقمًا ليصل إليه. ولا أحد غيرهم: قائمةُ عملاءِ
-- المنصّة ليست بيانات يقرأها كل حامل رمز.
create policy profiles_read on profiles
  for select using (
    id = auth.uid()
    or auth_is_super_admin()
    or auth_has_role('customer_service')
    or exists (
      select 1 from orders o
      where o.customer_id = profiles.id
        and (o.pickup_driver_id = auth.uid()
             or o.delivery_driver_id = auth.uid()
             or o.branch_id in (select auth_branch_ids()))
    )
  );

create policy profiles_update on profiles
  for update using (id = auth.uid() or auth_is_super_admin())
  with check (id = auth.uid() or auth_is_super_admin());

create policy profiles_insert on profiles
  for insert with check (id = auth.uid() or auth_is_super_admin());

-- الأدوار: يرى المرء أدواره، وتراها إدارةُ فرعه. ومنحُها محكوم بمحفّز أدناه
-- لا بالسياسة وحدها — لأن السياسة لا تفرّق بين منح دورِ سائقٍ ومنح super_admin.
create policy user_roles_read on user_roles
  for select using (
    user_id = auth.uid()
    or auth_is_super_admin()
    or (branch_id is not null and auth_has_branch_role(branch_id, 'branch_manager'))
  );

create policy user_roles_write on user_roles
  for all using (
    auth_is_super_admin()
    or (branch_id is not null and auth_has_branch_role(branch_id, 'branch_manager'))
  )
  with check (
    auth_is_super_admin()
    or (branch_id is not null and auth_has_branch_role(branch_id, 'branch_manager'))
  );

-- ═════════════════════════════════════════════════════════════════════════
-- العناوين
-- ═════════════════════════════════════════════════════════════════════════
-- عنوان العميل له وحده — إلا لمن يحتاجه لينفّذ: فرعُ الطلب وسائقُه.
create policy addresses_owner on addresses
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy addresses_operational_read on addresses
  for select using (
    auth_is_super_admin()
    or auth_has_role('customer_service')
    or exists (
      select 1 from orders o
      where (o.pickup_address_id = addresses.id or o.delivery_address_id = addresses.id)
        and (o.pickup_driver_id = auth.uid()
             or o.delivery_driver_id = auth.uid()
             or o.branch_id in (select auth_branch_ids()))
    )
  );

-- ═════════════════════════════════════════════════════════════════════════
-- الطلبات
-- ═════════════════════════════════════════════════════════════════════════
-- دالّة واحدة تعرّف «من يرى هذا الطلب»، وتُستدعى من كل جدول تابع — كي لا
-- تُكتب القاعدة خمس مرّات فتفترق خمس نتائج عند أول تعديل.
create or replace function can_see_order(p_order uuid)
returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select exists (
    select 1 from orders o
    where o.id = p_order
      and (
        o.customer_id = auth.uid()
        or o.pickup_driver_id = auth.uid()
        or o.delivery_driver_id = auth.uid()
        or auth_is_super_admin()
        or auth_has_role('customer_service')
        or o.branch_id in (select auth_branch_ids())
      )
  );
$$;

create policy orders_read on orders for select using (can_see_order(id));

-- العميل ينشئ طلبه هو، مسوّدةً لا أكثر: حالةٌ أبعد تعني طلبًا يتخطّى القبول.
create policy orders_insert on orders
  for insert with check (
    (customer_id = auth.uid() and status = 'draft')
    or auth_is_super_admin()
    or auth_has_branch_role(branch_id, 'branch_manager', 'customer_service')
  );

-- التحديث مسموح لمن يرى الطلب؛ و**أيّ** انتقال حالة يمرّ بعدها على محفّز
-- enforce_order_transition الذي يعرف من يملك كل انتقال. فالسياسة تفتح الباب،
-- والمحفّز يحدّد الخطوة.
create policy orders_update on orders
  for update using (can_see_order(id)) with check (can_see_order(id));

create policy orders_delete on orders for delete using (auth_is_super_admin());

create policy order_items_all on order_items
  for all using (can_see_order(order_id)) with check (can_see_order(order_id));

create policy order_garments_all on order_garments
  for all using (can_see_order(order_id)) with check (can_see_order(order_id));

create policy order_events_read on order_events
  for select using (can_see_order(order_id));
-- السجلّ لا يُكتب من عميل: يكتبه المحفّز وحده (security definer يتجاوز RLS).
-- وبلا هذا يستطيع أيّ طرفٍ تلفيقُ تاريخٍ للطلب.
create policy order_events_insert on order_events
  for insert with check (auth_is_super_admin());

create policy order_proofs_read on order_proofs
  for select using (can_see_order(order_id));
create policy order_proofs_write on order_proofs
  for insert with check (
    driver_id = auth.uid() or auth_is_super_admin()
    or exists (select 1 from orders o where o.id = order_proofs.order_id
               and auth_has_branch_role(o.branch_id, 'branch_manager'))
  );

-- رمز التسليم: لا يُقرأ من أحد عبر الواجهة إطلاقًا. التحقّق يقع في دالّة
-- security definer تقارن المُجزَّأ ولا تُعيده. ولا سياسة select هنا = لا قراءة.
create policy delivery_codes_no_read on order_delivery_codes
  for select using (false);

-- ─────────────────────────────────────────────────────────────────────────
-- السياق الخادميّ
-- ─────────────────────────────────────────────────────────────────────────
-- سؤالٌ يجب أن يُجاب صراحةً: من يصنع أوّل super_admin؟ لا أحد — إن كان كل
-- منحٍ يشترط super_admin قائمًا. فالجواب أن الإدارة الأولى تقع من الخادم:
-- مفتاح `service_role` أو محرّر SQL، وكلاهما بلا جلسة مستخدم فـ`auth.uid()`
-- فيه NULL.
--
-- ولماذا هذا آمن: طلبُ الزائر (anon) لا يصل إلى الكتابة أصلًا — منحُه `select`
-- وحده، والمنع يقع قبل المحفّز. وطلبُ المستخدم المسجَّل يحمل uid دائمًا.
-- فـNULL هنا لا تعني «مجهولًا» بل «الخادم نفسه»، ومفتاحه سرٌّ لا يغادره.
create or replace function auth_is_service_context()
returns boolean language sql stable as $$
  select auth.uid() is null;
$$;

-- ═════════════════════════════════════════════════════════════════════════
-- حرّاس الأعمدة — ما لا تحرسه السياسة
-- ═════════════════════════════════════════════════════════════════════════
-- السياسة تحرس الصفّ. فمن يملك «عدّل ملفّك» يملك كل عمود فيه — ومنها الحظر.
create or replace function guard_profile_columns()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth_is_service_context() or auth_is_super_admin() or auth_has_role('customer_service') then
    return new;
  end if;
  if new.blocked_at is distinct from old.blocked_at
     or new.blocked_reason is distinct from old.blocked_reason then
    raise exception 'لا تملك تعديل حالة الحظر' using errcode = 'insufficient_privilege';
  end if;
  -- والهوية نفسها لا تُنقل إلى مستخدم آخر.
  if new.id is distinct from old.id then
    raise exception 'لا يُنقل الملف الشخصي' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

create trigger t_profiles_guard before update on profiles
  for each row execute function guard_profile_columns();

-- تصعيد الامتيازات: مدير الفرع يوظّف ويفصل في فرعه — ولا يصنع super_admin،
-- ولا يمنح دورًا في فرعٍ ليس فرعه. سياسةٌ واحدة لا تفرّق بين هذه الحالات.
create or replace function guard_role_grants()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth_is_service_context() or auth_is_super_admin() then
    return new;
  end if;
  -- دور العميل بلا فرع هو ما يمنحه محفّزُ التسجيل لكل مستخدم جديد. ولو لم
  -- يُستثنَ لَمَا استطاع أحدٌ التسجيل إطلاقًا — والحارس نفسه هو من يمنعه.
  -- واستثناؤه بلا ضرر: 'customer' لا يمنح شيئًا فوق ما يُمنح بالتسجيل.
  if new.role = 'customer' and new.branch_id is null then
    return new;
  end if;
  if new.role = 'super_admin' then
    raise exception 'لا يُمنح دور super_admin إلا من super_admin'
      using errcode = 'insufficient_privilege';
  end if;
  if new.branch_id is null then
    raise exception 'لا يُمنح دور بلا فرع إلا من super_admin'
      using errcode = 'insufficient_privilege';
  end if;
  if not auth_has_branch_role(new.branch_id, 'branch_manager') then
    raise exception 'لا تملك منح أدوار في هذا الفرع'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

create trigger t_user_roles_guard before insert or update on user_roles
  for each row execute function guard_role_grants();

-- والمبالغ: العميل لا يكتب `total` الخاص به. تُحسب من البنود ورسم التوصيل،
-- ولا تُقبل من الواجهة بعد إرسال الطلب.
create or replace function guard_order_amounts()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth_is_service_context() or auth_is_super_admin()
     or auth_has_branch_role(new.branch_id, 'branch_manager', 'accountant') then
    return new;
  end if;
  if old.status <> 'draft' and (
       new.subtotal        is distinct from old.subtotal
    or new.delivery_fee    is distinct from old.delivery_fee
    or new.discount_amount is distinct from old.discount_amount
    or new.total           is distinct from old.total
  ) then
    raise exception 'لا تُعدَّل مبالغ طلبٍ أُرسل' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

create trigger t_orders_guard_amounts before update on orders
  for each row execute function guard_order_amounts();
