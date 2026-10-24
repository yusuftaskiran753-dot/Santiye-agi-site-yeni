import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/data/cities.dart';
import 'package:santiye_agi/data/demo_data.dart';
import 'package:santiye_agi/logic/load_matcher.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/utils/format.dart';

/// Boş dönüş (yük eşleştirme) için uç durum testleri.

const _owner = PublicProfile(id: 'sahip-1', name: 'Yük Sahibi');

Load load(
  String id,
  String from,
  String to, {
  VehicleType vehicle = VehicleType.tir,
  double price = 20000,
  int inDays = 1,
  ListingStatus status = ListingStatus.active,
  bool hidden = false,
  PublicProfile owner = _owner,
}) =>
    Load(
      id: id,
      owner: owner,
      fromCity: from,
      toCity: to,
      cargo: 'Yük $id',
      tons: 20,
      vehicle: vehicle,
      price: price,
      date: startOfToday().add(Duration(days: inDays)),
      status: status,
      hidden: hidden,
    );

List<String> ids(List<LoadMatch> matches) => [for (final m in matches) m.load.id];

void main() {
  group('Girdi', () {
    test('Yük yoksa sonuç boş', () {
      expect(matchLoads(loads: const [], emptyAt: 'Ankara', home: 'İstanbul'), isEmpty);
    });

    test('Bilinmeyen başlangıç veya ev ili sonuç vermez (İstanbul varsayılmaz)', () {
      final loads = [load('L1', 'Ankara', 'İstanbul')];
      expect(matchLoads(loads: loads, emptyAt: 'Atlantis', home: 'İstanbul'), isEmpty);
      expect(matchLoads(loads: loads, emptyAt: 'Ankara', home: ''), isEmpty);
    });

    test('İl adları büyük/küçük harf ve boşluk farkından etkilenmez', () {
      final loads = [load('L1', 'ankara', ' İstanbul '), load('L2', 'Ankara', 'Kayseri')];
      final canonical = matchLoads(loads: loads, emptyAt: 'Ankara', home: 'İstanbul');
      final messy = matchLoads(loads: loads, emptyAt: '  ankara ', home: 'İSTANBUL');
      expect(ids(messy), ids(canonical));
      expect([for (final m in messy) m.score], [for (final m in canonical) m.score]);
      expect(canonical.first.load.id, 'L1');
      expect(canonical.first.score, 100);
    });

    test('Yükleme veya teslim ili bilinmeyen yük atlanır', () {
      final matches = matchLoads(
        loads: [load('Bilinmeyen', 'Narnia', 'İstanbul'), load('Bilinmeyen2', 'Ankara', 'Mordor'), load('L', 'Ankara', 'Bursa')],
        emptyAt: 'Ankara',
        home: 'İstanbul',
      );
      expect(ids(matches), ['L']);
    });
  });

  group('Filtreler', () {
    test('Yayında olmayan, gizlenen ve tarihi geçmiş yükler önerilmez', () {
      final matches = matchLoads(
        loads: [
          load('Kapali', 'Ankara', 'İstanbul', status: ListingStatus.closed),
          load('Gizli', 'Ankara', 'İstanbul', hidden: true),
          load('Gecmis', 'Ankara', 'İstanbul', inDays: -1),
          load('Bugun', 'Ankara', 'İstanbul', inDays: 0),
        ],
        emptyAt: 'Ankara',
        home: 'İstanbul',
      );
      expect(ids(matches), ['Bugun'], reason: 'Bugün yüklenecek ilan hâlâ geçerlidir');
    });

    test('Kendi ilanım önerilmez', () {
      const me = PublicProfile(id: 'ben', name: 'Ben');
      final matches = matchLoads(
        loads: [load('Benim', 'Ankara', 'İstanbul', owner: me), load('Baskasi', 'Ankara', 'İstanbul')],
        emptyAt: 'Ankara',
        home: 'İstanbul',
        excludeOwnerId: 'ben',
      );
      expect(ids(matches), ['Baskasi']);
    });

    test('Araç tipi seçilmezse tüm araçlar, seçilirse yalnızca o tip', () {
      final loads = [
        load('Tir', 'Ankara', 'İstanbul'),
        load('Frigo', 'Ankara', 'İstanbul', vehicle: VehicleType.frigo),
      ];
      expect(matchLoads(loads: loads, emptyAt: 'Ankara', home: 'İstanbul'), hasLength(2));
      expect(ids(matchLoads(loads: loads, emptyAt: 'Ankara', home: 'İstanbul', vehicle: VehicleType.frigo)), ['Frigo']);
    });

    test('Boş gidiş sınırı tam sınırda dahil, üstünde hariç', () {
      final km = roadKm(cityLatLng('Ankara'), cityLatLng('Kırıkkale'));
      final loads = [load('Kirikkale', 'Kırıkkale', 'İstanbul')];
      expect(matchLoads(loads: loads, emptyAt: 'Ankara', home: 'İstanbul', maxEmptyKm: km), hasLength(1));
      expect(matchLoads(loads: loads, emptyAt: 'Ankara', home: 'İstanbul', maxEmptyKm: km - 0.01), isEmpty);
    });

    test('Sınır 0 veya negatifse yalnızca bulunduğum ildeki yükler', () {
      final loads = [load('Burada', 'Ankara', 'İstanbul'), load('Yakinda', 'Kırıkkale', 'İstanbul')];
      expect(ids(matchLoads(loads: loads, emptyAt: 'Ankara', home: 'İstanbul', maxEmptyKm: 0)), ['Burada']);
      expect(ids(matchLoads(loads: loads, emptyAt: 'Ankara', home: 'İstanbul', maxEmptyKm: -10)), ['Burada']);
    });

    test('Varsayılan sınır 250 km', () {
      final far = load('Uzak', 'İzmir', 'İstanbul'); // Ankara–İzmir > 250 km
      expect(roadKm(cityLatLng('Ankara'), cityLatLng('İzmir')), greaterThan(250));
      expect(matchLoads(loads: [far], emptyAt: 'Ankara', home: 'İstanbul'), isEmpty);
      expect(matchLoads(loads: [far], emptyAt: 'Ankara', home: 'İstanbul', maxEmptyKm: double.nan), isEmpty);
    });
  });

  group('Puan', () {
    test('Bulunduğum ilden eve giden yük tam puan alır', () {
      final m = matchLoads(loads: [load('L', 'Ankara', 'İstanbul')], emptyAt: 'Ankara', home: 'İstanbul').single;
      expect(m.emptyKm, 0);
      expect(m.score, 100);
      expect(m.label, 'Çok uygun');
      expect(m.closerToHomeKm, closeTo(m.loadedKm, 1e-9));
    });

    test('Eve doğru giden yük, ters yöne gidenden üstte', () {
      final matches = matchLoads(
        loads: [load('Ters', 'Ankara', 'Kayseri'), load('Eve', 'Ankara', 'İstanbul')],
        emptyAt: 'Ankara',
        home: 'İstanbul',
      );
      expect(ids(matches), ['Eve', 'Ters']);
      expect(matches.last.closerToHomeKm, lessThan(0), reason: 'Kayseri İstanbul\'dan uzaklaştırır');
      expect(matches.first.score, greaterThan(matches.last.score));
    });

    test('Aynı yük için yükleme yeri yakın olan daha yüksek puan alır', () {
      final matches = matchLoads(
        loads: [load('Uzaktan', 'Kırşehir', 'İstanbul'), load('Yakindan', 'Kırıkkale', 'İstanbul')],
        emptyAt: 'Ankara',
        home: 'İstanbul',
      );
      final near = matches.firstWhere((m) => m.load.id == 'Yakindan');
      final far = matches.firstWhere((m) => m.load.id == 'Uzaktan');
      expect(near.emptyKm, lessThan(far.emptyKm));
      expect(near.score, greaterThanOrEqualTo(far.score));
    });

    test('Boşaldığım il evimse yön değil yakınlık belirleyicidir', () {
      final matches = matchLoads(
        loads: [load('BuradanUzaga', 'İzmir', 'Van'), load('KomsuIl', 'Manisa', 'İzmir')],
        emptyAt: 'İzmir',
        home: 'İzmir',
        maxEmptyKm: 500,
      );
      final here = matches.firstWhere((m) => m.load.id == 'BuradanUzaga');
      expect(here.emptyKm, 0);
      expect(here.closerToHomeKm, lessThan(0), reason: 'Van, İzmir\'den uzaklaştırır');
      // Ters yöne gitse de bulunduğum ilden alınan yük en az 80 puan alır.
      expect(here.score, greaterThanOrEqualTo(80));
    });

    test('Aynı ilde yüklenip boşalan yük (0 km) hata vermez', () {
      final m = matchLoads(loads: [load('Sehirici', 'Ankara', 'Ankara')], emptyAt: 'Ankara', home: 'İstanbul').single;
      expect(m.loadedKm, 1, reason: 'En az 1 km sayılır (bölme hatası olmaz)');
      expect(m.closerToHomeKm, closeTo(0, 1e-9));
      expect(m.score, inInclusiveRange(0, 100));
      expect(m.pricePerKm.isFinite, isTrue);
    });

    test('Puan her zaman 0–100 arasında ve sayı', () {
      final matches = matchLoads(
        loads: [for (final l in DemoData.loads()) l, load('X', 'Edirne', 'Hakkari'), load('Y', 'Ankara', 'Kars')],
        emptyAt: 'Ankara',
        home: 'Erzurum',
        maxEmptyKm: 5000,
      );
      expect(matches, isNotEmpty);
      for (final m in matches) {
        expect(m.score, inInclusiveRange(0, 100));
        expect(m.emptyKm.isFinite && m.loadedKm.isFinite && m.closerToHomeKm.isFinite, isTrue);
      }
    });

    test('Km başı navlun ve etiket eşikleri', () {
      final l = load('L', 'Ankara', 'İstanbul', price: 0);
      LoadMatch m(int score, {double loadedKm = 100}) =>
          LoadMatch(load: l, score: score, emptyKm: 0, closerToHomeKm: 0, loadedKm: loadedKm);
      expect(m(75).label, 'Çok uygun');
      expect(m(74).label, 'Uygun');
      expect(m(50).label, 'Uygun');
      expect(m(49).label, 'Kısmen');
      expect(m(10).pricePerKm, 0, reason: 'Navlun yoksa km başı 0');
      expect(m(10, loadedKm: 0).pricePerKm, 0);
      final paid = LoadMatch(load: load('P', 'Ankara', 'İstanbul', price: 30000), score: 1, emptyKm: 0, closerToHomeKm: 0, loadedKm: 400);
      expect(paid.pricePerKm, 75);
    });
  });

  group('Sıralama', () {
    test('Eşit puanda sıra her zaman aynı: erken tarih, sonra kimlik', () {
      final a = load('B', 'Ankara', 'İstanbul', inDays: 3);
      final b = load('A', 'Ankara', 'İstanbul', inDays: 3);
      final c = load('C', 'Ankara', 'İstanbul', inDays: 1);
      final forward = matchLoads(loads: [a, b, c], emptyAt: 'Ankara', home: 'İstanbul');
      final backward = matchLoads(loads: [c, b, a], emptyAt: 'Ankara', home: 'İstanbul');
      expect(ids(forward), ['C', 'A', 'B']);
      expect(ids(backward), ids(forward));
    });

    test('Eşit puanda km başı navlunu yüksek olan önce', () {
      final cheap = load('Ucuz', 'Ankara', 'İstanbul', price: 10000);
      final rich = load('Pahali', 'Ankara', 'İstanbul', price: 40000);
      expect(ids(matchLoads(loads: [cheap, rich], emptyAt: 'Ankara', home: 'İstanbul')), ['Pahali', 'Ucuz']);
    });

    test('Puan sıralaması azalan', () {
      final matches = matchLoads(loads: DemoData.loads(), emptyAt: 'Ankara', home: 'İstanbul', maxEmptyKm: 2000);
      for (var i = 1; i < matches.length; i++) {
        expect(compareMatches(matches[i - 1], matches[i]), lessThanOrEqualTo(0));
        expect(matches[i - 1].score, greaterThanOrEqualTo(matches[i].score));
      }
    });
  });
}
