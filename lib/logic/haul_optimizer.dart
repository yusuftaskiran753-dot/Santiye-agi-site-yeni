import 'dart:math' as math;

import '../models/models.dart';
import '../utils/format.dart';

class HaulParams {
  const HaulParams({
    this.truckM3 = 18,
    this.trucks = 8,
    this.litersPer100Km = 45,
    this.fuelPrice = 55,
    this.speedKmh = 30,
    this.hoursPerDay = 10,
    this.handlingMin = 15,
  });

  final double truckM3;
  final int trucks;
  final double litersPer100Km;
  final double fuelPrice;
  final double speedKmh;
  final double hoursPerDay;
  final double handlingMin;

  /// Parametre hataları (boşsa geçerli). Hesap, geçersiz parametreyle
  /// sonsuz / anlamsız sonuç üretmemek için [optimizeHaul] içinde reddedilir.
  List<String> get problems => [
        if (!(truckM3 > 0) || !truckM3.isFinite) 'Kamyon kapasitesi sıfırdan büyük olmalı',
        if (trucks < 1) 'En az bir kamyon olmalı',
        if (!(speedKmh > 0) || !speedKmh.isFinite) 'Ortalama hız sıfırdan büyük olmalı',
        if (!(hoursPerDay > 0) || hoursPerDay > 24) 'Günlük çalışma 0–24 saat arasında olmalı',
        if (!(litersPer100Km >= 0) || !litersPer100Km.isFinite) 'Yakıt tüketimi geçersiz',
        if (!(fuelPrice >= 0) || !fuelPrice.isFinite) 'Yakıt fiyatı geçersiz',
        if (!(handlingMin >= 0) || !handlingMin.isFinite) 'Yükleme/boşaltma süresi geçersiz',
      ];

  bool get isValid => problems.isEmpty;

  double fuelCostForKm(double km) => km * litersPer100Km / 100 * fuelPrice;

  /// [m3] hacim için gereken sefer sayısı. Tam bölünen hacimde kayan nokta
  /// artığı yüzünden fazladan sefer sayılmaz (18000 m³ / 18 = 1000 sefer);
  /// sıfırdan büyük her hacim en az bir sefer demektir.
  int tripsFor(double m3) {
    if (!(m3 > 1e-6) || !m3.isFinite || !(truckM3 > 0)) return 0;
    final ratio = m3 / truckM3;
    return math.max(1, (ratio - 1e-9 * math.max(1.0, ratio)).ceil());
  }
}

/// Döküm ücreti (negatif veya sayı olmayan değer 0 sayılır).
double _fee(HaulPoint d) => d.feePerM3.isFinite && d.feePerM3 > 0 ? d.feePerM3 : 0;

class HaulAssignment {
  HaulAssignment({required this.site, required this.dump, required this.oneWayKm});

  final HaulPoint site;
  final HaulPoint dump;
  final double oneWayKm;
  double volume = 0;

  int trips(HaulParams p) => p.tripsFor(volume);
  double km(HaulParams p) => trips(p) * oneWayKm * 2;
  double fuelCost(HaulParams p) => p.fuelCostForKm(km(p));
  double dumpFee() => volume * _fee(dump);
  double total(HaulParams p) => fuelCost(p) + dumpFee();
  double tripMinutes(HaulParams p) => oneWayKm * 2 / p.speedKmh * 60 + p.handlingMin;
}

class BackhaulSuggestion {
  const BackhaulSuggestion({
    required this.site,
    required this.dump,
    required this.source,
    required this.m3,
    required this.trips,
    required this.savedKm,
    required this.savedCost,
  });

  final HaulPoint site;
  final HaulPoint dump;
  final HaulPoint source;
  final double m3;
  final int trips;
  final double savedKm;
  final double savedCost;
}

class HaulPlan {
  const HaulPlan({
    required this.params,
    required this.assignments,
    required this.backhauls,
    required this.unassignedM3,
    required this.naiveCost,
  });

  final HaulParams params;
  final List<HaulAssignment> assignments;
  final List<BackhaulSuggestion> backhauls;
  final double unassignedM3;
  final double naiveCost;

  int get totalTrips => assignments.fold(0, (a, x) => a + x.trips(params));
  double get totalKm => assignments.fold(0.0, (a, x) => a + x.km(params));
  double get fuelLiters => totalKm * params.litersPer100Km / 100;
  double get fuelCost => assignments.fold(0.0, (a, x) => a + x.fuelCost(params));
  double get dumpFees => assignments.fold(0.0, (a, x) => a + x.dumpFee());
  double get totalCost => fuelCost + dumpFees;
  double get backhaulSavings => backhauls.fold(0.0, (a, b) => a + b.savedCost);
  double get savingsVsNaive => math.max(0, naiveCost - totalCost);
  double get totalVolume => assignments.fold(0.0, (a, x) => a + x.volume);

