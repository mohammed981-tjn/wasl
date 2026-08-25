import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_role.dart';
import 'services/supabase_service.dart';

/// مدخل نكهة «laundry».
///
/// النكهة تُثبَّت هنا وقت البناء، ولا تُقرأ من القاعدة ولا من إعداد: حزمةُ
/// السائق يجب ألّا **تحمل** شيفرة الإدارة أصلًا، لا أن تُخفيها.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.init();
  runApp(const WaslApp(flavor: AppFlavor.laundry));
}
