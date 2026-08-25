import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_role.dart';
import 'services/supabase_service.dart';

/// المدخل الموحَّد، والنكهة تُثبَّت وقت البناء.
///
/// النكهة لا تُقرأ من القاعدة ولا من إعدادٍ يُبدَّل بعد التثبيت: حزمةُ السائق
/// يجب ألّا **تحمل** شيفرة الإدارة أصلًا، لا أن تُخفيها خلف شرط.
///
/// و«العميل» هو الافتراضُ حين لا تُمرَّر `--dart-define=WASL_FLAVOR=`: البناء
/// بلا نكهةٍ يجب أن ينتج تطبيقًا صالحًا لا شاشةً فارغة.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.init();
  runApp(WaslApp(flavor: pinnedFlavor ?? AppFlavor.customer));
}
