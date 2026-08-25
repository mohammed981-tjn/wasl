import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// تنزيل ملفّ نصّيّ في المتصفّح عبر رابط `blob`.
///
/// وترميز UTF-8 صريحٌ لأن العربية بغيره تصل مشوّهة إلى Excel.
Future<bool> downloadText(String filename, String content) async {
  final bytes = utf8.encode(content);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // تحرير الرابط بعد النقر: تركُه يبقي المحتوى في الذاكرة حتى إغلاق التبويب.
  web.URL.revokeObjectURL(url);
  return true;
}
