import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// إحداثيّةٌ مقروءة.
class Fix {
  const Fix(this.lat, this.lng, {this.accuracyM});
  final double lat;
  final double lng;
  final double? accuracyM;
}

/// قراءةُ موقع الجهاز.
///
/// **لا ترفع استثناءً أبدًا.** الموقع في هذا التطبيق سندٌ لا شرط: السائق قد
/// يمنع الإذن، أو يكون في قبوٍ لا إشارة فيه، أو يفتح النسخة على متصفّحٍ بلا
/// HTTPS. وشاشةٌ تقف لأجل ذلك تمنع تسليمًا وقع فعلًا — فالفشل يُعاد `null`
/// ويمضي العمل، ويُكتب الإثبات بلا إحداثيّة.
class LocationService {
  const LocationService();

  static const _timeout = Duration(seconds: 8);

  Future<Fix?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _timeout,
        ),
      );
      return Fix(p.latitude, p.longitude, accuracyM: p.accuracy);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
