-- ═══════════════════════════════════════════════════════════════════════════
-- وصل | فهارس المفاتيح الأجنبية
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Postgres يفهرس المفتاح الأساسيّ والقيدَ الفريد تلقائيًّا، **ولا يفهرس المفتاح
-- الأجنبيّ**. وغيابُ الفهرس هنا لا يُفسد نتيجةً فيُمسك في اختبار — يُبطئ بصمت:
--
--   • كل ربطٍ عبر المفتاح يصير مسحًا كاملًا للجدول
--   • وحذفُ الأب أو تحديثُه يمسح الابن كاملًا للتحقّق من القيد — فحذفُ مغسلةٍ
--     من عشرة صفوف يمسح مليون طلب
--
-- ويظهر الأثر بعد أشهر، حين يكبر الجدول، فيُنسب إلى «Supabase بطيء».

set search_path = public, extensions;

create index on branch_services      (service_id);
create index on coupon_redemptions   (order_id);
create index on coupons              (branch_id);
create index on coupons              (created_by);
create index on loyalty_transactions (laundry_id);
create index on notifications        (template_id);
create index on order_events         (actor_id);
create index on order_garments       (order_item_id);
create index on order_items          (service_id);
create index on order_proofs         (driver_id);
create index on orders               (cancelled_by);
create index on orders               (coupon_id);
create index on orders               (delivery_address_id);
create index on orders               (laundry_id);
create index on orders               (pickup_address_id);
create index on payments             (provider_id);
create index on refunds              (approved_by);
create index on refunds              (order_id);
create index on refunds              (requested_by);
create index on user_roles           (granted_by);
create index on user_roles           (laundry_id);
create index on zone_service_rules   (service_id);
