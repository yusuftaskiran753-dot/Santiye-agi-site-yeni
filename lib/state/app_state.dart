import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../data/cities.dart';
import '../data/demo_data.dart';
import '../data/trade_catalog.dart';
import '../logic/deal_rules.dart';
import '../logic/social_rules.dart';
import '../models/models.dart';
import '../models/social.dart';
import '../services/app_notice.dart';
import '../services/backend.dart';
import '../services/photo_storage.dart';
import '../services/local_store.dart';
import '../services/social_store.dart';
import '../services/sync_queue.dart';
import '../utils/validators.dart';

/// Uygulamanın bütün verisi ve işlemleri.
///
/// Ekranlar yalnızca bu sınıfı kullanır; veri, [Backend] üzerinden ya cihazda
/// (Demo modu) ya da sunucuda (canlı mod) tutulur. Hatalar
/// [BackendException] olarak fırlatılır ve ekranlarda Türkçe mesajla gösterilir.
///
/// ## Çevrimdışı çalışma (canlı mod)
///
/// Şantiyede çekim sık kesilir. Bu yüzden:
/// * Son sunucu verisi cihazda saklanır; uygulama internetsiz de açılır.
/// * İnternet yokken yapılan yazma işlemleri (ilan, teklif, anlaşma adımı,
///   puan, şikâyet, engelleme, profil…) kaybolmaz: cihazdaki gönderim
///   sırasına ([SyncQueue]) alınır, ekranda hemen görünür ve bağlantı gelince
///   sırayla, otomatik gönderilir. Her işlemin bir kimliği vardır; yanıtı
///   kaybolan istek yeniden gönderilse bile sunucuda bir kez uygulanır.
/// * Sunucu bir işlemi kalıcı olarak reddederse (ör. anlaşma bu arada iptal
///   edilmiş) kullanıcıya bildirilir ve sunucudaki doğru hâl gösterilir.
/// * Kod gerektiren işlemler (iletişim hakkı açma, kredi harcama, anlaşma kodu
///   oluşturma, satın alma) yalnızca çevrimiçi yapılır.
class AppState extends ChangeNotifier {
  AppState(this.backend, this._store)
    : _sync = SyncQueue(_store),
      social = SocialStore(_store);

  final Backend backend;
  final LocalStore _store;
  final SyncQueue _sync;
  final SocialStore social;
  Future<void> Function()? beforeSignOut;
  Future<void> Function()? afterAccountDeleted;

  static const String _kShowDemo = 'app_show_demo';
  static const String _kTerms = 'app_terms_accepted';
  static const String _kHidden = 'app_hidden_listings';
  static const String _kHaul = 'app_haul_points';
  static const String _kCache = 'cache_v2';

  // ───────────── Durum ─────────────

  bool ready = false;

  /// İlk yükleme hatası (ör. internet yok ve önbellek de yok).
  String? loadError;

  /// Son yenileme sunucuya ulaşamadı; önbellekteki veriler gösteriliyor.
  bool offline = false;
  bool refreshing = false;
  DateTime? lastRefresh;

  /// Gönderim sırası şu an sunucuya gönderiliyor.
  bool syncing = false;

  /// Son yazma işlemi internet olmadığı için cihazdaki gönderim sırasına
  /// alındıysa true. Ekranlar başarı mesajını buna göre seçer.
  bool lastWriteQueued = false;

  PublicProfile? me;
  String myPhone = '';
  UsageInfo usage = const UsageInfo(
    freeLimit: AppConfig.freeMonthlyUnlocks,
    freeListingLimit: AppConfig.freeActiveListings,
    boostDayCost: AppConfig.boostDayCost,
    boostWeekCost: AppConfig.boostWeekCost,
  );

  bool showDemo = AppConfig.showSamplesByDefault;
  bool termsAccepted = false;

  final Map<ListingKind, List<Listing>> _listings = {
    for (final k in ListingKind.values) k: <Listing>[],
  };
  List<TradeRequest> requests = [];
  List<Deal> deals = [];
  List<AppNotification> notifications = [];
  Set<String> unlocked = {};
  Set<String> blocked = {};
  Set<String> ratedDeals = {};

  /// Kullanıcının şikâyet ettiği ve artık görmek istemediği ilanlar.
  Set<String> hiddenByMe = {};
  List<HaulPoint> haulPoints = [];

  StreamSubscription<BackendEvent>? _eventsSub;
  Timer? _eventDebounce;
  Timer? _retryTimer;
  int _retryFailures = 0;
  bool _disposed = false;
  final StreamController<String> _flashes =
      StreamController<String>.broadcast();
  final StreamController<AppNotice> _notices =
      StreamController<AppNotice>.broadcast();
  final StreamController<void> _connectivity =
      StreamController<void>.broadcast();

  /// Kullanıcıya kısa süreli gösterilecek bilgi mesajları (yeni bildirim vb.).
  Stream<String> get flashes => _flashes.stream;

  /// Senkron sonuçları (gönderildi / reddedildi) gibi arka plan bildirimleri.
  Stream<AppNotice> get notices => _notices.stream;

  /// Çevrimdışıyken sunucuya yeniden ulaşıldı (ör. bekleyen satın alma doğrulamalarını tamamlamak için).
  Stream<void> get connectivityRestored => _connectivity.stream;

  String? get myId => backend.userId;
  String? get developmentPhoneCode => backend is DevelopmentPhoneCode
      ? (backend as DevelopmentPhoneCode).developmentPhoneCode
      : null;
  bool get isLive => backend.isLive;
  bool get requiresPhoneVerification => backend is RuntimeAuthPolicy
      ? (backend as RuntimeAuthPolicy).requiresPhoneVerification
      : AppConfig.authMode == AuthMode.phone;

  Future<void> refreshAuthPolicy() async {
    if (backend is RuntimeAuthPolicy) {
      await (backend as RuntimeAuthPolicy).refreshAuthPolicy();
      notifyListeners();
    }
  }

  bool get onboarded => me != null;
  String get city => me?.city ?? 'İstanbul';
  LatLng get userPosition => cityLatLng(city);
  bool get isPremium => usage.isPremium;

  int get unreadCount => notifications.where((n) => n.unread).length;
  List<TradeRequest> get incomingRequests =>
      requests.where((r) => r.ownerId == myId).toList();
  List<TradeRequest> get outgoingRequests =>
      requests.where((r) => r.requesterId == myId).toList();
  int get pendingIncoming => incomingRequests.where((r) => r.isPending).length;
  int get dealsNeedingMe => deals.where(dealNeedsMe).length;

  /// Kullanıcının yanıt vermesi gereken toplam iş (alt menü rozeti).
  int get actionCount => pendingIncoming + dealsNeedingMe;

  /// Sunucuya gönderilmeyi bekleyen işlem sayısı.
  int get pendingSyncCount => _sync.countFor(myId);
  List<SyncOp> get pendingSyncOps => _sync.pendingFor(myId);

  /// Bu kayıt (ilan, anlaşma, teklif) için gönderilmeyi bekleyen değişiklik var mı?
  bool isPendingSync(String refId) => _sync.hasPendingFor(myId, refId);

  // ───────────── Başlatma ─────────────

  Future<void> init() async {
    showDemo =
        !isLive &&
        (_store.prefs.getBool(_kShowDemo) ?? AppConfig.showSamplesByDefault);
    termsAccepted = _store.prefs.getBool(_kTerms) ?? false;
    hiddenByMe = _store.readStrings(_kHidden).toSet();
    haulPoints = backend is HaulBackend
        ? []
        : _store.has(_kHaul)
        ? [for (final m in _store.readMaps(_kHaul)) HaulPoint.fromJson(m)]
        : DemoData.haulPoints();
    social.load();
    await social.seedIfNeeded();
    await social.purgeExpiredMessages();
    await _purgeStories();
    try {
      await backend.init();
      await refreshAuthPolicy();
      _eventsSub ??= backend.events.listen(_onEvent);
      if (backend.hasSession) {
        me = await backend.fetchMyProfile();
        if (me != null) {
          myPhone = await backend.fetchMyPhone();
          await refreshAll();
        }
      }
    } catch (e) {
      final error = BackendException.from(e);
      if (error.code == 'PHONE_REQUIRED') {
        _clearUserData();
        loadError = null;
        offline = false;
      } else if (_loadCache()) {
        _reapplyOverlays(dealsFresh: true);
        offline = true;
        _scheduleRetry();
      } else {
        loadError = error.message;
        offline = true;
        _scheduleRetry();
      }
    }
    ready = true;
    notifyListeners();
  }

  /// İlk yükleme başarısız olduysa yeniden dener.
  Future<void> retryInit() async {
    loadError = null;
    ready = false;
    notifyListeners();
    await _eventsSub?.cancel();
    _eventsSub = null;
    await init();
  }

  @override
  void dispose() {
    _disposed = true;
    _eventsSub?.cancel();
    _eventDebounce?.cancel();
    _retryTimer?.cancel();
    _flashes.close();
    _notices.close();
    _connectivity.close();
    backend.dispose();
    super.dispose();
  }

