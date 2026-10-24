import 'dart:math' as math;

import '../data/cities.dart';
import '../models/models.dart';
import '../utils/format.dart';

class LoadMatch {
  const LoadMatch({
    required this.load,
    required this.score,
    required this.emptyKm,
    required this.closerToHomeKm,
    required this.loadedKm,
  });

  final Load load;

  /// 0–100 arası uygunluk puanı.
  final int score;

  /// Boşaldığın yerden yükün alınacağı yere boş gidiş.
  final double emptyKm;

  /// Yük teslim edildiğinde eve ne kadar yaklaşmış olursun (negatif = uzaklaşır).
  final double closerToHomeKm;

  /// Yüklü gidilecek mesafe.
  final double loadedKm;

  double get pricePerKm => loadedKm <= 0 ? 0 : load.price / loadedKm;

  String get label {
    if (score >= 75) return 'Çok uygun';
    if (score >= 50) return 'Uygun';
    return 'Kısmen';
  }
}

/// Boş dönüşü önlemek için yük eşleştirme.
///
/// Kamyon [emptyAt] şehrinde boşalmış ve [home] yönüne dönmek istiyor.
/// Puan iki şeye bakar: yükü almak için ne kadar boş gidileceği ve
/// yükün teslim noktasının eve doğru olup olmadığı.
///
/// * İl adları büyük/küçük harf ve boşluk farkı gözetmeden eşleşir.
/// * [emptyAt] veya [home] bilinmeyen bir il ise sonuç boştur; yükleme ya
///   da teslim ili bilinmeyen yük atlanır (yanlış konumla puanlanmaz).
/// * Eşit puanlı yükler sırayla: daha az boş yol, eve daha çok yaklaştıran,
///   km başı daha yüksek navlun, daha erken yükleme tarihi.
List<LoadMatch> matchLoads({
  required List<Load> loads,
  required String emptyAt,
  required String home,
  VehicleType? vehicle,
  double maxEmptyKm = 250,
  String? excludeOwnerId,
}) {
  final startCity = findCity(emptyAt);
  final homeCity = findCity(home);
  if (startCity == null || homeCity == null) return const [];
  final start = kCities[startCity]!;
  final homePos = kCities[homeCity]!;
  final limit = maxEmptyKm.isNaN ? 250.0 : math.max(0.0, maxEmptyKm);
  // Aynı şehirdeysen ve ev de oradaysa yön önemsizdir.
  final sameHome = startCity == homeCity;
  final results = <LoadMatch>[];

  for (final load in loads) {
    // Yayında olmayan, yükleme günü geçmiş ve kendi ilanlarım önerilmez.
    if (!load.isOpen || (excludeOwnerId != null && load.ownerId == excludeOwnerId)) continue;
    if (vehicle != null && load.vehicle != vehicle) continue;

    final from = cityLatLngOrNull(load.fromCity);
    final to = cityLatLngOrNull(load.toCity);
    if (from == null || to == null) continue;
    final emptyKm = roadKm(start, from);
    if (emptyKm > limit) continue;

    final loadedKm = math.max(roadKm(from, to), 1.0);
    final gain = roadKm(from, homePos) - roadKm(to, homePos);

    // Yön: +1 tam eve doğru, 0 yan yol, -1 ters yön.
    final direction = math.max(-1.0, math.min(1.0, gain / loadedKm));
    final directionFactor = 0.5 + 0.5 * direction;
    final proximityFactor = math.exp(-emptyKm / 150);

    final raw = sameHome
        ? proximityFactor * 0.8 + 0.2 * directionFactor
        : proximityFactor * 0.55 + directionFactor * 0.45;
    final score = raw.isFinite ? math.max(0, math.min(100, (raw * 100).round())) : 0;

    results.add(LoadMatch(
      load: load,
      score: score,
      emptyKm: emptyKm,
      closerToHomeKm: gain,
      loadedKm: loadedKm,
    ));
  }

  results.sort(compareMatches);
  return results;
}

/// Eşleşme sıralaması (önce puan). Eşitlikte sonuç her zaman aynı sırada döner.
int compareMatches(LoadMatch a, LoadMatch b) {
  final byScore = b.score.compareTo(a.score);
  if (byScore != 0) return byScore;
  final byEmpty = a.emptyKm.compareTo(b.emptyKm);
  if (byEmpty != 0) return byEmpty;
  final byHome = b.closerToHomeKm.compareTo(a.closerToHomeKm);
  if (byHome != 0) return byHome;
  final byPrice = b.pricePerKm.compareTo(a.pricePerKm);
  if (byPrice != 0) return byPrice;
  final byDate = a.load.date.compareTo(b.load.date);
  return byDate != 0 ? byDate : a.load.id.compareTo(b.load.id);
}
