import 'supabase_service.dart';

double _num(dynamic v) => switch (v) {
      null => 0,
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

int _int(dynamic v) => switch (v) {
      null => 0,
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

class ReportSummary {
  const ReportSummary({
    required this.ordersCount,
    required this.revenue,
    required this.avgOrderValue,
    required this.deliveryRevenue,
    required this.discountsGiven,
    required this.cancelledCount,
    required this.lateCount,
    required this.piecesProcessed,
  });

  final int ordersCount;
  final double revenue;
  final double avgOrderValue;
  final double deliveryRevenue;
  final double discountsGiven;
  final int cancelledCount;
  final int lateCount;
  final double piecesProcessed;

  /// نسبة الإلغاء — أهمّ مؤشّرٍ تشغيليّ بعد الإيراد، وأكثرُه إهمالًا.
  double get cancelRate =>
      ordersCount == 0 ? 0 : cancelledCount / ordersCount * 100;

  static const empty = ReportSummary(
    ordersCount: 0, revenue: 0, avgOrderValue: 0, deliveryRevenue: 0,
    discountsGiven: 0, cancelledCount: 0, lateCount: 0, piecesProcessed: 0,
  );

  factory ReportSummary.fromMap(Map<String, dynamic> m) => ReportSummary(
        ordersCount: _int(m['orders_count']),
        revenue: _num(m['revenue']),
        avgOrderValue: _num(m['avg_order_value']),
        deliveryRevenue: _num(m['delivery_revenue']),
        discountsGiven: _num(m['discounts_given']),
        cancelledCount: _int(m['cancelled_count']),
        lateCount: _int(m['late_count']),
        piecesProcessed: _num(m['pieces_processed']),
      );
}

class DailyPoint {
  const DailyPoint({
    required this.day,
    required this.ordersCount,
    required this.revenue,
  });

  final DateTime day;
  final int ordersCount;
  final double revenue;

  factory DailyPoint.fromMap(Map<String, dynamic> m) => DailyPoint(
        day: DateTime.parse(m['day'] as String),
        ordersCount: _int(m['orders_count']),
        revenue: _num(m['revenue']),
      );
}

class ServiceMixRow {
  const ServiceMixRow({
    required this.serviceName,
    required this.unit,
    required this.ordersCount,
    required this.quantity,
    required this.revenue,
  });

  final String serviceName;
  final String unit;
  final int ordersCount;
  final double quantity;
  final double revenue;

  factory ServiceMixRow.fromMap(Map<String, dynamic> m) => ServiceMixRow(
        serviceName: m['service_name'] as String,
        unit: m['unit'] as String? ?? 'piece',
        ordersCount: _int(m['orders_count']),
        quantity: _num(m['quantity']),
        revenue: _num(m['revenue']),
      );
}

class StageDuration {
  const StageDuration({
    required this.stage,
    required this.samples,
    required this.avgHours,
    required this.medianHours,
    required this.maxHours,
  });

  final String stage;
  final int samples;
  final double avgHours;

  /// الوسيط مع المتوسّط عمدًا: طلبٌ نُسي في آلةٍ أسبوعًا يرفع الثاني ولا يمسّ
  /// الأول — واختلافُهما الكبير هو نفسه الإشارة.
  final double medianHours;
  final double maxHours;

  bool get isSkewed => medianHours > 0 && avgHours > medianHours * 2;

  factory StageDuration.fromMap(Map<String, dynamic> m) => StageDuration(
        stage: m['stage'] as String,
        samples: _int(m['samples']),
        avgHours: _num(m['avg_hours']),
        medianHours: _num(m['median_hours']),
        maxHours: _num(m['max_hours']),
      );
}

/// التقارير — كلّها تُحسب في القاعدة.
///
/// **ولا واحدة منها تُجمَّع هنا**: تقريرُ شهرٍ يمسح آلاف الطلبات، وجلبُها إلى
/// الجهاز ليجمعها يدفع ثمن نقلها ويعطي رقمًا قد يختلف بين جهازٍ وآخر. والدوالّ
/// `security invoker`، فسياسات RLS ترشّح بالفعل: تقريرُ مديرِ فرعٍ يشمل فرعه
/// وحده دون شرطٍ نكتبه.
class ReportsService {
  const ReportsService();

  String _d(DateTime d) => d.toIso8601String().split('T').first;

  Future<ReportSummary> summary(String branchId, DateTime from, DateTime to) async {
    final rows = await Db.client.rpc('report_summary',
        params: {'p_branch': branchId, 'p_from': _d(from), 'p_to': _d(to)});
    final list = rows as List;
    return list.isEmpty
        ? ReportSummary.empty
        : ReportSummary.fromMap(list.first as Map<String, dynamic>);
  }

  Future<List<DailyPoint>> daily(String branchId, DateTime from, DateTime to) async {
    final rows = await Db.client.rpc('report_daily',
        params: {'p_branch': branchId, 'p_from': _d(from), 'p_to': _d(to)});
    return (rows as List)
        .map((e) => DailyPoint.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ServiceMixRow>> serviceMix(
      String branchId, DateTime from, DateTime to) async {
    final rows = await Db.client.rpc('report_service_mix',
        params: {'p_branch': branchId, 'p_from': _d(from), 'p_to': _d(to)});
    return (rows as List)
        .map((e) => ServiceMixRow.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StageDuration>> stageDurations(
      String branchId, DateTime from, DateTime to) async {
    final rows = await Db.client.rpc('report_stage_durations',
        params: {'p_branch': branchId, 'p_from': _d(from), 'p_to': _d(to)});
    return (rows as List)
        .map((e) => StageDuration.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}
