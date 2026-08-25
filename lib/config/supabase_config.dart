/// إعداد الاتصال بمشروع Supabase.
///
/// **الرابط والمفتاح المنشور ليسا سرّين.** مصمَّمان أصلًا للتضمين في تطبيق
/// العميل: كلُّ التحكّم الأمنيّ يقع في سياسات RLS على الجداول لا في إخفاء هذا
/// المفتاح. وقد أُثبت مرارًا أن استخراج المفاتيح من حزمة APK يستغرق ثوانٍ —
/// فأمنٌ يقوم على إخفاء ما في الحزمة ليس أمنًا.
///
/// **ومفتاح `service_role` سرٌّ مطلق**: يتجاوز RLS بتصميمه، فلا يوضع في حزمة
/// ولا في مستودع. موضعه أسرارُ دوالّ Edge وحدها.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kdpzhkapmbzysqzmchzp.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_j6y-tRztkRsyWU1EN3bFiw_p_L4_oZc',
  );
}
