import 'package:latlong2/latlong.dart';

import 'models.dart';

class LocationFix {
  const LocationFix({
    required this.lat,
    required this.lng,
    required this.at,
    this.accuracy,
    this.heading,
    this.speed,
  });

  final double lat;
  final double lng;
  final DateTime at;

  /// Metre.
  final double? accuracy;

  /// Derece (0–360).
  final double? heading;

  /// Metre/saniye.
  final double? speed;

  LatLng get position => LatLng(lat, lng);

  /// Ham değerleri sunucunun kabul edeceği aralığa çeker; geçersiz ölçümde null döner.
  /// (Cihazlar bilinmeyen yön/hız için -1 verir; 0,0 "konum yok" demektir.)
  static LocationFix? clean({
    required double lat,
    required double lng,
    DateTime? at,
    double? accuracy,
    double? heading,
    double? speed,
  }) {
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    if (lat == 0 && lng == 0) return null;
    double? inRange(double? v, double min, double max) =>
        v != null && v.isFinite && v >= min && v <= max ? v : null;
    return LocationFix(
      lat: lat,
      lng: lng,
      at: at ?? DateTime.now(),
      accuracy: inRange(accuracy, 0, 100000),
      heading: inRange(heading, 0, 360),
      speed: inRange(speed, 0, 150),
    );
  }
}

/// Bir anlaşmada bir tarafın paylaştığı son konum.
class LiveLocation {
  const LiveLocation({
    required this.dealId,
    required this.userId,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    required this.expiresAt,
    required this.startedAt,
    this.accuracy,
    this.heading,
    this.speed,
    this.untilDelivered = false,
  });

  final String dealId;
  final String userId;
  final double lat;
  final double lng;
  final double? accuracy;
  final double? heading;
  final double? speed;
  final bool untilDelivered;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime expiresAt;

  LatLng get position => LatLng(lat, lng);

  /// Paylaşım sürüyor mu (süre dolmadı, durdurulmadı).
  bool isActiveAt(DateTime now) => expiresAt.isAfter(now);
  bool get isActive => isActiveAt(DateTime.now());

  /// Son güncellemeden bu yana geçen süre.
  Duration ageAt(DateTime now) {
    final d = now.difference(updatedAt);
    return d.isNegative ? Duration.zero : d;
  }

  static double? _optDouble(Object? v) => v == null ? null : asDouble(v);

  factory LiveLocation.fromJson(Map<String, dynamic> j) {
    final lat = j['lat'];
    final lng = j['lng'];
    if (lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180 ||
        asString(j['deal_id']).isEmpty ||
        asString(j['user_id']).isEmpty ||
        asDateOrNull(j['updated_at']) == null ||
        asDateOrNull(j['started_at']) == null ||
        asDateOrNull(j['expires_at']) == null) {
      throw const FormatException('Invalid live location');
    }
    return LiveLocation(
      dealId: asString(j['deal_id']),
      userId: asString(j['user_id']),
      lat: asDouble(j['lat']),
      lng: asDouble(j['lng']),
      accuracy: _optDouble(j['accuracy']),
      heading: _optDouble(j['heading']),
      speed: _optDouble(j['speed']),
      untilDelivered: asBool(j['until_delivered']),
      startedAt: asDate(j['started_at']),
      updatedAt: asDate(j['updated_at']),
      // Bozuk/eksik kayıt "bitmiş" sayılır (yanlışlıkla canlı görünmesin).
      expiresAt:
          asDateOrNull(j['expires_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'deal_id': dealId,
    'user_id': userId,
    'lat': lat,
    'lng': lng,
    'accuracy': accuracy,
    'heading': heading,
    'speed': speed,
    'until_delivered': untilDelivered,
    'started_at': isoOrNull(startedAt),
    'updated_at': isoOrNull(updatedAt),
    'expires_at': isoOrNull(expiresAt),
  };

  LiveLocation copyWith({
    DateTime? expiresAt,
    DateTime? updatedAt,
    LocationFix? fix,
  }) => LiveLocation(
    dealId: dealId,
    userId: userId,
    lat: fix?.lat ?? lat,
    lng: fix?.lng ?? lng,
    accuracy: fix == null ? accuracy : fix.accuracy,
    heading: fix == null ? heading : fix.heading,
    speed: fix == null ? speed : fix.speed,
    untilDelivered: untilDelivered,
    startedAt: startedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
}
