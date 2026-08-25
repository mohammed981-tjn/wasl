// اختبار عرض صفّ الطلب.
//
// **ما يُختبر هنا بالتحديد**: أن الحقائق التي يحتاجها المشغّل تظهر فعلًا —
// الرقم، والحالة، ووسم التأخير. وأن التأخير **لا** يُوسَم على طلبٍ انتهى، فلوحةٌ
// تُعلن متأخّرًا ما لا يُعمل عليه تُدرَّب على تجاهلها.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/enums.dart';
import 'package:wasl/models/models.dart';
import 'package:wasl/screens/admin/orders_tab.dart';

LaundryOrder order({
  OrderStatus status = OrderStatus.washing,
  DateTime? promised,
  String? customer = 'محمد',
  bool express = false,
}) =>
    LaundryOrder(
      id: 'o1',
      orderNumber: 10042,
      laundryId: 'l',
      branchId: 'b',
      customerId: 'c',
      status: status,
      paymentStatus: PaymentStatus.paid,
      subtotal: 100,
      deliveryFee: 15,
      discountAmount: 0,
      vatAmount: 15,
      total: 115,
      isExpress: express,
      promisedReadyAt: promised,
      createdAt: DateTime(2026, 8, 25, 9),
      customerName: customer,
    );

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
  testWidgets('يعرض الرقم واسم العميل والحالة والإجمالي', (tester) async {
    await pump(tester, OrderRow(order: order()));

    expect(find.text('#10042'), findsOneWidget);
    expect(find.text('محمد'), findsOneWidget);
    expect(find.text('جاري الغسيل'), findsOneWidget);
    expect(find.textContaining('115.00'), findsOneWidget);
    expect(find.textContaining('مدفوع'), findsOneWidget);
  });

  testWidgets('عميلٌ بلا اسم لا يترك الصفّ فارغًا', (tester) async {
    // ملفّ العميل قد لا يكون مرئيًّا لهذا الدور (سياسة profiles_read)، فالصفّ
    // يجب أن يبقى مقروءًا لا أن يظهر فراغًا.
    await pump(tester, OrderRow(order: order(customer: null)));
    expect(find.text('عميل'), findsOneWidget);
  });

  testWidgets('المتأخّر يُوسَم', (tester) async {
    await pump(
      tester,
      OrderRow(
          order: order(
              promised: DateTime.now().subtract(const Duration(hours: 3)))),
    );
    expect(find.text('متأخّر'), findsOneWidget);
  });

  testWidgets('المسلَّم لا يُوسَم متأخّرًا مهما تجاوز وعده', (tester) async {
    await pump(
      tester,
      OrderRow(
          order: order(
              status: OrderStatus.delivered,
              promised: DateTime.now().subtract(const Duration(days: 3)))),
    );
    expect(find.text('متأخّر'), findsNothing);
    expect(find.text('تم التسليم'), findsOneWidget);
  });

  testWidgets('المستعجل يُميَّز بأيقونة', (tester) async {
    await pump(tester, OrderRow(order: order(express: true)));
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });

  testWidgets('كل حالة تُعرض بتسميتها العربية لا باسمها في القاعدة',
      (tester) async {
    for (final s in OrderStatus.values) {
      await pump(tester, OrderStatusChip(status: s));
      expect(find.text(s.labelAr), findsOneWidget,
          reason: 'الحالة ${s.name} لا تُعرض بالعربية');
      // ولا يتسرّب الاسم التقنيّ إلى الشاشة.
      expect(find.text(s.wireName), findsNothing);
    }
  });

  testWidgets('النقر يفتح التفصيل', (tester) async {
    var tapped = false;
    await pump(tester, OrderRow(order: order(), onTap: () => tapped = true));
    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });
}
