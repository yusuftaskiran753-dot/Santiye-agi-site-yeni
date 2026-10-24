import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:santiye_agi/data/demo_data.dart';
import 'package:santiye_agi/logic/haul_optimizer.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/utils/format.dart';

/// Hafriyat optimizasyonu ve ulaştırma çözücüsü için uç durum testleri.

HaulPoint site(String id, double lat, double lng, double volume, {double need = 0}) =>
    HaulPoint(id: id, name: id, kind: HaulPointKind.excavation, lat: lat, lng: lng, volume: volume, needM3: need);

HaulPoint dump(String id, double lat, double lng, double capacity, {double fee = 0}) =>
    HaulPoint(id: id, name: id, kind: HaulPointKind.dump, lat: lat, lng: lng, volume: capacity, feePerM3: fee);

HaulPoint quarry(String id, double lat, double lng, double stock) => HaulPoint(
      id: id,
      name: id,
      kind: HaulPointKind.source,
      lat: lat,
      lng: lng,
      volume: stock,
      material: 'Stabilize',
    );

double usedCapacity(HaulPlan plan, String dumpId) =>
    plan.assignments.where((a) => a.dump.id == dumpId).fold<double>(0, (s, a) => s + a.volume);

double shippedFrom(HaulPlan plan, String siteId) =>
    plan.assignments.where((a) => a.site.id == siteId).fold<double>(0, (s, a) => s + a.volume);

/// Küçük tam sayılı örneklerde tüm dağılımları deneyerek en iyi sonucu bulur:
/// (taşınan en büyük miktar, o miktar için en düşük maliyet).
(int, double) bruteForceTransport(List<int> supply, List<int> capacity, List<List<double>> cost) {
  final n = supply.length;
  final m = capacity.length;
  final cells = n * m;
  final x = List<int>.filled(cells, 0);
  var bestShipped = -1;
  var bestCost = double.infinity;

  void visit(int k) {
    if (k == cells) {
      for (var j = 0; j < m; j++) {
        var col = 0;
        for (var i = 0; i < n; i++) {
          col += x[i * m + j];
        }
        if (col > capacity[j]) return;
      }
      var shipped = 0;
      var total = 0.0;
      for (var c = 0; c < cells; c++) {
        shipped += x[c];
        total += x[c] * cost[c ~/ m][c % m];
      }
      if (shipped > bestShipped || (shipped == bestShipped && total < bestCost - 1e-9)) {
        bestShipped = shipped;
        bestCost = total;
      }
      return;
    }
    final i = k ~/ m;
    var rowUsed = 0;
    for (var j = 0; j < k % m; j++) {
      rowUsed += x[i * m + j];
    }
    for (var v = 0; v <= supply[i] - rowUsed; v++) {
      x[k] = v;
      visit(k + 1);
    }
    x[k] = 0;
  }

  visit(0);
  return (bestShipped, bestCost);
}

