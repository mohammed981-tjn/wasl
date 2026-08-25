/// واجهةٌ واحدة لتنزيل CSV، بتنفيذين.
///
/// الاستيراد الشرطيّ لا `kIsWeb`: `dart:js_interop` **لا يُترجَم** على الجوّال
/// أصلًا، فالفحص وقت التشغيل لا ينفع — يجب ألّا تدخل الشيفرة الحزمة.
library;

export 'csv_download_stub.dart'
    if (dart.library.js_interop) 'csv_download_web.dart';
