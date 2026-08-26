// اختبار عرض الطلبات المعرَّضة للتأخير.
//
// **ما يُختبر هنا بالتحديد**: أن «سيتأخّر» و«تأخّر» لا تُخلطان في العرض،
// وأن **ضعف التقدير يُعلَن**. رقمٌ مبنيٌّ على طلبين يبدو على الشاشة كرقمٍ
// مبنيٍّ على مئة — والفرق بينهما قرارُ استعجالٍ خاطئ.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wasl/models/enums.dart';
import 'package:wasl/screens/admin/dashboard_tab.dart';
import 'package:wasl/services/reports_service.dart';

Map<String, dynamic> row({
  int number = 10042,
  String status = 'washing',
  int lateBy = 120,
  int samples = 12,
  bool confident = true,
  bool alreadyLate = false,
  bool express = false,
}) =>
    {
      'order_id': 'o$number',
      'order_number': number,
      'customer_name': 'محمد',
      'status': status,
      'is_express': express,
      'promised_ready_at': '2026-08-26T14:00:00Z',
      'expected_ready_at': '2026-08-26T16:00:00Z',
      'late_by_minutes': lateBy,
      'minutes_in_stage': 45,
      'samples': samples,
      'confident': confident,
      'already_late': alreadyLate,
    };

void main() {
  // في التطبيق تُحمَّل بيانات اللغة عبر `GlobalMaterialLocalizations`، وفي
  // الاختبار لا مندوحة عن تحميلها يدويًّا — وإلّا رمت `DateFormat` استثناءً
  // لا علاقة له بما يُختبَر.
  setUpAll(() => initializeDateFormatting('ar'));

  group('نموذج الطلب المعرَّض', () {
    test('الحقول تُقرأ، والوقت يُحوَّل إلى المحلّيّ', () {
      final o = OrderAtRisk.fromMap(row());
      expect(o.orderNumber, 10042);
      expect(o.status, OrderStatus.washing);
      expect(o.lateByMinutes, 120);
      expect(o.confident, isTrue);
      expect(o.promisedReadyAt,
          DateTime.parse('2026-08-26T14:00:00Z').toLocal());
    });

    test('المدّة تُقرأ بالساعات والدقائق لا بالدقائق وحدها', () {
      // «١٥٠ د» تُقرأ أبطأ من «٢ س ٣٠ د» على شاشةٍ تُلمح لا تُدرَس.
      expect(OrderAtRisk.fromMap(row(lateBy: 45)).lateLabel, '45 د');
      expect(OrderAtRisk.fromMap(row(lateBy: 120)).lateLabel, '2 س');
      expect(OrderAtRisk.fromMap(row(lateBy: 150)).lateLabel, '2 س 30 د');
    });

    test('فرعٌ بلا تاريخ: التقدير غير موثوق', () {
      final o = OrderAtRisk.fromMap(row(samples: 0, confident: false));
      expect(o.confident, isFalse);
      expect(o.samples, 0);
    });
  });

  group('البطاقة في اللوحة', () {
    Future<void> pump(WidgetTester tester, List<OrderAtRisk> items) =>
        tester.pumpWidget(MaterialApp(
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(child: AtRiskCard(items: items)),
            ),
          ),
        ));

    testWidgets('يُفصَل المتوقَّع عن الواقع', (tester) async {
      await pump(tester, [
        OrderAtRisk.fromMap(row(number: 1, alreadyLate: false)),
        OrderAtRisk.fromMap(row(number: 2, alreadyLate: true, lateBy: 300)),
      ]);

      expect(find.text('سيتأخّر'), findsOneWidget);
      expect(find.text('تأخّر'), findsOneWidget);
      // العنوان يعدّ المتوقَّع وحده: المتأخّر معروفٌ من قبل.
      expect(find.textContaining('1 طلبًا يُتوقَّع'), findsOneWidget);
    });

    testWidgets('المتأخّر فعلًا يُعرض أوّلًا', (tester) async {
      await pump(tester, [
        OrderAtRisk.fromMap(row(number: 111, alreadyLate: false, lateBy: 600)),
        OrderAtRisk.fromMap(row(number: 222, alreadyLate: true, lateBy: 30)),
      ]);

      final first = tester.getTopLeft(find.text('#222'));
      final second = tester.getTopLeft(find.text('#111'));
      expect(first.dy, lessThan(second.dy),
          reason: 'المتأخّر فعلًا أوّلًا ولو كان تأخّرُه أقلّ');
    });

    testWidgets('ضعفُ التقدير يُقال ولا يُخفى', (tester) async {
      await pump(tester, [
        OrderAtRisk.fromMap(row(samples: 1, confident: false)),
      ]);

      expect(find.textContaining('تاريخُ الفرع قصير'), findsOneWidget);
      // ولا يُعرض رقمٌ لا يستحقّ التصديق.
      expect(find.text('؟'), findsOneWidget);
      expect(find.text('بـ2 س'), findsNothing);
    });

    testWidgets('التقدير الموثوق يُعرض بمدّته', (tester) async {
      await pump(tester, [OrderAtRisk.fromMap(row(lateBy: 90))]);
      expect(find.text('بـ1 س 30 د'), findsOneWidget);
      expect(find.textContaining('تاريخُ الفرع قصير'), findsNothing);
    });

    testWidgets('القائمة الطويلة تُقصّ وتُقال بقيّتُها', (tester) async {
      await pump(tester, [
        for (var i = 1; i <= 9; i++) OrderAtRisk.fromMap(row(number: i)),
      ]);
      expect(find.textContaining('و3 غيرها'), findsOneWidget);
    });
  });
}
