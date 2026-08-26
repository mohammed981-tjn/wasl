import '../models/models.dart';
import 'supabase_service.dart';

/// التقييم ونقاط الولاء في طرف العميل.
class FeedbackService {
  const FeedbackService();

  /// أسبابٌ جاهزة تُنقر بدل أن تُكتب.
  ///
  /// **وهي في الشيفرة عمدًا**: هذه ليست قاعدةَ عملٍ تُسعَّر أو تُحسب، بل صياغةُ
  /// سؤالٍ في واجهة. وجعلُها صفوفًا يُثقل الإدارة بضبطٍ لا يغيّر مالًا ولا حكمًا.
  static const positiveTags = ['سريع', 'نظيف', 'كيٌّ ممتاز', 'سائق مهذّب'];
  static const negativeTags = [
    'تأخّر',
    'بقعة لم تُزل',
    'قطعة ناقصة',
    'رائحة',
    'تغليف سيّئ',
  ];

  Future<OrderRating?> ratingOf(String orderId) async {
    final rows = await Db.client
        .from('order_ratings')
        .select()
        .eq('order_id', orderId)
        .limit(1);
    final list = rows as List;
    return list.isEmpty
        ? null
        : OrderRating.fromMap(list.first as Map<String, dynamic>);
  }

  /// حفظُ التقييم. القاعدة تملأ العميلَ والفرعَ والسائق وتحرس النافذة.
  Future<void> rate({
    required String orderId,
    required int stars,
    int? deliveryStars,
    List<String> tags = const [],
    String? comment,
  }) async {
    await Db.client.from('order_ratings').upsert({
      'order_id': orderId,
      // تُرسل لأن العمودين `not null`، وتُستبدل في الحارس بما في الطلب.
      'customer_id': Db.currentUser?.id,
      'branch_id': '00000000-0000-0000-0000-000000000000',
      'stars': stars,
      'delivery_stars': deliveryStars,
      'tags': tags,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
    }, onConflict: 'order_id');
  }

  /// الرصيد وما يُسمح بصرفه على فاتورةٍ بهذا المبلغ.
  Future<LoyaltyState> loyalty({
    required String userId,
    required String laundryId,
    double subtotal = 0,
  }) async {
    final balance = await Db.client.rpc('loyalty_balance', params: {
      'p_user': userId,
      'p_laundry': laundryId,
    });

    if (subtotal <= 0) {
      return LoyaltyState(balance: (balance as num?)?.toInt() ?? 0);
    }

    final rows = await Db.client.rpc('quote_loyalty_redemption', params: {
      'p_user': userId,
      'p_laundry': laundryId,
      'p_subtotal': subtotal,
    });
    final list = rows as List;
    final q = list.isEmpty ? null : list.first as Map<String, dynamic>;

    return LoyaltyState(
      balance: (balance as num?)?.toInt() ?? 0,
      redeemablePoints: (q?['points_to_spend'] as num?)?.toInt() ?? 0,
      redeemableRiyal:
          double.tryParse('${q?['riyal_value'] ?? 0}') ?? 0,
      reason: q?['reason'] as String?,
    );
  }

  Future<List<LoyaltyTxn>> loyaltyHistory({
    required String userId,
    required String laundryId,
    int limit = 20,
  }) async {
    final rows = await Db.client
        .from('loyalty_transactions')
        .select('points, kind, note, created_at')
        .eq('user_id', userId)
        .eq('laundry_id', laundryId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => LoyaltyTxn.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// صرفُ نقاطٍ على مسوّدة. يعيد `null` عند النجاح ورسالةً عند الرفض.
  Future<String?> redeem({required String orderId, required int points}) async {
    final res = await Db.client.rpc('redeem_loyalty_on_order', params: {
      'p_order': orderId,
      'p_points': points,
    });
    final map = Map<String, dynamic>.from(res as Map);
    return map['ok'] == true ? null : (map['reason'] as String? ?? 'تعذّر الصرف');
  }
}
