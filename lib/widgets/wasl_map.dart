import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// إحداثيّاتُ المدينة المنوّرة — مركزُ كل خريطةٍ بلا موقعٍ معلوم.
///
/// **ولماذا ليست ٠،٠**: خريطةٌ تفتح على تقاطع خطّ الاستواء وغرينتش تبدو
/// معطَّلة، والمستخدم يظنّ أن التطبيق لم يحمّل — لا أنه لا يعرف مكانه.
const kMedina = LatLng(24.4672, 39.6142);

/// خريطةٌ واحدة يستعملها الجميع.
///
/// **لماذا مكوّنٌ مشترك**: البلاطات وشرطُ الإسناد وحدودُ التقريب أشياءٌ تُنسى
/// إن كُتبت في كل شاشة. وإسنادُ OpenStreetMap **شرطُ استعمالها** لا زينة —
/// خريطةٌ بلا إسناد مخالفةٌ للرخصة.
class WaslMap extends StatelessWidget {
  const WaslMap({
    super.key,
    required this.controller,
    this.initialCenter = kMedina,
    this.initialZoom = 13,
    this.onTap,
    this.children = const [],
    this.interactive = true,
  });

  final MapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(LatLng)? onTap;
  final List<Widget> children;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        minZoom: 5,
        maxZoom: 18,
        onTap: onTap == null ? null : (_, point) => onTap!(point),
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // تشترطه سياسة استعمال بلاطات OSM: خادمُهم يحتاج أن يعرف من يطلب.
          userAgentPackageName: 'sa.wasl.app',
          maxNativeZoom: 19,
        ),
        ...children,
        const _Attribution(),
      ],
    );
  }
}

/// إسناد OpenStreetMap. صغيرٌ لكنّه لا يُحذف.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: Colors.white70,
        child: const Text(
          '© OpenStreetMap',
          textDirection: TextDirection.ltr,
          style: TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ),
    );
  }
}

/// دبّوسٌ على الخريطة.
Marker waslMarker({
  required LatLng at,
  required IconData icon,
  required Color color,
  String? label,
  VoidCallback? onTap,
}) {
  return Marker(
    point: at,
    width: label == null ? 44 : 120,
    height: 56,
    alignment: Alignment.topCenter,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          if (label != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 3),
                ],
              ),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87),
              ),
            ),
        ],
      ),
    ),
  );
}
