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

/// ملخّص التقييم.
class RatingSummary {
  const RatingSummary({
    required this.count,
    required this.avgStars,
    required this.avgDelivery,
    required this.lowCount,
    required this.distribution,
  });

  static const empty = RatingSummary(
      count: 0, avgStars: 0, avgDelivery: 0, lowCount: 0,
      distribution: [0, 0, 0, 0, 0]);

  final int count;
  final double avgStars;
  final double avgDelivery;

  /// عددُ التقييمات دون حدّ الشكوى. **يُعرض بجانب المتوسّط لا تحته**: أربعُ
  /// نجماتٍ ونصف قد تُخفي عشرَ شكاوى تحت مئةِ رضًا.
  final int lowCount;

  /// من نجمةٍ إلى خمس.
  final List<int> distribution;

  factory RatingSummary.fromMap(Map<String, dynamic> m) => RatingSummary(
        count: _asInt(m['ratings_count']),
        avgStars: _asNum(m['avg_stars']),
        avgDelivery: _asNum(m['avg_delivery']),
        lowCount: _asInt(m['low_count']),
        distribution: [
          _asInt(m['stars_1']),
          _asInt(m['stars_2']),
          _asInt(m['stars_3']),
          _asInt(m['stars_4']),
          _asInt(m['stars_5']),
        ],
      );
}

/// تقييمٌ مفرد كما يُعرض للإدارة.
class RatingEntry {
  const RatingEntry({
    required this.orderNumber,
    required this.stars,
    required this.createdAt,
    this.deliveryStars,
    this.tags = const [],
    this.comment,
  });

  final int orderNumber;
  final int stars;
  final int? deliveryStars;
  final List<String> tags;
  final String? comment;
  final DateTime createdAt;

  factory RatingEntry.fromMap(Map<String, dynamic> m) {
    final order = m['orders'];
    return RatingEntry(
      orderNumber: order is Map ? _asInt(order['order_number']) : 0,
      stars: _asInt(m['stars']),
      deliveryStars:
          m['delivery_stars'] == null ? null : _asInt(m['delivery_stars']),
      tags: (m['tags'] as List?)?.cast<String>() ?? const [],
      comment: m['comment'] as String?,
      createdAt:
          DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }
}

int _asInt(dynamic v) => switch (v) {
      null => 0,
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

double _asNum(dynamic v) => switch (v) {
      null => 0,
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

extension RatingsReports on ReportsService {
  Future<RatingSummary> ratings(
      String branchId, DateTime from, DateTime to) async {
    final rows = await Db.client.rpc('rating_summary', params: {
      'p_branch': branchId,
      'p_from': from.toIso8601String().split('T').first,
      'p_to': to.toIso8601String().split('T').first,
    });
    final list = rows as List;
    return list.isEmpty
        ? RatingSummary.empty
        : RatingSummary.fromMap(list.first as Map<String, dynamic>);
  }

  /// آخرُ التقييمات المكتوبة. **الشكاوى أوّلًا**: المتوسّط يُقرأ في ثانية،
  /// وما يُصلَح إنما يُعرف من نصٍّ كتبه عميلٌ غاضب.
  Future<List<RatingEntry>> recentRatings(String branchId,
      {int limit = 20}) async {
    final rows = await Db.client
        .from('order_ratings')
        .select('stars, delivery_stars, tags, comment, created_at, '
            'orders!order_ratings_order_id_fkey(order_number)')
        .eq('branch_id', branchId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => RatingEntry.fromMap(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        if ((a.stars <= 3) != (b.stars <= 3)) return a.stars <= 3 ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
  }
}
