// اختبار بطاقة الشكوى كما يراها صاحبُها.
//
// **وهذه البطاقة هي النظام كلُّه.** بلا سؤال «هل حُلّت فعلًا؟» يصير إغلاقُ
// الشكوى قرارَ من اشتُكي إليه. فيُختبر أن السؤال يظهر **حين يجب**، وأن
// الإغلاقَ بالصمت يُميَّز عن الإغلاق بالرضا، وأن ردَّ الإدارة يُعرض.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wasl/models/models.dart';
import 'package:wasl/screens/customer/my_complaints_screen.dart';

Complaint _c({
  ComplaintStatus status = ComplaintStatus.open,
  int reopenCount = 0,
  bool closedByTimeout = false,
  DateTime? autoCloseAt,
  DateTime? responseDueAt,
  String? resolution,
}) =>
    Complaint(
      id: 'c1',
      number: 1042,
      status: status,
      description: 'وصلت القطع وفيها بقعةٌ لم تُزل',
      createdAt: DateTime(2026, 8, 20, 10),
      typeLabel: 'بقعةٌ لم تُزل',
      orderNumber: 10251,
      reopenCount: reopenCount,
      closedByTimeout: closedByTimeout,
      autoCloseAt: autoCloseAt,
      responseDueAt: responseDueAt,
      resolution: resolution,
    );

Future<void> pump(WidgetTester tester, Complaint c) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: ComplaintCard(
                complaint: c,
                role: 'customer',
                onChanged: () {},
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  testWidgets('شكوى جديدة: لا يُسأل صاحبُها عن حلٍّ لم يقع', (tester) async {
    await pump(tester, _c(responseDueAt: DateTime.now().add(const Duration(hours: 8))));

    expect(find.text('بقعةٌ لم تُزل #1042'), findsOneWidget);
    // **ولا يُعرض السؤال قبل أوانه**: «هل حُلّت؟» على شكوى لم تُلمَس بعدُ
    // سؤالٌ ساخر.
    expect(find.text('هل حُلّت مشكلتك فعلًا؟'), findsNothing);
    expect(find.text('نعم، حُلّت'), findsNothing);
    // ووعدُ الردّ يُعرض: أن نقول «نردّ خلال ٨ ساعات» أفضلُ من صمت.
    expect(find.textContaining('نردّ خلال'), findsOneWidget);
  });

  testWidgets('وتجاوزُنا لوعدنا يُقال لا يُخفى', (tester) async {
    await pump(
      tester,
      _c(responseDueAt: DateTime.now().subtract(const Duration(hours: 3))),
    );
    // **إخفاءُ التأخّر يجعل الشاكي يشكّ في أنّ أحدًا قرأها أصلًا.**
    expect(find.textContaining('تأخّرنا عن وعدنا'), findsOneWidget);
  });

  testWidgets('وحين تُحلّ: يُعرض الردّ ويُسأل صاحبُها', (tester) async {
    await pump(
      tester,
      _c(
        status: ComplaintStatus.resolved,
        resolution: 'أُعيد غسلُ القطعة واستُرِدّ نصفُ قيمة الخدمة',
        autoCloseAt:
            DateTime.now().add(const Duration(days: 2, hours: 1)),
      ),
    );

    expect(find.text('ردُّ الإدارة'), findsOneWidget);
    expect(find.text('أُعيد غسلُ القطعة واستُرِدّ نصفُ قيمة الخدمة'),
        findsOneWidget);

    expect(find.text('هل حُلّت مشكلتك فعلًا؟'), findsOneWidget);
    expect(find.text('نعم، حُلّت'), findsOneWidget);
    expect(find.text('لا، لم تُحل'), findsOneWidget);
    // **ويُقال له كم بقي**: مهلةٌ تنقضي بلا إعلامٍ إغلاقٌ بلا علم.
    expect(find.textContaining('يومان'), findsOneWidget);
  });

  testWidgets('و«لا، لم تُحل» تُسأل عن سببها ولا تُرسَل صامتة', (tester) async {
    await pump(
      tester,
      _c(
        status: ComplaintStatus.resolved,
        autoCloseAt: DateTime.now().add(const Duration(days: 2)),
      ),
    );

    await tester.tap(find.text('لا، لم تُحل'));
    await tester.pumpAndSettle();

    // **الرفضُ بلا سبب يعيدها إلى موظّفٍ لا يعرف ما الذي أخطأ فيه**، فيكرّر
    // الحلّ نفسه وترتدّ ثانية.
    expect(find.text('ما الذي بقي؟'), findsOneWidget);
    expect(find.text('تراجُع'), findsOneWidget);
  });

  testWidgets('والمرتدَّةُ يُقال عنها إنّها ارتدّت', (tester) async {
    await pump(tester, _c(status: ComplaintStatus.inProgress, reopenCount: 1));
    expect(find.textContaining('أُعيدت مرّةً'), findsOneWidget);
  });

  testWidgets('والإغلاقُ بالصمت لا يُعرض «مغلقة» فحسب', (tester) async {
    await pump(tester, _c(status: ComplaintStatus.closed, closedByTimeout: true));

    // **الفرقُ يظهر للشاكي كما يظهر في التقرير**: بابٌ أُغلق دون أن يقرّر هو.
    expect(find.text('أُغلقت تلقائيًّا'), findsOneWidget);
    expect(find.textContaining('لانقضاء مهلة التأكيد'), findsOneWidget);
    // ولا يُسأل بعد الإغلاق.
    expect(find.text('نعم، حُلّت'), findsNothing);
  });

  testWidgets('والمغلقةُ بإقراره تُعرض مغلقةً بلا اعتذار', (tester) async {
    await pump(tester, _c(status: ComplaintStatus.closed));
    expect(find.text('مغلقة'), findsOneWidget);
    expect(find.textContaining('لانقضاء مهلة التأكيد'), findsNothing);
  });
}
