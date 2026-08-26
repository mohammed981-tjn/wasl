// اختبار نماذج الخريطة.
//
// **ما يُختبر هنا بالتحديد**: أن ترتيب الإحداثيّات يُقلب عند القراءة.
// GeoJSON يكتبها `[lng, lat]`، والخرائط تقرؤها `(lat, lng)` — وقلبُها يضع
// المدينة المنوّرة قرب الصومال. والعطل لا يظهر رسالةً بل **خريطةً فارغة**،
// فيُظنّ أن المنطقة لم تُحفظ وتُرسم من جديد.
//
// ويُختبر أن قِدَم الموقع محسوبٌ ومعروض: دبّوسٌ عمرُه ساعةٌ يبدو سائقًا واقفًا،
// فيُرسل إليه طلبٌ وهو في حيٍّ آخر.

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl/models/models.dart';

Map<String, dynamic> zoneRow({List<List<double>>? ring}) => {
      'id': 'z1',
      'branch_id': 'b1',
      'name_ar': 'قباء',
      'pickup_fee': '10.00',
      'delivery_fee': '15.00',
      'combined_fee': '20.00',
      'priority': 5,
      'is_active': true,
      'area_km2': '3.25',
      'center_lat': 24.44,
      'center_lng': 39.61,
      'area_geojson': {
        'type': 'Polygon',
        'coordinates': [
          ring ??
              [
                // [lng, lat] — هكذا يكتبها GeoJSON.
                [39.610, 24.470],
                [39.620, 24.470],
                [39.620, 24.460],
                [39.610, 24.470],
              ],
        ],
      },
    };

void main() {
  group('منطقة التوصيل', () {
    test('الإحداثيّات تُقلب من [lng,lat] إلى (lat,lng)', () {
      final z = DeliveryZone.fromMap(zoneRow());
      expect(z.ring.first, (24.470, 39.610));
      // ولو لم تُقلب لجاءت خط العرض ٣٩ — وهي في تركيا لا في المدينة.
      expect(z.ring.first.$1, closeTo(24.47, 0.001));
      expect(z.ring.first.$2, closeTo(39.61, 0.001));
    });

    test('الحلقة تُقرأ كاملةً بنقطة الإغلاق', () {
      final z = DeliveryZone.fromMap(zoneRow());
      expect(z.ring.length, 4);
      expect(z.ring.first, z.ring.last);
    });

    test('الرسوم والأولوية تُقرأ من نصٍّ أو عدد', () {
      final z = DeliveryZone.fromMap(zoneRow());
      expect(z.pickupFee, 10.0);
      expect(z.deliveryFee, 15.0);
      expect(z.combinedFee, 20.0);
      expect(z.priority, 5);
      expect(z.areaKm2, 3.25);
    });

    test('منطقةٌ بلا هندسة لا تُسقط الشاشة — تُقرأ بحلقةٍ فارغة', () {
      final row = zoneRow()..remove('area_geojson');
      final z = DeliveryZone.fromMap(row);
      expect(z.ring, isEmpty);
      expect(z.nameAr, 'قباء');
    });

    test('رسمٌ مجمَّعٌ غائبٌ يبقى فارغًا لا صفرًا', () {
      // صفرٌ يعني «مجّانًا»، والفراغ يعني «لا رسم مجمَّع» — والفرق فاتورة.
      final row = zoneRow()..['combined_fee'] = null;
      expect(DeliveryZone.fromMap(row).combinedFee, isNull);
    });
  });

  group('دبّوس السائق', () {
    DriverPin pin({required Duration ago, bool online = true}) =>
        DriverPin.fromMap({
          'driver_id': 'd1',
          'lat': 24.4672,
          'lng': 39.6142,
          'is_online': online,
          'accuracy_m': 12.5,
          'updated_at':
              DateTime.now().toUtc().subtract(ago).toIso8601String(),
        });

    test('الحديث ليس قديمًا', () {
      final p = pin(ago: const Duration(minutes: 2));
      expect(p.isStale, isFalse);
      expect(p.ageLabel, 'قبل 2 د');
    });

    test('عشرُ دقائق فأكثر تُعدّ قديمة', () {
      expect(pin(ago: const Duration(minutes: 10)).isStale, isTrue);
      expect(pin(ago: const Duration(hours: 3)).isStale, isTrue);
    });

    test('«الآن» لِما دون الدقيقة', () {
      expect(pin(ago: const Duration(seconds: 20)).ageLabel, 'الآن');
    });

    test('القِدَم يُقرأ بالساعات ثم بالأيام', () {
      expect(pin(ago: const Duration(hours: 5)).ageLabel, 'قبل 5 س');
      expect(pin(ago: const Duration(days: 2)).ageLabel, 'قبل 2 ي');
    });

    test('الاسم والحِمل يُضافان بعد الجلب', () {
      final p = pin(ago: Duration.zero).withMeta(name: 'أحمد', activeJobs: 3);
      expect(p.name, 'أحمد');
      expect(p.activeJobs, 3);
      // ولا يفقد ما كان فيه.
      expect(p.lat, 24.4672);
      expect(p.isOnline, isTrue);
    });
  });
}
