// اختبار تحويل بيانات القاعدة إلى نماذج.
//
// **لماذا هذا أهمّ اختبارٍ في التطبيق**: كل خطأٍ هنا يظهر بعيدًا عن سببه —
// مبلغٌ صفر في فاتورة، أو حالةٌ لا تطابقها شاشة، أو انفجارٌ عند فتح طلب. ولا
// يمسكه محلّلٌ لأن `Map<String, dynamic>` تقبل كل شيء.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/enums.dart';
import 'package:wasl/models/models.dart';

void main() {
  group('الأنواع المُعدَّدة', () {
    test('كل حالة طلب تُقرأ من اسمها في القاعدة وتعود إليه', () {
      for (final s in OrderStatus.values) {
        expect(OrderStatus.fromWire(s.wireName), s,
            reason: 'الحالة ${s.name} لا تعود إلى نفسها');
        expect(s.labelAr, isNotEmpty, reason: '${s.name} بلا تسمية عربية');
      }
    });

    test('قيمة غير معروفة ترفع خطأً ولا تُبتلع بصمت', () {
      // الابتلاع أخطر: حالةٌ مجهولة تصير قيمةً افتراضية، فيبدو الطلب في مرحلة
      // ليس فيها ولا يشتكي أحد حتى يشتكي عميل.
      expect(() => OrderStatus.fromWire('washng'), throwsArgumentError);
      expect(() => AppRole.fromWire('Admin'), throwsArgumentError);
      expect(() => PricingUnit.fromWire(''), throwsArgumentError);
    });

    test('مراحل داخل المغسلة ست، والنهائية ثلاث', () {
      expect(OrderStatus.values.where((s) => s.isInsideLaundry).length, 6);
      expect(OrderStatus.values.where((s) => s.isTerminal).length, 3);
      expect(OrderStatus.draft.isActive, isFalse);
      expect(OrderStatus.delivered.isActive, isFalse);
      expect(OrderStatus.washing.isActive, isTrue);
    });

    test('من يفتح حزمة الإدارة أربعة أدوار لا سبعة', () {
      final admins =
          AppRole.values.where((r) => r.usesAdminApp).map((r) => r.name);
      expect(admins,
          containsAll(['superAdmin', 'branchManager', 'customerService', 'accountant']));
      expect(AppRole.driver.usesAdminApp, isFalse);
      expect(AppRole.laundryStaff.usesAdminApp, isFalse);
      expect(AppRole.customer.usesAdminApp, isFalse);
    });
  });

  group('قراءة الأرقام', () {
    // أعمدة numeric تصل عبر PostgREST **نصًّا** حفاظًا على الدقّة، بينما int
    // تصل عددًا. فقراءة `as double` تنفجر على أوّل مبلغ.
    test('numeric تصل نصًّا و int تصل عددًا — وكلاهما يُقرأ', () {
      final s = LaundryService.fromMap({
        'id': 'x',
        'laundry_id': 'l',
        'name_ar': 'ثوب',
        'unit': 'piece',
        'base_price': '8.50',        // نصّ — كما تصل فعلًا
        'turnaround_hours': 24,      // عدد
        'min_quantity': '0',
        'express_multiplier': '1.50',
        'is_active': true,
        'sort_order': 1,
      });
      expect(s.basePrice, 8.5);
      expect(s.turnaroundHours, 24);
      expect(s.expressMultiplier, 1.5);
      expect(s.acceptsExpress, isTrue);
    });

    test('القيم الغائبة تصير أصفارًا لا استثناءات', () {
      final b = Branch.fromMap({
        'id': 'b', 'laundry_id': 'l', 'name_ar': 'فرع',
        // daily_capacity_pieces غائب
      });
      expect(b.dailyCapacityPieces, 0);
      expect(b.hasCapacityLimit, isFalse, reason: 'صفر يعني بلا سقف لا بلا طاقة');
      expect(b.city, 'المدينة المنورة');
    });

    test('مضاعِف الاستعجال 1.0 يعني «لا تقبل الاستعجال»', () {
      final s = LaundryService.fromMap({
        'id': 'x', 'laundry_id': 'l', 'name_ar': 'بطانية',
        'unit': 'piece', 'base_price': 25, 'turnaround_hours': 48,
        'min_quantity': 0, 'express_multiplier': 1.0,
      });
      expect(s.acceptsExpress, isFalse);
    });
  });

  group('الطلب', () {
    Map<String, dynamic> orderMap({
      String status = 'washing',
      String? promised,
      double total = 115,
    }) =>
        {
          'id': 'o1',
          'order_number': 10042,
          'laundry_id': 'l',
          'branch_id': 'b',
          'customer_id': 'c',
          'status': status,
          'payment_status': 'unpaid',
          'subtotal': '100.00',
          'delivery_fee': '15.00',
          'discount_amount': '0',
          'vat_amount': '15.00',
          'total': '$total',
          'created_at': '2026-08-25T09:00:00Z',
          'promised_ready_at': promised,
          'profiles': {'full_name': 'محمد'},
          'branches': {'name_ar': 'فرع المركز'},
          'order_items': [
            {
              'id': 'i1', 'order_id': 'o1', 'service_name_ar': 'ثوب',
              'unit': 'piece', 'quantity': '3', 'unit_price': '8',
              'line_total': '24',
            }
          ],
        };

    test('يُقرأ كاملًا مع الجداول المضمومة', () {
      final o = LaundryOrder.fromMap(orderMap());
      expect(o.orderNumber, 10042);
      expect(o.customerName, 'محمد');
      expect(o.branchName, 'فرع المركز');
      expect(o.items, hasLength(1));
      expect(o.items.first.quantity, 3);
      expect(o.total, 115);
    });

    test('«متأخّر» = وُعِد بالجاهزية ولم يجهز', () {
      final late = LaundryOrder.fromMap(orderMap(
          promised: DateTime.now()
              .subtract(const Duration(hours: 2))
              .toUtc()
              .toIso8601String()));
      expect(late.isLate, isTrue);

      final onTime = LaundryOrder.fromMap(orderMap(
          promised: DateTime.now()
              .add(const Duration(hours: 2))
              .toUtc()
              .toIso8601String()));
      expect(onTime.isLate, isFalse);
    });

    test('المسلَّم لا يكون متأخّرًا مهما تجاوز وعده', () {
      // الطلب الذي سُلِّم انتهى. ووسمُه «متأخّرًا» يملأ اللوحة بما لا يُعمل عليه.
      final delivered = LaundryOrder.fromMap(orderMap(
          status: 'delivered',
          promised: DateTime.now()
              .subtract(const Duration(days: 3))
              .toUtc()
              .toIso8601String()));
      expect(delivered.isLate, isFalse);
    });

    test('الجاهز لا يكون متأخّرًا: الوعد كان بالجاهزية وقد تحقّق', () {
      final ready = LaundryOrder.fromMap(orderMap(
          status: 'ready',
          promised: DateTime.now()
              .subtract(const Duration(hours: 5))
              .toUtc()
              .toIso8601String()));
      expect(ready.isLate, isFalse);
    });

    test('طلبٌ بلا وعدِ جاهزية لا يكون متأخّرًا', () {
      expect(LaundryOrder.fromMap(orderMap()).isLate, isFalse);
    });
  });

  group('فتحة الموعد', () {
    test('تحمل سبب الإغلاق — «ممتلئ» تبيع و«لا مواعيد» لا', () {
      final slot = BookingSlot.fromMap({
        'slot_start': '2026-08-26T17:00:00Z',
        'slot_end': '2026-08-26T18:00:00Z',
        'is_available': false,
        'orders_booked': 8,
        'pieces_booked': '120',
        'blocked_reason': 'الفتحة ممتلئة',
      });
      expect(slot.isAvailable, isFalse);
      expect(slot.blockedReason, 'الفتحة ممتلئة');
      expect(slot.piecesBooked, 120);
    });
  });

  group('تسعيرة التوصيل', () {
    test('غير قابل للخدمة يحمل سببه', () {
      final q = DeliveryQuote.fromMap({
        'fee': '0',
        'distance_km': '31.40',
        'zone_id': null,
        'reason': 'خارج نطاق خدمة الفرع',
        'serviceable': false,
      });
      expect(q.serviceable, isFalse);
      expect(q.fee, 0);
      expect(q.distanceKm, 31.4);
      expect(q.reason, 'خارج نطاق خدمة الفرع');
    });
  });
}
