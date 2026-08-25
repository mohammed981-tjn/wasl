/// توليد CSV.
///
/// **الاقتباس ليس تجميلًا**: اسم خدمةٍ فيه فاصلة («ثوب، غسيل وكوي») يكسر كل
/// الأعمدة بعده في Excel — بلا رسالة خطأ، فيبدو الملفّ سليمًا ويقرأ المحاسبُ
/// أرقامًا في غير خاناتها.
String toCsv(List<String> headers, List<List<Object?>> rows) {
  String cell(Object? v) {
    final s = v?.toString() ?? '';
    // الاقتباس يلزم عند وجود فاصلة أو اقتباسٍ أو سطرٍ جديد. والاقتباس داخل
    // النصّ يُضاعَف — هذا ما يفهمه Excel.
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  final buffer = StringBuffer()
    // BOM كي يفتح Excel العربية بترميزها الصحيح. بدونه يعرض «Ø«Ù^Ø¨».
    ..write('﻿')
    ..writeln(headers.map(cell).join(','));

  for (final r in rows) {
    buffer.writeln(r.map(cell).join(','));
  }
  return buffer.toString();
}
