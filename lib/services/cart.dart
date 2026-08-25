import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/models.dart';

/// سطرٌ في السلّة.
class CartLine {
  const CartLine({required this.service, required this.quantity, required this.unitPrice});

  final LaundryService service;
  final double quantity;

  /// **السعر النافذ في الفرع** كما أعادته القاعدة — لا `service.basePrice`.
  /// الفرق بينهما هو بالضبط ما يجعل تجاوز سعر الفرع يعمل.
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;

  CartLine copyWith({double? quantity}) =>
      CartLine(service: service, quantity: quantity ?? this.quantity, unitPrice: unitPrice);
}

/// سلّة العميل.
///
/// **لا تحسب ضريبةً ولا رسمَ توصيلٍ ولا خصمًا.** تجمع البنود وحدها، وما عداها
/// تسأل عنه القاعدة — فلو حسبت السلّة رسمًا وحسبته القاعدة، اختلفا يومًا وصار
/// الخلاف مع العميل على رقمٍ لا أحد يملك مرجعه.
class Cart extends ChangeNotifier {
  final Map<String, CartLine> _lines = {};

  List<CartLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;
  int get count => _lines.length;

  double get subtotal =>
      _lines.values.fold(0, (sum, l) => sum + l.lineTotal);

  /// حِمل السلّة بالقطع المكافئة — نفس معامِلات القاعدة (`order_piece_load`).
  /// يُرسل إلى `available_slots` كي تُقاس الفتحة بما سيدخلها فعلًا.
  double get pieceLoad => _lines.values.fold(0, (sum, l) {
        final factor = switch (l.service.unit) {
          PricingUnit.piece => 1.0,
          PricingUnit.kilogram => 4.0,
          PricingUnit.basket => 15.0,
        };
        return sum + l.quantity * factor;
      });

  double quantityOf(String serviceId) => _lines[serviceId]?.quantity ?? 0;

  void setQuantity(LaundryService service, double quantity, double unitPrice) {
    if (quantity <= 0) {
      _lines.remove(service.id);
    } else {
      _lines[service.id] =
          CartLine(service: service, quantity: quantity, unitPrice: unitPrice);
    }
    notifyListeners();
  }

  /// الخدمات التي لم تبلغ حدَّها الأدنى.
  ///
  /// **تُفحص قبل الإرسال لا بعده**: الحدّ الأدنى قاعدةُ عملٍ تعرفها القاعدة،
  /// لكن ردّها يأتي بعد إنشاء الطلب — وإخبار العميل مبكرًا أرحم من رفضٍ متأخّر.
  List<LaundryService> get belowMinimum => _lines.values
      .where((l) => l.service.minQuantity > 0 && l.quantity < l.service.minQuantity)
      .map((l) => l.service)
      .toList();

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
