import '../models/models.dart';
import 'orders_service.dart';
import 'supabase_service.dart';

/// إعدادات التوصيل وتسعيره.
class DeliveryService {
  const DeliveryService();

  Future<DeliverySettings?> settings(String branchId) async {
    final row = await Db.client
        .from('delivery_settings')
        .select()
        .eq('branch_id', branchId)
        .maybeSingle();
    return row == null ? null : DeliverySettings.fromMap(row);
  }

  Future<DeliverySettings> save(DeliverySettings s) async {
    final row = await Db.client
        .from('delivery_settings')
        .upsert(s.toUpsert())
        .select()
        .single();
    return DeliverySettings.fromMap(row);
  }

  Future<List<DistanceTier>> tiers(String branchId) async {
    final rows = await Db.client
        .from('delivery_distance_tiers')
        .select()
        .eq('branch_id', branchId)
        .order('from_km');
    return (rows as List)
        .map((e) => DistanceTier.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// إضافة شريحة. القاعدة ترفض التداخل بقيد استبعاد — فالخطأ يعود منها
  /// مترجَمًا، ولا يُفحص هنا فحصًا ثانيًا ينحرف.
  Future<void> addTier({
    required String branchId,
    required double fromKm,
    required double toKm,
    required double pickupFee,
    required double deliveryFee,
  }) async {
    await Db.client.from('delivery_distance_tiers').insert({
      'branch_id': branchId,
      'from_km': fromKm,
      'to_km': toKm,
      'pickup_fee': pickupFee,
      'delivery_fee': deliveryFee,
    });
  }

  Future<void> removeTier(String tierId) async {
    await Db.client.from('delivery_distance_tiers').delete().eq('id', tierId);
  }

  /// معاينة الرسم على نقطةٍ ومبلغ — نفس الدالّة التي يسألها تطبيق العميل.
  ///
  /// وجودها في لوحة الإدارة مقصود: من يضبط شرائح المسافة يجب أن يرى أثر ضبطه
  /// **قبل** أن يكتشفه عميل.
  Future<DeliveryQuote> quote({
    required String branchId,
    required double lat,
    required double lng,
    required double subtotal,
    bool wantsPickup = true,
    bool wantsDelivery = true,
  }) async {
    final rows = await Db.client.rpc('quote_delivery_fee', params: {
      'p_branch': branchId,
      'p_point': 'SRID=4326;POINT($lng $lat)',
      'p_subtotal': subtotal,
      'p_wants_pickup': wantsPickup,
      'p_wants_delivery': wantsDelivery,
    });
    final list = (rows as List);
    if (list.isEmpty) {
      return const DeliveryQuote(fee: 0, serviceable: false, reason: 'لا نتيجة');
    }
    return DeliveryQuote.fromMap(list.first as Map<String, dynamic>);
  }

  /// أقرب موعد استلامٍ متاح — الجواب المباشر لسؤال العميل.
  Future<List<BookingSlot>> slots({
    required String branchId,
    String kind = 'pickup',
    DateTime? from,
    int? days,
    double pieceLoad = 0,
  }) async {
    final rows = await Db.client.rpc('available_slots', params: {
      'p_branch': branchId,
      'p_kind': kind,
      if (from != null) 'p_from': from.toIso8601String().split('T').first,
      if (days != null) 'p_days': days,
      'p_piece_load': pieceLoad,
    });
    return (rows as List)
        .map((e) => BookingSlot.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}

/// إعدادات السائقين ورمز التسليم — يقرؤها التطبيق وتكتبها الإدارة.
extension DriverSettingsAdmin on DeliveryService {
  Future<DriverSettings?> driverSettings(String branchId) async {
    final rows = await Db.client
        .from('driver_settings')
        .select()
        .eq('branch_id', branchId)
        .limit(1);
    final list = rows as List;
    return list.isEmpty
        ? null
        : DriverSettings.fromMap(list.first as Map<String, dynamic>);
  }

  Future<void> saveDriverSettings(DriverSettings s) async {
    await Db.client
        .from('driver_settings')
        .upsert(s.toMap(), onConflict: 'branch_id');
  }
}

/// الخرائط: مواقع السائقين ومناطق التوصيل.
extension MapsService on DeliveryService {
  /// مواقع سائقي الفرع، بأسمائهم وحِملهم.
  ///
  /// **من لا موقع له لا يُعرض على خريطة** — ويُعرف من قائمة السائقين أنه غائب.
  Future<List<DriverPin>> driverPins(String branchId) async {
    final drivers = await const OrdersService().branchDrivers(branchId);
    if (drivers.isEmpty) return const [];

    final rows = await Db.client
        .from('driver_locations')
        .select()
        .inFilter('driver_id', drivers.map((d) => d.id).toList());

    final meta = {for (final d in drivers) d.id: d};
    return (rows as List).map((e) {
      final pin = DriverPin.fromMap(e as Map<String, dynamic>);
      final d = meta[pin.driverId];
      return pin.withMeta(name: d?.name, activeJobs: d?.activeJobs);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<DeliveryZone>> zones(String branchId) async {
    final rows = await Db.client
        .from('delivery_zones_map')
        .select()
        .eq('branch_id', branchId)
        .order('priority', ascending: false);
    return (rows as List)
        .map((e) => DeliveryZone.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// حفظُ منطقة. الحلقةُ تُغلق والصحّةُ تُفحص في القاعدة لا هنا.
  Future<String> saveZone({
    String? id,
    required String branchId,
    required String nameAr,
    required List<(double, double)> ring,
    double pickupFee = 0,
    double deliveryFee = 0,
    double? combinedFee,
    int priority = 0,
    bool isActive = true,
  }) async {
    final res = await Db.client.rpc('save_delivery_zone', params: {
      'p_branch': branchId,
      'p_name': nameAr,
      'p_points': [
        for (final (lat, lng) in ring) {'lat': lat, 'lng': lng},
      ],
      'p_pickup_fee': pickupFee,
      'p_delivery_fee': deliveryFee,
      'p_combined_fee': combinedFee,
      'p_priority': priority,
      'p_active': isActive,
      'p_id': id,
    });
    return res as String;
  }

  Future<void> deleteZone(String id) async {
    await Db.client.from('delivery_zones').delete().eq('id', id);
  }
}
