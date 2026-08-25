// اختبار اشتقاق مهمّة السائق من صفّ الطلب.
//
// **ما يُختبر هنا بالتحديد**: أن نوع المهمّة يُشتقّ من **حالة الطلب** لا من
// معرّف السائق. والفرق ليس نظريًّا: السائق نفسه قد يكون سائقَ الاستلام
// والتسليم لطلبٍ واحد، فلو اشتُقّ النوع من «أيّ خانةٍ فيها اسمي» لَظهرت
// المهمّة استلامًا وهي تسليم — فيقود إلى بيت العميل ليأخذ ملابس سلّمها.
//
// ويُختبر أن الخطوة التالية تُقرأ من الحالة نفسها، وأن الفعل الأخير (الذي
// يحتاج إثباتًا ورمزًا) يُميَّز عمّا قبله.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/enums.dart';
import 'package:wasl/models/models.dart';

const _me = 'd0000000-0000-0000-0000-000000000001';

Map<String, dynamic> row({
  required String status,
  String? pickupDriver = _me,
  String? deliveryDriver,
  String? pickupSlot,
  String? deliverySlot,
  Map<String, dynamic>? pickupAddress,
  Map<String, dynamic>? deliveryAddress,
  String? phone,
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
      'discount_amount': '0.00',
      'vat_amount': '17.25',
      'total': '132.25',
      'created_at': '2026-08-25T09:00:00Z',
      'pickup_driver_id': pickupDriver,
      'delivery_driver_id': deliveryDriver,
      'pickup_slot_start': pickupSlot,
      'delivery_slot_start': deliverySlot,
      if (pickupAddress != null) 'pickup_address': pickupAddress,
      if (deliveryAddress != null) 'delivery_address': deliveryAddress,
      'profiles': {'full_name': 'محمد', if (phone != null) 'phone': phone},
    };

Map<String, dynamic> address({String label = 'المنزل', double lat = 24.46}) => {
      'id': 'a1',
      'user_id': 'c',
      'kind': 'home',
      'label': label,
      'district': 'قباء',
      'lat': lat,
      'lng': 39.61,
    };

void main() {
  group('نوع المهمّة يُشتقّ من الحالة', () {
    test('طلبٌ أُسند للاستلام ⇒ مهمّة استلام', () {
      final j = DriverJob.fromMap(row(status: 'pickup_assigned'), _me);
      expect(j.kind, JobKind.pickup);
      expect(j.isPickup, isTrue);
    });

    test('طلبٌ خرج للتوصيل ⇒ مهمّة تسليم', () {
      final j = DriverJob.fromMap(
          row(status: 'out_for_delivery', deliveryDriver: _me), _me);
      expect(j.kind, JobKind.delivery);
    });

    test('السائق نفسه في الخانتين: العبرة بالحالة لا بالخانة', () {
      // لو اشتُقّ النوع من «أين اسمي» لَجاء استلامًا — والطلب خرج للتوصيل.
      final j = DriverJob.fromMap(
        row(status: 'out_for_delivery', pickupDriver: _me, deliveryDriver: _me),
        _me,
      );
      expect(j.kind, JobKind.delivery);
    });
  });

  group('الموعد والعنوان يتبعان النوع', () {
    test('مهمّة الاستلام تأخذ فتحة الاستلام وعنوانه', () {
      final j = DriverJob.fromMap(
        row(
          status: 'pickup_assigned',
          pickupSlot: '2026-08-26T14:00:00Z',
          deliverySlot: '2026-08-29T14:00:00Z',
          pickupAddress: address(label: 'بيت العميل'),
          deliveryAddress: address(label: 'الفندق'),
        ),
        _me,
      );
      // النماذج تحوّل إلى التوقيت المحلّيّ، فالمقارنة بالمحوَّل لا بالخام.
      expect(j.slotStart, DateTime.parse('2026-08-26T14:00:00Z').toLocal());
      expect(j.address?.label, 'بيت العميل');
    });

    test('مهمّة التسليم تأخذ فتحة التسليم وعنوانه', () {
      final j = DriverJob.fromMap(
        row(
          status: 'delivery_assigned',
          deliveryDriver: _me,
          pickupSlot: '2026-08-26T14:00:00Z',
          deliverySlot: '2026-08-29T14:00:00Z',
          pickupAddress: address(label: 'بيت العميل'),
          deliveryAddress: address(label: 'الفندق'),
        ),
        _me,
      );
      expect(j.slotStart, DateTime.parse('2026-08-29T14:00:00Z').toLocal());
      expect(j.address?.label, 'الفندق');
    });

    test('طلبٌ بلا عنوانٍ مرفق لا ينهار', () {
      final j = DriverJob.fromMap(row(status: 'pickup_assigned'), _me);
      expect(j.address, isNull);
      expect(j.slotStart, isNull);
    });
  });

  group('الخطوة التالية', () {
    test('كل حالةٍ نشطة لها خطوةٌ واحدة تليها', () {
      expect(
          DriverJob.fromMap(row(status: 'pickup_assigned'), _me).nextStatus,
          OrderStatus.pickupEnRoute);
      expect(
          DriverJob.fromMap(row(status: 'pickup_en_route'), _me).nextStatus,
          OrderStatus.pickedUp);
      expect(
          DriverJob.fromMap(
                  row(status: 'delivery_assigned', deliveryDriver: _me), _me)
              .nextStatus,
          OrderStatus.outForDelivery);
      expect(
          DriverJob.fromMap(
                  row(status: 'out_for_delivery', deliveryDriver: _me), _me)
              .nextStatus,
          OrderStatus.delivered);
    });

    test('الحالة المنتهية بلا خطوةٍ تالية — ولا زرَّ يُعرض', () {
      final j = DriverJob.fromMap(
          row(status: 'delivered', deliveryDriver: _me), _me);
      expect(j.nextStatus, isNull);
    });
  });

  group('الفعل الأخير يُميَّز', () {
    test('«انطلقت» ليست فعلًا أخيرًا — لا إثبات ولا رمز', () {
      expect(DriverJob.fromMap(row(status: 'pickup_assigned'), _me).isFinalStep,
          isFalse);
      expect(
          DriverJob.fromMap(
                  row(status: 'delivery_assigned', deliveryDriver: _me), _me)
              .isFinalStep,
          isFalse);
    });

    test('«استلمت» و«سلّمت» فعلان أخيران — بإثبات', () {
      expect(DriverJob.fromMap(row(status: 'pickup_en_route'), _me).isFinalStep,
          isTrue);
      expect(
          DriverJob.fromMap(
                  row(status: 'out_for_delivery', deliveryDriver: _me), _me)
              .isFinalStep,
          isTrue);
    });
  });

  test('هاتف العميل يُقرأ من الملفّ المضموم', () {
    final j = DriverJob.fromMap(
        row(status: 'pickup_assigned', phone: '+966500000001'), _me);
    expect(j.customerPhone, '+966500000001');
    expect(j.order.customerName, 'محمد');
  });

  test('عميلٌ لا تسمح السياسة برؤية ملفّه: لا رقم ولا انهيار', () {
    final r = row(status: 'pickup_assigned')..remove('profiles');
    final j = DriverJob.fromMap(r, _me);
    expect(j.customerPhone, isNull);
  });
}
