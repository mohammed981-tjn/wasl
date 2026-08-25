// اختبار مقارنة المطلوب بالمجرود.
//
// **ما يُختبر هنا بالتحديد**: أن الفارق بين ما طلبه العميل وما جُرِد فعلًا
// يُعلَن صراحةً — زائدًا كان أو ناقصًا. هذا الفارق هو ما تُحسم به الخلافات
// بعد التسليم، وشاشةٌ تطمسه تُحوّل القطعة الزائدة إلى ضياعٍ بلا أثر.
//
// ويُختبر كذلك أنّ بنود الوزن والسلّة **لا** تُعدّ بالقطعة: كيلوان من الغسيل
// ليسا قطعتين، ومقارنتهما بعدد القطع تُنتج إنذارًا كاذبًا يُدرَّب على تجاهله.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/enums.dart';
import 'package:wasl/models/models.dart';
import 'package:wasl/screens/laundry/count_compare.dart';

OrderItem item({
  required PricingUnit unit,
  required double qty,
  String id = 'i1',
}) =>
    OrderItem(
      id: id,
      orderId: 'o1',
      serviceNameAr: 'غسيل وكي',
      unit: unit,
      quantity: qty,
      unitPrice: 10,
      lineTotal: 10 * qty,
    );

LaundryOrder order(List<OrderItem> items) => LaundryOrder(
      id: 'o1',
      orderNumber: 10042,
      laundryId: 'l',
      branchId: 'b',
      customerId: 'c',
      status: OrderStatus.sorting,
      paymentStatus: PaymentStatus.paid,
      subtotal: 100,
      deliveryFee: 15,
      discountAmount: 0,
      vatAmount: 15,
      total: 115,
      createdAt: DateTime(2026, 8, 25, 9),
      items: items,
    );

List<OrderGarment> garments(int n) => [
      for (var i = 1; i <= n; i++)
        OrderGarment(
          id: 'g$i',
          orderId: 'o1',
          barcode: 'WSL-10042-${i.toString().padLeft(2, '0')}',
          labelAr: 'ثوب',
          currentStage: OrderStatus.sorting,
        ),
    ];

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  testWidgets('تطابقُ العدد يُعرض بلا إنذار', (tester) async {
    await pump(
      tester,
      CountCompare(
        order: order([item(unit: PricingUnit.piece, qty: 3)]),
        garments: garments(3),
      ),
    );

    expect(find.text('طلب 3 — جُرِد 3'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.textContaining('زائدة'), findsNothing);
    expect(find.textContaining('ينقص'), findsNothing);
  });

  testWidgets('القطعة الزائدة تُعلَن بعددها', (tester) async {
    await pump(
      tester,
      CountCompare(
        order: order([item(unit: PricingUnit.piece, qty: 3)]),
        garments: garments(4),
      ),
    );

    expect(find.text('طلب 3 — جُرِد 4'), findsOneWidget);
    expect(find.textContaining('وصلت 1 قطعة زائدة'), findsOneWidget);
    expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
  });

  testWidgets('النقص يُعلَن بعدده', (tester) async {
    await pump(
      tester,
      CountCompare(
        order: order([item(unit: PricingUnit.piece, qty: 5)]),
        garments: garments(2),
      ),
    );

    expect(find.textContaining('ينقص 3 قطعة'), findsOneWidget);
  });

  testWidgets('بنودُ القطعة تُجمَع من كل البنود', (tester) async {
    await pump(
      tester,
      CountCompare(
        order: order([
          item(unit: PricingUnit.piece, qty: 2, id: 'a'),
          item(unit: PricingUnit.piece, qty: 3, id: 'b'),
        ]),
        garments: garments(5),
      ),
    );

    expect(find.text('طلب 5 — جُرِد 5'), findsOneWidget);
  });

  testWidgets('الوزن لا يُقارَن بالقطع بل يُنبَّه عليه', (tester) async {
    await pump(
      tester,
      CountCompare(
        order: order([item(unit: PricingUnit.kilogram, qty: 6)]),
        garments: garments(9),
      ),
    );

    // لا «طلب ٦ وجُرِد ٩»: ستّة كيلوغرامات ليست ستّ قطع.
    expect(find.text('جُرِدت 9 قطعة'), findsOneWidget);
    expect(find.textContaining('زائدة'), findsNothing);
    expect(find.textContaining('بالوزن أو بالسلّة'), findsOneWidget);
  });

  testWidgets('طلبٌ مختلط: يُقارَن بالقطع ويُنبَّه على الوزن', (tester) async {
    await pump(
      tester,
      CountCompare(
        order: order([
          item(unit: PricingUnit.piece, qty: 2, id: 'a'),
          item(unit: PricingUnit.kilogram, qty: 4, id: 'b'),
        ]),
        garments: garments(2),
      ),
    );

    expect(find.text('طلب 2 — جُرِد 2'), findsOneWidget);
    expect(find.textContaining('بالوزن أو بالسلّة'), findsOneWidget);
  });

  testWidgets('لا قطعةَ مجرودةً بعد: يُعرض النقص لا الصفر الصامت',
      (tester) async {
    await pump(
      tester,
      CountCompare(
        order: order([item(unit: PricingUnit.piece, qty: 4)]),
        garments: const [],
      ),
    );

    expect(find.text('طلب 4 — جُرِد 0'), findsOneWidget);
    expect(find.textContaining('ينقص 4 قطعة'), findsOneWidget);
  });
}
