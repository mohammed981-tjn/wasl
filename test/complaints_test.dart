// اختبار نظام الشكاوى في الواجهة.
//
// **ما يُختبر هنا بالتحديد ثلاثةٌ، وكلُّها أخطاءٌ لا تظهر في شاشة**:
//
//   ١) **صياغةُ المدّة.** العربية تعدّ ثلاثةَ أعداد لا عددين، و«2 ساعة» في
//      شاشةٍ عربيّة تُقرأ ركيكة — وركّةُ النصّ في لحظةِ شكوى تزيد الشاكيَ
//      نفورًا. والحدودُ (١، ٢، ١٠، ١١) هي بالضبط ما يُخطئ فيه من كتب
//      `'$n ساعات'` مرّةً واحدة.
//
//   ٢) **العدّادُ ينتهي في لحظته.** نصٌّ ثابتٌ يُحسب مرّةً يتجمّد، فيبقى
//      الزرُّ حيًّا بعد انقضاء المهلة ويُردّ الشاكي **بعد** أن كتب.
//
//   ٣) **الإغلاقُ بالصمت يُميَّز عن الإغلاق بالرضا.** جمعُهما في «مغلقة»
//      يجعل أسوأَ مؤشّرٍ في النظام يبدو إنجازًا.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wasl/models/models.dart';
import 'package:wasl/widgets/countdown.dart';

