import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/app_notice.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Çevrimdışı-öncelikli çalışma: canlı mod, bağlantısı kesilebilen sahte
/// bir sunucuyla (cihazdaki demo arka ucunu saran [FlakyBackend]) uçtan uca denenir.

/// "Sunucu": istendiğinde bağlantı yokmuş gibi davranır veya isteği uygulayıp
/// yanıtı kaybeder (zaman aşımı). İşlem kimliği (opId) gelen isteği bir kez
/// uygular — gerçek sunucudaki client_ops tablosunun davranışı.
class FlakyBackend implements Backend {
  FlakyBackend(this.inner);

  final LocalBackend inner;

  /// true: her istek "bağlantı yok" hatası verir.
  bool offline = false;

  /// true: bir sonraki yazma sunucuda uygulanır ama yanıt kaybolur.
  bool loseNextResponse = false;

  final Map<String, Object?> _appliedOps = {};
  final Map<String, int> calls = {};

  void _check(String name) {
    calls[name] = (calls[name] ?? 0) + 1;
    if (offline) throw const BackendException('NETWORK');
  }

  Future<T> _write<T>(String name, Future<T> Function() body, {String? opId, T Function(Object? cached)? replay}) async {
    _check(name);
    if (opId != null && _appliedOps.containsKey(opId) && replay != null) return replay(_appliedOps[opId]);
    final result = await body();
    if (opId != null) _appliedOps[opId] = result;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const BackendException('NETWORK');
    }
    return result;
  }

  Future<T> _read<T>(String name, Future<T> Function() body) async {
    _check(name);
    return body();
  }

  /// Örnek ilanları "gerçek" ilan gibi göster (canlı modda örnekle işlem yapılamaz).
  static Listing _real(Listing l) => Listing.fromJson(l.kind, {...l.toJson(), 'demo': false});

  @override
  bool get isLive => true;
  @override
  String? get userId => inner.userId;
  @override
  bool get hasSession => true;
  @override
  Stream<BackendEvent> get events => inner.events;
  @override
  Future<void> init() => inner.init();
  @override
  void dispose() => inner.dispose();

  @override
  Future<void> signInAnonymously() => _read('signIn', inner.signInAnonymously);
  @override
  Future<void> sendPhoneCode(String phoneE164) => _read('sendPhoneCode', () => inner.sendPhoneCode(phoneE164));
  @override
  Future<void> verifyPhoneCode(String phoneE164, String code) =>
      _read('verifyPhoneCode', () => inner.verifyPhoneCode(phoneE164, code));
  @override
  Future<void> signOut() => _read('signOut', inner.signOut);
  @override
  Future<void> deleteAccount() => _read('deleteAccount', inner.deleteAccount);

  @override
  Future<PublicProfile?> fetchMyProfile() => _read('fetchMyProfile', inner.fetchMyProfile);
  @override
  Future<String> fetchMyPhone() => _read('fetchMyPhone', inner.fetchMyPhone);
  @override
  Future<PublicProfile> saveMyProfile({
    required String name,
    required String company,
    required UserRole role,
    required String city,
    required String phone,
  }) =>
      _write('saveMyProfile',
          () => inner.saveMyProfile(name: name, company: company, role: role, city: city, phone: phone));
  @override
  Future<PublicProfile?> fetchProfile(String userId) => _read('fetchProfile', () => inner.fetchProfile(userId));
  @override
  Future<List<PublicProfile>> fetchProfiles(List<String> ids) => _read('fetchProfiles', () => inner.fetchProfiles(ids));
  @override
  Future<List<Rating>> fetchRatingsFor(String userId) => _read('fetchRatingsFor', () => inner.fetchRatingsFor(userId));
  @override
  Future<Set<String>> fetchMyRatedDealIds() => _read('fetchMyRatedDealIds', inner.fetchMyRatedDealIds);
  @override
  Future<UsageInfo> fetchUsage() => _read('fetchUsage', inner.fetchUsage);

  @override
  Future<List<Listing>> fetchListings(ListingKind kind) =>
      _read('fetchListings', () async => [for (final l in await inner.fetchListings(kind)) _real(l)]);
  @override
  Future<Listing> saveListing(Listing listing, {required bool isNew}) =>
      _write('saveListing', () => inner.saveListing(listing, isNew: isNew));
  @override
  Future<void> setListingStatus(ListingKind kind, String id, ListingStatus status) =>
      _write('setListingStatus', () => inner.setListingStatus(kind, id, status));
  @override
  Future<void> deleteListing(ListingKind kind, String id) => _write('deleteListing', () => inner.deleteListing(kind, id));
  @override
  Future<void> setMachineAvailable(String id, bool available) =>
      _write('setMachineAvailable', () => inner.setMachineAvailable(id, available));
  @override
  Future<DateTime> boostListing(ListingKind kind, String id, BoostOption option) =>
      _write('boostListing', () => inner.boostListing(kind, id, option));

  @override
  Future<Set<String>> fetchUnlockedKeys() => _read('fetchUnlockedKeys', inner.fetchUnlockedKeys);
  @override
  Future<UnlockResult> unlock(ListingKind kind, String id, {bool useCredit = false}) =>
      _write('unlock', () => inner.unlock(kind, id, useCredit: useCredit));
  @override
  Future<ContactInfo> contactFor(String refType, String refId) => _read('contactFor', () => inner.contactFor(refType, refId));

  @override
  Future<List<TradeRequest>> fetchRequests() => _read('fetchRequests', inner.fetchRequests);
  @override
  Future<TradeRequest> createRequest(RequestDraft draft, {String? opId}) => _write(
        'createRequest',
        () => inner.createRequest(draft, opId: opId),
        opId: opId,
        replay: (cached) => cached! as TradeRequest,
      );
  @override
  Future<String?> respondRequest(String id, {required bool accept, String? opId}) => _write(
        'respondRequest',
        () => inner.respondRequest(id, accept: accept, opId: opId),
        opId: opId,
        replay: (cached) => cached as String?,
      );
  @override
  Future<void> withdrawRequest(String id) => _write('withdrawRequest', () => inner.withdrawRequest(id));

  @override
  Future<List<Deal>> fetchDeals() => _read('fetchDeals', inner.fetchDeals);
  @override
  Future<Deal> createDeal(DealDraft draft) => _write('createDeal', () => inner.createDeal(draft));
  @override
  Future<Deal> joinDeal(String code) => _write('joinDeal', () => inner.joinDeal(code));
  @override
  Future<Deal> dealAction(String id, DealAction action, {int? index, String? note, String? opId}) => _write(
        'dealAction',
        () => inner.dealAction(id, action, index: index, note: note, opId: opId),
        opId: opId,
        replay: (cached) => cached! as Deal,
      );
  @override
  Future<void> rateDeal(String dealId, int stars, String comment, {String? opId}) => _write(
        'rateDeal',
        () => inner.rateDeal(dealId, stars, comment, opId: opId),
        opId: opId,
        replay: (_) {},
      );

  @override
  Future<void> report(String targetType, String targetId, String reason, String note) =>
      _write('report', () => inner.report(targetType, targetId, reason, note));
  @override
  Future<Set<String>> fetchBlockedIds() => _read('fetchBlockedIds', inner.fetchBlockedIds);
  @override
  Future<void> block(String userId) => _write('block', () => inner.block(userId));
  @override
  Future<void> unblock(String userId) => _write('unblock', () => inner.unblock(userId));

  @override
  Future<List<AppNotification>> fetchNotifications() => _read('fetchNotifications', inner.fetchNotifications);
  @override
  Future<void> markNotificationsRead() => _write('markNotificationsRead', inner.markNotificationsRead);

  @override
  Future<VerifyResult> verifyPurchase(StoreClaim claim) => _write('verifyPurchase', () => inner.verifyPurchase(claim));
  @override
  Future<void> resetLocalData() => inner.resetLocalData();
}

