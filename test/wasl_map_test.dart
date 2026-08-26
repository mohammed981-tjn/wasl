// اختبار الخريطة المشتركة.
//
// **ما يُختبر هنا بالتحديد**: أن الخريطة **تُبنى** وأن إسناد OpenStreetMap
// معروضٌ فيها. والإسناد شرطُ رخصة البلاطات لا زينة — وحذفُه مخالفة، وهو أوّل
// ما يُنسى حين تُنسخ الخريطة إلى شاشةٍ جديدة.
//
// ولا تُختبر البلاطات نفسها: تحميلها يحتاج شبكةً، وهذا اختبار وحدة.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:wasl/widgets/wasl_map.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SizedBox(width: 400, height: 600, child: child)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('الخريطة تُبنى ويظهر إسناد OpenStreetMap', (tester) async {
    final c = MapController();
    addTearDown(c.dispose);

    await pump(tester, WaslMap(controller: c));

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('© OpenStreetMap'), findsOneWidget);
  });

  testWidgets('المركز الافتراضي في المدينة المنوّرة لا عند خطّ الاستواء',
      (tester) async {
    // خريطةٌ تفتح على (٠،٠) تبدو معطَّلةً لا جاهلةً بالموقع.
    expect(kMedina.latitude, closeTo(24.4672, 0.001));
    expect(kMedina.longitude, closeTo(39.6142, 0.001));

    final c = MapController();
    addTearDown(c.dispose);
    await pump(tester, WaslMap(controller: c));
    expect(c.camera.center.latitude, closeTo(24.4672, 0.001));
  });

  testWidgets('الطبقات الممرَّرة تُعرض فوق البلاطات', (tester) async {
    final c = MapController();
    addTearDown(c.dispose);

    await pump(
      tester,
      WaslMap(
        controller: c,
        children: [
          MarkerLayer(markers: [
            waslMarker(
              at: kMedina,
              icon: Icons.storefront,
              color: Colors.green,
              label: 'الفرع',
            ),
          ]),
        ],
      ),
    );

    expect(find.text('الفرع'), findsOneWidget);
    expect(find.byIcon(Icons.storefront), findsOneWidget);
  });

  testWidgets('النقر يُعيد النقطة حين يُطلب ذلك', (tester) async {
    final c = MapController();
    addTearDown(c.dispose);
    LatLng? tapped;

    await pump(tester, WaslMap(controller: c, onTap: (p) => tapped = p));
    await tester.tapAt(const Offset(200, 300));
    // النقرة تُؤجَّل قليلًا لتُميَّز عن النقرة المزدوجة (وهي تقرّب الخريطة).
    await tester.pump(const Duration(milliseconds: 400));

    expect(tapped, isNotNull);
    expect(tapped!.latitude, closeTo(kMedina.latitude, 1.0));
  });
}
