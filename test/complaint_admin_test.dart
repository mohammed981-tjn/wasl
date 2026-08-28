// اختبار ضبط الشكاوى من اللوحة.
//
// **الخطر هنا صمتٌ لا خطأ.** أخطاءُ شاشةِ الإعدادات لا تنفجر: رقمٌ يُحفظ
// بلا أثر، أو نوعٌ يُحذف فيُفرغ شكاوى قديمةً من معناها، أو حدثُ «حُلّت»
// يبقى بلا رسالةٍ فلا يُغلق ملفٌّ بالصمت أبدًا — والشكاوى تتراكم في الطابور
// بلا سببٍ ظاهر.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/models.dart';

void main() {
  group('حدثُ الشكوى', () {
    test('«حُلّت» وحدها يقوم عليها الإغلاق', () {
      // بلا رسالتها لا يُغلق ملفٌّ بالصمت: الكنسُ يشترط أن يكون صاحبُها
      // قد سُئل. فغيابُها ليس نقصَ لطفٍ بل تعطيلُ دورة الحياة.
      expect(ComplaintEvent.resolved.isLoadBearing, isTrue);
      for (final e in ComplaintEvent.values) {
        if (e != ComplaintEvent.resolved) {
          expect(e.isLoadBearing, isFalse, reason: '${e.code} ليس كذلك');
        }
      }
    });

    test('وكلُّ حدثٍ له وصفٌ يقول لمن الرسالة', () {
      // الوصفُ ليس زينة: مديرٌ يكتب «نعتذر إليك» في حدث «فُتحت» يرسل اعتذارًا
      // إلى موظّفيه هو.
      for (final e in ComplaintEvent.values) {
        expect(e.label, isNotEmpty);
        expect(e.hint, isNotEmpty);
      }
    });

    test('والمجهولُ يسقط إلى «فُتحت» ولا يُسقط الشاشة', () {
      expect(ComplaintEvent.parse('resolved'), ComplaintEvent.resolved);
      expect(ComplaintEvent.parse('closed_by_timeout'),
          ComplaintEvent.closedByTimeout);
      // حدثٌ يُضاف في خادمٍ أحدث لا يكسر لوحةً قديمة.
      expect(ComplaintEvent.parse('escalated'), ComplaintEvent.opened);
      expect(ComplaintEvent.parse(null), ComplaintEvent.opened);
    });
  });

  group('نوعُ الشكوى في اللوحة', () {
    ComplaintType t({bool isActive = true}) => ComplaintType(
          id: 'x',
          code: 'stain_remains',
          labelAr: 'بقعةٌ لم تُزل',
          forRole: 'customer',
          suggestedAgainst: 'laundry_staff',
          isActive: isActive,
          sortOrder: 10,
        );

    test('التعطيلُ يقلب الرايةَ ولا يمسّ الرمز', () {
      // **الرمزُ يُجمَّع عليه التقرير.** وتبديلُه على نوعٍ استُعمل يجعل تقريرَ
      // الشهر الماضي يقول غيرَ ما وقع — والقاعدةُ تمنعه، وهذا يوافقها.
      final off = t().copyWith(isActive: false);
      expect(off.isActive, isFalse);
      expect(off.code, 'stain_remains');
      expect(off.id, 'x');
    });

    test('والاسمُ المعروض يُحسَّن والرمزُ تحته ثابت', () {
      final renamed = t().copyWith(labelAr: 'بقعةٌ لم تُزَل تمامًا');
      expect(renamed.labelAr, 'بقعةٌ لم تُزَل تمامًا');
      expect(renamed.code, 'stain_remains');
    });

    test('و«لا أحد» في الطرف المقترَح تُمحى ولا تُبقي القديم', () {
      // **فخُّ `copyWith`**: `suggestedAgainst: null` لا يمحو شيئًا لأنّ
      // `null` هي «لم يُمرَّر». ولولا راية صريحة لَبقي الطرفُ القديم بعد أن
      // اختار المديرُ «لا أحد» — فيُقترح سائقٌ على شكوى لا علاقة له بها.
      final cleared = t().copyWith(clearSuggested: true);
      expect(cleared.suggestedAgainst, isNull);

      final notCleared = t().copyWith();
      expect(notCleared.suggestedAgainst, 'laundry_staff');
    });

    test('و«كلُّ الأدوار» كذلك', () {
      expect(t().copyWith(clearForRole: true).forRole, isNull);
      expect(t().copyWith().forRole, 'customer');
    });

    test('والقراءةُ تلتقط التعطيلَ والترتيب', () {
      final parsed = ComplaintType.fromMap({
        'id': 'y',
        'code': 'other',
        'label_ar': 'أخرى',
        'is_active': false,
        'sort_order': 999,
        'allows_general': true,
      });
      expect(parsed.isActive, isFalse);
      expect(parsed.sortOrder, 999);
      expect(parsed.allowsGeneral, isTrue);
      expect(parsed.forRole, isNull);
    });
  });

  group('قالبُ الرسالة', () {
    test('يُقرأ بحدثه وقناته وجمهوره', () {
      final t = ComplaintTemplate.fromMap({
        'id': 'tp1',
        'event': 'resolved',
        'channel': 'in_app',
        'audience': 'customer',
        'title_ar': 'ردٌّ على شكواك #{رقم_الشكوى}',
        'body_ar': '{ردّ_الإدارة}\n\nهل حُلّت؟',
        'is_active': true,
      });
      expect(t.event, ComplaintEvent.resolved);
      expect(t.channel, 'in_app');
      expect(t.bodyAr, contains('{ردّ_الإدارة}'));
    });

    test('والتحريرُ يمسّ النصَّ ولا يمسّ هُويّة القالب', () {
      // الحدثُ والقناةُ والجمهور تُحدَّد عند الإنشاء: تبديلُها على قالبٍ قائم
      // ينقل رسالةً من جمهورٍ إلى آخر بلا أن يلحظ أحد.
      final t = ComplaintTemplate.fromMap({
        'id': 'tp1',
        'event': 'resolved',
        'channel': 'in_app',
        'audience': 'customer',
        'body_ar': 'نصٌّ قديم',
      });
      final edited = t.copyWith(bodyAr: 'نصٌّ جديد', isActive: false);

      expect(edited.bodyAr, 'نصٌّ جديد');
      expect(edited.isActive, isFalse);
      expect(edited.event, ComplaintEvent.resolved);
      expect(edited.channel, 'in_app');
      expect(edited.audience, 'customer');
      expect(edited.id, 'tp1');
    });
  });

  group('الإعدادات', () {
    test('تُبنى وتُقرأ بالقيم نفسها — ورقمٌ يُحفظ بلا أثرٍ أسوأُ من خطأ', () {
      const s = ComplaintSettings(
        windowHours: 96,
        responseSlaHours: 12,
        autoCloseDays: 5,
        driverWarningThreshold: 4,
        allowGeneralTickets: false,
      );
      expect(s.windowHours, 96);
      expect(s.responseSlaHours, 12);
      expect(s.autoCloseDays, 5);
      expect(s.driverWarningThreshold, 4);
      expect(s.allowGeneralTickets, isFalse);
    });

    test('والافتراضاتُ تطابق القاعدة', () {
      // **لو اختلفت لَعرضت الشاشةُ رقمًا والقاعدةُ تعمل بآخر** — على مغسلةٍ
      // بلا صفِّ إعداداتٍ بعد.
      const d = ComplaintSettings();
      expect(d.windowHours, 48);
      expect(d.responseSlaHours, 24);
      expect(d.autoCloseDays, 3);
      expect(d.driverWarningThreshold, 3);
      expect(d.isEnabled, isTrue);
      expect(d.allowGeneralTickets, isTrue);
    });
  });
}
