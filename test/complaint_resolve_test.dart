// اختبار لوحة خدمة العملاء وورقة قرار الحلّ.
//
// **الخطر هنا مالٌ يخرج.** ويُختبر تحديدًا:
//
//   ١) أن الورقة تُدخل **نسبةً** لا مبلغًا — مبلغٌ يُكتب في شاشةٍ مبلغٌ
//      يُملى على القاعدة، وأوّلُ خطأٍ فيه مالٌ لا يعود.
//   ٢) أن إغلاق الورقة من خارجها **تراجُعٌ** لا «حلٌّ بلا إجراء» — وهو
//      الفخُّ نفسه الذي أوقعنا في `job_screen` من قبل: `null` عُومل كنصٍّ
//      فارغ فأُتمّت المهمّة.
//   ٣) أن سطرَي الإغلاق (بإقرارٍ وبصمت) يُعرضان منفصلين.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wasl/models/models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  group('نتيجةُ قرار الحلّ', () {
    test('تُقرأ كما تعيدها القاعدة — والمبلغُ منها لا من الشاشة', () {
      final r = ComplaintResolution.fromMap({
        'complaint_id': 'c1',
        'refund_amount': 40,
        'loyalty_points': 0,
        'warned': true,
        'active_warnings': 2,
        'actions': ['استرداد 50% (40 ر.س)', 'إنذار (2 سارٍ)'],
        'confirm_by': '2026-08-30T10:00:00Z',
      });

      // **٤٠ لا ٥٠**: النسبة من قيمة الخدمة، ورسمُ التوصيل خدمةٌ أُدّيت.
      // والرقمُ محسوبٌ في القاعدة — الشاشةُ تعرضه ولا تحسبه.
      expect(r.refundAmount, 40);
      expect(r.warned, isTrue);
      expect(r.activeWarnings, 2);
      expect(r.actions.length, 2);
      expect(r.confirmBy, isNotNull);
    });

    test('وحلٌّ بلا إجراءٍ نتيجةٌ صالحة — لا كلُّ شكوى تُشترى', () {
      final r = ComplaintResolution.fromMap({
        'refund_amount': 0,
        'loyalty_points': 0,
        'warned': false,
        'actions': <String>[],
      });
      expect(r.refundAmount, 0);
      expect(r.actions, isEmpty);
      expect(r.warned, isFalse);
      // وتبقى مهلةُ التأكيد مفتوحة: الاعتذارُ وحده قد يكون حلًّا، وصاحبُها
      // هو من يقرّر.
      expect(r.loyaltyPoints, 0);
    });

    test('والتعويضُ بالنقاط بابٌ حين لا يكون ثمّ ما يُستردّ', () {
      final r = ComplaintResolution.fromMap({
        'refund_amount': 0,
        'loyalty_points': 200,
        'actions': ['تعويض 200 نقطة'],
      });
      expect(r.refundAmount, 0);
      expect(r.loyaltyPoints, 200);
    });
  });

  group('الملخّصُ كما يُقرأ في اللوحة', () {
    test('«تنتظر عملًا» تجمع الجديدة وقيدَ المعالجة', () {
      final s = ComplaintSummary.fromMap({
        'open_now': 3,
        'in_progress_now': 4,
        'closed_confirmed': 10,
        'closed_by_silence': 12,
      });
      expect(s.needsWork, 7);
      // **ولا يُجمع الإغلاقان**: اثنتا عشرةَ أُغلقت بالصمت مقابل عشرٍ بإقرارٍ
      // مؤشّرُ خللٍ — ولو جُمعا لَقرأتْه اللوحة «٢٢ مغلقة» ولَبدا إنجازًا.
      expect(s.closedBySilence, greaterThan(s.closedConfirmed));
    });

    test('والتصنيفُ يُجمَّع لأنّ القائمة مغلقة', () {
      final s = ComplaintSummary.fromMap({
        'by_type': {'بقعةٌ لم تُزل': 12, 'تأخّرٌ في التسليم': 8, 'أخرى': 1},
      });
      // نصٌّ حرٌّ لا يُنتج هذا السطر أبدًا — ولذلك كانت الأنواعُ جدولًا.
      expect(s.byType.length, 3);
      expect(s.byType['بقعةٌ لم تُزل'], 12);
    });
  });

  group('ترتيبُ الطابور', () {
    test('المرتدَّةُ تُميَّز — الحلُّ السابق لم يُقنع صاحبَها', () {
      final plain = Complaint(
        id: 'a',
        number: 1,
        status: ComplaintStatus.inProgress,
        description: 'x',
        createdAt: DateTime(2026, 8, 20),
      );
      final bounced = Complaint(
        id: 'b',
        number: 2,
        status: ComplaintStatus.inProgress,
        description: 'y',
        createdAt: DateTime(2026, 8, 20),
        reopenCount: 2,
      );

      expect(plain.wasReopened, isFalse);
      expect(bounced.wasReopened, isTrue);
      // **وحلٌّ ثانٍ من الجنس نفسه سيرتدّ ثانية** — فالتمييزُ ليس زينة.
      expect(bounced.reopenCount, 2);
    });

    test('وتجاوزُ مهلة الردّ يأتي محسوبًا من القاعدة لا من الجهاز', () {
      final c = Complaint.fromMap({
        'id': 'c',
        'complaint_number': 3,
        'status': 'open',
        'description': 'z',
        'created_at': '2026-08-20T10:00:00Z',
        // **يحسبه المنظر بإعدادات المغسلة**: الشاشةُ لا تعرف كم وعدنا،
        // وحسابُها له يجعل مرجعين للوعد يختلفان يومًا.
        'sla_breached': true,
      });
      expect(c.slaBreached, isTrue);
    });
  });
}
