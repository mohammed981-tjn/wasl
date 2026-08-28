-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | ضبطُ الشكاوى من اللوحة — لا من SQL
-- ═══════════════════════════════════════════════════════════════════════════
--
-- **قاعدةُ عملٍ لا تُضبط إلا بـSQL ليست مضبوطةً من الإدارة.** بنينا المُهَل
-- والأنواع والقوالب صفوفًا لا ثوابتَ في الشيفرة، ثم قصرنا الكتابة على مالك
-- المنصّة وحده. فصاحبُ المغسلة — وهو من يعرف أنّ مهلته يومان لا يومًا، وأنّ
-- عنده «العطر المطلوب لم يُستخدم» — لا يملك تغييرَ حرفٍ منها.
--
-- وهذا يناقض القاعدة التي بُني عليها المشروع كلُّه. فتُوسَّع الكتابة إلى
-- **مدير المغسلة في مغسلته** — بالمُسنَد نفسه الذي تستعمله قوالبُ الطلبات:
-- `branch_manager` بـ`laundry_id` مطابق.
--
-- **ولا تُوسَّع أبعد من ذلك.** خدمةُ العملاء تعالج الشكاوى ولا تُعدّل قواعدَها:
-- من يملك تمديد مهلة التأكيد يملك إغلاق ما يشاء بالصمت.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- «أنا مديرُ هذه المغسلة»
-- ─────────────────────────────────────────────────────────────────────────
-- دالّةٌ واحدة بدل تكرار `exists (select … from user_roles …)` في ستّ سياسات:
-- المُسنَدُ المكرَّر يُصحَّح في موضعٍ ويُنسى في خمسة.
create or replace function auth_manages_laundry(p_laundry uuid)
returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select auth_is_super_admin()
      or exists (
        select 1 from user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role = 'branch_manager'
          and ur.laundry_id = p_laundry
      );
$$;

comment on function auth_manages_laundry(uuid) is
  'مالكُ المنصّة أو مديرُ هذه المغسلة — ومن دونهما لا يُعدّل قاعدةَ عمل.';

-- ─────────────────────────────────────────────────────────────────────────
-- السياسات
-- ─────────────────────────────────────────────────────────────────────────
drop policy if exists complaint_settings_write on complaint_settings;
create policy complaint_settings_write on complaint_settings
  for all using (auth_manages_laundry(laundry_id))
  with check (auth_manages_laundry(laundry_id));

drop policy if exists complaint_types_write on complaint_types;
create policy complaint_types_write on complaint_types
  for all using (auth_manages_laundry(laundry_id))
  with check (auth_manages_laundry(laundry_id));

drop policy if exists complaint_templates_write on complaint_templates;
create policy complaint_templates_write on complaint_templates
  for all using (auth_manages_laundry(laundry_id))
  with check (auth_manages_laundry(laundry_id));

-- ─────────────────────────────────────────────────────────────────────────
-- والصلاحيات تتبع السياسات
-- ─────────────────────────────────────────────────────────────────────────
-- **سياسةٌ بلا منحٍ لا تعمل.** كانت الكتابة مسحوبةً من `authenticated` سحبًا
-- صريحًا، فسياسةٌ سخيّةٌ فوقها لا تُغيّر شيئًا — والخطأُ يظهر «صفر صفوف»
-- لا رسالةَ منعٍ مفهومة.
--
-- ويبقى الزائرُ ممنوعًا: RLS حارسٌ أوّل، والمنعُ بالصلاحية حارسٌ ثانٍ خلفه.
grant insert, update, delete on
  complaint_settings, complaint_types, complaint_templates to authenticated;

revoke insert, update, delete, truncate on
  complaint_settings, complaint_types, complaint_templates from anon;

revoke execute on function auth_manages_laundry(uuid) from public, anon;
grant execute on function auth_manages_laundry(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- ونوعٌ يُعطَّل ولا يُحذف
-- ─────────────────────────────────────────────────────────────────────────
-- **حذفُ نوعٍ يفقد معناه من كلّ شكوى قديمةٍ تشير إليه.** والمفتاح الأجنبيّ
-- يمنع الحذف بخطأٍ خامٍ من Postgres لا يفهمه مستخدم؛ فيُترجَم هنا إلى جملةٍ
-- تقول ما يجب أن يُفعل بدلًا منه.
create or replace function guard_complaint_type_delete()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if exists (select 1 from complaints where type_id = old.id) then
    raise exception
      'هذا النوع مستعمَلٌ في شكاوى سابقة — عطّله بدل حذفه كي تبقى لها معناها'
      using errcode = 'check_violation';
  end if;
  return old;
end;
$$;

create trigger t_complaint_types_guard_delete
  before delete on complaint_types
  for each row execute function guard_complaint_type_delete();

revoke execute on function guard_complaint_type_delete()
  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- ورمزُ النوع لا يتبدّل تحت شكوى قائمة
-- ─────────────────────────────────────────────────────────────────────────
-- `code` هو ما يُجمَّع عليه في التقارير، وتبديلُه على نوعٍ استُعمل يجعل
-- تقريرَ الشهر الماضي يقول شيئًا غير الذي وقع. والاسمُ المعروض (`label_ar`)
-- يُعدَّل بحرّيّة: صياغةٌ تُحسَّن لا هُويّةٌ تُبدَّل.
create or replace function guard_complaint_type_update()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if auth_is_service_context() then
    return new;
  end if;
  if new.laundry_id is distinct from old.laundry_id then
    raise exception 'لا يُنقل نوعٌ من مغسلةٍ إلى أخرى'
      using errcode = 'insufficient_privilege';
  end if;
  if new.code is distinct from old.code
     and exists (select 1 from complaints where type_id = old.id) then
    raise exception
      'الرمز يُجمَّع عليه في التقارير — لا يُبدَّل على نوعٍ استُعمل. عدّل الاسم المعروض.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger t_complaint_types_guard_update
  before update on complaint_types
  for each row execute function guard_complaint_type_update();

revoke execute on function guard_complaint_type_update()
  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- ولا مغسلةَ تُكتب في صفِّ مغسلةٍ أخرى
-- ─────────────────────────────────────────────────────────────────────────
-- السياسةُ تحرس الصفَّ بمعرّف مغسلته، لكنّ الإدراجَ يقبل ما يُرسَل. ومديرٌ
-- يُدرج قالبًا بمعرّف مغسلةٍ لا يديرها ترفضه `with check` — أمّا **التحديث
-- الذي ينقل الصفَّ** فيمرّ إن كان يملك الطرفين. فيُمنع النقلُ صراحةً.
create or replace function guard_laundry_scoped_row()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  if auth_is_service_context() then
    return new;
  end if;
  if new.laundry_id is distinct from old.laundry_id then
    raise exception 'لا يُنقل صفٌّ من مغسلةٍ إلى أخرى'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger t_complaint_templates_guard_scope
  before update on complaint_templates
  for each row execute function guard_laundry_scoped_row();

revoke execute on function guard_laundry_scoped_row()
  from public, anon, authenticated;
