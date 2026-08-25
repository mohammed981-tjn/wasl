import '../models/enums.dart';
import '../models/models.dart';
import 'supabase_service.dart';

/// ملخّص تشغيل اليوم — الأرقام التي تفتح عليها لوحة الإدارة.
class TodayOperations {
  const TodayOperations({
    required this.byStatus,
    required this.revenue,
    required this.ordersToday,
    required this.lateCount,
  });

  final Map<OrderStatus, int> byStatus;
  final double revenue;
  final int ordersToday;
  final int lateCount;

  int countIn(Set<OrderStatus> statuses) =>
      statuses.fold(0, (sum, s) => sum + (byStatus[s] ?? 0));

  int get insideLaundry =>
      countIn(OrderStatus.values.where((s) => s.isInsideLaundry).toSet());

  /// متوسّط قيمة الطلب. الحارس على القسمة ليس تزيُّدًا: أوّل يومٍ بلا طلبات
  /// يعطي `NaN` فتظهر على الشاشة كما هي.
  double get averageOrderValue =>
      ordersToday == 0 ? 0 : revenue / ordersToday;
}

class OrdersService {
  const OrdersService();

  static const _selection = '''
    *,
    profiles!orders_customer_id_fkey(full_name, phone),
    branches!orders_branch_id_fkey(name_ar),
    order_items(*)
  ''';

  /// طلبات اليوم في فرع. الترشيح بالفرع صريحٌ هنا **للسرعة لا للأمن** —
  /// سياسة `orders_read` ترشّح على أي حال، لكن جلب طلبات كل الفروع ثم رميها
  /// في التطبيق يدفع ثمن نقلها.
  Future<TodayOperations> todayOperations(String branchId) async {
    final since = DateTime.now().copyWith(
      hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);

    final rows = await Db.client
        .from('orders')
        .select('status, total, promised_ready_at, created_at')
        .eq('branch_id', branchId)
        .gte('created_at', since.toUtc().toIso8601String());

    final byStatus = <OrderStatus, int>{};
    var revenue = 0.0;
    var late = 0;
    final now = DateTime.now();

    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final status = OrderStatus.fromWire(r['status'] as String);
      byStatus[status] = (byStatus[status] ?? 0) + 1;

      // الإيراد لا يشمل الملغى ولا المسترَدّ — وإلا صار رقمًا يسرّ ولا يصدق.
      if (status != OrderStatus.cancelled &&
          status != OrderStatus.refunded &&
          status != OrderStatus.draft) {
        final t = r['total'];
        revenue += t is num ? t.toDouble() : double.tryParse('$t') ?? 0;
      }

      final promised = r['promised_ready_at'];
      if (promised != null && !status.isTerminal &&
          status.index < OrderStatus.ready.index) {
        final due = DateTime.tryParse(promised as String)?.toLocal();
        if (due != null && now.isAfter(due)) late++;
      }
    }

    final counted = byStatus.entries
        .where((e) => e.key != OrderStatus.draft)
        .fold(0, (s, e) => s + e.value);

    return TodayOperations(
      byStatus: byStatus,
      revenue: revenue,
      ordersToday: counted,
      lateCount: late,
    );
  }

  /// قائمة الطلبات مرشَّحةً.
  ///
  /// [search] يقبل رقم الطلب أو الباركود. **ولا يبحث في اسم العميل**: البحث في
  /// جدولٍ مضموم يجبر Postgres على مسحه كاملًا قبل أن ترشّح RLS، وهو أبطأ ممّا
  /// يبدو. والرقم هو ما يُقال في الهاتف على أي حال.
  Future<List<LaundryOrder>> list(
    String branchId, {
    Set<OrderStatus>? statuses,
    String? search,
    int limit = 60,
  }) async {
    var q = Db.client.from('orders').select(_selection).eq('branch_id', branchId);

    if (statuses != null && statuses.isNotEmpty) {
      q = q.inFilter('status', statuses.map((s) => s.wireName).toList());
    }

    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      final asNumber = int.tryParse(term.replaceAll(RegExp(r'[^0-9]'), ''));
      if (asNumber != null) {
        q = q.eq('order_number', asNumber);
      } else {
        q = q.eq('barcode', term);
      }
    }

    final rows = await q.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((e) => LaundryOrder.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<LaundryOrder> byId(String orderId) async {
    final row =
        await Db.client.from('orders').select(_selection).eq('id', orderId).single();
    return LaundryOrder.fromMap(row);
  }

  /// سجلّ أحداث الطلب — «كيف وصل إلى هنا؟».
  Future<List<OrderEvent>> events(String orderId) async {
    final rows = await Db.client
        .from('order_events')
        .select('*, profiles!order_events_actor_id_fkey(full_name)')
        .eq('order_id', orderId)
        .order('created_at');
    return (rows as List)
        .map((e) => OrderEvent.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// نقلُ الطلب إلى حالةٍ تالية.
  ///
  /// **لا فحصَ هنا لما هو مسموح.** محفّز `enforce_order_transition` في القاعدة
  /// يعرف الانتقالات ومن يملكها، ويرفض ما عداها ويكتب السجلّ في المعاملة
  /// نفسها. وفحصٌ إضافيّ في التطبيق يصير مرجعًا ثانيًا ينحرف عن الأوّل.
  Future<void> advance(String orderId, OrderStatus to) async {
    await Db.client
        .from('orders')
        .update({'status': to.wireName})
        .eq('id', orderId);
  }

  /// الانتقالات المسموحة من حالةٍ ما — تُقرأ من الجدول لا من ثابتٍ في الشيفرة،
  /// فتعديل مسار التشغيل صفٌّ يُضاف ولا يحتاج إصدارًا.
  Future<List<OrderStatus>> allowedNext(OrderStatus from) async {
    final rows = await Db.client
        .from('order_transitions')
        .select('to_status')
        .eq('from_status', from.wireName);
    return (rows as List)
        .map((e) => OrderStatus.fromWire(e['to_status'] as String))
        .toList();
  }
}
