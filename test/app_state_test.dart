import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/config.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demo modu (cihazda çalışan arka uç) ile uçtan uca iş kuralları.
/// Simülasyon kapalıdır: örnek firmalar otomatik yanıt vermez.
Future<(AppState, LocalStore)> _signedIn() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = LocalStore(prefs);
  final app = AppState(LocalBackend(store, simulate: false), store);
  await app.init();
  expect(app.ready, isTrue);
  expect(app.me, isNull);
  await app.completeOnboarding(
    name: 'Ahmet Yılmaz',
    company: 'Yılmaz Nakliyat',
    role: UserRole.yukSahibi,
    city: 'Ankara',
    phone: '+905551234567',
  );
  await app.setShowDemo(true);
  return (app, store);
}

Load _myLoad(AppState app, {String to = 'İstanbul'}) => Load(
      id: '',
      owner: app.me!,
      fromCity: 'Ankara',
      toCity: to,
      cargo: 'Paletli seramik',
      tons: 22,
      vehicle: VehicleType.tir,
      price: 30000,
      date: DateTime.now().add(const Duration(days: 2)),
    );

Future<void> _expectCode(Future<Object?> future, String code) async {
  try {
    await future;
    fail('$code bekleniyordu');
  } on BackendException catch (e) {
    expect(e.code, code);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Profil kaydedilir, telefon gizli tutulur', () async {
    final (app, _) = await _signedIn();
    expect(app.me?.name, 'Ahmet Yılmaz');
    expect(app.me?.displayName, isNotEmpty);
    expect(app.myPhone, '+905551234567');
    expect(app.termsAccepted, isTrue);
  });

  test('Ücretsiz iletişim hakkı biter; kredi ile devam edilir', () async {
    final (app, _) = await _signedIn();
    final loads = app.marketLoads;
    expect(loads.length, greaterThan(AppConfig.freeMonthlyUnlocks + 1));

    for (var i = 0; i < AppConfig.freeMonthlyUnlocks; i++) {
      final r = await app.unlock(loads[i]);
      expect(r.ok, isTrue);
      expect(r.method, 'free');
      expect(app.isUnlocked(loads[i]), isTrue);
    }
    // Aynı ilan ikinci kez hak harcamaz.
    final again = await app.unlock(loads.first);
    expect(again.ok, isTrue);
    expect(again.method, 'already');

    final next = loads[AppConfig.freeMonthlyUnlocks];
    final blocked = await app.unlock(next);
    expect(blocked.ok, isFalse);
    expect(blocked.reason, 'QUOTA');

    // Kredi paketi satın alınır (Demo modunda doğrulama cihazdadır).
    final packId = AppConfig.creditPacks.keys.first;
    final packCredits = AppConfig.creditPacks[packId]!;
    final claim = StoreClaim(platform: 'android', productId: packId, token: 'tok-1');
    expect((await app.verifyPurchase(claim)).ok, isTrue);
    expect((await app.verifyPurchase(claim)).credits, packCredits, reason: 'Aynı satın alma iki kez yüklenmez');
    await app.refreshUsage();
    expect(app.usage.credits, packCredits);

    final paid = await app.unlock(next, useCredit: true);
    expect(paid.ok, isTrue);
    expect(paid.method, 'credit');
    await app.refreshUsage();
    expect(app.usage.credits, packCredits - 1);
  });

  test('Premium sınırsız iletişim hakkı verir', () async {
    final (app, _) = await _signedIn();
    final r = await app.verifyPurchase(
      const StoreClaim(platform: 'ios', productId: AppConfig.premiumMonthlyId, token: 'sub-1', isSubscription: true),
    );
    expect(r.ok, isTrue);
    expect(app.isPremium, isTrue);
    for (final l in app.marketLoads.take(AppConfig.freeMonthlyUnlocks + 2)) {
      final u = await app.unlock(l);
      expect(u.ok, isTrue);
      expect(u.method, 'premium');
    }
  });

  test('Ücretsiz üyelikte aktif ilan sınırı uygulanır', () async {
    final (app, _) = await _signedIn();
    for (var i = 0; i < AppConfig.freeActiveListings; i++) {
      await app.saveListing(_myLoad(app), isNew: true);
    }
    expect(app.mine(ListingKind.yuk).length, AppConfig.freeActiveListings);
    await _expectCode(app.saveListing(_myLoad(app), isNew: true), 'LISTING_LIMIT');

    // Biri kapatılınca yeni ilan verilebilir.
    await app.setListingStatus(app.mine(ListingKind.yuk).first, ListingStatus.closed);
    await app.saveListing(_myLoad(app), isNew: true);
    expect(app.mine(ListingKind.yuk).length, AppConfig.freeActiveListings + 1);
  });

  test('Teklif için önce iletişim hakkı gerekir; teklif geri çekilebilir', () async {
    final (app, _) = await _signedIn();
    final load = app.marketLoads.first;
    final draft = RequestDraft(kind: ListingKind.yuk, listingId: load.id, amount: 25000, note: 'Aracım hazır');
    await _expectCode(app.sendRequest(load, draft), 'LOCKED');

    await app.unlock(load);
    final r = await app.sendRequest(load, draft);
    expect(r.isPending, isTrue);
    expect(app.myPendingRequestFor(load)?.id, r.id);

    await app.withdraw(r);
    expect(app.requestById(r.id)?.status, RequestStatus.withdrawn);
    expect(app.myPendingRequestFor(load), isNull);
  });

  test('Kendi ilanına teklif verilemez', () async {
    final (app, _) = await _signedIn();
    final mine = await app.saveListing(_myLoad(app), isNew: true);
    expect(app.isMine(mine), isTrue);
    expect(app.market(ListingKind.yuk).any((l) => l.id == mine.id), isFalse);
    await _expectCode(
      app.sendRequest(mine, RequestDraft(kind: ListingKind.yuk, listingId: mine.id, amount: 1000)),
      'OWN_LISTING',
    );
  });

  test('Teklif kabulü → anlaşma kaydı → ödeme takibi → tamamlama → puan', () async {
    final (app, store) = await _signedIn();
    final mine = await app.saveListing(_myLoad(app), isNew: true);

    // İki taşıyıcıdan gelen teklifler.
    Map<String, dynamic> offer(String id, String from, double amount) => {
          'id': id,
          'kind': 'yuk',
          'listing_id': mine.id,
          'listing_title': 'Ankara → İstanbul · Paletli seramik',
          'owner_id': app.myId,
          'requester_id': from,
          'amount': amount,
          'quantity': 22.0,
          'unit': 'ton',
          'start_date': null,
          'address': '',
          'note': '',
          'status': 'pending',
          'deal_id': null,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
    await store.writeMaps('v2_requests', [offer('r1', 'demo-u9', 28000), offer('r2', 'demo-u1', 29500)]);
    await app.refreshRequestsAndDeals();
    expect(app.pendingIncoming, 2);
    expect(app.actionCount, greaterThanOrEqualTo(2));

    final dealId = await app.respond(app.requestById('r1')!, accept: true);
    expect(dealId, isNotNull);
    expect(app.requestById('r1')?.status, RequestStatus.accepted);
    expect(app.requestById('r2')?.status, RequestStatus.rejected, reason: 'Yük tek taşıyıcıya verilir');
    expect(app.mine(ListingKind.yuk).first.status, ListingStatus.closed);

    var deal = app.dealById(dealId)!;
    expect(deal.status, DealStatus.active);
    expect(deal.isCustomer(app.myId), isTrue, reason: 'Yük sahibi işi veren taraftır');
    expect(deal.providerId, 'demo-u9');
    expect(deal.amount, 28000);
    expect(deal.milestones, hasLength(1));

    // Karşı taraf tahsilatı onaylar; yük sahibi bunu yapamaz.
    await _expectCode(app.dealAction(deal, DealAction.markReceived, index: 0), 'BAD_INPUT');
    deal = await app.dealAction(deal, DealAction.markPaid, index: 0);
    expect(deal.milestones.first.paid, isTrue);
    expect(deal.paidTotal, 28000);

    deal = await app.dealAction(deal, DealAction.complete);
    expect(deal.status, DealStatus.completed);
    await app.refreshAll();
    expect(app.me?.dealsCompleted, 1);
    expect(app.dealNeedsMe(deal), isTrue, reason: 'Tamamlanan anlaşma puan bekler');

    await app.rateDeal(deal, 5, 'Zamanında teslim');
    expect(app.ratedDeals, contains(deal.id));
    expect(app.dealNeedsMe(deal), isFalse);
    await _expectCode(app.rateDeal(deal, 4, 'tekrar'), 'ALREADY_RATED');
    final ratings = await app.fetchRatingsFor('demo-u9');
    expect(ratings.any((r) => r.dealId == deal.id && r.stars == 5), isTrue);
  });

  test('Karşı tarafı uygulamada olmayan anlaşma kaydı tek kişiyle yürür', () async {
    final (app, _) = await _signedIn();
    var deal = await app.createDeal(
      const DealDraft(
        title: 'Hafriyat taşıma',
        iAmCustomer: true,
        counterpartyName: 'Ali Usta',
        amount: 50000,
        paymentMethod: PaymentMethod.havale,
        milestones: [DealMilestone(title: 'Avans', amount: 20000), DealMilestone(title: 'Kalan', amount: 30000)],
      ),
    );
    expect(deal.status, DealStatus.pending);
    expect(deal.code, hasLength(8));
    expect((await app.joinDeal(deal.code.toLowerCase())).id, deal.id);

    deal = await app.dealAction(deal, DealAction.confirm);
    expect(deal.status, DealStatus.active);
    deal = await app.dealAction(deal, DealAction.markPaid, index: 0);
    deal = await app.dealAction(deal, DealAction.markReceived, index: 0);
    expect(deal.receivedTotal, 20000);
    deal = await app.dealAction(deal, DealAction.dispute, note: 'Eksik sefer');
    expect(deal.status, DealStatus.disputed);
    deal = await app.dealAction(deal, DealAction.resolve);
    expect(deal.status, DealStatus.active);
    deal = await app.dealAction(deal, DealAction.deliver);
    expect(deal.status, DealStatus.delivered);
    deal = await app.dealAction(deal, DealAction.complete);
    expect(deal.status, DealStatus.completed);
    expect(deal.log.length, greaterThanOrEqualTo(7));

    // Karşı taraf olmadığından puan verilemez ve sayaç artmaz.
    await _expectCode(app.rateDeal(deal, 5, ''), 'NOT_AVAILABLE');
    await app.refreshAll();
    expect(app.me?.dealsCompleted, 0);
    await _expectCode(app.dealAction(deal, DealAction.cancel), 'BAD_STATE');
  });

  test('Engellenen kullanıcının ve şikâyet edilen ilanın görünmemesi', () async {
    final (app, _) = await _signedIn();
    final first = app.marketLoads.first;
    await app.block(first.ownerId);
    expect(app.marketLoads.any((l) => l.ownerId == first.ownerId), isFalse);
    await app.unblock(first.ownerId);
    expect(app.marketLoads.any((l) => l.ownerId == first.ownerId), isTrue);

    final target = app.marketLoads.last;
    await app.report(targetType: 'yuk', targetId: target.id, reason: 'Yanıltıcı ilan');
    expect(app.marketLoads.any((l) => l.id == target.id), isFalse);
  });

  test('Örnek ilanlar kapatılabilir', () async {
    final (app, _) = await _signedIn();
    expect(app.marketLoads, isNotEmpty);
    await app.setShowDemo(false);
    expect(app.marketLoads, isEmpty);
  });

  test('Hesap silinince profil ve kayıtlar temizlenir', () async {
    final (app, _) = await _signedIn();
    await app.saveListing(_myLoad(app), isNew: true);
    await app.deleteAccount();
    expect(app.me, isNull);
    expect(app.termsAccepted, isFalse);
    expect(await app.backend.fetchMyProfile(), isNull);
    expect(await app.backend.fetchListings(ListingKind.yuk), everyElement(predicate<Listing>((l) => l.demo)));
  });
}
