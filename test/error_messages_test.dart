// اختبار ترجمة الأخطاء.
//
// **لماذا يستحقّ ملفًّا**: هذا بالضبط ما فشل على الشاشة. عرضَ التطبيقُ
// «ClientException: Failed to fetch, uri=https://xxxx.supabase.co/auth/v1/otp»
// لمستخدمٍ عربيّ — غيرُ مفهوم، ويُفشي عنوان الخادم. وسببُه أن
// `supabase_flutter` **يغلّف** فشل الشبكة، ففحصُ النوع وحده يفوته.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wasl/services/supabase_service.dart';

const _networkMessage =
    'تعذّر الاتصال بالخادم — تحقّق من اتصالك بالإنترنت وأعد المحاولة';

void main() {
  group('أخطاء الشبكة', () {
    test('الأنواع المباشرة تُترجَم', () {
      expect(humanizeDbError(const SocketException('nope')), _networkMessage);
      expect(humanizeDbError(ClientException('Failed to fetch')), _networkMessage);
      expect(humanizeDbError(TimeoutException('slow')), _networkMessage);
    });

    test('الاستثناء الملفوف يُترجَم أيضًا — وهو ما فشل فعلًا', () {
      // هكذا يصل من supabase_flutter: AuthException نصّه ClientException.
      final wrapped = AuthException(
          'ClientException: Failed to fetch, uri=https://x.supabase.co/auth/v1/otp');
      expect(humanizeDbError(wrapped), _networkMessage);
    });

    test('ولا يُفشى عنوان الخادم في أي حال', () {
      final wrapped = AuthException(
          'ClientException: Failed to fetch, uri=https://secret.supabase.co/auth/v1/otp');
      expect(humanizeDbError(wrapped), isNot(contains('supabase.co')));
      expect(humanizeDbError(wrapped), isNot(contains('http')));
    });

    test('صيغ فشلٍ أخرى تُمسك كذلك', () {
      for (final raw in [
        'Failed host lookup: xxx.supabase.co',
        'Connection refused',
        'Connection timed out',
        'Network is unreachable',
      ]) {
        expect(humanizeDbError(AuthException(raw)), _networkMessage,
            reason: 'لم تُمسك: $raw');
      }
    });
  });

  group('أخطاء القاعدة', () {
    PostgrestException pg(String code, [String msg = 'x']) =>
        PostgrestException(message: msg, code: code);

    test('رموز Postgres تُترجَم إلى عربيّة مفهومة', () {
      expect(humanizeDbError(pg('23505')), 'هذا السجلّ موجود مسبقًا');
      expect(humanizeDbError(pg('23503')), contains('تعتمد عليه'));
      expect(humanizeDbError(pg('42501')), 'لا تملك صلاحية هذا الإجراء');
      expect(humanizeDbError(pg('23P01')), contains('تتعارض'));
    });

    test('رسائل حرّاسنا العربية تمرّ كما هي — كُتبت لتُقرأ', () {
      // هذه ترفعها محفّزات القاعدة نصًّا عربيًّا، فترجمتُها تفقد التفصيل.
      const guard = 'انتقال غير مسموح: placed ← delivered';
      expect(humanizeDbError(pg('P0001', guard)), guard);

      const roleGuard = 'لا يُمنح دور super_admin إلا من super_admin';
      expect(humanizeDbError(pg('42501', roleGuard)), roleGuard);
    });

    test('رمزٌ مجهول يعطي رسالةً عامّة لا نصًّا خامًا', () {
      expect(humanizeDbError(pg('99999', 'some internal detail')),
          'تعذّر تنفيذ العملية');
    });
  });

  group('أخطاء المصادقة', () {
    test('بيانات دخولٍ خاطئة', () {
      expect(humanizeDbError(AuthException('Invalid login credentials')),
          'بيانات الدخول غير صحيحة');
    });

    test('مزوّد الجوال غير مفعَّل يقترح البديل بدل أن يقف', () {
      // الرسالة التي سيراها أوّل من يجرّب الدخول بالجوال قبل تفعيل المزوّد.
      final msg = humanizeDbError(AuthException('Phone provider is disabled'));
      expect(msg, contains('غير مفعَّل'));
      expect(msg, contains('البريد'));
    });

    test('استثناءٌ غريب لا يُعرض نصّه الخام', () {
      expect(humanizeDbError(StateError('internal: table wasl_secret')),
          'حدث خطأ غير متوقّع');
    });
  });
}
