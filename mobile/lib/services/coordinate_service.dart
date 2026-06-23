import 'dart:math';

class CoordinateService {
  static String toDMS(double decimal, bool isLat) {
    final dir = isLat ? (decimal >= 0 ? 'N' : 'S') : (decimal >= 0 ? 'E' : 'W');
    final abs = decimal.abs();
    final deg = abs.floor();
    final minFull = (abs - deg) * 60;
    final min = minFull.floor();
    final sec = (minFull - min) * 60;
    return "$deg°${min.toString().padLeft(2, '0')}'${sec.toStringAsFixed(1).padLeft(4, '0')}\"$dir";
  }

  static String toMGRS(double lat, double lng) {
    // Simplified MGRS — returns a compact grid reference for display
    final latZone = ((lat + 80) / 8).floor().clamp(0, 19);
    const latBands = 'CDEFGHJKLMNPQRSTUVWX';
    final band = latBands[latZone];
    final lngZone = ((lng + 180) / 6).floor() + 1;
    return '$lngZone$band ${_easting(lng)} ${_northing(lat)}';
  }

  static String _easting(double lng) {
    final zone = ((lng + 180) / 6).floor() + 1;
    final centralMeridian = (zone - 1) * 6.0 - 180 + 3;
    final e = ((lng - centralMeridian) * 10000 + 500000).round() % 100000;
    return e.toString().padLeft(5, '0');
  }

  static String _northing(double lat) {
    final n = ((lat + 90) * 10000).round() % 100000;
    return n.toString().padLeft(5, '0');
  }

  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;

  static double bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
    final dLng = _rad(lng2 - lng1);
    final y = sin(dLng) * cos(_rad(lat2));
    final x = cos(_rad(lat1)) * sin(_rad(lat2)) - sin(_rad(lat1)) * cos(_rad(lat2)) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }
}
