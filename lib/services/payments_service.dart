import '../models/enums.dart';
import '../models/models.dart';
import 'supabase_service.dart';

/// خطأٌ من بوّابة الدفع برسالةٍ تُقرأ.
class PaymentException implements Exception {
  const PaymentException(this.messageAr);
  final String messageAr;
  @override
  String toString() => messageAr;
}

/// الدفع.
///
/// **التطبيق لا يكلّم المزوّد ولا يكتب دفعة.** يطلب من الخادم أن يفتح دفعًا،
/// فيعيد إليه رابطًا. ومفتاحُ السرّ والمبلغ كلاهما هناك — ولو كان أحدهما هنا
/// لَدفع من فكّ الحزمة ما يشاء لطلبه.
class PaymentsService {
  const PaymentsService();

  /// هل تُعرض البطاقة على هذا العميل؟
  ///
  /// يُسأل الكتالوج لا الشيفرة: مغسلةٌ بلا مزوّدٍ نشط يجب ألّا ترى الخيار
  /// أصلًا — وعرضُه ثم فشلُه أسوأ من إخفائه.
  Future<bool> cardAvailable(String laundryId) async {
    final rows = await Db.client
        .from('payment_providers')
        .select('methods')
        .eq('laundry_id', laundryId)
        .eq('is_active', true);

    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final methods = (r['methods'] as List?)?.cast<String>() ?? const [];
      if (methods.contains('card') || methods.contains('apple_pay')) return true;
    }
    return false;
  }

  /// يفتح دفعًا ويعيد رابط صفحة المزوّد.
  Future<String> start(String orderId) async {
    final res = await Db.client.functions
        .invoke('payments-start', body: {'order_id': orderId});

    final data = res.data;
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};

    if (res.status != 200 || map['ok'] != true) {
      throw PaymentException(
          (map['error'] as String?) ?? 'تعذّر فتح صفحة الدفع الآن.');
    }
    final url = map['url'] as String?;
    if (url == null || url.isEmpty) {
      throw const PaymentException('لم يُعِد المزوّد رابط دفع.');
    }
    return url;
  }

  Future<List<Payment>> ofOrder(String orderId) async {
    final rows = await Db.client
        .from('payments')
        .select('*, refunds(amount, status)')
        .eq('order_id', orderId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Payment.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// استرداد. يعيد `null` عند النجاح، ورسالةً عند الرفض.
  Future<String?> refund({
    required String paymentId,
    required double amount,
    required String reason,
  }) async {
    final res = await Db.client.functions.invoke('payments-refund', body: {
      'payment_id': paymentId,
      'amount': amount,
      'reason': reason,
    });
    final data = res.data;
    final map = data is Map ? Map<String, dynamic>.from(data) : const {};
    if (res.status == 200 && map['ok'] == true) return null;
    return (map['error'] as String?) ?? 'تعذّر تنفيذ الاسترداد.';
  }

  /// هل بقي على الطلب مبلغٌ يُدفع بالبطاقة؟
  static bool owesPayment(LaundryOrder order) =>
      order.total > 0 &&
      order.paymentStatus != PaymentStatus.paid &&
      order.paymentStatus != PaymentStatus.refunded &&
      !order.status.isTerminal;
}