  /// Tüm filoyla tahmini iş günü.
  double get days {
    final truckMinutes =
        assignments.fold(0.0, (a, x) => a + x.trips(params) * x.tripMinutes(params));
    final perDay = params.trucks * params.hoursPerDay * 60;
    return perDay <= 0 ? 0 : truckMinutes / perDay;
  }

  /// WhatsApp / e-posta ile paylaşmak için düz metin özet.
  String summaryText() {
    final b = StringBuffer()
      ..writeln('Hafriyat planı')
      ..writeln('Taşınacak: ${formatNumber(totalVolume)} m³ · ${formatNumber(totalTrips)} sefer')
      ..writeln('Süre: ${formatNumber(days, decimals: 1)} gün (${params.trucks} kamyon)')
      ..writeln('Yakıt: ${formatNumber(fuelLiters)} L · ${formatTL(fuelCost)}')
      ..writeln('Döküm ücreti: ${formatTL(dumpFees)}')
      ..writeln('Toplam: ${formatTL(totalCost)}');
    if (unassignedM3 > 0) {
      b.writeln('Kapasite yetmeyen: ${formatNumber(unassignedM3)} m³');
    }
    b.writeln();
    for (final a in assignments) {
      b.writeln('• ${a.site.name} → ${a.dump.name}: ${formatNumber(a.volume)} m³, '
          '${a.trips(params)} sefer, ${formatKm(a.oneWayKm)} tek yön');
    }
    if (backhauls.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Dönüş yükleri (${formatTL(backhaulSavings)} tasarruf):');
      for (final x in backhauls) {
        b.writeln('• ${x.dump.name} → ${x.source.name} → ${x.site.name}: '
            '${formatNumber(x.m3)} m³ ${x.source.material}, ${x.trips} sefer');
      }
    }
    return b.toString().trimRight();
  }
}

/// Kazı sahalarını döküm sahalarına dağıtır: önce taşınabilecek hacmi en
/// büyük yapar, bu hacmi de toplam (yakıt + döküm ücreti) maliyeti en düşük
/// olacak şekilde ve döküm kapasitelerini aşmadan dağıtır. Bu, klasik
/// ulaştırma problemidir ve en düşük maliyetli akış ile tam çözülür (m³ başı
/// maliyet doğrusal kabul edilir). Ardından geri dolgu ihtiyacı olan sahalar
/// için "dönüş yükü" fırsatlarını çıkarır.
///
/// Geçersiz parametrede [ArgumentError] fırlatır. Hacmi sıfır/negatif ya da
/// konumu/hacmi sayı olmayan (NaN, sonsuz) noktalar hesaba katılmaz.
HaulPlan optimizeHaul(List<HaulPoint> points, HaulParams p) {
  if (!p.isValid) throw ArgumentError(p.problems.join('; '));
  bool usable(HaulPoint x) => x.lat.isFinite && x.lng.isFinite && x.volume.isFinite && x.volume > 0;
  final sites = points.where((x) => x.kind == HaulPointKind.excavation && usable(x)).toList();
  final dumps = points.where((x) => x.kind == HaulPointKind.dump && usable(x)).toList();
  final sources = points.where((x) => x.kind == HaulPointKind.source && usable(x)).toList();

  double unitCost(HaulPoint s, HaulPoint d) {
    final km = roadKm(s.position, d.position);
    return p.fuelCostForKm(km * 2) / p.truckM3 + _fee(d);
  }

  // 1) Ulaştırma problemi: saha × döküm m³ dağılımı.
  final flow = solveTransport(
    supply: [for (final s in sites) s.volume],
    capacity: [for (final d in dumps) d.volume],
    cost: [
      for (final s in sites) [for (final d in dumps) unitCost(s, d)],
    ],
  );

  final assignments = <HaulAssignment>[];
  for (var i = 0; i < sites.length; i++) {
    for (var j = 0; j < dumps.length; j++) {
      // Kayan nokta artıklarını temizle (0,001 m³ hassasiyet).
      final volume = (flow[i][j] * 1000).roundToDouble() / 1000;
      if (volume <= 0) continue;
      assignments.add(
        HaulAssignment(site: sites[i], dump: dumps[j], oneWayKm: roadKm(sites[i].position, dumps[j].position))
          ..volume = volume,
      );
    }
  }
  assignments.sort((a, b) {
    final bySite = a.site.name.compareTo(b.site.name);
    if (bySite != 0) return bySite;
    final byKm = a.oneWayKm.compareTo(b.oneWayKm);
    return byKm != 0 ? byKm : a.dump.name.compareTo(b.dump.name);
  });

  final totalSite = sites.fold(0.0, (a, s) => a + s.volume);
  final shipped = assignments.fold(0.0, (a, x) => a + x.volume);
  // 0,001 m³ altındaki yuvarlama artığı "kapasite yetmedi" diye raporlanmaz.
  final unassigned = math.max(0.0, ((totalSite - shipped) * 1000).roundToDouble() / 1000);

  // 2) Karşılaştırma: her saha tüm hafriyatı en yakın döküm sahasına götürseydi
  //    (kapasite gözetmeden; sahada sık yapılan "en yakına dök" alışkanlığı).
  var naive = 0.0;
  for (final s in sites) {
    if (dumps.isEmpty) break;
    final nearest = dumps.reduce((a, b) =>
        roadKm(s.position, a.position) <= roadKm(s.position, b.position) ? a : b);
    final km = roadKm(s.position, nearest.position);
    naive += p.fuelCostForKm(p.tripsFor(s.volume) * km * 2) + s.volume * _fee(nearest);
  }

  return HaulPlan(
    params: p,
    assignments: assignments,
    backhauls: _backhauls(sites, sources, assignments, p),
    unassignedM3: unassigned,
    naiveCost: naive,
  );
}

