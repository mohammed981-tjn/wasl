import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// تهيئة الاتصال ونقطةُ وصولٍ واحدة إليه.
///
/// **لماذا نقطة واحدة**: `Supabase.instance.client` منثورةً في مئة ملفّ تجعل
/// استبدال الخادم — أو إدخال طبقة تسجيلٍ أو مهلة — تعديلًا في مئة موضع.
class Db {
  const Db._();

  static Future<void> init() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // `publishableKey` لا `anonKey`: الأخيرة مهجورة في الإصدار الحالي.
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => Supabase.instance.client.auth;

  static User? get currentUser => auth.currentUser;
  static bool get isSignedIn => currentUser != null;
}

/// خطأٌ من القاعدة مُترجَمٌ إلى رسالةٍ تُقال لمستخدم.
///
/// رسائل Postgres الخام («new row violates row-level security policy for table
/// orders») صحيحةٌ ولا تصلح لشاشة. وأهمّ من ذلك أنها تُفشي أسماء الجداول
/// وسياساتها لمن يجرّب.
String humanizeDbError(Object error) {
  // **أشيعُ خطأٍ في الاستعمال الحقيقيّ ليس خطأ قاعدة بل انقطاع شبكة** — نفقٌ
  // في مصعد، أو بيانات نفدت، أو خادمٌ محجوب.
  //
  // والفحص بالنوع وحده لا يكفي: `supabase_flutter` **يغلّف** فشل الجلب في
  // `AuthRetryableFetchException`، فيلتقطه فرع `AuthException` أدناه ويعيد
  // نصّه الخام. وقد ظهر ذلك فعلًا على الشاشة:
  //   «ClientException: Failed to fetch, uri=https://xxxx.supabase.co/auth/v1/otp»
  // غيرُ مفهوم لمستخدم، ويُفشي عنوان الخادم كاملًا.
  //
  // فيُفحص النوعُ **والنصّ** معًا، ويقع الفحص أوّلًا قبل كل فرعٍ آخر.
  final raw = error.toString();
  final looksLikeNetwork = error is SocketException ||
      error is ClientException ||
      error is TimeoutException ||
      RegExp(
        r'Failed to fetch|Failed host lookup|Connection (refused|reset|closed|timed out)'
        r'|Network is unreachable|SocketException|ClientException|XMLHttpRequest',
        caseSensitive: false,
      ).hasMatch(raw);

  if (looksLikeNetwork) {
    return 'تعذّر الاتصال بالخادم — تحقّق من اتصالك بالإنترنت وأعد المحاولة';
  }

  if (error is PostgrestException) {
    final msg = error.message;
    // الرسائل التي نرفعها نحن بالعربية من الحرّاس تمرّ كما هي: كُتبت لتُقرأ.
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(msg)) return msg;

    return switch (error.code) {
      '23505' => 'هذا السجلّ موجود مسبقًا',
      '23503' => 'لا يمكن الحذف: سجلّات أخرى تعتمد عليه',
      '23514' => 'قيمة غير مقبولة',
      '23P01' => 'تتعارض القيمة مع سجلّ آخر',
      '42501' => 'لا تملك صلاحية هذا الإجراء',
      'PGRST116' => 'لم يُعثر على السجلّ',
      _ => 'تعذّر تنفيذ العملية',
    };
  }

  if (error is AuthException) {
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(error.message)) return error.message;
    return switch (error.message) {
      'Invalid login credentials' => 'بيانات الدخول غير صحيحة',
      'Email not confirmed' => 'لم يُؤكَّد البريد بعد',
      'Token has expired or is invalid' => 'انتهت صلاحية الرمز',
      'Unsupported phone provider' ||
      'Phone provider is disabled' =>
        'الدخول برقم الجوال غير مفعَّل بعد — استعمل البريد مؤقّتًا',
      _ => 'تعذّر تسجيل الدخول',
    };
  }

  // وما بقي: رسالةٌ عامّة، ولا يُعرض نصّ الاستثناء الخام. من يحتاج التفصيل
  // يجده في سجلّ المطوّر لا على شاشة عميل.
  return 'حدث خطأ غير متوقّع';
}