  /// Kapatıldıktan sonra tamamlanan arka plan işleri (ör. geç gelen yanıt) hata vermesin.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _notify(AppNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  void _onEvent(BackendEvent event) {
    if (event.type == 'phone_required') {
      _eventDebounce?.cancel();
      _clearUserData();
      loadError = null;
      offline = false;
      notifyListeners();
      return;
    }
    if (event.message.isNotEmpty && !_flashes.isClosed) {
      _flashes.add(event.message);
    }
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_refreshActivity());
    });
  }

  Future<void> _refreshActivity() async {
    try {
      final results = await Future.wait<Object?>([
        backend.fetchNotifications(),
        backend.fetchRequests(),
        backend.fetchDeals(),
        backend.fetchUsage(),
        backend.fetchMyProfile(),
        backend.fetchMyRatedDealIds(),
      ]);
      notifications = results[0]! as List<AppNotification>;
      requests = results[1]! as List<TradeRequest>;
      deals = results[2]! as List<Deal>;
      usage = results[3]! as UsageInfo;
      me = (results[4] as PublicProfile?) ?? me;
      ratedDeals = results[5]! as Set<String>;
      social.load();
      _reapplyOverlays(dealsFresh: true);
      _markOnline();
      notifyListeners();
    } catch (_) {
      // Arka plan yenilemesi sessizce başarısız olabilir.
    }
  }

  Future<void>? _refreshFuture;

  /// Bütün verileri yeniler (aşağı çekerek yenileme, uygulama öne gelince,
  /// bağlantı geri gelince). Önce bekleyen çevrimdışı işlemleri gönderir.
  /// Yenileme sürerken yapılan ikinci çağrı aynı yenilemenin bitmesini bekler.
  Future<void> refreshAll() {
    if (me == null) return Future<void>.value();
    return _refreshFuture ??= _refreshAll().whenComplete(
      () => _refreshFuture = null,
    );
  }

  Future<void> _refreshAll() async {
    refreshing = true;
    notifyListeners();
    try {
      if (isLive && pendingSyncCount > 0) {
        final result = await _flushQueue();
        final stop = result.stoppedBy;
        // Bağlantı yoksa sunucudan okumayı denemenin anlamı yok.
        if (stop != null && stop.isTransient) throw stop;
      }
      final results = await Future.wait<Object?>([
        backend.fetchMyProfile(),
        backend.fetchUsage(),
        backend.fetchRequests(),
        backend.fetchDeals(),
        backend.fetchNotifications(),
        backend.fetchUnlockedKeys(),
        backend.fetchBlockedIds(),
        backend.fetchMyRatedDealIds(),
        for (final k in ListingKind.values) backend.fetchListings(k),
        if (backend is HaulBackend) (backend as HaulBackend).fetchHaulPoints(),
      ]);
      var i = 0;
      me = (results[i++] as PublicProfile?) ?? me;
      usage = results[i++]! as UsageInfo;
      requests = results[i++]! as List<TradeRequest>;
      deals = results[i++]! as List<Deal>;
      notifications = results[i++]! as List<AppNotification>;
      unlocked = results[i++]! as Set<String>;
      blocked = results[i++]! as Set<String>;
      ratedDeals = results[i++]! as Set<String>;
      for (final k in ListingKind.values) {
        _listings[k] = results[i++]! as List<Listing>;
      }
      if (backend is HaulBackend) {
        haulPoints = results[i++]! as List<HaulPoint>;
      }
      lastRefresh = DateTime.now();
      social.load();
      // Önbelleğe sunucudaki hâl yazılır; bekleyen işlemler her açılışta üstüne uygulanır.
      unawaited(_saveCache());
      _reapplyOverlays(dealsFresh: true);
      _markOnline();
    } catch (e) {
      final error = BackendException.from(e);
      if (!error.isTransient) rethrow;
      _markOffline();
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  /// "Şimdi gönder" düğmesi: bekleyen işlemleri göndermeyi ve verileri yenilemeyi hemen dener.
  Future<void> syncNow() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryFailures = 0;
    await refreshAll();
  }

  Future<void> refreshListings(ListingKind kind) async {
    _listings[kind] = await backend.fetchListings(kind);
    _reapplyOverlays(dealsFresh: false);
    notifyListeners();
  }

  Future<void> refreshUsage() async {
    try {
      usage = await backend.fetchUsage();
      notifyListeners();
    } catch (_) {
      // Sayaçlar bir sonraki yenilemede güncellenir.
    }
  }

  Future<void> refreshRequestsAndDeals() async {
    final results = await Future.wait<Object?>([
      backend.fetchRequests(),
      backend.fetchDeals(),
    ]);
    requests = results[0]! as List<TradeRequest>;
    deals = results[1]! as List<Deal>;
    _reapplyOverlays(dealsFresh: true);
    notifyListeners();
  }

  /// Yazma sonrası arka plan yenilemesi: kayıt yapıldıysa yenilemenin
  /// başarısız olması kullanıcıya hata olarak gösterilmez.
  Future<void> _quietly(Future<void> Function() refresh) async {
    try {
      await refresh();
    } catch (_) {
      // Veriler bir sonraki yenilemede düzelir.
    }
  }

  // ───────────── Önbellek (çekim zayıfken açılış) ─────────────

  Future<void> _saveCache() async {
    if (!isLive) return;
    await _store.writeMap(_kCache, {
      'user': myId,
      'me': me?.toJson(),
      'phone': myPhone,
      'usage': usage.toJson(),
      for (final k in ListingKind.values)
        'l_${k.name}': [for (final l in _listings[k]!) l.toJson()],
      'requests': [for (final r in requests) r.toJson()],
      'deals': [for (final d in deals) d.toJson()],
      'notifications': [for (final n in notifications) n.toJson()],
      'unlocked': unlocked.toList(),
      'blocked': blocked.toList(),
      'rated': ratedDeals.toList(),
      'haul_points': [for (final p in haulPoints) p.toJson()],
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  bool _loadCache() {
    if (!isLive) return false;
    final c = _store.readMap(_kCache);
    if (c == null || c['me'] == null || c['user'] != myId) return false;
    me = PublicProfile.fromJson(asMap(c['me']));
    myPhone = asString(c['phone']);
    final cachedUsage = asMap(c['usage']);
    // Premium kullanıcı çevrimdışıyken ödeme ekranıyla karşılaşmasın.
    if (cachedUsage.isNotEmpty) usage = UsageInfo.fromJson(cachedUsage);
    for (final k in ListingKind.values) {
      _listings[k] = [
        for (final m in asMapList(c['l_${k.name}'])) Listing.fromJson(k, m),
      ];
    }
    requests = [
      for (final m in asMapList(c['requests'])) TradeRequest.fromJson(m),
    ];
    deals = [for (final m in asMapList(c['deals'])) Deal.fromJson(m)];
    notifications = [
      for (final m in asMapList(c['notifications']))
        AppNotification.fromJson(m),
    ];
    unlocked = asStringList(c['unlocked']).toSet();
    blocked = asStringList(c['blocked']).toSet();
    // Puanlanmış anlaşmalar "puan bekliyor" diye yeniden görünmesin.
    ratedDeals = asStringList(c['rated']).toSet();
    if (backend is HaulBackend) {
      haulPoints = [
        for (final p in asMapList(c['haul_points'])) HaulPoint.fromJson(p),
      ];
    }
    lastRefresh = asDateOrNull(c['saved_at']);
    return true;
  }

  // ───────────── Çevrimdışı gönderim sırası ─────────────

  /// Yazma işlemini çalıştırır. Canlı modda internet yoksa (veya sırada
  /// bekleyen işlem varsa) işlemi cihazdaki gönderim sırasına alır, ekrandaki
  /// veriyi hemen günceller ve [queued] sonucunu döner; [lastWriteQueued] true olur.
  ///
  /// [validateOffline], işlem sıraya alınmadan önce cihazda denetlenebilen
  /// kuralları uygular (ör. anlaşma durumu); kurala uymayan işlem sıraya
  /// alınmaz, hata hemen gösterilir.
  Future<T> _write<T>(
    SyncOp op, {
    required Future<T> Function() online,
    required T Function() queued,
    void Function()? validateOffline,
  }) async {
    lastWriteQueued = false;
    if (!isLive) return online();
    // Sırada işlem varken yenisi önce gönderilemez (sıra bozulur): önce sırayı boşaltmayı dene.
    if (_sync.countFor(myId) > 0 && !offline) await _flushQueue();
    if (_sync.countFor(myId) == 0) {
      try {
        final result = await online();
        _markOnline();
        return result;
      } catch (error) {
        final e = BackendException.from(error);
        if (!e.isTransient) rethrow;
        // İstek sunucuya ulaşmış olabilir; işlem kimliği sayesinde tekrar gönderimde çift uygulanmaz.
        op.attempts = 1;
        op.lastError = e.code;
      }
    }
    validateOffline?.call();
    await _sync.enqueue(op);
    lastWriteQueued = true;
    _applyOverlay(op);
    _markOffline();
    notifyListeners();
    return queued();
  }

  SyncOp _op(SyncOpType type, Map<String, dynamic> payload) =>
      SyncOp(id: newUuid(), type: type, userId: myId ?? '', payload: payload);

  Future<SyncFlushResult> _flushQueue() async {
    final uid = myId;
    if (!isLive || uid == null || _sync.countFor(uid) == 0) {
      return const SyncFlushResult();
    }
    syncing = true;
    notifyListeners();
    try {
      final result = await _sync.flush(uid, _execute);
      for (final f in result.dropped) {
        _notify(
          AppNotice.error(
            'Çevrimdışı yapılan "${f.op.type.label}" işlemi uygulanamadı: ${f.error.message}',
          ),
        );
      }
      if (result.applied.isNotEmpty && result.complete) {
        final n = result.applied.length;
        _notify(
          AppNotice.success(
            n == 1
                ? 'Çevrimdışıyken yaptığınız işlem sunucuya gönderildi.'
                : 'Çevrimdışıyken yaptığınız $n işlem sunucuya gönderildi.',
          ),
        );
      }
      if (result.applied.isNotEmpty) _markOnline();
      return result;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Sıradaki işlemi sunucuya gönderir.
  Future<void> _execute(SyncOp op) async {
    final p = op.payload;
    ListingKind kind() =>
        enumByName(ListingKind.values, p['kind'], ListingKind.yuk);
    final id = asString(p['id']);
    switch (op.type) {
      case SyncOpType.saveListing:
        await backend.saveListing(
          Listing.fromJson(kind(), asMap(p['listing'])),
          isNew: asBool(p['is_new']),
        );
      case SyncOpType.setListingStatus:
        await backend.setListingStatus(
          kind(),
          id,
          enumByName(ListingStatus.values, p['status'], ListingStatus.active),
        );
      case SyncOpType.deleteListing:
        await backend.deleteListing(kind(), id);
      case SyncOpType.setMachineAvailable:
        await backend.setMachineAvailable(id, asBool(p['available'], true));
      case SyncOpType.saveProfile:
        await backend.saveMyProfile(
          name: asString(p['name']),
          company: asString(p['company']),
          role: enumByName(UserRole.values, p['role'], UserRole.nakliyeci),
          city: asString(p['city']),
          phone: asString(p['phone']),
        );
      case SyncOpType.createRequest:
        await backend.createRequest(
          RequestDraft.fromJson(asMap(p['draft'])),
          opId: op.id,
        );
      case SyncOpType.respondRequest:
        await backend.respondRequest(
          id,
          accept: asBool(p['accept']),
          opId: op.id,
        );
      case SyncOpType.withdrawRequest:
        await backend.withdrawRequest(id);
      case SyncOpType.dealAction:
        await backend.dealAction(
          asString(p['deal_id']),
          enumByName(DealAction.values, p['action'], DealAction.note),
          index: p['index'] == null ? null : asInt(p['index']),
          note: p['note'] == null ? null : asString(p['note']),
          opId: op.id,
        );
      case SyncOpType.rateDeal:
        await backend.rateDeal(
          asString(p['deal_id']),
          asInt(p['stars']),
          asString(p['comment']),
          opId: op.id,
        );
      case SyncOpType.report:
        await backend.report(
          asString(p['target_type']),
          asString(p['target_id']),
          asString(p['reason']),
          asString(p['note']),
        );
      case SyncOpType.block:
        await backend.block(asString(p['user_id']));
      case SyncOpType.unblock:
        await backend.unblock(asString(p['user_id']));
      case SyncOpType.markNotificationsRead:
        await backend.markNotificationsRead();
    }
  }

  void _markOnline() {
    _retryFailures = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    final wasOffline = offline;
    offline = false;
    if (wasOffline && !_connectivity.isClosed) _connectivity.add(null);
    // Bağlantı geri geldiyse bekleyenleri gönder ve verileri tazele.
    if (wasOffline && isLive && !refreshing) unawaited(_quietly(refreshAll));
  }

  void _markOffline() {
    offline = true;
    _scheduleRetry();
  }

  /// Bağlantı yokken artan aralıklarla (5 sn … 5 dk) yeniden dener.
  void _scheduleRetry() {
    if (!isLive || _disposed || (_retryTimer?.isActive ?? false)) return;
    final delay = SyncQueue.backoff(_retryFailures);
    _retryFailures++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      // Profil hiç yüklenemediyse açılış ekranındaki "Tekrar dene" düğmesi kullanılır.
      if (_disposed || me == null) return;
      unawaited(_quietly(refreshAll));
    });
  }

  /// Bekleyen işlemlerin etkisini ekrandaki veriye uygular. Sunucudan yeni
  /// veri gelince yeniden çağrılır. Anlaşma adımları yalnızca anlaşmalar
  /// sunucudan tazelendiyse ([dealsFresh]) yeniden uygulanır (iki kez işlenmesin).
  void _reapplyOverlays({required bool dealsFresh}) {
    if (!isLive) return;
    for (final op in _sync.pendingFor(myId)) {
      if (op.type == SyncOpType.dealAction && !dealsFresh) continue;
      _applyOverlay(op);
    }
  }

  void _applyOverlay(SyncOp op) {
    final p = op.payload;
    final id = asString(p['id']);
    ListingKind kind() =>
        enumByName(ListingKind.values, p['kind'], ListingKind.yuk);
    try {
      switch (op.type) {
        case SyncOpType.saveListing:
          final listing = Listing.fromJson(kind(), asMap(p['listing']));
          if (listing.kind == ListingKind.sicil) {
            _listings[ListingKind.sicil] = _listings[ListingKind.sicil]!
                .where((l) => !isMine(l))
                .toList();
          }
          _upsertLocalListing(listing);
        case SyncOpType.setListingStatus:
          _patchListing(kind(), id, {'status': asString(p['status'])});
        case SyncOpType.setMachineAvailable:
          _patchListing(ListingKind.makine, id, {
            'available': asBool(p['available'], true),
          });
        case SyncOpType.deleteListing:
          _listings[kind()] = _listings[kind()]!
              .where((l) => l.id != id)
              .toList();
        case SyncOpType.saveProfile:
          final m = me;
          if (m != null) {
            me = m.copyWith(
              name: asString(p['name']),
              company: asString(p['company']),
              role: enumByName(UserRole.values, p['role'], m.role),
              city: asString(p['city']),
            );
          }
          myPhone = asString(p['phone']);
        case SyncOpType.createRequest:
          _overlayRequest(op);
        case SyncOpType.respondRequest:
          final accept = asBool(p['accept']);
          final listingId = asString(p['listing_id']);
          final isLoad = p['kind'] == ListingKind.yuk.name;
          requests = [
            for (final r in requests)
              if (r.id == id && r.isPending)
                _requestWith(
                  r,
                  accept ? RequestStatus.accepted : RequestStatus.rejected,
                  op.createdAt,
                )
              else if (accept &&
                  isLoad &&
                  r.listingId == listingId &&
                  r.isPending &&
                  r.id != id)
                _requestWith(r, RequestStatus.rejected, op.createdAt)
              else
                r,
          ];
          if (accept && isLoad) {
            _patchListing(ListingKind.yuk, listingId, {
              'status': ListingStatus.closed.name,
            });
          }
        case SyncOpType.withdrawRequest:
          requests = [
            for (final r in requests)
              r.id == id && r.isPending
                  ? _requestWith(r, RequestStatus.withdrawn, op.createdAt)
                  : r,
          ];
        case SyncOpType.dealAction:
          final dealId = asString(p['deal_id']);
          final d = dealById(dealId);
          final uid = myId;
          if (d == null || uid == null) return;
          final updated = DealRules.apply(
            d.toJson(),
            actor: uid,
            actorName: me?.displayName ?? 'Ben',
            action: enumByName(DealAction.values, p['action'], DealAction.note),
            index: p['index'] == null ? null : asInt(p['index']),
            note: p['note'] == null ? null : asString(p['note']),
            now: op.createdAt,
          );
          final i = deals.indexWhere((x) => x.id == dealId);
          if (i >= 0) deals = [...deals]..[i] = Deal.fromJson(updated);
        case SyncOpType.rateDeal:
          ratedDeals = {...ratedDeals, asString(p['deal_id'])};
        case SyncOpType.report:
          // Şikâyet edilen ilan zaten cihazda gizlenmiştir (hiddenByMe).
          break;
        case SyncOpType.block:
          blocked = {...blocked, asString(p['user_id'])};
        case SyncOpType.unblock:
          blocked = {...blocked}..remove(asString(p['user_id']));
        case SyncOpType.markNotificationsRead:
          notifications = [
            for (final n in notifications)
              n.unread && !n.createdAt.isAfter(op.createdAt)
                  ? _readNotification(n, op.createdAt)
                  : n,
          ];
      }
    } catch (_) {
      // Kural artık uymuyorsa (ör. anlaşma sunucuda değişmiş) iyimser görünüm
      // atlanır; işlem gönderildiğinde son kararı sunucu verir.
    }
  }

  void _upsertLocalListing(Listing listing) {
    final list = _listings[listing.kind]!;
    final i = list.indexWhere((l) => l.id == listing.id);
    _listings[listing.kind] = i >= 0
        ? ([...list]..[i] = listing)
        : [listing, ...list];
  }

  void _patchListing(ListingKind kind, String id, Map<String, dynamic> patch) {
    final list = _listings[kind]!;
    final i = list.indexWhere((l) => l.id == id);
    if (i < 0) return;
    _listings[kind] = [...list]
      ..[i] = Listing.fromJson(kind, {...list[i].toJson(), ...patch});
  }

  static TradeRequest _requestWith(
    TradeRequest r,
    RequestStatus status,
    DateTime at,
  ) => TradeRequest.fromJson({
    ...r.toJson(),
    'status': status.name,
    'updated_at': isoOrNull(at),
  });

  static AppNotification _readNotification(AppNotification n, DateTime at) =>
      AppNotification(
        id: n.id,
        type: n.type,
        title: n.title,
        body: n.body,
        refType: n.refType,
        refId: n.refId,
        readAt: at,
        createdAt: n.createdAt,
      );

  /// Çevrimdışı gönderilen teklif: bekleyen teklif varsa güncellenir, yoksa
  /// geçici kimlikle ("pending-…") listede gösterilir.
  TradeRequest _overlayRequest(SyncOp op) {
    final p = op.payload;
    final draft = RequestDraft.fromJson(asMap(p['draft']));
    final existing = requests
        .where(
          (r) =>
              r.listingId == draft.listingId &&
              r.requesterId == myId &&
              r.isPending,
        )
        .firstOrNull;
    final r = TradeRequest(
      id: existing?.id ?? asString(p['temp_id']),
      kind: draft.kind,
      listingId: draft.listingId,
      listingTitle: existing?.listingTitle ?? asString(p['listing_title']),
      ownerId: asString(p['owner_id']),
      requesterId: myId ?? '',
      owner: existing?.owner,
      requester: me,
      amount: draft.amount,
      quantity: draft.quantity,
      unit: draft.unit,
      startDate: draft.startDate,
      address: draft.address,
      note: draft.note,
      createdAt: existing?.createdAt ?? op.createdAt,
      updatedAt: op.createdAt,
    );
    requests = [r, ...requests.where((x) => x.id != r.id)];
    return r;
  }

  static bool isTemporaryId(String id) => id.startsWith('pending-');

  // ───────────── Görünür listeler ─────────────

  List<Listing> _all(ListingKind kind) {
    final fromBackend = _listings[kind]!;
    final List<Listing> items;
    items = fromBackend;
    return !isLive && showDemo ? items : items.where((l) => !l.demo).toList();
  }

  bool isMine(Listing l) => myId != null && l.ownerId == myId;

  bool isUnlocked(Listing l) =>
      isMine(l) || unlocked.contains('${l.kind.name}:${l.id}');

  bool isBlocked(String? userId) => userId != null && blocked.contains(userId);

  /// Pazarda görünen ilanlar: başkalarının, yayındaki ilanları. Öne
  /// çıkarılanlar en üstte, sonra en yeniler.
  List<Listing> market(ListingKind kind) {
    final list =
        _all(kind)
            .where(
              (l) =>
                  !isMine(l) &&
                  l.isOpen &&
                  !isBlocked(l.ownerId) &&
                  !hiddenByMe.contains(l.id),
            )
            .toList()
          ..sort(compareListings);
    return list;
  }

  static int compareListings(Listing a, Listing b) {
    if (a.isBoosted != b.isBoosted) return a.isBoosted ? -1 : 1;
    return b.createdAt.compareTo(a.createdAt);
  }

  List<Listing> mine(ListingKind kind) =>
      _all(kind).where(isMine).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<Listing> get allMine => [for (final k in ListingKind.values) ...mine(k)];

  List<Load> get marketLoads =>
      market(ListingKind.yuk).whereType<Load>().toList();
  List<Machine> get marketMachines =>
      market(ListingKind.makine).whereType<Machine>().toList();
  List<MaterialListing> get marketMaterials =>
      market(ListingKind.malzeme).whereType<MaterialListing>().toList();
  List<JobPost> get marketJobs =>
      market(ListingKind.personel).whereType<JobPost>().toList();
  List<WorkerCard> get marketWorkers =>
      market(ListingKind.sicil).whereType<WorkerCard>().toList();

  WorkerCard? get myWorkerCard =>
      mine(ListingKind.sicil).whereType<WorkerCard>().firstOrNull;

  Listing? listingById(ListingKind kind, String id) {
    for (final l in _all(kind)) {
      if (l.id == id) return l;
    }
    for (final l in _listings[kind]!) {
      if (l.id == id) return l;
    }
    return null;
  }

  Deal? dealById(String? id) =>
      id == null ? null : deals.where((d) => d.id == id).firstOrNull;

  TradeRequest? requestById(String? id) =>
      id == null ? null : requests.where((r) => r.id == id).firstOrNull;

  /// Kullanıcının bu ilana gönderdiği bekleyen teklif/talep.
  TradeRequest? myPendingRequestFor(Listing l) => requests
      .where((r) => r.listingId == l.id && r.requesterId == myId && r.isPending)
      .firstOrNull;

  /// Kullanıcının bu ilana gönderdiği en son teklif/talep (durumu ne olursa olsun).
  TradeRequest? myLatestRequestFor(Listing l) => requests
      .where((r) => r.listingId == l.id && r.requesterId == myId)
      .firstOrNull;

  /// İlanıma gelen teklif/talepler.
  List<TradeRequest> incomingFor(Listing l) =>
      requests.where((r) => r.listingId == l.id && r.ownerId == myId).toList();

  int pendingCountFor(Listing l) =>
      incomingFor(l).where((r) => r.isPending).length;

  /// Anlaşma kullanıcının bir işlem yapmasını bekliyor mu?
  bool dealNeedsMe(Deal d) {
    final id = myId;
    if (id == null) return false;
    if (d.cancelRequestedBy != null && d.cancelRequestedBy != id) return true;
    if (d.status == DealStatus.pending) {
      return d.createdBy != id && (d.isCustomer(id) || d.isProvider(id));
    }
    if (d.status == DealStatus.delivered) return d.isCustomer(id);
    if (d.status == DealStatus.completed) {
      return !ratedDeals.contains(d.id) &&
          d.counterpartyId(id) != null &&
          (d.isCustomer(id) || d.isProvider(id));
    }
    return false;
  }

  // ───────────── Ayarlar ─────────────

  Future<void> setShowDemo(bool value) async {
    if (isLive) return;
    showDemo = value;
    notifyListeners();
    await _store.prefs.setBool(_kShowDemo, value);
  }

  Future<void> acceptTerms() async {
    termsAccepted = true;
    notifyListeners();
    await _store.prefs.setBool(_kTerms, true);
  }

  // ───────────── Oturum ve profil ─────────────

  /// İlk açılış: (gerekirse) oturum açar, profili kaydeder, verileri yükler.
  /// Hesap sunucuda oluşturulduğu için internet gerekir.
  Future<void> completeOnboarding({
    required String name,
    required String company,
    required UserRole role,
    required String city,
    required String phone,
    TradeProfession? profession,
    List<WorkSector>? sectors,
  }) async {
    lastWriteQueued = false;
    if (!backend.hasSession) await backend.signInAnonymously();
    me = await backend.saveMyProfile(
      name: name,
      company: company,
      role: role,
      city: city,
      phone: phone,
    );
    myPhone = phone;
    await social.saveIdentity(
      SocialIdentity(
        userId: me!.id,
        profession: profession ?? professionFromRole(role),
        sectors: sectors ?? defaultSectorsFor(role),
      ),
    );
    await acceptTerms();
    notifyListeners();
    await refreshAll();
  }

  Future<void> sendPhoneCode(String phoneE164) =>
      backend.sendPhoneCode(phoneE164);

  bool get passwordLoginEnabled =>
      backend is PasswordLoginBackend &&
      (backend as PasswordLoginBackend).passwordLoginEnabled;

  Future<void> signInWithPassword(String username, String password) async {
    if (!passwordLoginEnabled) throw const BackendException('CONFIG');
    await (backend as PasswordLoginBackend).signInWithPassword(
      username,
      password,
    );
    me = await backend.fetchMyProfile();
    myPhone = await backend.fetchMyPhone();
    await acceptTerms();
    await refreshAll();
    notifyListeners();
  }

  /// Telefon kodu doğrulanır; hesap daha önce varsa profil geri gelir.
  Future<bool> verifyPhoneCode(String phoneE164, String code) async {
    await backend.verifyPhoneCode(phoneE164, code);
    me = await backend.fetchMyProfile();
    if (me != null) {
      myPhone = await backend.fetchMyPhone();
      await acceptTerms();
      await refreshAll();
    }
    notifyListeners();
    return me != null;
  }

  Future<void> saveProfile({
    required String name,
    required String company,
    required UserRole role,
    required String city,
    required String phone,
    TradeProfession? profession,
    List<WorkSector>? sectors,
  }) async {
    final op = _op(SyncOpType.saveProfile, {
      'name': name,
      'company': company,
      'role': role.name,
      'city': city,
      'phone': phone,
    });
    return _write<void>(
      op,
      online: () async {
        me = await backend.saveMyProfile(
          name: name,
          company: company,
          role: role,
          city: city,
          phone: phone,
        );
        myPhone = await backend.fetchMyPhone();
        if (profession != null || sectors != null) {
          final cur = myIdentity;
          await social.saveIdentity(
            SocialIdentity(
              userId: me!.id,
              profession: profession ?? cur.profession,
              sectors: sectors ?? cur.sectors,
            ),
          );
        }
        notifyListeners();
      },
      queued: () {},
    );
  }

  void _clearUserData() {
    me = null;
    myPhone = '';
    for (final k in ListingKind.values) {
      _listings[k] = <Listing>[];
    }
    requests = [];
    deals = [];
    notifications = [];
    unlocked = {};
    blocked = {};
    ratedDeals = {};
    haulPoints = [];
    usage = const UsageInfo(
      freeLimit: AppConfig.freeMonthlyUnlocks,
      freeListingLimit: AppConfig.freeActiveListings,
      boostDayCost: AppConfig.boostDayCost,
      boostWeekCost: AppConfig.boostWeekCost,
    );
  }

  /// Çıkış yapar. Gönderilmemiş işlemler bu hesaba aittir ve silinir
  /// (ekran, [pendingSyncCount] > 0 ise kullanıcıyı önceden uyarır).
  Future<void> signOut() async {
    final uid = myId;
    await beforeSignOut?.call();
    try {
      await backend.signOut();
    } catch (_) {
      // HTTP çıkışı başarısız olsa da veri katmanı yerel tokenları sildiyse
      // önceki hesabın profili ve gönderim sırası ekranda kalmamalı.
      if (backend.hasSession) rethrow;
      _notify(const AppNotice.info('Bu cihazdaki oturum kapatıldı.'));
    }
    await _sync.clearFor(uid);
    await _store.remove(_kCache);
    _clearUserData();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final uid = myId;
    await backend.deleteAccount();
    await afterAccountDeleted?.call();
    await _sync.clearFor(uid);
    await _store.remove(_kCache);
    await _store.remove(_kTerms);
    termsAccepted = false;
    _clearUserData();
    notifyListeners();
  }

  /// Demo modunda kayıtları sıfırlar (profil ve satın alımlar korunur).
  Future<void> resetDemoData() async {
    await backend.resetLocalData();
    hiddenByMe = {};
    await _store.remove(_kHidden);
    await refreshAll();
  }

  Future<PublicProfile?> fetchProfile(String userId) async {
    if (DemoData.isDemoId(userId)) return DemoData.profile(userId);
    if (userId == myId) return me;
    return backend.fetchProfile(userId);
  }

  Future<List<Rating>> fetchRatingsFor(String userId) async {
    if (isLive && DemoData.isDemoId(userId)) return DemoData.ratingsFor(userId);
    return backend.fetchRatingsFor(userId);
  }

  Future<List<PublicProfile>> fetchProfiles(List<String> ids) async {
    final demo = [
      for (final id in ids)
        if (DemoData.isDemoId(id)) DemoData.profile(id),
    ];
    final real = ids.where((id) => !DemoData.isDemoId(id)).toList();
    final fetched = real.isEmpty
        ? <PublicProfile>[]
        : await backend.fetchProfiles(real);
    return [...fetched, ...demo];
  }

  // ───────────── İlan işlemleri ─────────────

  void _rejectDemoInLive(Listing l) {
    if (isLive && l.demo) throw const BackendException('DEMO_ITEM');
  }

  /// İlanı kaydeder. Canlı modda yeni ilanın kimliği cihazda üretilir; böylece
  /// internet yokken sıraya alınıp sonra gönderilen ilan sunucuda bir kez oluşur.
  Future<Listing> saveListing(Listing listing, {required bool isNew}) async {
    final prepared = isNew && listing.id.isEmpty && isLive
        ? Listing.fromJson(listing.kind, {...listing.toJson(), 'id': newUuid()})
        : listing;
    final op = _op(SyncOpType.saveListing, {
      'kind': prepared.kind.name,
      'id': prepared.id,
      'is_new': isNew,
      'listing': prepared.toJson(),
    });
    return _write<Listing>(
      op,
      online: () async {
        final saved = await backend.saveListing(prepared, isNew: isNew);
        _upsertLocalListing(saved);
        notifyListeners();
        await _quietly(() => refreshListings(saved.kind));
        unawaited(refreshUsage());
        if (isNew) {
          unawaited(
            _notifySector(
              [listingKindSector(saved.kind), ...myIdentity.sectors],
              title: _listingNoticeTitle(saved),
              body: saved.title,
              type: saved.kind.name,
              refType: saved.kind.name,
              refId: saved.id,
            ),
          );
        }
        return saved;
      },
      queued: () => prepared,
    );
  }

  Future<void> setListingStatus(Listing l, ListingStatus status) async {
    final op = _op(SyncOpType.setListingStatus, {
      'kind': l.kind.name,
      'id': l.id,
      'status': status.name,
    });
    return _write<void>(
      op,
      online: () async {
        await backend.setListingStatus(l.kind, l.id, status);
        _patchListing(l.kind, l.id, {'status': status.name});
        notifyListeners();
        await _quietly(() => refreshListings(l.kind));
        unawaited(refreshUsage());
      },
      queued: () {},
    );
  }

  Future<void> deleteListing(Listing l) async {
    if (isLive) {
      // Bu ilanın bekleyen değişiklikleri artık gereksiz.
      final removed = await _sync.removeWhere(
        myId,
        (op) =>
            op.refId == l.id &&
            const [
              SyncOpType.saveListing,
              SyncOpType.setListingStatus,
              SyncOpType.setMachineAvailable,
            ].contains(op.type),
      );
      // Hiç gönderilmemiş yeni ilan: sunucuda yok, silmek için bağlantı gerekmez.
      final neverSent = removed.any(
        (op) =>
            op.type == SyncOpType.saveListing &&
            op.payload['is_new'] == true &&
            op.attempts == 0,
      );
      if (neverSent) {
        lastWriteQueued = false;
        _listings[l.kind] = _listings[l.kind]!
            .where((x) => x.id != l.id)
            .toList();
        notifyListeners();
        return;
      }
    }
    final op = _op(SyncOpType.deleteListing, {'kind': l.kind.name, 'id': l.id});
    await _write<void>(
      op,
      online: () async {
        await backend.deleteListing(l.kind, l.id);
        _listings[l.kind] = _listings[l.kind]!
            .where((x) => x.id != l.id)
            .toList();
        notifyListeners();
        await _quietly(() => refreshListings(l.kind));
        unawaited(refreshUsage());
        unawaited(_quietly(refreshRequestsAndDeals));
      },
      queued: () {},
    );
  }

  Future<void> setMachineAvailable(Machine m, bool available) async {
    final op = _op(SyncOpType.setMachineAvailable, {
      'kind': ListingKind.makine.name,
      'id': m.id,
      'available': available,
    });
    return _write<void>(
      op,
      online: () async {
        await backend.setMachineAvailable(m.id, available);
        _patchListing(ListingKind.makine, m.id, {'available': available});
        notifyListeners();
        await _quietly(() => refreshListings(ListingKind.makine));
      },
      queued: () {},
    );
  }

  /// Öne çıkarma kredi harcar; yalnızca çevrimiçi.
  Future<DateTime> boost(Listing l, BoostOption option) async {
    lastWriteQueued = false;
    final until = await backend.boostListing(l.kind, l.id, option);
    await _quietly(() => refreshListings(l.kind));
    await refreshUsage();
    return until;
  }

  // ───────────── İletişim hakkı (yalnızca çevrimiçi) ─────────────

  Future<UnlockResult> unlock(Listing l, {bool useCredit = false}) async {
    lastWriteQueued = false;
    _rejectDemoInLive(l);
    final result = await backend.unlock(l.kind, l.id, useCredit: useCredit);
    if (result.ok) {
      unlocked = {...unlocked, '${l.kind.name}:${l.id}'};
      notifyListeners();
      unawaited(refreshUsage());
    }
    return result;
  }

  ContactInfo _maskUnverifiedPhone(ContactInfo c) => c.phoneVerified
      ? c
      : ContactInfo(
          userId: c.userId,
          name: c.name,
          phone: '',
          phoneVerified: false,
        );

  Future<ContactInfo> contactForListing(Listing l) async {
    _rejectDemoInLive(l);
    return _maskUnverifiedPhone(await backend.contactFor(l.kind.name, l.id));
  }

  Future<ContactInfo> contactForRequest(TradeRequest r) async {
    if (isTemporaryId(r.id)) throw const BackendException('SYNC_PENDING');
    return _maskUnverifiedPhone(await backend.contactFor('request', r.id));
  }

  Future<ContactInfo> contactForDeal(Deal d) async =>
      _maskUnverifiedPhone(await backend.contactFor('deal', d.id));

  // ───────────── Teklif / talep ─────────────

  Future<TradeRequest> sendRequest(Listing l, RequestDraft draft) async {
    _rejectDemoInLive(l);
    final op = _op(SyncOpType.createRequest, {
      'listing_id': draft.listingId,
      'draft': draft.toJson(),
      'owner_id': l.ownerId,
      'listing_title': l.title,
    });
    op.payload['temp_id'] = 'pending-${op.id}';
    return _write<TradeRequest>(
      op,
      online: () async {
        final r = await backend.createRequest(draft, opId: op.id);
        await _quietly(refreshRequestsAndDeals);
        return r;
      },
      queued: () => requests.firstWhere(
        (r) =>
            r.listingId == draft.listingId &&
            r.requesterId == myId &&
            r.isPending,
        orElse: () => _overlayRequest(op),
      ),
      validateOffline: () {
        // Sunucunun da isteyeceği koşullar: hak açılmış ve ilan yayında olmalı.
        if (isMine(l)) throw const BackendException('OWN_LISTING');
        if (!isUnlocked(l)) throw const BackendException('LOCKED');
        if (!l.isOpen) throw const BackendException('NOT_AVAILABLE');
      },
    );
  }

  /// Kabulde oluşan anlaşmanın kimliğini döner (çevrimdışıyken null; anlaşma gönderimden sonra oluşur).
  Future<String?> respond(TradeRequest r, {required bool accept}) async {
    final op = _op(SyncOpType.respondRequest, {
      'id': r.id,
      'accept': accept,
      'kind': r.kind.name,
      'listing_id': r.listingId,
    });
    return _write<String?>(
      op,
      online: () async {
        final dealId = await backend.respondRequest(
          r.id,
          accept: accept,
          opId: op.id,
        );
        await _quietly(refreshRequestsAndDeals);
        if (accept && r.kind == ListingKind.yuk) {
          await _quietly(() => refreshListings(ListingKind.yuk));
        }
        return dealId;
      },
      queued: () => null,
      validateOffline: () {
        if (r.ownerId != myId) throw const BackendException('FORBIDDEN');
        if (!r.isPending) throw const BackendException('NOT_PENDING');
      },
    );
  }

  Future<void> withdraw(TradeRequest r) async {
    if (isTemporaryId(r.id)) {
      // Henüz gönderilmemiş teklif: sıradan çıkarmak yeterli.
      final removed = await _sync.removeWhere(
        myId,
        (op) =>
            op.type == SyncOpType.createRequest &&
            op.payload['temp_id'] == r.id &&
            op.attempts == 0,
      );
      if (removed.isEmpty) throw const BackendException('SYNC_PENDING');
      lastWriteQueued = false;
      requests = requests.where((x) => x.id != r.id).toList();
      notifyListeners();
      return;
    }
    final op = _op(SyncOpType.withdrawRequest, {'id': r.id});
    await _write<void>(
      op,
      online: () async {
        await backend.withdrawRequest(r.id);
        await _quietly(refreshRequestsAndDeals);
      },
      queued: () {},
      validateOffline: () {
        if (r.requesterId != myId || !r.isPending) {
          throw const BackendException('NOT_PENDING');
        }
      },
    );
  }

  // ───────────── Anlaşmalar ─────────────

  void _putDeal(Deal d) {
    final i = deals.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      deals[i] = d;
    } else {
      deals.insert(0, d);
    }
    notifyListeners();
  }

  /// Anlaşma kodu sunucuda üretildiği için yalnızca çevrimiçi.
  Future<Deal> createDeal(DealDraft draft) async {
    lastWriteQueued = false;
    final d = await backend.createDeal(draft);
    _putDeal(d);
    return d;
  }

  Future<Deal> joinDeal(String code) async {
    lastWriteQueued = false;
    final d = await backend.joinDeal(code);
    _putDeal(d);
    return d;
  }

  /// Anlaşma adımı (onay, teslim, ödeme işareti, not…). İnternet yoksa kural
  /// cihazda denetlenir, adım ekranda hemen görünür ve sonra gönderilir.
  Future<Deal> dealAction(
    Deal deal,
    DealAction action, {
    int? index,
    String? note,
  }) async {
    final op = _op(SyncOpType.dealAction, {
      'deal_id': deal.id,
      'action': action.name,
      'index': index,
      'note': note,
    });
    return _write<Deal>(
      op,
      online: () async {
        final d = await backend.dealAction(
          deal.id,
          action,
          index: index,
          note: note,
          opId: op.id,
        );
        _putDeal(d);
        if (action == DealAction.complete) {
          unawaited(
            backend
                .fetchMyProfile()
                .then((p) {
                  if (p != null) {
                    me = p;
                    notifyListeners();
                  }
                })
                .catchError((Object _) {}),
          );
        }
        return d;
      },
      queued: () => dealById(deal.id) ?? deal,
      validateOffline: () {
        final uid = myId;
        if (uid == null) throw const BackendException('AUTH_REQUIRED');
        DealRules.apply(
          (dealById(deal.id) ?? deal).toJson(),
          actor: uid,
          actorName: me?.displayName ?? 'Ben',
          action: action,
          index: index,
          note: note,
          now: DateTime.now(),
        );
      },
    );
  }

  Future<void> rateDeal(Deal deal, int stars, String comment) async {
    final op = _op(SyncOpType.rateDeal, {
      'deal_id': deal.id,
      'stars': stars,
      'comment': comment,
    });
    return _write<void>(
      op,
      online: () async {
        await backend.rateDeal(deal.id, stars, comment, opId: op.id);
        ratedDeals = {...ratedDeals, deal.id};
        notifyListeners();
      },
      queued: () {},
      validateOffline: () {
        if (stars < 1 || stars > 5) throw const BackendException('BAD_INPUT');
        if (deal.status != DealStatus.completed) {
          throw const BackendException('BAD_STATE');
        }
        if (ratedDeals.contains(deal.id)) {
          throw const BackendException('ALREADY_RATED');
        }
        if (deal.counterpartyId(myId) == null) {
          throw const BackendException('NOT_AVAILABLE');
        }
      },
    );
  }

  // ───────────── Güvenlik ─────────────

  /// Şikâyet eder; ilan şikâyet edene artık gösterilmez.
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String note = '',
  }) async {
    lastWriteQueued = false;
    if (!(isLive && DemoData.isDemoId(targetId))) {
      final op = _op(SyncOpType.report, {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'note': note,
      });
      await _write<void>(
        op,
        online: () => backend.report(targetType, targetId, reason, note),
        queued: () {},
      );
    }
    if (targetType != 'profil' && targetType != 'anlasma') {
      hiddenByMe = {...hiddenByMe, targetId};
      await _store.writeStrings(_kHidden, hiddenByMe);
    }
    notifyListeners();
  }

  /// Sebep seçimi ve kanıt fotoğrafı zorunlu engelleme (arayüz bunu kullanır).
  /// Eksikse [BackendException] fırlatır ve hiçbir şey kaydedilmez.
  Future<void> blockWithProof(
    String userId, {
    required String reason,
    required String evidencePhotoPath,
  }) async {
    final err = SocialRules.reviewBlock(
      reason: Sanitize.line(reason),
      evidencePhotoPath: evidencePhotoPath,
    );
    if (err != null) throw BackendException('BAD_INPUT', err);
    await block(userId, reason: reason, evidencePhotoPath: evidencePhotoPath);
  }

  Future<void> block(
    String userId, {
    String reason = '',
    String evidencePhotoPath = '',
  }) async {
    lastWriteQueued = false;
    final why = Sanitize.line(reason);
    social.blockReasons[userId] = BlockRecord(
      userId: userId,
      reason: why.isEmpty ? 'Belirtilmedi' : why,
      at: DateTime.now(),
      evidencePhotoPath: evidencePhotoPath,
    );
    await social.persistBlocks();
    if (!(isLive && DemoData.isDemoId(userId))) {
      final op = _op(SyncOpType.block, {'user_id': userId});
      await _write<void>(
        op,
        online: () => backend.block(userId),
        queued: () {},
      );
    }
    blocked = {...blocked, userId};
    notifyListeners();
  }

  Future<void> unblock(String userId) async {
    lastWriteQueued = false;
    if (!(isLive && DemoData.isDemoId(userId))) {
      final op = _op(SyncOpType.unblock, {'user_id': userId});
      await _write<void>(
        op,
        online: () => backend.unblock(userId),
        queued: () {},
      );
    }
    blocked = {...blocked}..remove(userId);
    notifyListeners();
  }

  // ───────────── Bildirimler ─────────────

  Future<void> markNotificationsRead() async {
    if (unreadCount == 0) return;
    final now = DateTime.now();
    notifications = [
      for (final n in notifications) n.unread ? _readNotification(n, now) : n,
    ];
    notifyListeners();
    try {
      // Bağlantı yoksa "okundu" bilgisi sıraya alınır ve sonra gönderilir.
      await _write<void>(
        _op(SyncOpType.markNotificationsRead, {}),
        online: backend.markNotificationsRead,
        queued: () {},
      );
    } catch (_) {
      // Sunucu reddederse rozet bir sonraki yenilemede düzelir.
    }
  }

  // ───────────── Mağaza ─────────────

  Future<VerifyResult> verifyPurchase(StoreClaim claim) async {
    final result = await backend.verifyPurchase(claim);
    if (result.ok) await refreshUsage();
    return result;
  }

  // ───────────── Hafriyat planlama (cihazda) ─────────────

  Future<void> _saveHaul() =>
      _store.writeMaps(_kHaul, [for (final p in haulPoints) p.toJson()]);

  Future<void> addHaulPoint(HaulPoint p) async {
    if (backend is HaulBackend) {
      if (p.demo) throw const BackendException('DEMO_ITEM');
      final actor = myId;
      final saved = await (backend as HaulBackend).saveHaulPoint(p);
      if (actor != myId) throw const BackendException('AUTH_REQUIRED');
      haulPoints = [
        ...haulPoints.where((point) => point.id != saved.id),
        saved,
      ];
      notifyListeners();
      await _saveCache();
      return;
    }
    haulPoints = [...haulPoints, p];
    notifyListeners();
    await _saveHaul();
  }

  Future<void> removeHaulPoint(String id) async {
    if (backend is HaulBackend) {
      final actor = myId;
      await (backend as HaulBackend).deleteHaulPoint(id);
      if (actor != myId) throw const BackendException('AUTH_REQUIRED');
      haulPoints = haulPoints.where((p) => p.id != id).toList();
      notifyListeners();
      await _saveCache();
      return;
    }
    haulPoints = haulPoints.where((p) => p.id != id).toList();
    notifyListeners();
    await _saveHaul();
  }

  Future<void> restoreDemoHaulPoints() async {
    if (isLive) return;
    haulPoints = [
      ...haulPoints.where((p) => !p.demo),
      ...DemoData.haulPoints(),
    ];
    notifyListeners();
    await _saveHaul();
  }

  // ───────────── Sosyal ağ (yerel iskelet) ─────────────

  SocialIdentity get myIdentity {
    final p = me;
    if (p == null) {
      return const SocialIdentity(
        userId: '',
        profession: TradeProfession.muteahhit,
        sectors: [],
      );
    }
    return social.identityOrDefault(p);
  }

  Set<String> get following => social.followingOf(myId ?? '');

  List<SocialPost> get feedPosts {
    final uid = myId ?? '';
    final mine = myIdentity.sectors;
    final fol = following;
    final blockedIds = blocked;
    final list = [
      for (final p in social.posts)
        if (!blockedIds.contains(p.authorId) &&
            SocialRules.inFeed(
              mySectors: mine,
              following: fol,
              authorId: p.authorId,
              postSectors: p.sectors,
              myId: uid,
            ))
          p,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<SocialPost> wallOf(String userId) =>
      social.posts.where((p) => p.authorId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> follow(String userId) async {
    final uid = myId;
    if (uid == null || uid == userId) return;
    final set = {...social.followingOf(uid), userId};
    social.follows[uid] = set;
    await social.persistFollows();
    notifyListeners();
  }

  Future<void> unfollow(String userId) async {
    final uid = myId;
    if (uid == null) return;
    social.follows[uid] = {...social.followingOf(uid)}..remove(userId);
    await social.persistFollows();
    notifyListeners();
  }

  // ───────────── Profil / kapak fotoğrafı, hikaye, gönderi silme ─────────────

  /// Kendi profil fotoğrafı (cihazdaki dosya yolu).
  String get myAvatarPath => social.avatarOf(myId ?? '');

  Future<void> _changeMedia({String? avatar, String? cover}) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final cur = social.media[uid] ?? SocialMedia(userId: uid);
    final next = cur.copyWith(avatarPath: avatar, coverPath: cover);
    social.media = {...social.media, uid: next};
    await social.persistMedia();
    // Yeni fotoğraf yerine geçen eski dosya (varsa) silinir.
    if (avatar != null && cur.avatarPath != avatar) {
      await PhotoStorage.deleteOwned(cur.avatarPath);
    }
    if (cover != null && cur.coverPath != cover) {
      await PhotoStorage.deleteOwned(cur.coverPath);
    }
    notifyListeners();
  }

  Future<void> setProfilePhoto(String path) async {
    if (path.trim().isEmpty) {
      throw const BackendException('BAD_INPUT', 'Fotoğraf seçilmedi.');
    }
    await _changeMedia(avatar: path);
  }

  Future<void> setCoverPhoto(String path) async {
    if (path.trim().isEmpty) {
      throw const BackendException('BAD_INPUT', 'Fotoğraf seçilmedi.');
    }
    await _changeMedia(cover: path);
  }

  Future<void> removeProfilePhoto() => _changeMedia(avatar: '');

  Future<void> removeCoverPhoto() => _changeMedia(cover: '');

  Future<void> _purgeStories() async {
    final removed = await social.purgeExpiredStories();
    for (final s in removed) {
      await PhotoStorage.deleteOwned(s.photoPath);
    }
  }

  /// Hikaye paylaşır: fotoğraf ve/veya kısa yazı; 24 saat sonra silinir.
  Future<SocialStory> addStory({String photoPath = '', String caption = ''}) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final clean = Sanitize.line(caption);
    if (photoPath.trim().isEmpty && clean.isEmpty) {
      throw const BackendException('BAD_INPUT', 'Fotoğraf ekleyin veya bir şeyler yazın.');
    }
    if (clean.runes.length > 140) {
      throw const BackendException('BAD_INPUT', 'Hikaye yazısı en fazla 140 karakter olabilir.');
    }
    if (SocialRules.reviewMessage(clean) != null) {
      throw const BackendException('BAD_INPUT', 'Uygunsuz ifade var.');
    }
    await _purgeStories();
    final story = SocialStory(
      id: newLocalId(),
      authorId: uid,
      photoPath: photoPath,
      caption: clean,
    );
    social.stories = [...social.stories, story];
    await social.persistStories();
    notifyListeners();
    return story;
  }

  Future<void> deleteStory(String storyId) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final story = social.stories.where((s) => s.id == storyId).firstOrNull;
    if (story == null) return;
    if (story.authorId != uid) {
      throw const BackendException('FORBIDDEN', 'Yalnızca kendi hikayenizi silebilirsiniz.');
    }
    social.stories = [
      for (final s in social.stories)
        if (s.id != storyId) s,
    ];
    await social.persistStories();
    await PhotoStorage.deleteOwned(story.photoPath);
    notifyListeners();
  }

  /// Hikayesi olan (engellenmemiş) diğer kullanıcılar; en yeni hikaye önce.
  List<String> get storyAuthorIds {
    final uid = myId ?? '';
    final latest = <String, DateTime>{};
    for (final s in social.stories) {
      if (s.isExpired() || s.authorId == uid || isBlocked(s.authorId)) continue;
      final cur = latest[s.authorId];
      if (cur == null || s.createdAt.isAfter(cur)) latest[s.authorId] = s.createdAt;
    }
    return latest.keys.toList()..sort((a, b) => latest[b]!.compareTo(latest[a]!));
  }

  /// Kendi gönderinizi siler (yorumları, beğenileri ve fotoğrafı ile).
  Future<void> deletePost(String postId) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final post = social.posts.where((p) => p.id == postId).firstOrNull;
    if (post == null) return;
    if (post.authorId != uid) {
      throw const BackendException('FORBIDDEN', 'Yalnızca kendi gönderinizi silebilirsiniz.');
    }
    if (post.tenderId != null) {
      throw const BackendException('BAD_STATE', 'İhale gönderisi silinemez.');
    }
    social.posts = [
      for (final p in social.posts)
        if (p.id != postId) p,
    ];
    social.comments = [
      for (final c in social.comments)
        if (c.postId != postId) c,
    ];
    social.likes = {...social.likes}..remove(postId);
    await social.persistPosts();
    await social.persistComments();
    await social.persistLikes();
    await PhotoStorage.deleteOwned(post.photoPath);
    notifyListeners();
  }

  Future<void> toggleLike(String postId) async {
    final uid = myId;
    if (uid == null) return;
    final set = {...?social.likes[postId]};
    if (set.contains(uid)) {
      set.remove(uid);
    } else {
      set.add(uid);
    }
    social.likes[postId] = set;
    await social.persistLikes();
    notifyListeners();
  }

  Future<CommentReview> addComment({
    required String postId,
    required String text,
    required bool negative,
    required bool workedTogether,
    required String evidenceNote,
    bool workedAnswered = true,
    String evidencePhotoPath = '',
  }) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final clean = Sanitize.block(text);
    final review = SocialRules.reviewComment(
      text: clean,
      negative: negative,
      workedTogether: workedTogether,
      evidenceNote: evidenceNote,
      workedAnswered: workedAnswered,
      hasEvidencePhoto: evidencePhotoPath.trim().isNotEmpty,
    );
    // Küfürlü ya da kanıtsız yorum hiç kaydedilmez.
    if (review.verdict == CommentVerdict.filtered ||
        review.verdict == CommentVerdict.evidenceRequired) {
      return review;
    }
    social.comments.add(
      SocialComment(
        id: newLocalId(),
        postId: postId,
        authorId: uid,
        text: clean,
        negative: negative,
        workedTogether: workedTogether,
        evidenceNote: Sanitize.line(evidenceNote),
        evidencePhotoPath: evidencePhotoPath,
        status: review.status,
      ),
    );
    await social.persistComments();
    notifyListeners();
    return review;
  }

  Future<SocialPost> createPost({
    required SocialPostKind kind,
    required String caption,
    List<WorkSector>? sectors,
    String photoPath = '',
    String? listingId,
    ListingKind? listingKind,
    String? tenderId,
  }) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final clean = Sanitize.block(caption);
    if (SocialRules.reviewMessage(clean) != null) {
      throw const BackendException('BAD_INPUT', 'Uygunsuz ifade var.');
    }
    final post = SocialPost(
      id: newLocalId(),
      authorId: uid,
      kind: kind,
      caption: clean,
      sectors: sectors ?? myIdentity.sectors,
      photoPath: photoPath,
      listingId: listingId,
      listingKind: listingKind,
      tenderId: tenderId,
    );
    social.posts.insert(0, post);
    await social.persistPosts();
    await _notifySector(
      post.sectors,
      title: switch (kind) {
        SocialPostKind.jobSeek => 'Yeni: iş arayan paylaşımı',
        SocialPostKind.machineSeek => 'Yeni: makine arayan paylaşımı',
        SocialPostKind.tender => 'Yeni ihale',
        SocialPostKind.listing => 'Yeni ilan paylaşımı',
        SocialPostKind.work => 'Sektöründe yeni iş paylaşımı',
      },
      body: clean,
      type: kind.name,
      refType: 'post',
      refId: post.id,
    );
    notifyListeners();
    return post;
  }

  Future<Tender> createTender({
    required String title,
    required String detail,
    required String city,
    required List<WorkSector> sectors,
    required List<TradeProfession> allowed,
    DateTime? closesAt,
  }) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    if (SocialRules.reviewMessage('$title $detail') != null) {
      throw const BackendException('BAD_INPUT', 'Uygunsuz ifade var.');
    }
    if (closesAt != null && !closesAt.isAfter(DateTime.now())) {
      throw const BackendException(
        'BAD_INPUT',
        'Bitiş zamanı ileri bir tarih olmalı.',
      );
    }
    if (!myIdentity.profession.canOpenTender) {
      throw const BackendException(
        'FORBIDDEN',
        'İhale açmak için müteahhit veya şantiye şefi olmalısınız.',
      );
    }
    if (sectors.isEmpty || allowed.isEmpty) {
      throw const BackendException('BAD_INPUT', 'Sektör ve meslek seçin.');
    }
    final tender = Tender(
      id: newLocalId(),
      ownerId: uid,
      title: Sanitize.line(title),
      detail: Sanitize.block(detail),
      city: city,
      sectors: sectors,
      allowedProfessions: allowed,
      closesAt: closesAt,
    );
    social.tenders.insert(0, tender);
    await social.persistTenders();
    await createPost(
      kind: SocialPostKind.tender,
      caption: tender.title,
      sectors: sectors,
      tenderId: tender.id,
    );
    notifyListeners();
    return tender;
  }

  Future<TenderBid> bidTender({
    required Tender tender,
    required double amount,
    required String note,
    required String referenceNote,
  }) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    if (!SocialRules.canBid(
      tender: tender,
      profession: myIdentity.profession,
      myId: uid,
    )) {
      throw const BackendException(
        'FORBIDDEN',
        'Bu ihaleye meslek grubunuz katılamaz.',
      );
    }
    final cleanNote = Sanitize.block(note);
    final err = SocialRules.reviewBid(amount: amount, note: cleanNote);
    if (err != null) throw BackendException('BAD_INPUT', err);
    if (SocialRules.reviewMessage(referenceNote) != null) {
      throw const BackendException('BAD_INPUT', 'Uygunsuz ifade var.');
    }
    if (social.bidOf(tender.id, uid) != null) {
      throw const BackendException(
        'BAD_STATE',
        'Bu ihaleye zaten teklif verdiniz.',
      );
    }
    final bid = TenderBid(
      id: newLocalId(),
      tenderId: tender.id,
      bidderId: uid,
      amount: amount,
      note: cleanNote,
      referenceNote: Sanitize.block(referenceNote),
    );
    social.bids.add(bid);
    await social.persistTenders();
    notifyListeners();
    return bid;
  }

  // ───────────── İhale: onay, kapanış, kazanan seçimi ─────────────

  Tender _ownedTender(String tenderId) {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final t = social.tenderById(tenderId);
    if (t == null) throw const BackendException('NOT_FOUND');
    if (!SocialRules.canDecide(tender: t, myId: uid)) {
      throw const BackendException(
        'FORBIDDEN',
        'Bu işlemi yalnızca ihaleyi açan yapabilir.',
      );
    }
    return t;
  }

  void _replaceTender(Tender t) {
    social.tenders = [
      for (final x in social.tenders)
        if (x.id == t.id) t else x,
    ];
  }

  void _replaceBid(TenderBid b) {
    social.bids = [
      for (final x in social.bids)
        if (x.id == b.id) b else x,
    ];
  }

  /// İhaleyi açan, bu teklif sahibiyle telefon paylaşımını onaylar.
  Future<void> approveBidContact(String tenderId, String bidId) async {
    _ownedTender(tenderId);
    final bid = social.bids.where((b) => b.id == bidId && b.tenderId == tenderId).firstOrNull;
    if (bid == null) throw const BackendException('NOT_FOUND');
    _replaceBid(bid.copyWith(contactApproved: true));
    await social.persistTenders();
    notifyListeners();
  }

  /// İhaleyi açan, süre dolmadan teklif almayı bitirir.
  Future<void> closeTender(String tenderId) async {
    final t = _ownedTender(tenderId);
    if (t.status != TenderStatus.open) return;
    _replaceTender(t.copyWith(status: TenderStatus.closed));
    await social.persistTenders();
    notifyListeners();
  }

  /// İhale bittikten sonra kazanan teklifi seçer: ihale "Verildi" olur, seçilen
  /// teklifin iletişimi onaylanır, diğer teklifler "Seçilmedi" işaretlenir.
  Future<void> awardTender(String tenderId, String bidId) async {
    final t = _ownedTender(tenderId);
    if (t.status == TenderStatus.awarded) {
      throw const BackendException('BAD_STATE', 'Bu ihalenin kazananı seçildi.');
    }
    if (t.acceptsBids()) {
      throw const BackendException(
        'BAD_STATE',
        'İhale hâlâ açık. Önce teklif almayı bitirin.',
      );
    }
    final bids = social.bidsFor(tenderId);
    final winner = bids.where((b) => b.id == bidId).firstOrNull;
    if (winner == null) throw const BackendException('NOT_FOUND');
    for (final b in bids) {
      _replaceBid(
        b.id == winner.id
            ? b.copyWith(decision: BidStatus.selected, contactApproved: true)
            : b.copyWith(decision: BidStatus.notSelected),
      );
    }
    _replaceTender(
      t.copyWith(status: TenderStatus.awarded, awardedBidId: winner.id),
    );
    await social.persistTenders();
    notifyListeners();
  }

  /// Teklif sahibinin / ihaleyi açanın telefonu. Teklif onaylanmadıkça asla
  /// verilmez. Not: ihaleler şimdilik cihazda tutulur; karşı tarafın gerçek
  /// numarası yalnızca örnek kullanıcılar ve kendi numaranız için bilinir.
  Future<ContactInfo> contactForTenderBid(Tender tender, TenderBid bid) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    if (!SocialRules.canRevealPhone(tender: tender, bid: bid, viewerId: uid)) {
      throw const BackendException(
        'FORBIDDEN',
        'Telefon numarası, ihaleyi açan onaylayana kadar gizlidir.',
      );
    }
    final otherId = uid == tender.ownerId ? bid.bidderId : tender.ownerId;
    if (DemoData.isDemoId(otherId)) {
      final p = DemoData.profile(otherId);
      return _maskUnverifiedPhone(
        ContactInfo(
          userId: otherId,
          name: p.displayName,
          phone: DemoData.phoneOf(otherId),
          phoneVerified: p.phoneVerified,
        ),
      );
    }
    throw const BackendException(
      'NOT_FOUND',
      'Bu kullanıcının numarası bu cihazda yok. İhaleler sunucuya '
          'bağlandığında numara, onaydan sonra burada görünecek.',
    );
  }

  /// Meslek ve sektör bilgisini günceller (sosyal akış kimliği).
  Future<void> updateMyIdentity({
    required TradeProfession profession,
    required List<WorkSector> sectors,
  }) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    if (sectors.isEmpty) {
      throw const BackendException('BAD_INPUT', 'En az bir sektör seçin.');
    }
    await social.saveIdentity(
      SocialIdentity(userId: uid, profession: profession, sectors: sectors),
    );
    notifyListeners();
  }

  ChatThread _threadWith(String otherId) {
    final uid = myId ?? '';
    for (final t in social.threads) {
      if ((t.userA == uid && t.userB == otherId) ||
          (t.userB == uid && t.userA == otherId)) {
        return t;
      }
    }
    final t = ChatThread(id: newLocalId(), userA: uid, userB: otherId);
    social.threads.insert(0, t);
    return t;
  }

  List<ChatThread> get myThreads {
    final uid = myId ?? '';
    return social.threads.where((t) => t.userA == uid || t.userB == uid).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<ChatMessage> messagesOf(String threadId) => social.messages
      .where((m) => m.threadId == threadId && !m.isExpired())
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<ChatThread> openChat(String otherId) async {
    final t = _threadWith(otherId);
    await social.persistChat();
    notifyListeners();
    return t;
  }

  Future<void> sendMessage(String threadId, String text) async {
    final uid = myId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    final clean = Sanitize.line(text);
    final err = SocialRules.reviewMessage(clean);
    if (err != null) throw BackendException('BAD_INPUT', err);
    if (clean.isEmpty) throw const BackendException('BAD_INPUT', 'Mesaj boş.');
    await social.purgeExpiredMessages();
    social.messages.add(
      ChatMessage(
        id: newLocalId(),
        threadId: threadId,
        senderId: uid,
        text: clean,
      ),
    );
    social.threads = [
      for (final t in social.threads)
        if (t.id == threadId)
          ChatThread(
            id: t.id,
            userA: t.userA,
            userB: t.userB,
            updatedAt: DateTime.now(),
          )
        else
          t,
    ];
    await social.persistChat();
    notifyListeners();
  }

  String _listingNoticeTitle(Listing l) => switch (l.kind) {
    ListingKind.yuk => 'Yeni yük ilanı',
    ListingKind.makine => 'Yeni makine ilanı',
    ListingKind.malzeme => 'Yeni malzeme ilanı',
    ListingKind.personel => 'Yeni iş ilanı (iş arayan / personel)',
    ListingKind.sicil => 'Yeni operatör kartı',
  };

  Future<void> _notifySector(
    Iterable<WorkSector> sectors, {
    required String title,
    required String body,
    required String type,
    String refType = '',
    String? refId,
  }) async {
    final n = AppNotification(
      id: newLocalId(),
      type: type,
      title: title,
      body: body,
      refType: refType,
      refId: refId,
      createdAt: DateTime.now(),
    );
    notifications = [n, ...notifications];
    if (!_flashes.isClosed) {
      _flashes.add(
        '$title · ${[for (final s in sectors) s.label].take(3).join(', ')} sektörüne anında iletildi.',
      );
    }
    notifyListeners();
  }
}
