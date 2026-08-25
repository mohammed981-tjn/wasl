import '../models/enums.dart';
import '../models/models.dart';
import 'supabase_service.dart';

/// عمليات السائق.
class DriverService {
  const DriverService();

  static const _activePickup = ['pickup_assigned', 'pickup_en_route'];
  static const _activeDelivery = ['delivery_assigned', 'out_for_delivery'];

  static const _select = '*, profiles!orders_customer_id_fkey(full_name, phone), '
      'branches!orders_branch_id_fkey(name_ar), '
      'pickup_address:addresses!orders_pickup_address_id_fkey(*), '
      'delivery_address:addresses!orders_delivery_address_id_fkey(*)';

  /// مهامّ السائق المفتوحة.
  ///
  /// **استعلامٌ واحدٌ للاستلام والتسليم معًا**: السائق لا يعمل في قائمتين،
  /// بل في طريقٍ واحدٍ فيه محطّات — فالترتيب بالموعد لا بالنوع.
  Future<List<DriverJob>> myJobs(String driverId) async {
    final rows = await Db.client.from('orders').select(_select).or(
        'and(pickup_driver_id.eq.$driverId,status.in.(${_activePickup.join(',')})),'
        'and(delivery_driver_id.eq.$driverId,status.in.(${_activeDelivery.join(',')}))');

    final jobs = (rows as List)
        .map((e) => DriverJob.fromMap(e as Map<String, dynamic>, driverId))
        .toList();

    // الترتيب في التطبيق لا في القاعدة: المفتاح `pickup_slot_start` للاستلام
    // و`delivery_slot_start` للتسليم — عمودان مختلفان لصفوفٍ في قائمةٍ واحدة.
    jobs.sort((a, b) {
      final x = a.slotStart, y = b.slotStart;
      if (x == null && y == null) return a.order.orderNumber.compareTo(b.order.orderNumber);
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return jobs;
  }

  /// ما أنجزه اليوم — كي يرى عملَه لا قائمةً تفرغ فتبدو كأن شيئًا لم يكن.
  Future<List<LaundryOrder>> doneToday(String driverId) async {
    final since = DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final rows = await Db.client
        .from('orders')
        .select('*, profiles!orders_customer_id_fkey(full_name), '
            'branches!orders_branch_id_fkey(name_ar)')
        .or('pickup_driver_id.eq.$driverId,delivery_driver_id.eq.$driverId')
        .inFilter('status', ['picked_up', 'delivered'])
        .gte('updated_at', since.toIso8601String())
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((e) => LaundryOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<DriverJob?> job(String orderId, String driverId) async {
    final rows =
        await Db.client.from('orders').select(_select).eq('id', orderId).limit(1);
    final list = rows as List;
    return list.isEmpty
        ? null
        : DriverJob.fromMap(list.first as Map<String, dynamic>, driverId);
  }

  /// «انطلقت» و«خرجت للتوصيل» — انتقالٌ بلا إثبات.
  Future<void> advance(String orderId, OrderStatus to) async {
    await Db.client
        .from('orders')
        .update({'status': to.wireName})
        .eq('id', orderId);
  }

  /// إتمام الاستلام: الإثبات والانتقال في نداءٍ واحد لا في نداءين.
  Future<void> completePickup(
    String orderId, {
    double? lat,
    double? lng,
    String? note,
  }) async {
    await Db.client.rpc('complete_pickup', params: {
      'p_order': orderId,
      'p_lat': lat,
      'p_lng': lng,
      'p_note': note,
    });
  }

  /// إتمام التسليم. يعيد سببَ الرفض إن رُفض — ولا يرفع استثناءً على رمزٍ خاطئ.
  ///
  /// **الرمز الخاطئ ليس عطلًا بل جوابًا**: رفعُه استثناءً يتراجع بعدّاد
  /// المحاولات في القاعدة، فيصير السقفُ الذي يحمي من التخمين وهمًا.
  Future<String?> completeDelivery(
    String orderId, {
    String? code,
    double? lat,
    double? lng,
    String? note,
  }) async {
    final res = await Db.client.rpc('complete_delivery', params: {
      'p_order': orderId,
      'p_code': code,
      'p_lat': lat,
      'p_lng': lng,
      'p_note': note,
    });
    final map = Map<String, dynamic>.from(res as Map);
    if (map['ok'] == true) return null;
    final left = map['attempts_left'];
    final reason = map['reason'] as String? ?? 'تعذّر التسليم';
    return left is int && left > 0 ? '$reason — بقيت $left محاولة' : reason;
  }

  Future<void> ping({
    required double lat,
    required double lng,
    double? accuracyM,
    bool online = true,
  }) async {
    await Db.client.rpc('ping_driver_location', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_accuracy_m': accuracyM,
      'p_online': online,
    });
  }

  Future<DriverSettings?> settings(String branchId) async {
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
}
