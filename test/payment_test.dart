// اختبار نموذج الدفعة.
//
// **ما يُختبر هنا بالتحديد**: حسابُ ما بقي قابلًا للاسترداد. والخطأ فيه لا
// يُرى على شاشة بل يظهر في الدفاتر: رقمٌ أكبر من الحقيقة يعرض على المحاسب
// استردادًا يتجاوز المقبوض (فترفضه القاعدة ويبدو النظام معطَّلًا)، ورقمٌ أصغر
// يمنع استردادًا يستحقّه العميل.
//
// ويُختبر أن الاستردادات **الفاشلة لا تُحسب**: طلبُ استردادٍ رفضه المزوّد لم
// يُخرج مالًا، فعدُّه ضمن المستردّ يُجمّد مبلغًا لم يخرج.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/enums.dart';
import 'package:wasl/models/models.dart';
import 'package:wasl/services/payments_service.dart';

Map<String, dynamic> row({
  String status = 'captured',
  String amount = '230.00',
  List<Map<String, dynamic>>? refunds,
  String? last4 = '4242',
  String? brand = 'mada',
  String? failure,
}) =>
    {
      'id': 'p1',
      'order_id': 'o1',
      'method': 'card',
      'status': status,
      'amount': amount,
      'provider_ref': 'moy_1',
      'card_brand': brand,
      'card_last4': last4,
      'failure_message': failure,
      'created_at': '2026-08-25T09:00:00Z',
      if (refunds != null) 'refunds': refunds,
    };

void main() {
  test('دفعةٌ مقبوضةٌ بلا استرداد: كلُّها قابلٌ للاسترداد', () {
    final p = Payment.fromMap(row());
    expect(p.status, PaymentTxnStatus.captured);
    expect(p.refunded, 0);
    expect(p.refundable, 230.00);
  });

  test('الاسترداد الجزئيّ يُنقص المتبقّي', () {
    final p = Payment.fromMap(row(refunds: [
      {'amount': '30.00', 'status': 'completed'},
    ]));
    expect(p.refunded, 30.00);
    expect(p.refundable, 200.00);
  });

  test('استردادان جزئيّان يُجمعان', () {
    final p = Payment.fromMap(row(refunds: [
      {'amount': '30.00', 'status': 'completed'},
      {'amount': '20.50', 'status': 'completed'},
    ]));
    expect(p.refunded, 50.50);
    expect(p.refundable, 179.50);
  });

  test('الاسترداد الفاشل لا يُحسب — لم يخرج منه مال', () {
    final p = Payment.fromMap(row(refunds: [
      {'amount': '100.00', 'status': 'failed'},
      {'amount': '30.00', 'status': 'completed'},
    ]));
    expect(p.refunded, 30.00);
    expect(p.refundable, 200.00);
  });

  test('المعلَّق كذلك لا يُحسب مستردًّا حتى يكتمل', () {
    final p = Payment.fromMap(row(refunds: [
      {'amount': '50.00', 'status': 'pending'},
    ]));
    expect(p.refunded, 0);
  });

  test('الاسترداد الكامل لا يترك شيئًا', () {
    final p = Payment.fromMap(row(refunds: [
      {'amount': '230.00', 'status': 'completed'},
    ]));
    expect(p.refundable, 0);
  });

  test('دفعةٌ لم تُقبض لا تُستردّ مهما كان مبلغها', () {
    for (final s in ['pending', 'failed', 'authorized', 'cancelled']) {
      expect(Payment.fromMap(row(status: s)).refundable, 0,
          reason: 'الحالة $s');
    }
  });

  test('الوسم يُظهر البطاقة بآخر أربعة أرقام لا بالوسيلة المجرّدة', () {
    expect(Payment.fromMap(row()).label, 'mada •••• 4242');
    expect(Payment.fromMap(row(brand: null)).label, 'بطاقة •••• 4242');
    expect(Payment.fromMap(row(last4: null)).label, PaymentMethod.card.labelAr);
  });

  test('سبب الفشل يُقرأ — «فشل» وحدها لا تُقال لعميل', () {
    final p = Payment.fromMap(
        row(status: 'failed', failure: 'رصيد غير كافٍ'));
    expect(p.failureMessage, 'رصيد غير كافٍ');
  });

  group('هل بقي على الطلب مبلغ؟', () {
    LaundryOrder order({
      required PaymentStatus payment,
      OrderStatus status = OrderStatus.placed,
      double total = 230,
    }) =>
        LaundryOrder(
          id: 'o1',
          orderNumber: 10042,
          laundryId: 'l',
          branchId: 'b',
          customerId: 'c',
          status: status,
          paymentStatus: payment,
          subtotal: 200,
          deliveryFee: 15,
          discountAmount: 0,
          vatAmount: 15,
          total: total,
          createdAt: DateTime(2026, 8, 25),
        );

    test('غير المدفوع يُطالَب', () {
      expect(PaymentsService.owesPayment(order(payment: PaymentStatus.unpaid)),
          isTrue);
    });

    test('المدفوع لا يُطالَب', () {
      expect(PaymentsService.owesPayment(order(payment: PaymentStatus.paid)),
          isFalse);
    });

    test('الملغى لا يُطالَب ولو كان غير مدفوع', () {
      expect(
        PaymentsService.owesPayment(order(
            payment: PaymentStatus.unpaid, status: OrderStatus.cancelled)),
        isFalse,
      );
    });

    test('المسترَدّ لا يُطالَب', () {
      expect(
          PaymentsService.owesPayment(order(payment: PaymentStatus.refunded)),
          isFalse);
    });

    test('طلبٌ بصفرٍ لا يُطالَب بشيء', () {
      expect(
        PaymentsService.owesPayment(
            order(payment: PaymentStatus.unpaid, total: 0)),
        isFalse,
      );
    });
  });
}
