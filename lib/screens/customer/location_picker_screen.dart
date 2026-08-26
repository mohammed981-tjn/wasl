import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/location_service.dart';
import '../../widgets/wasl_map.dart';

/// اختيار موقعٍ على الخريطة.
///
/// **الدبّوس ثابتٌ في وسط الشاشة والخريطة هي التي تتحرّك.** والفرق ليس ذوقًا:
/// دبّوسٌ يُسحب بالإصبع يختفي تحت الإصبع نفسه في اللحظة التي يحتاج المرء فيها
/// أن يرى أين يضعه. أمّا الوسط الثابت فيبقى مرئيًّا، ويُضبط بيدٍ واحدة.
///
/// **ومسافةُ الفرع تُعرض دائمًا**: رسمُ التوصيل يُحسب منها، ومن يضع دبّوسه على
/// بُعد ثلاثين كيلومترًا يجب أن يعرف ذلك **الآن** لا في صفحة الدفع.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initial,
    this.branchAt,
    this.title = 'حدّد الموقع',
  });

  final LatLng initial;

  /// موقع الفرع — تُقاس منه المسافة وتُعرض.
  final LatLng? branchAt;
  final String title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _controller = MapController();
  final _location = const LocationService();

  late LatLng _center = widget.initial;
  bool _locating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final fix = await _location.current();
    if (!mounted) return;
    setState(() => _locating = false);

    if (fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذّر تحديد موقعك — حرّك الخريطة يدويًّا.'),
      ));
      return;
    }
    final at = LatLng(fix.lat, fix.lng);
    _controller.move(at, 17);
    setState(() => _center = at);
  }

  /// المسافة الهوائية بالكيلومتر. وهي **تقديرٌ يُعرض لا رسمٌ يُحسب**: الرسم
  /// تحسبه القاعدة، والطريق أطول من الخطّ المستقيم دائمًا.
  double? get _km {
    final b = widget.branchAt;
    if (b == null) return null;
    return const Distance().as(LengthUnit.Kilometer, b, _center);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final km = _km;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                WaslMap(
                  controller: _controller,
                  initialCenter: widget.initial,
                  initialZoom: 15,
                  onTap: (p) {
                    _controller.move(p, _controller.camera.zoom);
                    setState(() => _center = p);
                  },
                  children: [
                    if (widget.branchAt != null)
                      MarkerLayer(markers: [
                        waslMarker(
                          at: widget.branchAt!,
                          icon: Icons.storefront,
                          color: scheme.secondary,
                          label: 'الفرع',
                        ),
                      ]),
                  ],
                ),

                // الدبّوس الثابت. `IgnorePointer` شرطٌ لا زينة: بدونه يبتلع
                // الدبّوسُ سحبَ الخريطة تحته فلا تتحرّك.
                IgnorePointer(
                  child: Padding(
                    // نصفُ ارتفاع الأيقونة، كي يقع طرفُها السفليّ على الوسط
                    // الحقيقيّ لا مركزُها.
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Icon(Icons.location_on,
                        size: 44, color: scheme.primary),
                  ),
                ),

                PositionedDirectional(
                  end: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'my-location',
                    onPressed: _locating ? null : _useMyLocation,
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),

          Material(
            elevation: 8,
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_center.latitude.toStringAsFixed(5)}، '
                            '${_center.longitude.toStringAsFixed(5)}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (km != null)
                          Text(
                            'يبعد ${km.toStringAsFixed(1)} كم عن الفرع',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: km > 20 ? scheme.error : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'حرّك الخريطة حتى يقف الدبّوس على بابك.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(_center),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        child: const Text('تأكيد الموقع'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
