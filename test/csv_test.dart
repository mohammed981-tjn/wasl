// اختبار توليد CSV.
//
// **العطل هنا لا يبدو عطلًا**: اسم خدمةٍ فيه فاصلة يكسر كل الأعمدة بعده في
// Excel بلا رسالة خطأ — فيبدو الملفّ سليمًا، ويقرأ المحاسبُ أرقامًا في غير
// خاناتها ويبني عليها قرارًا.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/services/csv.dart';

void main() {
  test('الحالة البسيطة بلا اقتباسٍ زائد', () {
    final csv = toCsv(['الخدمة', 'الإيراد'], [
      ['ثوب', 120],
      ['شماغ', 45.5],
    ]);
    expect(csv, contains('الخدمة,الإيراد'));
    expect(csv, contains('ثوب,120'));
    expect(csv, contains('شماغ,45.5'));
    expect(csv, isNot(contains('"ثوب"')), reason: 'لا اقتباس بلا داعٍ');
  });

  test('الفاصلة اللاتينية تُقتبس — وإلا انزاحت كل الأعمدة بعدها', () {
    final csv = toCsv(['الخدمة', 'الإيراد'], [
      ['ثوب, غسيل وكوي', 120],
    ]);
    expect(csv, contains('"ثوب, غسيل وكوي",120'));
  });

  test('والفاصلة العربية «،» لا تُقتبس — لأنها لا تفصل شيئًا', () {
    // تمييزٌ يسهل الخلط فيه: «،» (U+060C) حرفٌ عربيّ، وفاصلُ CSV هو «,»
    // اللاتينيّ وحده. فاقتباس الأولى تشويهٌ بلا سبب — والأسماء العربية مليئة
    // بها.
    final csv = toCsv(['الخدمة'], [
      ['ثوب، غسيل وكوي'],
    ]);
    expect(csv, contains('ثوب، غسيل وكوي'));
    expect(csv, isNot(contains('"ثوب، غسيل وكوي"')));
  });

  test('الاقتباس داخل النصّ يُضاعَف — هذا ما يفهمه Excel', () {
    final csv = toCsv(['a'], [
      ['قال "مرحبًا"'],
    ]);
    expect(csv, contains('"قال ""مرحبًا"""'));
  });

  test('السطر الجديد داخل خليّة يُقتبس ولا يُنشئ صفًّا', () {
    final csv = toCsv(['ملاحظة'], [
      ['سطر\nثانٍ'],
    ]);
    expect(csv, contains('"سطر\nثانٍ"'));
    // ثلاثة أسطر: BOM+الترويسة، ثم سطرا الخليّة، وسطرٌ فارغ في الآخر.
    expect(csv.trim().split('\n').length, 3);
  });

  test('يبدأ بـBOM كي يفتح Excel العربية بترميزها', () {
    // بدونه يعرض Excel «Ø«Ù^Ø¨» بدل «ثوب» — وهو أشهر أعطال CSV العربية.
    final csv = toCsv(['أ'], []);
    expect(csv.codeUnitAt(0), 0xFEFF);
  });

  test('القيم الفارغة تصير خلايا فارغة لا كلمة null', () {
    final csv = toCsv(['a', 'b'], [
      [null, 5],
    ]);
    expect(csv, contains(',5'));
    expect(csv, isNot(contains('null')));
  });

  test('جدولٌ بلا صفوف يعطي ترويسةً وحدها', () {
    final csv = toCsv(['أ', 'ب'], []);
    expect(csv.trim().split('\n'), hasLength(1));
  });
}