class _Live {
  _Live(this.app, this.server, this.store);

  final AppState app;
  final FlakyBackend server;
  final LocalStore store;
  final List<AppNotice> notices = [];
}

Future<_Live> _liveApp() async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  final server = FlakyBackend(LocalBackend(store, simulate: false));
  final app = AppState(server, store);
  final live = _Live(app, server, store);
  final sub = app.notices.listen(live.notices.add);
  addTearDown(() async {
    await sub.cancel();
    app.dispose();
  });
  await app.init();
  await app.completeOnboarding(
    name: 'Ahmet Yılmaz',
    company: 'Yılmaz Nakliyat',
    role: UserRole.yukSahibi,
    city: 'Ankara',
    phone: '+905551234567',
  );
  // Örnek ilanlar sahte sunucudan "gerçek" ilan olarak gelir; ikinci kez eklenmesin.
  await app.setShowDemo(false);
  return live;
}

Load _newLoad(AppState app, {String cargo = 'Paletli seramik'}) => Load(
      id: '',
      owner: app.me!,
      fromCity: 'Ankara',
      toCity: 'İstanbul',
      cargo: cargo,
      tons: 22,
      vehicle: VehicleType.tir,
      price: 30000,
      date: DateTime.now().add(const Duration(days: 2)),
    );