/// Dönüş yükü: döküm sahasından boş dönen kamyon, yoldaki bir ocaktan geri
/// dolgu malzemesi alıp şantiyeye dolu döner. Her saha için (döküm, ocak)
/// seçenekleri sefer başı kazanca göre sıralanır; dolgu ihtiyacı, o dökümden
/// dönen sefer sayısı ve ocak stoku aşılmadan dağıtılır.
/// Sefer başına bundan az yol kazandıran dönüş yükü önerilmez (km).
const double _minBackhaulSavingKm = 0.5;

List<BackhaulSuggestion> _backhauls(
  List<HaulPoint> sites,
  List<HaulPoint> sources,
  List<HaulAssignment> assignments,
  HaulParams p,
) {
  final result = <BackhaulSuggestion>[];
  final stockLeft = {for (final s in sources) s.id: s.volume};

  for (final site in sites.where((x) => x.needM3 > 0)) {
    final options = <(HaulAssignment, HaulPoint, double)>[];
    for (final a in assignments.where((x) => x.site.id == site.id)) {
      final direct = roadKm(a.dump.position, site.position);
      for (final src in sources) {
        final viaSource = roadKm(a.dump.position, src.position) + roadKm(src.position, site.position);
        final extraKm = viaSource - direct;
        final separateTripKm = roadKm(site.position, src.position) * 2;
        final perTripSaving = separateTripKm - extraKm;
        // Ocak, sahayla döküm arasında değilse kazanç ~0'dır; ölçüm gürültüsü
        // (birkaç yüz metre) öneri olarak sunulmaz.
        if (perTripSaving >= _minBackhaulSavingKm) options.add((a, src, perTripSaving));
      }
    }
    // En çok kazandıran önce; eşitlikte ad sırası (her çalıştırmada aynı sonuç).
    options.sort((x, y) {
      final bySaving = y.$3.compareTo(x.$3);
      if (bySaving != 0) return bySaving;
      final bySource = x.$2.name.compareTo(y.$2.name);
      return bySource != 0 ? bySource : x.$1.dump.name.compareTo(y.$1.dump.name);
    });

    var needLeft = site.needM3;
    final returnsUsed = <String, int>{};
    for (final (a, src, perTripSaving) in options) {
      if (needLeft <= 1e-6) break;
      final freeTrips = a.trips(p) - (returnsUsed[a.dump.id] ?? 0);
      final stock = stockLeft[src.id] ?? 0.0;
      final m3 = math.min(needLeft, math.min(freeTrips * p.truckM3, stock));
      if (m3 <= 1e-6) continue;
      final trips = p.tripsFor(m3);
      returnsUsed[a.dump.id] = (returnsUsed[a.dump.id] ?? 0) + trips;
      stockLeft[src.id] = stock - m3;
      needLeft -= m3;
      final savedKm = perTripSaving * trips;
      result.add(BackhaulSuggestion(
        site: site,
        dump: a.dump,
        source: src,
        m3: m3,
        trips: trips,
        savedKm: savedKm,
        savedCost: p.fuelCostForKm(savedKm),
      ));
    }
  }
  return result;
}

