import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../data/cities.dart';
import '../models/models.dart';
import '../models/live_location.dart';
import '../utils/format.dart';

/// Canlı konum ekranının hesapları. Saf Dart: test edilebilir, cihaza bağlı değil.
class LiveRules {
  LiveRules._();

  /// Bu süreden eski konum "güncel değil" diye uyarılır (WhatsApp'taki gri nokta gibi).
  static const Duration staleAfter = Duration(minutes: 3);

  /// İki gönderim arasında en az bu kadar beklenir (pil ve veri tasarrufu).
  static const Duration minInterval = Duration(seconds: 10);

  /// Araç dursa bile bu aralıkla "hâlâ buradayım" gönderilir; izleyen taraf
  /// paylaşımın koptuğunu sanmaz.
  static const Duration heartbeat = Duration(seconds: 60);

  /// Bundan az yer değiştirme (ve kalp atışı süresi dolmamışsa) gönderilmez.
  static const double minMoveMeters = 25;

  /// Kalp atışında yeniden gönderilecek son ölçüm en fazla bu kadar eski olabilir.
  /// (Daha eskiyse cihaz konum alamıyordur; eski konumu "yeni" diye göstermeyiz.)
  static const Duration maxFixAgeForHeartbeat = Duration(minutes: 3);

  /// Kamyon için ortalama yol hızı (km/sa); varış tahmini kaba bir göstergedir.
  static const double truckAvgKmh = 60;

  /// Paylaşım süresi seçenekleri (dakika).
  static const List<int> durations = [60, 480];

  static const Distance _distance = Distance();

  static double metersBetween(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);

  /// Yeni ölçüm şimdi gönderilmeli mi?
  static bool shouldSend({
    required DateTime now,
    required LatLng position,
    DateTime? lastSentAt,
    LatLng? lastSentPosition,
  }) {
    if (lastSentAt == null || lastSentPosition == null) return true;
    final elapsed = now.difference(lastSentAt);
    if (elapsed.isNegative) return true; // saat geri alındı
    if (elapsed >= heartbeat) return true;
    if (elapsed < minInterval) return false;
    return metersBetween(position, lastSentPosition) >= minMoveMeters;
  }

  /// Kalp atışı: uzun süredir gönderilmediyse elimizdeki son ölçüm yeniden gönderilir.
  static bool heartbeatDue({
    required DateTime now,
    DateTime? lastSentAt,
    DateTime? lastFixAt,
  }) {
    if (lastFixAt == null) return false;
    if (now.difference(lastFixAt) > maxFixAgeForHeartbeat) return false;
    return lastSentAt == null || now.difference(lastSentAt) >= heartbeat;
  }

  /// "İstanbul → Ankara · Demir" biçimindeki anlaşma başlığından güzergâh.
  /// Yük ilanından doğan anlaşmalar bu biçimdedir; başkalarında null döner.
  static ({String from, String to})? routeFromTitle(String title) {
    final arrow = title.indexOf('→');
    if (arrow <= 0) return null;
    final from = findCity(title.substring(0, arrow));
    var rest = title.substring(arrow + 1);
    final dot = rest.indexOf('·');
    if (dot >= 0) rest = rest.substring(0, dot);
    final to = findCity(rest);
    if (from == null || to == null) return null;
    return (from: from, to: to);
  }

  /// Kalan yol (km, tahmini) ve süre. Varışa çok yakınsa süre null.
  static ({double km, Duration? eta}) remaining(
    LatLng from,
    LatLng destination,
  ) {
    final km = roadKm(from, destination);
    if (km < 2) return (km: km, eta: null);
    final minutes = (km / truckAvgKmh * 60).round();
    return (km: km, eta: Duration(minutes: math.max(1, minutes)));
  }

  static String formatEta(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m dk';
    if (m == 0) return '$h sa';
    return '$h sa $m dk';
  }

  /// "az önce", "45 sn önce", "3 dk önce", "2 sa önce".
  static String formatAge(Duration d) {
    if (d.inSeconds < 15) return 'az önce';
    if (d.inSeconds < 60) return '${d.inSeconds} sn önce';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
    return '${d.inHours} sa önce';
  }

  /// Kalan paylaşım süresi: "47 dk kaldı", "7 sa 12 dk kaldı".
  static String formatLeft(Duration d) {
    if (d.isNegative || d.inMinutes < 1) return 'bitmek üzere';
    return '${formatEta(d)} kaldı';
  }

  /// m/sn → "62 km/sa" (yürüme hızının altı gösterilmez).
  static String? formatSpeed(double? metersPerSecond) {
    if (metersPerSecond == null || metersPerSecond < 1.5) return null;
    return '${(metersPerSecond * 3.6).round()} km/sa';
  }

  /// İzleyen taraf için durum: canlı / güncel değil / bitti.
  static LiveState stateOf(LiveLocation? l, DateTime now) {
    if (l == null) return LiveState.none;
    if (!l.isActiveAt(now)) return LiveState.ended;
    return l.ageAt(now) > staleAfter ? LiveState.stale : LiveState.live;
  }

  /// Bu anlaşmada canlı konum kullanılabilir mi (iki taraf da uygulamada, iş sürüyor).
  static bool dealAllows(Deal d, String? me) =>
      me != null &&
      d.customerId != null &&
      d.providerId != null &&
      d.customerId != d.providerId &&
      (d.isCustomer(me) || d.isProvider(me)) &&
      (d.status == DealStatus.active ||
          d.status == DealStatus.delivered ||
          d.status == DealStatus.disputed);

  /// "Teslimata kadar" yalnızca teslim bildirilmeden önce seçilebilir.
  static bool canShareUntilDelivered(Deal d) => d.status == DealStatus.active;
}

enum LiveState { none, live, stale, ended }
