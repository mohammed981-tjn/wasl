import '../models/enums.dart';
import '../models/models.dart';
import 'supabase_service.dart';

/// عمليات موظّف المغسلة.
class LaundryOpsService {
  const LaundryOpsService();

  /// المراحل الداخلية بترتيب خطّ التشغيل — وهي ما يعمل عليه الموظّف.
  static const stages = [
    OrderStatus.atLaundry,
    OrderStatus.sorting,
    OrderStatus.washing,
    OrderStatus.drying,
    OrderStatus.ironing,
    OrderStatus.packaging,
    OrderStatus.ready,
  ];

  /// عددُ الطلبات في كل مرحلة.
  ///
  /// **استعلامٌ واحدٌ لا سبعة**: سبعة نداءاتٍ لسبع مراحل تُبطئ الشاشة التي
  /// تُفتح كل دقيقة في المغسلة.
  Future<Map<OrderStatus, int>> stageCounts(String branchId) async {
    final rows = await Db.client
        .from('orders')
        .select('status')
        .eq('branch_id', branchId)
        .inFilter('status', stages.map((s) => s.wireName).toList());

    final counts = {for (final s in stages) s: 0};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final s = OrderStatus.fromWire(r['status'] as String);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  Future<List<LaundryOrder>> ofStage(String branchId, OrderStatus stage) async {
    final rows = await Db.client
        .from('orders')
        .select('*, profiles!orders_customer_id_fkey(full_name), '
            'branches!orders_branch_id_fkey(name_ar), order_items(*)')
        .eq('branch_id', branchId)
        .eq('status', stage.wireName)
        .order('promised_ready_at', ascending: true, nullsFirst: false);
    return (rows as List)
        .map((e) => LaundryOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// حلُّ باركودٍ ممسوحٍ أو مكتوب.
  Future<BarcodeHit?> resolve(String code) async {
    final rows = await Db.client.rpc('resolve_barcode', params: {'p_code': code});
    final list = rows as List;
    return list.isEmpty
        ? null
        : BarcodeHit.fromMap(list.first as Map<String, dynamic>);
  }

  Future<List<OrderGarment>> garments(String orderId) async {
    final rows = await Db.client
        .from('order_garments')
        .select()
        .eq('order_id', orderId)
        .order('barcode');
    return (rows as List)
        .map((e) => OrderGarment.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// تسجيل قطعة. **الباركود يُولَّد في القاعدة** فلا يُمرَّر من هنا.
  Future<void> addGarment({
    required String orderId,
    required String labelAr,
    String? color,
    String? defectNotes,
  }) async {
    await Db.client.from('order_garments').insert({
      'order_id': orderId,
      'label_ar': labelAr,
      if (color != null && color.trim().isNotEmpty) 'color': color.trim(),
      if (defectNotes != null && defectNotes.trim().isNotEmpty)
        'defect_notes': defectNotes.trim(),
    });
  }

  Future<void> removeGarment(String garmentId) async {
    await Db.client.from('order_garments').delete().eq('id', garmentId);
  }

  Future<void> advance(String orderId, OrderStatus to) async {
    await Db.client
        .from('orders')
        .update({'status': to.wireName})
        .eq('id', orderId);
  }

  Future<List<OrderStatus>> allowedNext(OrderStatus from) async {
    final rows = await Db.client
        .from('order_transitions')
        .select('to_status')
        .eq('from_status', from.wireName);
    return (rows as List)
        .map((e) => OrderStatus.fromWire(e['to_status'] as String))
        .toList();
  }

  Future<LaundryOrder> order(String orderId) async {
    final row = await Db.client
        .from('orders')
        .select('*, profiles!orders_customer_id_fkey(full_name), '
            'branches!orders_branch_id_fkey(name_ar), order_items(*)')
        .eq('id', orderId)
        .single();
    return LaundryOrder.fromMap(row);
  }
}