class _Edge {
  _Edge(this.to, this.rev, this.cap, this.cost);

  final int to;
  final int rev;
  double cap;
  final double cost;
}

/// En düşük maliyetli en büyük akış ile ulaştırma problemi çözümü.
///
/// [supply] i. kaynağın arzı, [capacity] j. hedefin kapasitesi,
/// [cost] [i][j] birim taşıma maliyeti (≥ 0). Önce taşınan toplam miktar en
/// büyük yapılır, bu miktar için toplam maliyet en düşüktür. Dönen matris
/// [i][j] taşınacak miktardır. Küçük ağlar (onlarca nokta) için anlıktır.
///
/// * Negatif, NaN veya sonsuz arz/kapasite 0 sayılır.
/// * Maliyeti sonsuz veya NaN olan hücre "yol yok" demektir; oraya gönderilmez.
/// * [cost] boyutu arz × kapasite değilse [ArgumentError] fırlatır.
List<List<double>> solveTransport({
  required List<double> supply,
  required List<double> capacity,
  required List<List<double>> cost,
}) {
  final n = supply.length;
  final m = capacity.length;
  if (cost.length != n || cost.any((row) => row.length != m)) {
    throw ArgumentError('Maliyet tablosu ${n}x$m olmalı');
  }
  final result = List.generate(n, (_) => List<double>.filled(m, 0));
  if (n == 0 || m == 0) return result;
  double clean(double v) => v.isFinite && v > 0 ? v : 0;

  const eps = 1e-9;
  final source = n + m;
  final sink = n + m + 1;
  final size = n + m + 2;
  final graph = List.generate(size, (_) => <_Edge>[]);

  void addEdge(int from, int to, double cap, double edgeCost) {
    graph[from].add(_Edge(to, graph[to].length, cap, edgeCost));
    graph[to].add(_Edge(from, graph[from].length - 1, 0, -edgeCost));
  }

  for (var i = 0; i < n; i++) {
    final s = clean(supply[i]);
    if (s > eps) addEdge(source, i, s, 0);
  }
  for (var j = 0; j < m; j++) {
    final c = clean(capacity[j]);
    if (c > eps) addEdge(n + j, sink, c, 0);
  }
  final arc = List.generate(n, (_) => List<int>.filled(m, -1));
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < m; j++) {
      final c = cost[i][j];
      if (!c.isFinite) continue;
      arc[i][j] = graph[i].length;
      addEdge(i, n + j, double.infinity, c);
    }
  }

  // Ardışık en kısa yol (Bellman-Ford; artık ağda negatif kenarlar olabilir).
  // Her adım en az bir kenarı doyurur; üst sınır yalnızca güvenlik içindir.
  final maxRounds = 4 * (n + 1) * (m + 1) + 100;
  for (var guard = 0; guard < maxRounds; guard++) {
    final dist = List<double>.filled(size, double.infinity);
    final prevNode = List<int>.filled(size, -1);
    final prevEdge = List<int>.filled(size, -1);
    dist[source] = 0;
    var changed = true;
    for (var round = 0; round < size && changed; round++) {
      changed = false;
      for (var u = 0; u < size; u++) {
        if (dist[u] == double.infinity) continue;
        final edges = graph[u];
        for (var k = 0; k < edges.length; k++) {
          final e = edges[k];
          if (e.cap > eps && dist[u] + e.cost < dist[e.to] - eps) {
            dist[e.to] = dist[u] + e.cost;
            prevNode[e.to] = u;
            prevEdge[e.to] = k;
            changed = true;
          }
        }
      }
    }
    if (dist[sink] == double.infinity) break;

    var push = double.infinity;
    for (var v = sink; v != source; v = prevNode[v]) {
      push = math.min(push, graph[prevNode[v]][prevEdge[v]].cap);
    }
    if (push <= eps) break;
    for (var v = sink; v != source; v = prevNode[v]) {
      final e = graph[prevNode[v]][prevEdge[v]];
      e.cap -= push;
      graph[v][e.rev].cap += push;
    }
  }

  for (var i = 0; i < n; i++) {
    for (var j = 0; j < m; j++) {
      if (arc[i][j] < 0) continue;
      final e = graph[i][arc[i][j]];
      // Ters kenardaki kapasite = gönderilen akış.
      result[i][j] = graph[e.to][e.rev].cap;
    }
  }
  return result;
}
