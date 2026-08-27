// اختبار صندوق الرسائل.
//
// **ولماذا يستحقّ اختبارًا**: هذه القناة صارت **حاملةَ سؤالٍ يترتّب عليه
// إغلاقُ ملفّ**. رسالةُ «ردٌّ على شكواك» هي ما يجعل الصمتَ ثلاثةَ أيّامٍ
// رضًا لا جهلًا؛ فإن لم تُعرَض، أو عُرضت ولم تفتح شيئًا، عاد الخللُ الذي
// بُنيت هذه القناة لسدّه.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/models.dart';

AppNotification _n(Map<String, dynamic> extra) => AppNotification.fromMap({
      'id': 'n1',
      'body': 'نصّ الرسالة',
      'created_at': '2026-08-27T09:00:00Z',
      ...extra,
    });

void main() {
  group('رسالةُ الصندوق', () {
    test('غيرُ المقروءة تُميَّز، والمقروءةُ لا', () {
      expect(_n(const {}).isUnread, isTrue);
      expect(_n(const {'read_at': '2026-08-27T10:00:00Z'}).isUnread, isFalse);
    });

    test('و«لم تُرسَل» تُعرض ولا تُخفى', () {
      // **من أوقف الدفع طلب ألّا يُزعَج بصوت، لا ألّا يعرف.** وإخفاءُ
      // المحتوى عنه يجعله لا يرى سؤالَ تأكيد شكواه أصلًا.
      final skipped = _n(const {'status': 'skipped'});
      expect(skipped.wasSkipped, isTrue);
      expect(skipped.body, isNotEmpty);
    });

    test('والشكوى تسبق الطلب في وجهة الفتح', () {
      // رسالةٌ عن شكوى على طلبٍ تحمل المعرّفين معًا. والمقصودُ منها الشكوى:
      // فيها زرّا «نعم» و«لا»، وشاشةُ الطلب لا تحملهما.
      final both = _n(const {
        'order_id': '11111111-1111-1111-1111-111111111111',
        'complaint_id': '22222222-2222-2222-2222-222222222222',
      });
      expect(both.complaintId, isNotNull);
      expect(both.orderId, isNotNull);

      final orderOnly =
          _n(const {'order_id': '11111111-1111-1111-1111-111111111111'});
      expect(orderOnly.complaintId, isNull);
    });

    test('ورسالةٌ بلا وجهةٍ لا تُسقط الشاشة', () {
      final plain = _n(const {});
      expect(plain.orderId, isNull);
      expect(plain.complaintId, isNull);
      expect(plain.body, 'نصّ الرسالة');
    });

    test('وعنوانٌ فارغٌ لا يترك البطاقة بلا سطرٍ أوّل', () {
      // القالبُ قد يُترك بلا عنوان (`title_ar` اختياريّ في القاعدة)، فتُبنى
      // البطاقة من أوّل سطرٍ في المتن.
      final noTitle = _n(const {'body': 'السطر الأوّل\nوالثاني'});
      expect(noTitle.title, isNull);
      expect(noTitle.body.split('\n').first, 'السطر الأوّل');
    });
  });
}