void main() {
  const params = HaulParams();

  group('Sefer sayısı (tripsFor)', () {
    test('Tam bölünen hacimde kayan nokta artığı fazladan sefer saydırmaz', () {
      expect(params.tripsFor(18), 1);
      expect(params.tripsFor(54), 3);
      // 0.1 * 3 * 60 = 18.000000000000004 (kayan nokta)
      expect(params.tripsFor(0.1 * 3 * 60), 1);
      expect(params.tripsFor(18 * 3 + 1e-12), 3);
    });

    test('Sıfırdan büyük her hacim en az bir sefer', () {
      expect(params.tripsFor(0.001), 1);
      expect(params.tripsFor(18.5), 2);
      expect(params.tripsFor(36.01), 3);
    });

    test('Sıfır, negatif ve sayı olmayan hacim sefer saymaz', () {
      expect(params.tripsFor(0), 0);
      expect(params.tripsFor(-5), 0);
      expect(params.tripsFor(double.nan), 0);
      expect(params.tripsFor(double.infinity), 0);
    });

    test('Küçük kamyon kapasitesi', () {
      const small = HaulParams(truckM3: 0.5);
      expect(small.tripsFor(1), 2);
      expect(small.tripsFor(1.2), 3);
    });

    test('Çok büyük hacim taşmadan hesaplanır', () {
      expect(params.tripsFor(10000000), 555556); // 10.000.000 / 18 = 555.555,6
    });
  });

  group('Parametre doğrulama', () {
    test('Varsayılan parametreler geçerli', () {
      expect(params.isValid, isTrue);
      expect(params.problems, isEmpty);
    });

    test('Geçersiz parametre hesaplanmadan reddedilir', () {
      final points = [site('S', 41, 29, 100), dump('D', 41.05, 29.05, 100)];
      for (final bad in const [
        HaulParams(truckM3: 0),
        HaulParams(truckM3: -18),
        HaulParams(trucks: 0),
        HaulParams(speedKmh: 0),
        HaulParams(hoursPerDay: 0),
        HaulParams(hoursPerDay: 25),
        HaulParams(fuelPrice: -1),
      ]) {
        expect(bad.isValid, isFalse, reason: '$bad geçersiz olmalı');
        expect(() => optimizeHaul(points, bad), throwsArgumentError);
      }
      expect(const HaulParams(truckM3: double.nan).isValid, isFalse);
      expect(const HaulParams(litersPer100Km: double.infinity).isValid, isFalse);
    });
  });

  group('Boş ve eksik girdiler', () {
    test('Hiç nokta yoksa boş plan', () {
      final plan = optimizeHaul(const [], params);
      expect(plan.assignments, isEmpty);
      expect(plan.backhauls, isEmpty);
      expect(plan.totalVolume, 0);
      expect(plan.unassignedM3, 0);
      expect(plan.totalCost, 0);
      expect(plan.totalTrips, 0);
      expect(plan.days, 0);
      expect(plan.naiveCost, 0);
      expect(plan.savingsVsNaive, 0);
      expect(plan.summaryText(), contains('Hafriyat planı'));
      expect(plan.summaryText(), isNot(contains('Kapasite yetmeyen')));
    });

    test('Döküm sahası yoksa tüm hafriyat açıkta kalır', () {
      final plan = optimizeHaul([site('S1', 41, 29, 500), site('S2', 41.1, 29.1, 250)], params);
      expect(plan.assignments, isEmpty);
      expect(plan.unassignedM3, closeTo(750, 1e-9));
      expect(plan.naiveCost, 0);
    });

    test('Kazı sahası yoksa plan boş, açıkta hacim yok', () {
      final plan = optimizeHaul([dump('D', 41, 29, 1000)], params);
      expect(plan.assignments, isEmpty);
      expect(plan.unassignedM3, 0);
    });

    test('Hacmi sıfır, negatif, NaN veya sonsuz olan noktalar yok sayılır', () {
      final plan = optimizeHaul([
        site('Gecerli', 41, 29, 100),
        site('Sifir', 41, 29.01, 0),
        site('Negatif', 41, 29.02, -50),
        site('NaN', 41, 29.03, double.nan),
        site('Sonsuz', 41, 29.04, double.infinity),
        site('Konumsuz', double.nan, 29, 100),
        dump('D', 41.05, 29.05, 1000),
        dump('KapasitesizD', 41.0, 29.0, 0),
      ], params);
      expect(plan.assignments.map((a) => a.site.id).toSet(), {'Gecerli'});
      expect(plan.totalVolume, closeTo(100, 1e-9));
      expect(plan.unassignedM3, 0);
      expect(plan.totalCost.isFinite, isTrue);
      expect(plan.days.isFinite, isTrue);
    });

    test('Negatif veya sayı olmayan döküm ücreti 0 sayılır', () {
      final plan = optimizeHaul([site('S', 41, 29, 90), dump('D', 41.02, 29.02, 100, fee: -40)], params);
      expect(plan.dumpFees, 0);
      final nanFee = optimizeHaul([site('S', 41, 29, 90), dump('D', 41.02, 29.02, 100, fee: double.nan)], params);
      expect(nanFee.dumpFees, 0);
      expect(nanFee.totalCost.isFinite, isTrue);
    });
  });

  group('Kapasite ve maliyet', () {
    test('Kapasite tam yettiğinde açıkta hacim kalmaz', () {
      final plan = optimizeHaul([site('S', 41, 29, 500), dump('D', 41.05, 29.05, 500)], params);
      expect(plan.totalVolume, closeTo(500, 1e-9));
      expect(plan.unassignedM3, 0);
      expect(usedCapacity(plan, 'D'), lessThanOrEqualTo(500 + 1e-9));
    });

    test('Yuvarlama artığı "kapasite yetmedi" diye raporlanmaz', () {
      final plan = optimizeHaul([site('S', 41, 29, 100.0004), dump('D', 41.05, 29.05, 100.0004)], params);
      expect(plan.unassignedM3, 0);
      expect(plan.summaryText(), isNot(contains('Kapasite yetmeyen')));
    });

    test('Yakın döküm dolunca kalan hacim uzak dökümlere gider', () {
      final plan = optimizeHaul([
        site('S', 41.0, 29.0, 1000),
        dump('Yakin', 41.01, 29.0, 300),
        dump('Uzak', 41.2, 29.0, 1000),
      ], params);
      expect(usedCapacity(plan, 'Yakin'), closeTo(300, 1e-6));
      expect(usedCapacity(plan, 'Uzak'), closeTo(700, 1e-6));
      expect(plan.unassignedM3, 0);
    });

    test('Döküm ücreti yüksekse uzak ama ucuz döküm seçilir', () {
      final s = site('S', 41.0, 29.0, 400);
      final near = dump('YakinPahali', 41.01, 29.0, 1000, fee: 100);
      final far = dump('UzakUcuz', 41.2, 29.0, 1000, fee: 0);
      double unit(HaulPoint d) => params.fuelCostForKm(roadKm(s.position, d.position) * 2) / params.truckM3 + d.feePerM3;
      expect(unit(far), lessThan(unit(near)), reason: 'Test kurgusu: uzak döküm m³ başı daha ucuz');

      final plan = optimizeHaul([s, near, far], params);
      expect(usedCapacity(plan, 'UzakUcuz'), closeTo(400, 1e-6));
      expect(usedCapacity(plan, 'YakinPahali'), closeTo(0, 1e-6));
      // "En yakına dök" alışkanlığına göre tasarruf pozitif.
      expect(plan.savingsVsNaive, greaterThan(0));
    });

    test('Kapasite yetmezse açıkta kalan hacim ve sefer doğru', () {
      final plan = optimizeHaul([site('S', 41, 29, 1000), dump('D', 41.05, 29.05, 600, fee: 50)], params);
      expect(plan.totalVolume, closeTo(600, 1e-6));
      expect(plan.unassignedM3, closeTo(400, 1e-6));
      expect(plan.totalTrips, 34); // 600 / 18 = 33,3 → 34
      expect(plan.dumpFees, closeTo(600 * 50, 1e-6));
      expect(plan.summaryText(), contains('Kapasite yetmeyen: 400 m³'));
    });

    test('Toplamlar tutarlı: maliyet = yakıt + döküm, km = sefer × 2 × tek yön', () {
      final plan = optimizeHaul(DemoData.haulPoints(), params);
      expect(plan.totalCost, closeTo(plan.fuelCost + plan.dumpFees, 1e-6));
      final km = plan.assignments.fold<double>(0, (s, a) => s + a.trips(params) * a.oneWayKm * 2);
      expect(plan.totalKm, closeTo(km, 1e-6));
      expect(plan.fuelLiters, closeTo(plan.totalKm * params.litersPer100Km / 100, 1e-6));
      for (final a in plan.assignments) {
        expect(a.volume, greaterThan(0));
        expect(a.trips(params), params.tripsFor(a.volume));
      }
    });

    test('Gün hesabı filo ve mesaiye göre', () {
      final s = site('S', 41.0, 29.0, 180);
      final d = dump('D', 41.1, 29.0, 1000);
      const p = HaulParams(trucks: 2, hoursPerDay: 10, speedKmh: 30, handlingMin: 15);
      final plan = optimizeHaul([s, d], p);
      final a = plan.assignments.single;
      final expected = a.trips(p) * (a.oneWayKm * 2 / 30 * 60 + 15) / (2 * 10 * 60);
      expect(plan.days, closeTo(expected, 1e-9));
      expect(a.trips(p), 10);
    });

    test('Aynı konumdaki döküm (0 km) yalnızca döküm ücretine mal olur', () {
      final plan = optimizeHaul([site('S', 41, 29, 36), dump('D', 41, 29, 100, fee: 20)], params);
      final a = plan.assignments.single;
      expect(a.oneWayKm, closeTo(0, 1e-9));
      expect(a.fuelCost(params), closeTo(0, 1e-9));
      expect(plan.totalCost, closeTo(36 * 20, 1e-6));
    });

    test('Nokta sırası değişse de en düşük maliyet aynı', () {
      // Doğrusal (m³ başı) maliyet; eşit maliyetli farklı dağılımlarda sefer
      // yuvarlaması toplamı az değiştirebileceği için bunu karşılaştırırız.
      double linearCost(HaulPlan plan) => plan.assignments.fold<double>(
            0,
            (s, a) => s + a.volume * (params.fuelCostForKm(a.oneWayKm * 2) / params.truckM3 + a.dump.feePerM3),
          );
      final points = DemoData.haulPoints();
      final shuffled = [...points]..shuffle(math.Random(7));
      final a = optimizeHaul(points, params);
      final b = optimizeHaul(shuffled, params);
      expect(b.totalVolume, closeTo(a.totalVolume, 1e-6));
      expect(linearCost(b), closeTo(linearCost(a), 1.0));
      expect(b.unassignedM3, closeTo(a.unassignedM3, 1e-6));
    });

    test('Her saha en fazla kendi hacmi kadar, her döküm en fazla kapasitesi kadar', () {
      final rnd = math.Random(11);
      for (var round = 0; round < 30; round++) {
        final points = <HaulPoint>[
          for (var i = 0; i < 4; i++)
            site('S$i', 40.9 + rnd.nextDouble() * 0.3, 28.9 + rnd.nextDouble() * 0.4, 50 + rnd.nextInt(2000).toDouble()),
          for (var j = 0; j < 3; j++)
            dump('D$j', 40.9 + rnd.nextDouble() * 0.3, 28.9 + rnd.nextDouble() * 0.4, rnd.nextInt(2500).toDouble(),
                fee: rnd.nextInt(80).toDouble()),
        ];
        final plan = optimizeHaul(points, params);
        for (final p in points) {
          if (p.kind == HaulPointKind.excavation) expect(shippedFrom(plan, p.id), lessThanOrEqualTo(p.volume + 0.01));
          if (p.kind == HaulPointKind.dump) expect(usedCapacity(plan, p.id), lessThanOrEqualTo(p.volume + 0.01));
        }
        final totalSite = points.where((p) => p.kind == HaulPointKind.excavation).fold<double>(0, (s, p) => s + p.volume);
        final totalCap = points.where((p) => p.kind == HaulPointKind.dump).fold<double>(0, (s, p) => s + p.volume);
        // Taşınan miktar en büyüktür: arz veya toplam kapasite (hangisi azsa).
        expect(plan.totalVolume, closeTo(math.min(totalSite, totalCap), 0.01));
        expect(plan.totalVolume + plan.unassignedM3, closeTo(totalSite, 0.01));
      }
    });
  });

  group('Ulaştırma çözücüsü (solveTransport)', () {
    test('Kaba kuvvetle bulunan en iyi sonuçla aynı (300 rastgele örnek)', () {
      final rnd = math.Random(42);
      for (var round = 0; round < 300; round++) {
        final n = 1 + rnd.nextInt(2);
        final m = 1 + rnd.nextInt(3);
        final supply = [for (var i = 0; i < n; i++) rnd.nextInt(5)];
        final capacity = [for (var j = 0; j < m; j++) rnd.nextInt(5)];
        final cost = [
          for (var i = 0; i < n; i++) [for (var j = 0; j < m; j++) (1 + rnd.nextInt(20)).toDouble()],
        ];
        final flow = solveTransport(
          supply: [for (final s in supply) s.toDouble()],
          capacity: [for (final c in capacity) c.toDouble()],
          cost: cost,
        );
        var shipped = 0.0;
        var total = 0.0;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < m; j++) {
            expect(flow[i][j], greaterThanOrEqualTo(-1e-9));
            shipped += flow[i][j];
            total += flow[i][j] * cost[i][j];
          }
        }
        final (bestShipped, bestCost) = bruteForceTransport(supply, capacity, cost);
        expect(shipped, closeTo(bestShipped, 1e-6), reason: 'örnek $round: taşınan miktar en büyük olmalı');
        expect(total, closeTo(bestCost, 1e-6), reason: 'örnek $round: maliyet en düşük olmalı');
      }
    });

    test('Açgözlü dağıtımın kaçırdığı en ucuz çözümü bulur', () {
      final flow = solveTransport(
        supply: [100, 100],
        capacity: [100, 100],
        cost: [
          [1, 2],
          [2, 100],
        ],
      );
      expect(flow[0][1], closeTo(100, 1e-6));
      expect(flow[1][0], closeTo(100, 1e-6));
    });

    test('Maliyeti sonsuz olan hücre "yol yok" demektir', () {
      final flow = solveTransport(
        supply: [10],
        capacity: [10, 10],
        cost: [
          [double.infinity, 5],
        ],
      );
      expect(flow[0][0], 0);
      expect(flow[0][1], closeTo(10, 1e-9));
      final none = solveTransport(supply: [10], capacity: [10], cost: [
        [double.nan],
      ]);
      expect(none[0][0], 0);
    });

    test('Negatif, NaN veya sonsuz arz/kapasite 0 sayılır', () {
      final flow = solveTransport(
        supply: [-5, double.nan, double.infinity, 4],
        capacity: [double.infinity, 3],
        cost: [
          [1, 1],
          [1, 1],
          [1, 1],
          [2, 1],
        ],
      );
      for (var i = 0; i < 3; i++) {
        expect(flow[i][0] + flow[i][1], 0, reason: 'geçersiz arz $i');
      }
      expect(flow[3][0], 0, reason: 'sonsuz kapasite kullanılmaz');
      expect(flow[3][1], closeTo(3, 1e-9));
    });

    test('Eşit maliyetlerde de toplam ve kapasite doğru', () {
      final flow = solveTransport(
        supply: [7, 7, 7],
        capacity: [5, 5, 5, 5],
        cost: List.generate(3, (_) => List<double>.filled(4, 3)),
      );
      final shipped = flow.expand((r) => r).fold<double>(0, (a, b) => a + b);
      expect(shipped, closeTo(20, 1e-9));
      for (var j = 0; j < 4; j++) {
        expect(flow.fold<double>(0, (s, r) => s + r[j]), lessThanOrEqualTo(5 + 1e-9));
      }
      for (var i = 0; i < 3; i++) {
        expect(flow[i].fold<double>(0, (a, b) => a + b), lessThanOrEqualTo(7 + 1e-9));
      }
    });

    test('Maliyet tablosu boyutu yanlışsa hata', () {
      expect(
        () => solveTransport(supply: [1, 2], capacity: [1], cost: [
          [1],
        ]),
        throwsArgumentError,
      );
      expect(
        () => solveTransport(supply: [1], capacity: [1, 2], cost: [
          [1],
        ]),
        throwsArgumentError,
      );
    });

    test('Boş girdi boş sonuç', () {
      expect(solveTransport(supply: const [], capacity: const [10], cost: const []), isEmpty);
      final noDumps = solveTransport(supply: const [5], capacity: const [], cost: const [<double>[]]);
      expect(noDumps.single, isEmpty);
    });
  });

  group('Dönüş yükü', () {
    // Döküm kuzeyde, saha ortada, ocak dökümün yanında (dönüş yolunun üstünde).
    final s = site('Saha', 41.00, 29.00, 360, need: 200);
    final d = dump('Doküm', 41.20, 29.00, 1000);
    final onTheWay = quarry('YoldakiOcak', 41.18, 29.01, 1000);

    test('Ocak yoksa öneri yok', () {
      final plan = optimizeHaul([s, d], params);
      expect(plan.backhauls, isEmpty);
      expect(plan.backhaulSavings, 0);
    });

    test('Dolgu ihtiyacı yoksa öneri yok', () {
      final plan = optimizeHaul([site('Saha', 41, 29, 360), d, onTheWay], params);
      expect(plan.backhauls, isEmpty);
    });

    test('Yoldaki ocaktan dolgu, ihtiyaç kadar ve yol kazancıyla önerilir', () {
      final plan = optimizeHaul([s, d, onTheWay], params);
      expect(plan.backhauls, hasLength(1));
      final b = plan.backhauls.single;
      expect(b.m3, closeTo(200, 1e-9));
      expect(b.trips, params.tripsFor(200));
      expect(b.savedKm, greaterThan(0));
      expect(b.savedCost, closeTo(params.fuelCostForKm(b.savedKm), 1e-9));
      expect(plan.summaryText(), contains('Dönüş yükleri'));
    });

    test('Ocak stoku ihtiyacı karşılamazsa stok kadar önerilir', () {
      final plan = optimizeHaul([site('Saha', 41, 29, 360, need: 1000), d, quarry('AzStok', 41.18, 29.01, 50)], params);
      expect(plan.backhauls.fold<double>(0, (a, b) => a + b.m3), closeTo(50, 1e-9));
    });

    test('Dönen sefer sayısı kadar dolgu taşınabilir', () {
      // 36 m³ hafriyat = 2 sefer → en fazla 2 × 18 = 36 m³ dolgu.
      final plan = optimizeHaul([site('Saha', 41, 29, 36, need: 500), d, onTheWay], params);
      final given = plan.backhauls.fold<double>(0, (a, b) => a + b.m3);
      expect(given, closeTo(36, 1e-9));
      expect(plan.backhauls.fold<int>(0, (a, b) => a + b.trips), lessThanOrEqualTo(2));
    });

    test('Saha döküm ile ocak arasındaysa (kazanç yok) öneri yapılmaz', () {
      // Aynı boylamda: ocak (40.80) — saha (41.00) — döküm (41.20).
      final plan = optimizeHaul([s, d, quarry('TersYondeOcak', 40.80, 29.00, 1000)], params);
      expect(plan.backhauls, isEmpty);
    });

    test('Birden fazla ocakta en çok kazandıran önce kullanılır', () {
      final plan = optimizeHaul([
        site('Saha', 41, 29, 360, need: 300),
        d,
        quarry('Iyi', 41.18, 29.01, 100),
        quarry('Orta', 41.10, 29.06, 1000),
      ], params);
      expect(plan.backhauls, isNotEmpty);
      expect(plan.backhauls.first.source.id, 'Iyi');
      expect(plan.backhauls.first.m3, closeTo(100, 1e-9));
      expect(plan.backhauls.fold<double>(0, (a, b) => a + b.m3), closeTo(300, 1e-9));
    });

    test('Aynı ocağı paylaşan sahalar stoku aşmaz', () {
      final plan = optimizeHaul([
        site('A', 41.00, 29.00, 360, need: 300),
        site('B', 41.00, 29.02, 360, need: 300),
        dump('D', 41.20, 29.01, 5000),
        quarry('Ocak', 41.18, 29.01, 400),
      ], params);
      final taken = plan.backhauls.where((b) => b.source.id == 'Ocak').fold<double>(0, (a, b) => a + b.m3);
      expect(taken, lessThanOrEqualTo(400 + 1e-9));
    });
  });

  test('Yol mesafesi kuş uçuşunun ${kRoadFactor}x katı', () {
    const a = LatLng(41, 29);
    const b = LatLng(41.1, 29);
    expect(roadKm(a, b), closeTo(haversineKm(a, b) * kRoadFactor, 1e-12));
    expect(roadKm(a, a), 0);
  });
}
