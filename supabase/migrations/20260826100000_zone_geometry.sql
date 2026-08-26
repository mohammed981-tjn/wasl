-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | مناطق التوصيل: رسمُها وقراءتُها
-- ═══════════════════════════════════════════════════════════════════════════
--
-- `delivery_zones.area` عمود `geography(polygon)`، وبينه وبين خريطةٍ في تطبيق
-- طريقان لا بدّ منهما:
--
--   ← **الكتابة**: التطبيق يملك نقاطًا، والقاعدة تريد مضلَّعًا. وبناؤه في
--     التطبيق بنصٍّ (`POLYGON((...))`) يعني أن **صحّته لا تُفحص**: مضلَّعٌ
--     يقطع نفسه يُقبل، ثم يُعطي `ST_Contains` نتائج لا معنى لها — فتُحسب
--     رسومٌ خاطئة ولا يظهر خطأٌ في أيّ سجلّ.
--
--   → **القراءة**: عمود geography يصل عبر PostgREST نصًّا سداسيًّا (EWKB) لا
--     نقاطًا. وهو الفخّ نفسه الذي أعطى العميلَ موقعًا عند خطّ الاستواء —
--     وحُلَّ هناك بعمودين مشتقّين، ويُحلّ هنا بـGeoJSON.

set search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────
-- القراءة: منطقةٌ يقرؤها التطبيق
-- ─────────────────────────────────────────────────────────────────────────
-- `security_invoker` لا `definer`: العرض نافذةٌ على الجدول، فيجب أن يرى
-- الناظرُ منه ما تسمح به سياساتُه هو — لا ما يسمح به من أنشأ العرض.
create or replace view delivery_zones_map
with (security_invoker = true) as
select
  z.id,
  z.branch_id,
  z.name_ar,
  z.pickup_fee,
  z.delivery_fee,
  z.combined_fee,
  z.priority,
  z.is_active,
  st_asgeojson(z.area::geometry)::jsonb as area_geojson,
  st_y(st_centroid(z.area::geometry)) as center_lat,
  st_x(st_centroid(z.area::geometry)) as center_lng,
  -- مساحةٌ بالكيلومتر المربّع: رقمٌ يُقرأ عند المراجعة، ومنطقةٌ بمساحة
  -- ٩٠٠ كم² غالبًا خطأُ رسمٍ لا قرارُ إدارة.
  round((st_area(z.area) / 1000000)::numeric, 2) as area_km2
from delivery_zones z;

grant select on delivery_zones_map to authenticated, anon;

comment on view delivery_zones_map is
  'المناطق بصيغة GeoJSON. عمود geography يصل نصًّا سداسيًّا لا نقاطًا — والقراءة منه مباشرةً لا تُرسم.';

-- ─────────────────────────────────────────────────────────────────────────
-- الكتابة: من نقاطٍ إلى مضلَّعٍ صحيح
-- ─────────────────────────────────────────────────────────────────────────
-- `p_points`: مصفوفة JSON من `{"lat": .., "lng": ..}` بترتيب الرسم.
--
-- **الحلقة تُغلق هنا لا في التطبيق**: PostGIS يشترط أن تكون النقطة الأخيرة
-- هي الأولى، ونسيانُها في شاشةٍ يعني رسالة خطأٍ إنجليزيّةً غامضة أمام مدير
-- فرع. فتُغلق في القاعدة صامتةً، ويُرفض ما لا يصلح **برسالةٍ تُقرأ**.
create or replace function save_delivery_zone(
  p_branch    uuid,
  p_name      text,
  p_points    jsonb,
  p_pickup_fee   numeric default 0,
  p_delivery_fee numeric default 0,
  p_combined_fee numeric default null,
  p_priority  int default 0,
  p_active    boolean default true,
  p_id        uuid default null
) returns uuid
language plpgsql security invoker set search_path = public, extensions
as $$
declare
  v_points jsonb := p_points;
  v_first  jsonb;
  v_last   jsonb;
  v_line   geometry;
  v_poly   geometry;
  v_id     uuid;
  v_count  int;
begin
  if v_points is null or jsonb_typeof(v_points) <> 'array' then
    raise exception 'لا نقاط للمنطقة' using errcode = 'check_violation';
  end if;

  v_count := jsonb_array_length(v_points);
  if v_count < 3 then
    raise exception 'المنطقة تحتاج ثلاث نقاطٍ على الأقل (وصلت %)', v_count
      using errcode = 'check_violation';
  end if;

  v_first := v_points -> 0;
  v_last  := v_points -> (v_count - 1);
  if (v_first ->> 'lat') is distinct from (v_last ->> 'lat')
     or (v_first ->> 'lng') is distinct from (v_last ->> 'lng') then
    v_points := v_points || jsonb_build_array(v_first);
  end if;

  select st_makeline(array_agg(
           st_setsrid(st_makepoint((p ->> 'lng')::float8, (p ->> 'lat')::float8), 4326)
           order by ord))
    into v_line
  from jsonb_array_elements(v_points) with ordinality as t(p, ord);

  v_poly := st_makepolygon(v_line);

  -- مضلَّعٌ يقطع نفسه يُقبل في العمود ويُفسد كلَّ حسابٍ بعده بصمت.
  if not st_isvalid(v_poly) then
    raise exception 'شكل المنطقة غير صالح — تقاطعت حدودُها. أعد الرسم.'
      using errcode = 'check_violation';
  end if;

  if p_id is null then
    insert into delivery_zones
      (branch_id, name_ar, area, pickup_fee, delivery_fee, combined_fee,
       priority, is_active)
    values (p_branch, p_name, v_poly::geography, p_pickup_fee, p_delivery_fee,
            p_combined_fee, p_priority, p_active)
    returning id into v_id;
  else
    update delivery_zones set
      name_ar = p_name,
      area = v_poly::geography,
      pickup_fee = p_pickup_fee,
      delivery_fee = p_delivery_fee,
      combined_fee = p_combined_fee,
      priority = p_priority,
      is_active = p_active
    where id = p_id and branch_id = p_branch
    returning id into v_id;

    -- صفرُ صفوفٍ لا يعني نجاحًا: إمّا منطقةٌ ليست لهذا الفرع أو منعتها
    -- السياسة. وسكوتُ التحديث عن ذلك هو ما يجعل «حُفظ» كذبةً على الشاشة.
    if v_id is null then
      raise exception 'لا تملك تعديل هذه المنطقة' using errcode = 'insufficient_privilege';
    end if;
  end if;

  return v_id;
end;
$$;

revoke execute on function save_delivery_zone(uuid, text, jsonb, numeric, numeric,
  numeric, int, boolean, uuid) from public, anon;
grant execute on function save_delivery_zone(uuid, text, jsonb, numeric, numeric,
  numeric, int, boolean, uuid) to authenticated;