Future<List<Listing>> _serverLoads(FlakyBackend server, String id) async =>
    (await server.inner.fetchListings(ListingKind.yuk)).where((l) => l.id == id).toList();

/// Bildirim akışındaki olayların teslim edilmesini bekler.
Future<void> _drain() => Future<void>.delayed(Duration.zero);

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

  test('İnternet yokken ilan kaybolmaz; bağlantı gelince sunucuya bir kez gider', () async {
    final t = await _liveApp();
    final app = t.app;
    t.server.offline = true;

    final saved = await app.saveListing(_newLoad(app), isNew: true);
    expect(app.lastWriteQueued, isTrue);
    expect(isUuid(saved.id), isTrue, reason: 'Kimlik cihazda üretilir');
    expect(app.offline, isTrue);
    expect(app.pendingSyncCount, 1);
    expect(app.isPendingSync(saved.id), isTrue);
    expect(app.mine(ListingKind.yuk).map((l) => l.id), contains(saved.id), reason: 'Ekranda hemen görünür');
    expect(await _serverLoads(t.server, saved.id), isEmpty);

    t.server.offline = false;
    await app.syncNow();
    await _drain();
    expect(app.pendingSyncCount, 0);
    expect(app.offline, isFalse);
    expect(app.isPendingSync(saved.id), isFalse);
    expect(await _serverLoads(t.server, saved.id), hasLength(1));
    expect(app.mine(ListingKind.yuk).where((l) => l.id == saved.id), hasLength(1));
    expect(t.notices.any((n) => n.kind == NoticeKind.success), isTrue);
  });

  test('Yanıtı kaybolan istek yeniden gönderilince çift ilan oluşmaz', () async {
    final t = await _liveApp();
    final app = t.app;
    t.server.loseNextResponse = true;

    final saved = await app.saveListing(_newLoad(app), isNew: true);
    expect(app.lastWriteQueued, isTrue, reason: 'Yanıt gelmedi: sonuç bilinmiyor, sıraya alınır');
    expect(await _serverLoads(t.server, saved.id), hasLength(1), reason: 'İstek aslında sunucuya ulaştı');

    await app.syncNow();
    expect(app.pendingSyncCount, 0);
    expect(await _serverLoads(t.server, saved.id), hasLength(1), reason: 'Aynı kimlik: ikinci kez eklenmez');
  });

  test('Çevrimdışı yeni ilan → düzenleme → yayından kaldırma: sunucuya son hâli gider', () async {
    final t = await _liveApp();
    final app = t.app;
    t.server.offline = true;

    final saved = await app.saveListing(_newLoad(app), isNew: true);
    final edited = Load.fromJson({...saved.toJson(), 'cargo': 'İnşaat demiri'});
    await app.saveListing(edited, isNew: false);
    await app.setListingStatus(app.listingById(ListingKind.yuk, saved.id)!, ListingStatus.closed);

    expect(app.pendingSyncCount, 2, reason: 'İki kayıt işlemi birleşir; durum değişikliği ayrı');
    final local = app.listingById(ListingKind.yuk, saved.id)! as Load;
    expect(local.cargo, 'İnşaat demiri');
    expect(local.status, ListingStatus.closed);

    t.server.offline = false;
    await app.syncNow();
    final server = (await _serverLoads(t.server, saved.id)).single as Load;
    expect(server.cargo, 'İnşaat demiri');
    expect(server.status, ListingStatus.closed);
    expect(app.pendingSyncCount, 0);
  });

  test('Hiç gönderilmemiş yeni ilan silinirse sunucuya istek gitmez', () async {
    final t = await _liveApp();
    final app = t.app;
    t.server.offline = true;

    final a = await app.saveListing(_newLoad(app, cargo: 'A yükü'), isNew: true);
    // Sırada işlem varken yeni işlem sunucuya denenmeden sıraya girer.
    final b = await app.saveListing(_newLoad(app, cargo: 'B yükü'), isNew: true);
    await app.deleteListing(app.listingById(ListingKind.yuk, b.id)!);
    expect(app.lastWriteQueued, isFalse);
    expect(app.listingById(ListingKind.yuk, b.id), isNull);
    expect(app.pendingSyncCount, 1);

    t.server.offline = false;
    await app.syncNow();
    expect(await _serverLoads(t.server, a.id), hasLength(1));
    expect(await _serverLoads(t.server, b.id), isEmpty);
    expect(t.server.calls['deleteListing'] ?? 0, 0);
  });

  test('Anlaşma adımı çevrimdışı hemen görünür; kurala uymayan adım sıraya alınmaz', () async {
    final t = await _liveApp();
    final app = t.app;
    var deal = await app.createDeal(const DealDraft(
      title: 'Hafriyat taşıma',
      iAmCustomer: true,
      counterpartyName: 'Ali Usta',
      amount: 50000,
      paymentMethod: PaymentMethod.havale,
      milestones: [DealMilestone(title: 'Tamamı', amount: 50000)],
    ));
    deal = await app.dealAction(deal, DealAction.confirm);
    expect(deal.status, DealStatus.active);

    t.server.offline = true;
    await app.dealAction(deal, DealAction.note, note: 'Kantar fişi alındı');
    expect(app.lastWriteQueued, isTrue);
    await app.dealAction(app.dealById(deal.id)!, DealAction.markPaid, index: 0);
    await app.dealAction(app.dealById(deal.id)!, DealAction.complete);
    final local = app.dealById(deal.id)!;
    expect(local.status, DealStatus.completed);
    expect(local.milestones.first.paid, isTrue);
    expect(local.log.where((l) => l.text == 'Not: Kantar fişi alındı'), hasLength(1));
    expect(app.pendingSyncCount, 3);

    // Tamamlanmış anlaşma yeniden onaylanamaz: hata hemen gösterilir, sıraya girmez.
    await _expectCode(app.dealAction(local, DealAction.confirm), 'BAD_STATE');
    expect(app.pendingSyncCount, 3);

    // Bağlantı gelir ama ilk yanıt kaybolur: aynı işlem kimliğiyle yeniden gönderilir.
    t.server.offline = false;
    t.server.loseNextResponse = true;
    await app.syncNow();
    expect(app.pendingSyncCount, greaterThan(0), reason: 'İlk denemede yanıt kayboldu');
    await app.syncNow();
    expect(app.pendingSyncCount, 0);

    final server = (await t.server.inner.fetchDeals()).firstWhere((d) => d.id == deal.id);
    expect(server.status, DealStatus.completed);
    expect(server.log.where((l) => l.text == 'Not: Kantar fişi alındı'), hasLength(1), reason: 'Not iki kez eklenmez');
    expect(app.dealById(deal.id)!.status, DealStatus.completed);
  });

  test('Sunucu reddederse işlem bırakılır, kullanıcı bilgilendirilir ve sunucudaki hâl gösterilir', () async {
    final t = await _liveApp();
    final app = t.app;
    var deal = await app.createDeal(const DealDraft(
      title: 'Kiralık ekskavatör',
      iAmCustomer: true,
      counterpartyName: 'Veli Usta',
      amount: 0,
      paymentMethod: PaymentMethod.nakit,
    ));
    deal = await app.dealAction(deal, DealAction.confirm);

    t.server.offline = true;
    await app.dealAction(deal, DealAction.deliver);
    expect(app.dealById(deal.id)!.status, DealStatus.delivered);

    // Bu arada anlaşma (ör. başka cihazdan) iptal edildi.
    await t.server.inner.dealAction(deal.id, DealAction.cancel, note: 'Vazgeçildi');

    t.server.offline = false;
    await app.syncNow();
    await _drain();
    expect(app.pendingSyncCount, 0);
    expect(app.dealById(deal.id)!.status, DealStatus.cancelled);
    expect(t.notices.any((n) => n.kind == NoticeKind.error && n.message.contains('Anlaşma işlemi')), isTrue);
  });

  test('Teklif: hak açılmışsa çevrimdışı sıraya alınır, açılmamışsa hemen hata verir', () async {
    final t = await _liveApp();
    final app = t.app;
    final loads = app.marketLoads;
    expect(loads.length, greaterThanOrEqualTo(2));
    final unlockedLoad = loads[0];
    final lockedLoad = loads[1];
    expect((await app.unlock(unlockedLoad)).ok, isTrue);

    t.server.offline = true;
    final draft = RequestDraft(kind: ListingKind.yuk, listingId: unlockedLoad.id, amount: 27500, note: 'Aracım hazır');
    final sent = await app.sendRequest(unlockedLoad, draft);
    expect(app.lastWriteQueued, isTrue);
    expect(AppState.isTemporaryId(sent.id), isTrue);
    expect(app.myPendingRequestFor(unlockedLoad)?.amount, 27500);
    expect(app.isPendingSync(unlockedLoad.id), isTrue);

    await _expectCode(
      app.sendRequest(lockedLoad, RequestDraft(kind: ListingKind.yuk, listingId: lockedLoad.id, amount: 1000)),
      'LOCKED',
    );
    // İlk gönderim denendiği için (sunucuya ulaşmış olabilir) geri çekme bağlantı bekler.
    await _expectCode(app.withdraw(sent), 'SYNC_PENDING');
    await _expectCode(app.contactForRequest(sent), 'SYNC_PENDING');

    t.server.offline = false;
    await app.syncNow();
    final serverRequests = await t.server.inner.fetchRequests();
    expect(serverRequests.where((r) => r.listingId == unlockedLoad.id && r.isPending), hasLength(1));
    expect(app.myPendingRequestFor(unlockedLoad), isNotNull);
    expect(AppState.isTemporaryId(app.myPendingRequestFor(unlockedLoad)!.id), isFalse);
  });

  test('Okundu bilgisi ve profil değişikliği çevrimdışı kaybolmaz', () async {
    final t = await _liveApp();
    final app = t.app;
    await t.store.writeMaps('v2_notifications', [
      {
        'id': 'n1',
        'type': 'request',
        'title': 'Yeni teklif',
        'body': '',
        'ref_type': 'request',
        'ref_id': null,
        'read_at': null,
        'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
      },
    ]);
    await app.refreshAll();
    expect(app.unreadCount, 1);

    t.server.offline = true;
    await app.markNotificationsRead();
    await app.saveProfile(name: 'Ahmet Yılmaz', company: 'Yılmaz Lojistik', role: UserRole.nakliyeci, city: 'Ankara', phone: '+905551234567');
    expect(app.unreadCount, 0);
    expect(app.me?.company, 'Yılmaz Lojistik');
    expect(app.pendingSyncCount, 2);

    t.server.offline = false;
    await app.syncNow();
    expect((await t.server.inner.fetchNotifications()).every((n) => !n.unread), isTrue);
    expect((await t.server.inner.fetchMyProfile())?.company, 'Yılmaz Lojistik');
    expect(app.unreadCount, 0);
  });

  test('Uygulama internetsiz yeniden açılınca son veriler ve bekleyen işlemler korunur', () async {
    final t = await _liveApp();
    t.server.offline = true;
    final saved = await t.app.saveListing(_newLoad(t.app), isNew: true);

    // Aynı cihazda uygulama yeniden açılır; internet hâlâ yok.
    final server2 = FlakyBackend(LocalBackend(t.store, simulate: false))..offline = true;
    final app2 = AppState(server2, t.store);
    addTearDown(app2.dispose);
    await app2.init();
    expect(app2.ready, isTrue);
    expect(app2.loadError, isNull);
    expect(app2.me?.name, 'Ahmet Yılmaz', reason: 'Profil önbellekten gelir');
    expect(app2.offline, isTrue);
    expect(app2.pendingSyncCount, 1);
    expect(app2.mine(ListingKind.yuk).map((l) => l.id), contains(saved.id), reason: 'Bekleyen ilan görünür');

    server2.offline = false;
    await app2.syncNow();
    expect(app2.pendingSyncCount, 0);
    expect(await _serverLoads(server2, saved.id), hasLength(1));
  });

  test('Bağlantı geri gelince olay yayınlanır (bekleyen satın almalar için)', () async {
    final t = await _liveApp();
    var restored = 0;
    final sub = t.app.connectivityRestored.listen((_) => restored++);
    addTearDown(sub.cancel);
    t.server.offline = true;
    await t.app.refreshAll();
    expect(t.app.offline, isTrue);
    t.server.offline = false;
    await t.app.syncNow();
    await _drain();
    expect(t.app.offline, isFalse);
    expect(restored, 1);
  });

  test('Demo modunda gönderim sırası kullanılmaz', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final app = AppState(LocalBackend(store, simulate: false), store);
    addTearDown(app.dispose);
    await app.init();
    await app.completeOnboarding(name: 'Ayşe Kaya', company: '', role: UserRole.yukSahibi, city: 'Ankara', phone: '+905551112233');
    final saved = await app.saveListing(_newLoad(app), isNew: true);
    expect(app.lastWriteQueued, isFalse);
    expect(app.pendingSyncCount, 0);
    expect(saved.id.startsWith('loc-'), isTrue);
  });
}
