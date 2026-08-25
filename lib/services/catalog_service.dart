import '../models/models.dart';
import 'supabase_service.dart';

/// كتالوج الخدمات والأسعار.
///
/// **الوعد الذي يحقّقه هذا الملفّ**: لا سعر في شيفرة التطبيق. كلُّ ما يُعرض
/// يأتي من `services`، وكلُّ تعديلٍ يذهب إليها — فتغييرُ سعر الثوب من ثمانية
/// إلى تسعة لا يحتاج إصدارًا على المتجر.
class CatalogService {
  const CatalogService();

  Future<List<ServiceCategory>> categories(String laundryId) async {
    final rows = await Db.client
        .from('service_categories')
        .select()
        .eq('laundry_id', laundryId)
        .order('sort_order');
    return (rows as List)
        .map((e) => ServiceCategory.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LaundryService>> services(
    String laundryId, {
    bool activeOnly = false,
  }) async {
    var q = Db.client.from('services').select().eq('laundry_id', laundryId);
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('sort_order').order('name_ar');
    return (rows as List)
        .map((e) => LaundryService.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<LaundryService> create(LaundryService s) async {
    final row = await Db.client
        .from('services')
        .insert(s.toInsert())
        .select()
        .single();
    return LaundryService.fromMap(row);
  }

  Future<LaundryService> update(LaundryService s) async {
    final row = await Db.client
        .from('services')
        .update(s.toInsert())
        .eq('id', s.id)
        .select()
        .single();
    return LaundryService.fromMap(row);
  }

  /// الإيقاف لا الحذف.
  ///
  /// حذفُ خدمةٍ يقطع صلتها ببنود طلباتٍ ماضية (`on delete set null`)، فيبقى
  /// اسم البند وسعره في الفاتورة — وهو الصواب — لكنّ التقارير التي تجمّع
  /// **بالخدمة** تفقد صفوفها. والإيقاف يحفظ الاثنين.
  Future<void> setActive(String serviceId, bool active) async {
    await Db.client
        .from('services')
        .update({'is_active': active})
        .eq('id', serviceId);
  }

  /// السعر النافذ في فرعٍ بعينه — تجاوزُ الفرع إن وُجد، وإلا سعرُ المغسلة.
  ///
  /// **تُسأل القاعدة ولا يُحسب هنا**: القاعدةُ نفسها تستعمل هذه الدالّة عند
  /// إنشاء الطلب، فلو حسبها التطبيق لصار في النظام مرجعان، وأوّل اختلافٍ
  /// بينهما شكوى.
  Future<double?> effectivePrice({
    required String branchId,
    required String serviceId,
  }) async {
    final v = await Db.client.rpc('effective_service_price', params: {
      'p_branch': branchId,
      'p_service': serviceId,
    });
    if (v == null) return null;
    return v is num ? v.toDouble() : double.tryParse(v.toString());
  }
}
