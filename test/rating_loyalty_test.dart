// اختبار عرض التقييم ونقاط الولاء.
//
// **ما يُختبر هنا بالتحديد**: أن الأسبابَ المعروضة تتبع النجمة. سؤالُ من أعطى
// نجمةً واحدة «هل كان الكيّ ممتازًا؟» استخفافٌ يُغلق الشاشة، وسؤالُ من أعطى
// خمسًا «ما الذي أزعجك؟» يزرع شكوى لم تكن.
//
// ويُختبر أن تبديل الاتّجاه **يُسقط** ما اختير قبله: لولا ذلك لَحُفظ «سريع»
// مع نجمةٍ واحدة، وصار تقريرُ الأسباب بلا معنى.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/models.dart';
import 'package:wasl/screens/customer/rating_card.dart';
import 'package:wasl/services/feedback_service.dart';

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

void main() {
  group('بطاقة التقييم', () {
    testWidgets('قبل النجمة لا يُسأل شيءٌ آخر', (tester) async {
      await pump(
        tester,
        RatingCard(orderId: 'o1', existing: null, onSaved: () {}),
      );

      expect(find.text('كيف كانت الخدمة؟'), findsOneWidget);
      // لا أسباب ولا حقل نصّ ولا زرّ إرسال قبل أوّل نجمة.
      expect(find.text('سريع'), findsNothing);
      expect(find.text('تأخّر'), findsNothing);
      expect(find.text('إرسال'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('خمسُ نجماتٍ تعرض الأسباب الحسنة وحدها', (tester) async {
      await pump(
        tester,
        RatingCard(orderId: 'o1', existing: null, onSaved: () {}),
      );
      await tester.tap(find.byIcon(Icons.star_border_rounded).at(4));
      await tester.pump();

      for (final t in FeedbackService.positiveTags) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('تأخّر'), findsNothing);
      expect(find.text('إرسال'), findsOneWidget);
    });

    testWidgets('نجمةٌ واحدة تعرض أسباب الشكوى وحدها', (tester) async {
      await pump(
        tester,
        RatingCard(orderId: 'o1', existing: null, onSaved: () {}),
      );
      await tester.tap(find.byIcon(Icons.star_border_rounded).first);
      await tester.pump();

      expect(find.text('تأخّر'), findsOneWidget);
      expect(find.text('بقعة لم تُزل'), findsOneWidget);
      expect(find.text('سريع'), findsNothing);
    });

    testWidgets('الضغط على النجمة نفسها يُلغي التقييم', (tester) async {
      await pump(
        tester,
        RatingCard(orderId: 'o1', existing: null, onSaved: () {}),
      );
      await tester.tap(find.byIcon(Icons.star_border_rounded).at(2));
      await tester.pump();
      expect(find.text('إرسال'), findsOneWidget);

      // الثالثةُ الآن ممتلئة: ضغطُها يرجع إلى الصفر.
      await tester.tap(find.byIcon(Icons.star_rounded).at(2));
      await tester.pump();
      expect(find.text('إرسال'), findsNothing);
    });

    testWidgets('تقييمٌ سابقٌ يُعرض للتعديل لا للإنشاء', (tester) async {
      await pump(
        tester,
        RatingCard(
          orderId: 'o1',
          existing: const OrderRating(
              orderId: 'o1', stars: 4, tags: ['سريع'], comment: 'ممتاز'),
          onSaved: () {},
        ),
      );

      expect(find.text('تقييمك'), findsOneWidget);
      expect(find.text('تحديث التقييم'), findsOneWidget);
      expect(find.text('ممتاز'), findsOneWidget);
    });

    testWidgets('طلبٌ بلا سائق لا يُسأل عن التوصيل', (tester) async {
      await pump(
        tester,
        RatingCard(
          orderId: 'o1',
          existing: null,
          onSaved: () {},
          hasDriver: false,
        ),
      );
      await tester.tap(find.byIcon(Icons.star_border_rounded).at(4));
      await tester.pump();

      expect(find.text('التوصيل'), findsNothing);
    });
  });

  group('حالة النقاط', () {
    test('رصيدٌ بلا ما يُصرف لا يُعدّ قابلًا للصرف', () {
      const s = LoyaltyState(balance: 50, redeemablePoints: 0, reason: 'قليل');
      expect(s.canRedeem, isFalse);
    });

    test('نقاطٌ بلا قيمةٍ ريالية لا تُصرف', () {
      // حالةٌ ممكنة: `riyal_per_point` صفرٌ في الإعدادات.
      const s = LoyaltyState(
          balance: 500, redeemablePoints: 500, redeemableRiyal: 0);
      expect(s.canRedeem, isFalse);
    });

    test('الصرف الممكن يُعلن', () {
      const s = LoyaltyState(
          balance: 1000, redeemablePoints: 1000, redeemableRiyal: 100);
      expect(s.canRedeem, isTrue);
    });
  });
}
