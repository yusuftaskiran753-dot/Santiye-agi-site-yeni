import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:santiye_agi/config.dart';
import 'package:santiye_agi/data/demo_data.dart';
import 'package:santiye_agi/logic/haul_optimizer.dart';
import 'package:santiye_agi/logic/load_matcher.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/billing_service.dart';
import 'package:santiye_agi/utils/content_filter.dart';
import 'package:santiye_agi/utils/format.dart';

void main() {
  group('Biçimlendirme', () {
    test('TL ve sayı', () {
      expect(formatTL(12500), '₺12.500');
      expect(formatNumber(2.5, decimals: 1), '2,5');
      expect(formatNumber(1234567), '1.234.567');
      expect(formatNumber(12500.50, decimals: 2), '12.500,5');
    });

    test('Negatif sıfır yazılmaz', () {
      expect(formatNumber(-0.2), '0');
      expect(formatTL(-0.2), '₺0');
      expect(formatTL(-1500), '-₺1.500');
    });

    test('Türkçe sayı girişi', () {
      expect(parseNumber('12.500'), 12500);
      expect(parseNumber('2,5'), 2.5);
      expect(parseNumber('2.5'), 2.5);
      expect(parseNumber('1.250,75'), 1250.75);
      expect(parseNumber('₺ 3.000'), 3000);
      expect(parseNumber(''), 0);
      expect(parseNumber('abc'), 0);
    });

    test('Türkçe baş harfler ve büyük harf', () {
      expect(initials('ismail çelik'), 'İÇ');
      expect(initials('Ali'), 'A');
      expect(initials('   '), '?');
      expect(trUpper('ışık'), 'IŞIK');
      expect(trUpper('istif'), 'İSTİF');
    });

    test('Mesafe biçimi', () {
      expect(formatKm(0.45), '450 m');
      expect(formatKm(5.26), '5,3 km');
      expect(formatKm(120), '120 km');
    });

    test('Selamlama saate göre değişir', () {
      expect(greeting(DateTime(2026, 1, 1, 8)), 'Günaydın');
      expect(greeting(DateTime(2026, 1, 1, 14)), 'İyi günler');
      expect(greeting(DateTime(2026, 1, 1, 22)), 'İyi akşamlar');
    });
  });

  group('Telefon', () {
    test('Türkiye numaraları tek biçime çevrilir', () {
      expect(normalizePhoneTr('0555 123 45 67'), '+905551234567');
      expect(normalizePhoneTr('+90 (555) 123 45 67'), '+905551234567');
      expect(normalizePhoneTr('5551234567'), '+905551234567');
      expect(normalizePhoneTr('0090 555 123 45 67'), '+905551234567');
      expect(normalizePhoneTr('0212 555 11 22'), '+902125551122');
    });

    test('Geçersiz numaralar reddedilir', () {
      expect(isValidTrPhone('123'), isFalse);
      expect(isValidTrPhone('0555 123 45'), isFalse);
      expect(isValidTrPhone('0955 123 45 67'), isFalse);
      expect(isValidTrPhone(''), isFalse);
    });

    test('Görünen biçim ve WhatsApp numarası', () {
      expect(formatPhoneDisplay('+905551234567'), '0555 123 45 67');
      expect(phoneToInternational('0555 123 45 67'), '905551234567');
      expect(phoneToInternational('+90 (555) 123 45 67'), '905551234567');
    });
  });

  group('İçerik filtresi', () {
    test('Normal ilan metni geçer', () {
      expect(ContentFilter.isOffensive('Ankara → İstanbul paletli seramik, 22 ton'), isFalse);
      expect(ContentFilter.validate('Operatörlü ekskavatör, günlük kiralık'), isNull);
      expect(ContentFilter.validate(null), isNull);
      expect(ContentFilter.isOffensive('   '), isFalse);
    });
  });

  group('Boş dönüş eşleştirme', () {
    test('Ankara\'da boşalıp İstanbul\'a dönen tır için en iyi yük Ankara → İstanbul', () {
      final matches = matchLoads(
        loads: DemoData.loads(),
        emptyAt: 'Ankara',
        home: 'İstanbul',
        vehicle: VehicleType.tir,
      );
      expect(matches, isNotEmpty);
      expect(matches.first.load.fromCity, 'Ankara');
      expect(matches.first.load.toCity, 'İstanbul');
      expect(matches.first.score, greaterThanOrEqualTo(75));
    });

    test('Araç tipi filtresi uygulanır', () {
      final matches = matchLoads(
        loads: DemoData.loads(),
        emptyAt: 'İzmir',
        home: 'İzmir',
        vehicle: VehicleType.damperli,
      );
      expect(matches.every((m) => m.load.vehicle == VehicleType.damperli), isTrue);
    });

    test('Kendi ilanı ve yükleme günü geçmiş ilan önerilmez', () {
      final owner = DemoData.profile('demo-u2');
      final past = Load(
        id: 'ESKI',
        owner: owner,
        fromCity: 'Ankara',
        toCity: 'İstanbul',
        cargo: 'Eski ilan',
        tons: 20,
        vehicle: VehicleType.tir,
        price: 40000,
        date: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(past.isExpired, isTrue);
      expect(past.isOpen, isFalse);
      final matches = matchLoads(
        loads: [past, ...DemoData.loads()],
        emptyAt: 'Ankara',
        home: 'İstanbul',
        vehicle: VehicleType.tir,
        excludeOwnerId: 'demo-u2',
      );
      expect(matches.any((m) => m.load.id == 'ESKI'), isFalse);
      expect(matches.any((m) => m.load.ownerId == 'demo-u2'), isFalse);
    });
  });

  group('Ulaştırma çözücüsü', () {
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
      expect(flow[0][0] + flow[1][1], closeTo(0, 1e-6));
    });

    test('Kapasitesi olmayan döküme gönderilmez, maliyet en düşük', () {
      final flow = solveTransport(
        supply: [100, 50],
        capacity: [30, 0, 200],
        cost: [
          [5, 1, 9],
          [3, 1, 2],
        ],
      );
      expect(flow[0][1] + flow[1][1], closeTo(0, 1e-6));
      expect(flow[0][0], closeTo(30, 1e-6));
      expect(flow[0][2], closeTo(70, 1e-6));
      expect(flow[1][2], closeTo(50, 1e-6));
    });

    test('Boş girdi boş sonuç verir', () {
      expect(solveTransport(supply: [], capacity: [10], cost: []), isEmpty);
    });
  });

  group('Hafriyat optimizasyonu', () {
    test('Tüm hafriyat kapasite aşılmadan dağıtılır', () {
      final points = DemoData.haulPoints();
      final plan = optimizeHaul(points, const HaulParams());
      final totalSite =
          points.where((p) => p.kind == HaulPointKind.excavation).fold<double>(0, (a, p) => a + p.volume);
      expect(plan.totalVolume + plan.unassignedM3, closeTo(totalSite, 0.01));
      for (final dump in points.where((p) => p.kind == HaulPointKind.dump)) {
        final used = plan.assignments.where((a) => a.dump.id == dump.id).fold<double>(0, (a, x) => a + x.volume);
        expect(used, lessThanOrEqualTo(dump.volume + 0.01));
      }
      expect(plan.totalTrips, greaterThan(0));
      expect(plan.totalCost, greaterThan(0));
      expect(plan.summaryText(), contains('Hafriyat planı'));
    });

    test('Döküm kapasitesi yetmezse açıkta kalan hacim raporlanır', () {
      final points = [
        HaulPoint(id: 'S', name: 'Saha', kind: HaulPointKind.excavation, lat: 41.0, lng: 29.0, volume: 1000),
        HaulPoint(id: 'D', name: 'Döküm', kind: HaulPointKind.dump, lat: 41.05, lng: 29.05, volume: 600, feePerM3: 50),
      ];
      final plan = optimizeHaul(points, const HaulParams(truckM3: 18));
      expect(plan.totalVolume, closeTo(600, 1e-6));
      expect(plan.unassignedM3, closeTo(400, 1e-6));
      expect(plan.totalTrips, 34); // 600 / 18 = 33,3 → 34 sefer
    });

    test('Tam bölünen hacimde fazladan sefer sayılmaz', () {
      const p = HaulParams(truckM3: 18);
      expect(p.tripsFor(18000), 1000);
      expect(p.tripsFor(18001), 1001);
      expect(p.tripsFor(0), 0);
    });

    test('Dönüş yükü dolgu ihtiyacını ve ocak stokunu aşmaz', () {
      final points = DemoData.haulPoints();
      final plan = optimizeHaul(points, const HaulParams());
      for (final site in points.where((p) => p.needM3 > 0)) {
        final given = plan.backhauls.where((b) => b.site.id == site.id).fold<double>(0, (a, b) => a + b.m3);
        expect(given, lessThanOrEqualTo(site.needM3 + 1e-6));
      }
      for (final src in points.where((p) => p.kind == HaulPointKind.source)) {
        final taken = plan.backhauls.where((b) => b.source.id == src.id).fold<double>(0, (a, b) => a + b.m3);
        expect(taken, lessThanOrEqualTo(src.volume + 1e-6));
      }
    });
  });

  group('Anlaşma modeli', () {
    Deal deal({String? customer, String? provider, String createdBy = 'a', DealStatus status = DealStatus.active}) =>
        Deal(
          id: 'd1',
          code: 'ABCD2345',
          kind: DealKind.yuk,
          title: 'Ankara → İstanbul',
          customerId: customer,
          providerId: provider,
          customerName: 'Alıcı',
          providerName: 'Taşıyıcı',
          createdBy: createdBy,
          amount: 30000,
          status: status,
          milestones: [
            DealMilestone(title: 'Avans', amount: 10000, paidAt: DateTime(2026, 1, 1)),
            const DealMilestone(title: 'Kalan', amount: 20000),
          ],
        );

    test('Roller ve karşı taraf doğru belirlenir', () {
      final d = deal(customer: 'a', provider: 'b');
      expect(d.isCustomer('a'), isTrue);
      expect(d.isProvider('b'), isTrue);
      expect(d.counterpartyId('a'), 'b');
      expect(d.counterpartyId('b'), 'a');
      expect(d.canActAsProvider('a'), isFalse);
      expect(d.isSolo('a'), isFalse);
    });

    test('Karşı tarafı uygulamada olmayan kayıtta oluşturan iki tarafı da yönetir', () {
      final d = deal(customer: 'a', createdBy: 'a', status: DealStatus.pending);
      expect(d.isSolo('a'), isTrue);
      expect(d.canActAsCustomer('a'), isTrue);
      expect(d.canActAsProvider('a'), isTrue);
      expect(d.awaitingCounterparty, isTrue);
      expect(d.counterpartyName('a'), 'Taşıyıcı');
    });

    test('Ödeme takibi toplamları', () {
      final d = deal(customer: 'a', provider: 'b');
      expect(d.plannedTotal, 30000);
      expect(d.paidTotal, 10000);
      expect(d.receivedTotal, 0);
    });

    test('JSON gidiş-dönüşü bilgileri korur', () {
      final d = deal(customer: 'a', provider: 'b');
      final back = Deal.fromJson(d.toJson());
      expect(back.title, d.title);
      expect(back.milestones.length, 2);
      expect(back.milestones.first.paid, isTrue);
      expect(back.status, DealStatus.active);
    });
  });

  group('Kullanım hakları', () {
    test('Ücretsiz hak sayacı ve Premium', () {
      const u = UsageInfo(freeUsed: 3, freeLimit: 5);
      expect(u.freeLeft, 2);
      expect(u.isPremium, isFalse);
      final p = UsageInfo(premiumUntil: DateTime.now().add(const Duration(days: 3)));
      expect(p.isPremium, isTrue);
      const over = UsageInfo(freeUsed: 9, freeLimit: 5);
      expect(over.freeLeft, 0);
    });
  });

  group('Mağaza', () {
    ProductDetails product(double rawPrice) => ProductDetails(
          id: AppConfig.premiumMonthlyId,
          title: 'Premium',
          description: '',
          price: '₺$rawPrice',
          rawPrice: rawPrice,
          currencyCode: 'TRY',
        );

    test('Google Play tekliflerinden temel plan fiyatı seçilir', () {
      final trialOffer = product(0);
      final basePlan = product(399.99);
      expect(BillingService.preferBasePlan(null, trialOffer).rawPrice, 0);
      expect(BillingService.preferBasePlan(trialOffer, basePlan).rawPrice, 399.99);
      expect(BillingService.preferBasePlan(basePlan, trialOffer).rawPrice, 399.99);
    });

    test('Kalıcı doğrulama hataları yeniden denenmez, geçiciler denenir', () {
      for (final code in ['INVALID', 'EXPIRED', 'REVOKED', 'UNKNOWN_PRODUCT', 'ACCOUNT_MISMATCH', 'ALREADY_USED', 'BAD_INPUT']) {
        expect(VerifyResult(ok: false, error: code).permanent, isTrue, reason: code);
      }
      for (final code in ['NETWORK', 'SERVER', 'CONFIG', 'AUTH']) {
        expect(VerifyResult(ok: false, error: code).permanent, isFalse, reason: code);
      }
      expect(const VerifyResult(ok: true).permanent, isFalse);
    });

    test('Abonelik ve kredi ürünleri ayrılır', () {
      expect(BillingService.isSubscription(AppConfig.premiumMonthlyId), isTrue);
      expect(BillingService.isSubscription(AppConfig.premiumYearlyId), isTrue);
      for (final id in AppConfig.creditPacks.keys) {
        expect(BillingService.isSubscription(id), isFalse);
      }
    });
  });
}