Complaint _complaint({
  ComplaintStatus status = ComplaintStatus.open,
  int reopenCount = 0,
  bool closedByTimeout = false,
  DateTime? autoCloseAt,
  DateTime? responseDueAt,
  bool slaBreached = false,
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
      slaBreached: slaBreached,
      resolution: resolution,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  group('صياغةُ المدّة المتبقّية', () {
    test('المفردُ والمثنّى وجمعُ القلّة والكثرة', () {
      expect(formatRemaining(const Duration(hours: 1)), 'ساعةٌ واحدة');
      expect(formatRemaining(const Duration(hours: 2)), 'ساعتان');
      expect(formatRemaining(const Duration(hours: 5)), '5 ساعات');
      // **الحدُّ الذي يُخطأ فيه**: عشرٌ جمعُ قلّة، وإحدى عشرةَ مفردٌ منصوب.
      expect(formatRemaining(const Duration(hours: 10)), '10 ساعات');
      expect(formatRemaining(const Duration(hours: 11)), '11 ساعة');
      expect(formatRemaining(const Duration(hours: 23)), '23 ساعة');
    });

    test('والدقائقُ كذلك', () {
      expect(formatRemaining(const Duration(minutes: 1)), 'دقيقةٌ واحدة');
      expect(formatRemaining(const Duration(minutes: 2)), 'دقيقتان');
      expect(formatRemaining(const Duration(minutes: 7)), '7 دقائق');
      expect(formatRemaining(const Duration(minutes: 45)), '45 دقيقة');
    });

    test('والأيّامُ كذلك — ومهلةُ التأكيد تُقاس بها', () {
      expect(formatRemaining(const Duration(days: 1)), 'يومٌ واحد');
      expect(formatRemaining(const Duration(days: 2)), 'يومان');
      expect(formatRemaining(const Duration(days: 3)), '3 أيّام');
    });

    test('والتقريبُ نزولًا لا صعودًا — عمدًا', () {
      // ساعتان وخمسون دقيقة تبقى «ساعتان»، ويومان إلا دقيقةً يبقيان «يومٌ
      // واحد».
      //
      // **والاتّجاه مقصود**: هذه مهلةٌ تنقضي، والتقليلُ يجعل صاحبَها يبادر،
      // والتكثيرُ يجعله يتأخّر فتُغلق شكواه بصمته. فالخطأ في جهة الاستعجال
      // أرحمُ من الخطأ في جهة الطمأنينة.
      expect(formatRemaining(const Duration(hours: 2, minutes: 50)), 'ساعتان');
      expect(
        formatRemaining(const Duration(days: 1, hours: 23, minutes: 59)),
        'يومٌ واحد',
      );
      expect(formatRemaining(const Duration(minutes: 59, seconds: 59)),
          '59 دقيقة');
    });

    test('وما دون الدقيقة يُقال ولا يُعرض صفرًا', () {
      expect(formatRemaining(const Duration(seconds: 30)), 'أقلّ من دقيقة');
      expect(formatRemaining(Duration.zero), 'انتهت');
      // ومدّةٌ سالبة (ساعةٌ رجعت، أو خادمٌ يسبق الجهاز) لا تُطبع بالسالب.
      expect(formatRemaining(const Duration(minutes: -5)), 'انتهت');
    });
  });

  group('العدّاد', () {
    testWidgets('بلا مهلةٍ لا يُعرض عدّ', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Countdown(
          deadline: null,
          builder: (_, left, expired) => Text(
            left == null ? 'بلا مهلة' : 'باقٍ',
            textDirection: TextDirection.rtl,
          ),
        ),
      ));
      expect(find.text('بلا مهلة'), findsOneWidget);
    });

    testWidgets('ومهلةٌ منقضيةٌ تُعلَن منقضية من أوّل بناء', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Countdown(
          deadline: DateTime.now().subtract(const Duration(hours: 1)),
          builder: (_, left, expired) => Text(
            expired ? 'انقضت' : 'باقٍ',
            textDirection: TextDirection.rtl,
          ),
        ),
      ));
      // **وهذا هو الفخّ**: زرٌّ يبقى حيًّا بعد الانقضاء يجعل الشاكي يكتب
      // شكواه ثم تُردّ — وردٌّ بعد الكتابة أسوأُ من زرٍّ معطَّلٍ قبلها.
      expect(find.text('انقضت'), findsOneWidget);
    });

    testWidgets('ويعيد بناء نفسه فينتهي في لحظته', (tester) async {
      // **ساعةٌ محقونة**: `pump` يقدّم ساعةَ المؤقّتات لا ساعةَ الحائط، فلولا
      // الحقنُ لَنبض المؤقّتُ وقرأ الوقتَ نفسه ولم ينقضِ العدّاد أبدًا —
      // ولَمرّ هذا الاختبار على ودجتٍ لا يعمل.
      var clock = DateTime(2026, 8, 27, 12);
      final deadline = clock.add(const Duration(seconds: 20));

      await tester.pumpWidget(MaterialApp(
        home: Countdown(
          deadline: deadline,
          now: () => clock,
          builder: (_, left, expired) => Text(
            expired ? 'انقضت' : 'باقٍ',
            textDirection: TextDirection.rtl,
          ),
        ),
      ));
      expect(find.text('باقٍ'), findsOneWidget);

      // في الساعة الأخيرة تكون الدقّة خمسَ عشرةَ ثانية، فنبضتان تكفيان.
      clock = clock.add(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('باقٍ'), findsOneWidget, reason: 'أربعُ ثوانٍ باقية');

      clock = clock.add(const Duration(seconds: 16));
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('انقضت'), findsOneWidget);
    });

    testWidgets('والدقّةُ تشتدّ في الساعة الأخيرة', (tester) async {
      // مهلةٌ بالساعات تنبض كلَّ دقيقة؛ فبعد نصف دقيقة لا يتغيّر المعروض.
      var clock = DateTime(2026, 8, 27, 12);
      var builds = 0;

      await tester.pumpWidget(MaterialApp(
        home: Countdown(
          deadline: clock.add(const Duration(hours: 5)),
          now: () => clock,
          builder: (_, left, __) {
            builds++;
            return Text(formatRemaining(left!),
                textDirection: TextDirection.rtl);
          },
        ),
      ));
      expect(find.text('5 ساعات'), findsOneWidget);

      final before = builds;
      clock = clock.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      // **ولا نبضَ كلَّ ثانيةٍ بلا فائدة**: بطاريّةُ السائق تُستهلك بمؤقّتٍ
      // يعيد البناء ستّين مرّةً في الدقيقة ليعرض الرقم نفسه.
      expect(builds, before, reason: 'لا نبض قبل انقضاء الدقيقة');

      clock = clock.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      expect(builds, greaterThan(before));
      expect(find.text('4 ساعات'), findsOneWidget);
    });

    testWidgets('ولا يبقى مؤقّتٌ بعد إزالة الودجت', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Countdown(
          deadline: DateTime.now().add(const Duration(hours: 5)),
          builder: (_, __, ___) => const SizedBox(),
        ),
      ));
      // إزالتُه بلا `dispose` تترك `Timer.periodic` يعمل إلى الأبد؛
      // و`pumpWidget` بشجرةٍ أخرى تُفشل الاختبار إن بقي مؤقّتٌ حيّ.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(tester.takeException(), isNull);
    });
  });

  group('نموذجُ الشكوى', () {
    test('«بانتظار تأكيدك» حالةٌ تنتظر صاحبَها لا الإدارة', () {
      final c = _complaint(status: ComplaintStatus.resolved);
      expect(c.awaitingConfirmation, isTrue);
      // **ولا تُعدّ منجَزة**: الحلُّ لا يُغلق.
      expect(c.status.needsStaff, isFalse);
      expect(c.status, isNot(ComplaintStatus.closed));
    });

    test('ومهلةُ التأكيد تُحسب من الآن ولا تُطبع بالسالب', () {
      final soon = _complaint(
        status: ComplaintStatus.resolved,
        autoCloseAt: DateTime.now().add(const Duration(days: 2)),
      );
      expect(soon.confirmTimeLeft!.inHours, greaterThan(40));

      final late = _complaint(
        status: ComplaintStatus.resolved,
        autoCloseAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(late.confirmTimeLeft, Duration.zero);
    });

    test('وشكوى لم تُحلّ بعدُ لا مهلةَ تأكيدٍ لها', () {
      final c = _complaint(
        status: ComplaintStatus.inProgress,
        autoCloseAt: DateTime.now().add(const Duration(days: 2)),
      );
      expect(c.confirmTimeLeft, isNull);
    });

    test('والارتدادُ يُعدّ — والرقمُ وحده يكشف حلولًا شكليّة', () {
      expect(_complaint().wasReopened, isFalse);
      expect(_complaint(reopenCount: 2).wasReopened, isTrue);
    });

    test('ورقمٌ يُقال في الهاتف لا UUID', () {
      expect(_complaint().displayNumber, '#1042');
    });

    test('والحالةُ تُقرأ من نصّ القاعدة، والمجهولُ يسقط إلى «جديدة»', () {
      expect(ComplaintStatus.parse('in_progress'), ComplaintStatus.inProgress);
      expect(ComplaintStatus.parse('closed'), ComplaintStatus.closed);
      // نصٌّ لا نعرفه (نسخةُ خادمٍ أحدث) لا يُسقط الشاشة.
      expect(ComplaintStatus.parse('archived'), ComplaintStatus.open);
      expect(ComplaintStatus.parse(null), ComplaintStatus.open);
    });

    test('و«تنتظر عملًا» تشمل الجديدة وقيدَ المعالجة معًا', () {
      expect(ComplaintStatus.open.needsStaff, isTrue);
      expect(ComplaintStatus.inProgress.needsStaff, isTrue);
      expect(ComplaintStatus.resolved.needsStaff, isFalse);
      expect(ComplaintStatus.closed.needsStaff, isFalse);
    });

    test('والقراءةُ من المنظر تلتقط ما يحسبه لا ما تحسبه الشاشة', () {
      final c = Complaint.fromMap({
        'id': 'c9',
        'complaint_number': 1099,
        'status': 'open',
        'description': 'قطعةٌ مفقودة',
        'created_at': '2026-08-25T09:00:00Z',
        'type_label': 'قطعةٌ مفقودة',
        'sla_breached': true,
        'reopen_count': 1,
        'closed_by_timeout': false,
        'response_due_at': '2026-08-26T09:00:00Z',
      });
      expect(c.slaBreached, isTrue);
      expect(c.reopenCount, 1);
      expect(c.responseDueAt, isNotNull);
      expect(c.typeLabel, 'قطعةٌ مفقودة');
    });
  });

  group('الملخّص', () {
    test('الإغلاقُ بالإقرار والإغلاقُ بالصمت رقمان لا رقم', () {
      final s = ComplaintSummary.fromMap({
        'total': 40,
        'open_now': 3,
        'in_progress_now': 2,
        'sla_breached': 1,
        'closed_confirmed': 25,
        'closed_by_silence': 10,
        'reopened': 4,
        'median_response_hours': 3.5,
        'by_type': {'بقعةٌ لم تُزل': 12, 'تأخّرٌ في التسليم': 8},
      });

      // **ولو جُمعا لَبدا الصمتُ رضًا**: ٣٥ «مغلقة» رقمٌ يسرّ، وعشرةٌ منها
      // أصحابُها لم يقولوا إنّها حُلّت.
      expect(s.closedConfirmed, 25);
      expect(s.closedBySilence, 10);
      expect(s.closedConfirmed + s.closedBySilence, 35);

      expect(s.needsWork, 5);
      expect(s.reopened, 4);
      expect(s.byType['بقعةٌ لم تُزل'], 12);
    });

    test('وملخّصٌ فارغٌ لا يُسقط اللوحة', () {
      final s = ComplaintSummary.fromMap(const {});
      expect(s.total, 0);
      expect(s.byType, isEmpty);
      expect(s.medianResponseHours, isNull);
    });
  });

  group('الإنذار', () {
    test('السارِي وحده يُعدّ — والساقطُ والمُلغى لا', () {
      DriverWarning w({DateTime? expires, DateTime? revoked}) =>
          DriverWarning.fromMap({
            'id': 'w1',
            'reason': 'تأخّرٌ متكرّر',
            'created_at': '2026-08-01T00:00:00Z',
            if (expires != null) 'expires_at': expires.toIso8601String(),
            if (revoked != null) 'revoked_at': revoked.toIso8601String(),
          });

      expect(w().isActive, isTrue);
      expect(
        w(expires: DateTime.now().add(const Duration(days: 30))).isActive,
        isTrue,
      );
      // **والعقوبةُ الأبديّة ليست تقويمًا**: خطأٌ قبل سنةٍ ليس كخطأٍ أمس.
      expect(
        w(expires: DateTime.now().subtract(const Duration(days: 1))).isActive,
        isFalse,
      );
      // وما راجعتْه الإدارة فبرّأت صاحبَه لا يُعدّ ولو لم تنقضِ مدّتُه.
      expect(w(revoked: DateTime.now()).isActive, isFalse);
    });
  });

  group('نوعُ الشكوى', () {
    test('يُقرأ من القاعدة لا من الشيفرة — ومعه نطاقُ دورِه', () {
      final t = ComplaintType.fromMap({
        'id': 't1',
        'code': 'stain_remains',
        'label_ar': 'بقعةٌ لم تُزل',
        'for_role': 'customer',
        'suggested_against': 'laundry_staff',
        'allows_general': false,
      });
      expect(t.labelAr, 'بقعةٌ لم تُزل');
      expect(t.forRole, 'customer');
      expect(t.suggestedAgainst, 'laundry_staff');
      expect(t.allowsGeneral, isFalse);
    });

    test('ونوعٌ بلا دورٍ نوعٌ لكلّ الأدوار', () {
      final t = ComplaintType.fromMap({
        'id': 't2',
        'code': 'general_inquiry',
        'label_ar': 'استفسارٌ عام',
        'allows_general': true,
      });
      expect(t.forRole, isNull);
      expect(t.allowsGeneral, isTrue);
    });
  });

  group('الإعدادات', () {
    test('تُقرأ من القاعدة، ولا رقمَ منها في الشيفرة', () {
      final s = ComplaintSettings.fromMap({
        'is_enabled': true,
        'window_hours': 72,
        'response_sla_hours': 12,
        'auto_close_days': 7,
        'driver_warning_threshold': 5,
        'allow_general_tickets': false,
      });
      expect(s.windowHours, 72);
      expect(s.responseSlaHours, 12);
      expect(s.autoCloseDays, 7);
      expect(s.driverWarningThreshold, 5);
      expect(s.allowGeneralTickets, isFalse);
    });
  });
}
