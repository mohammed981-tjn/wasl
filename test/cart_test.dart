// اختبار السلّة.
//
// **أهمّ ما هنا ثابتٌ يعبر حدودًا**: معامِلات تحويل الوحدات إلى «قطع مكافئة»
// مكتوبةٌ مرّتين — في `order_piece_load` بلغة SQL، وفي `Cart.pieceLoad` بلغة
// Dart. واختلافُهما يجعل السلّة تحجز فتحةً لا تتّسع لها فعلًا: العميل يحجز،
// والقاعدة تقبل، ثم يجد الفرعُ يومًا فوق طاقته.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/enums.dart';
import 'package:wasl/models/models.dart';
import 'package:wasl/services/cart.dart';

LaundryService svc({
  String id = 's1',
  String name = 'ثوب',
  PricingUnit unit = PricingUnit.piece,
  double price = 8,
  double minQuantity = 0,
  int hours = 24,
}) =>
    LaundryService(
      id: id,
      laundryId: 'l',
      nameAr: name,
      unit: unit,
      basePrice: price,
      turnaroundHours: hours,
      minQuantity: minQuantity,
    );

void main() {
  group('الحساب', () {
    test('المجموع يُحسب بالسعر النافذ لا بسعر الكتالوج', () {
      // الفرع قد يتجاوز سعر المغسلة؛ والسلّة تحمل ما أعادته القاعدة.
      final cart = Cart();
      cart.setQuantity(svc(price: 8), 3, 9.5); // basePrice=8 والنافذ 9.5
      expect(cart.subtotal, 28.5);
    });

    test('تصفير الكمّية يحذف السطر', () {
      final cart = Cart();
      cart.setQuantity(svc(), 3, 8);
      expect(cart.count, 1);
      cart.setQuantity(svc(), 0, 8);
      expect(cart.isEmpty, isTrue);
    });

    test('إعادة الضبط تستبدل ولا تُراكم', () {
      final cart = Cart();
      cart.setQuantity(svc(), 3, 8);
      cart.setQuantity(svc(), 5, 8);
      expect(cart.count, 1);
      expect(cart.subtotal, 40);
    });
  });

  group('حِمل القطع — يجب أن يطابق order_piece_load في SQL', () {
    test('القطعة = ١', () {
      final cart = Cart();
      cart.setQuantity(svc(unit: PricingUnit.piece), 3, 8);
      expect(cart.pieceLoad, 3);
    });

    test('الكيلو = ٤ قطع', () {
      final cart = Cart();
      cart.setQuantity(svc(unit: PricingUnit.kilogram), 5, 12);
      expect(cart.pieceLoad, 20);
    });

    test('السلّة = ١٥ قطعة', () {
      final cart = Cart();
      cart.setQuantity(svc(unit: PricingUnit.basket), 1, 60);
      expect(cart.pieceLoad, 15);
    });

    test('الخليط يجمع كما تجمعه القاعدة: ٣ + (٥×٤) + ١٥ = ٣٨', () {
      // هذا نفسه ما يؤكّده اختبار SQL «الحِمل: ٣ قطع + ٥ كجم + سلّة = ٣٨».
      final cart = Cart();
      cart.setQuantity(svc(id: 'a', unit: PricingUnit.piece), 3, 8);
      cart.setQuantity(svc(id: 'b', unit: PricingUnit.kilogram), 5, 12);
      cart.setQuantity(svc(id: 'c', unit: PricingUnit.basket), 1, 60);
      expect(cart.pieceLoad, 38);
    });
  });

  group('الحدّ الأدنى', () {
    test('يُكشف قبل الإرسال لا بعده', () {
      final cart = Cart();
      cart.setQuantity(svc(minQuantity: 3), 2, 8);
      expect(cart.belowMinimum, hasLength(1));
      expect(cart.belowMinimum.first.nameAr, 'ثوب');
    });

    test('بلوغه يرفع التنبيه', () {
      final cart = Cart();
      cart.setQuantity(svc(minQuantity: 3), 3, 8);
      expect(cart.belowMinimum, isEmpty);
    });

    test('خدمةٌ بلا حدٍّ أدنى لا تُقيَّد', () {
      final cart = Cart();
      cart.setQuantity(svc(minQuantity: 0), 1, 8);
      expect(cart.belowMinimum, isEmpty);
    });
  });

  test('السلّة تُخطر مستمعيها عند كل تغيير', () {
    final cart = Cart();
    var notifications = 0;
    cart.addListener(() => notifications++);
    cart.setQuantity(svc(), 1, 8);
    cart.setQuantity(svc(), 2, 8);
    cart.clear();
    expect(notifications, 3);
  });
}
