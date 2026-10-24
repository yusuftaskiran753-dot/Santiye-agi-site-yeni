import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../logic/live_route.dart';
import '../models/models.dart';
import '../models/live_location.dart';
import 'app_notice.dart';
import 'backend.dart';
import 'live_location_backend.dart';
import 'local_store.dart';

/// Konuma erişilemediğinde nedeni.
enum LocationProblem {
  /// Telefonun konum servisi (GPS) kapalı.
  serviceOff,

  /// İzin verilmedi (tekrar sorulabilir).
  denied,

  /// İzin kalıcı olarak reddedildi; yalnızca ayarlardan açılabilir.
  deniedForever,

  /// İzin var ama konum alınamadı (kapalı alan, zayıf GPS).
  noFix,
}

class LocationAccessException implements Exception {
  const LocationAccessException(this.problem);

  final LocationProblem problem;

  String get title => switch (problem) {
    LocationProblem.serviceOff => 'Konum kapalı',
    LocationProblem.denied => 'Konum izni gerekli',
    LocationProblem.deniedForever => 'Konum izni kapalı',
    LocationProblem.noFix => 'Konum bulunamadı',
  };

  String get message => switch (problem) {
    LocationProblem.serviceOff =>
      'Telefonunuzun konum servisini (GPS) açın, sonra tekrar deneyin.',
    LocationProblem.denied =>
      'Konumunuzu paylaşabilmemiz için izin vermeniz gerekiyor. İzin yalnızca siz paylaşırken kullanılır.',
    LocationProblem.deniedForever =>
      'Konum izni daha önce reddedilmiş. Ayarlar → İzinler → Konum bölümünden "Uygulama kullanılırken" seçin.',
    LocationProblem.noFix =>
      'Şu an konumunuz alınamadı. Açık alana çıkıp birkaç saniye sonra tekrar deneyin.',
  };

  @override
  String toString() => 'LocationAccessException(${problem.name})';
}

/// Cihaz konumu. Testlerde sahtesi kullanılır.
abstract class LocationSource {
  /// Erişim sorunu varsa döner. [request]: izin yoksa kullanıcıya sor.
  Future<LocationProblem?> check({required bool request});

  /// Android 12+ / iOS 14+: kullanıcı "yaklaşık konum" seçtiyse false.
  Future<bool> isPrecise();

  Future<LocationFix?> currentFix();

  /// Sürekli konum. Android'de bildirim çubuğunda [notificationText] ile
  /// ön plan servisi çalışır; iOS'ta üstte mavi konum göstergesi çıkar.
  /// Böylece uygulama arka plandayken de paylaşım sürer.
  Stream<LocationFix> watch({required String notificationText});

  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class GeolocatorSource implements LocationSource {
  const GeolocatorSource();

  @override
  Future<LocationProblem?> check({required bool request}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationProblem.serviceOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && request) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always || LocationPermission.whileInUse => null,
      LocationPermission.deniedForever => LocationProblem.deniedForever,
      _ => LocationProblem.denied,
    };
  }

  @override
  Future<bool> isPrecise() async {
    try {
      return await Geolocator.getLocationAccuracy() !=
          LocationAccuracyStatus.reduced;
    } catch (_) {
      return true;
    }
  }

  static LocationFix? _fromPosition(Position p) => LocationFix.clean(
    lat: p.latitude,
    lng: p.longitude,
    at: p.timestamp.toLocal(),
    accuracy: p.accuracy,
    heading: p.heading,
    speed: p.speed,
  );

  @override
  Future<LocationFix?> currentFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return _fromPosition(p);
    } catch (_) {
      // Zaman aşımı vb.: yakın zamanda bilinen konum varsa onu kullan.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return null;
        if (DateTime.now().difference(last.timestamp.toLocal()) >
            const Duration(minutes: 2)) {
          return null;
        }
        return _fromPosition(last);
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Stream<LocationFix> watch({required String notificationText}) {
    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter:
            0, // durağan araçta da düzenli ölçüm gelsin (seyreltme bizde)
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Konumunuz paylaşılıyor',
          notificationText: notificationText,
          notificationChannelName: 'Canlı konum paylaşımı',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }
    return Geolocator.getPositionStream(
      locationSettings: settings,
    ).map(_fromPosition).where((f) => f != null).cast<LocationFix>();
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// Only explicit consent and expiry are persisted; GPS coordinates never are.
class LiveShareSession {
  LiveShareSession({
    required this.dealId,
    required this.title,
    required this.userId,
    required this.expiresAt,
    required this.untilDelivered,
    this.counterpartyId,
  });

  final String dealId;
  final String title;
  final String userId;
  final String? counterpartyId;
  DateTime expiresAt;
  final bool untilDelivered;
  DateTime? lastSentAt;
  LatLng? lastSentPosition;
  LocationFix? pending;
  int failures = 0;
  DateTime? retryAt;
  bool sending = false;

  Map<String, dynamic> toJson() => {
    'deal_id': dealId,
    'title': title,
    'user_id': userId,
    'counterparty_id': counterpartyId,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'until_delivered': untilDelivered,
    'consent_version': 1,
  };

  static LiveShareSession? fromJson(Map<String, dynamic> json) {
    final expires = asDateOrNull(json['expires_at']);
    final dealId = asString(json['deal_id']);
    final userId = asString(json['user_id']);
    if (json['consent_version'] != 1 ||
        expires == null ||
        dealId.isEmpty ||
        userId.isEmpty) {
      return null;
    }
    return LiveShareSession(
      dealId: dealId,
      title: asString(json['title']),
      userId: userId,
      counterpartyId: json['counterparty_id'] as String?,
      expiresAt: expires,
      untilDelivered: asBool(json['until_delivered']),
    );
  }
}

/// The GPS stream exists only while a current account has consented shares.
/// Mutations are ordered per deal: a stop waits behind an in-flight upload,
/// so a late response cannot recreate a share the user has just stopped.
class LiveShareService extends ChangeNotifier {
  LiveShareService(
    this._backend,
    this._store, {
    LocationSource? source,
    DateTime Function()? clock,
  }) : _source = source ?? const GeolocatorSource(),
       _clock = clock ?? DateTime.now,
       _ownerId = _backend.userId;

  final LiveLocationBackend _backend;
  final LocalStore _store;
  final LocationSource _source;
  final DateTime Function() _clock;
  static const _key = 'live_share_v2';
  final Map<String, LiveShareSession> _sessions = {};
  final Map<String, LiveShareSession> _restoring = {};
  final Map<String, int> _revisions = {};
  final Map<String, int> _starting = {};
  final Map<String, int> _pendingStops = {};
  final Map<String, Future<void>> _queues = {};
  final Map<String, Future<void>> _stopJobs = {};
  final _notices = StreamController<AppNotice>.broadcast();
  Future<void> _persistTail = Future.value();
  StreamSubscription<LocationFix>? _sub;
  Timer? _timer;
  String? _ownerId;
  int _accountRevision = 0;
  int _consentRevision = 0;
  bool _disposed = false;
  bool _ticking = false;
  bool _resuming = false;
  LocationFix? lastFix;
  LocationProblem? problem;

  Stream<AppNotice> get notices => _notices.stream;
  Iterable<LiveShareSession> get sessions => List.unmodifiable(
    _sessions.values.where(
      (s) => s.userId == _backend.userId && s.expiresAt.isAfter(_clock()),
    ),
  );
  bool get isSharingAny => sessions.isNotEmpty;
  LiveShareSession? sessionFor(String id) =>
      sessions.where((s) => s.dealId == id).firstOrNull;
  bool isSharing(String id) => sessionFor(id) != null;
  bool isStopPending(String id) =>
      _ownerId == _backend.userId && _pendingStops.containsKey(id);
  Future<bool> isPrecise() => _source.isPrecise();
  Future<bool> openAppSettings() => _source.openAppSettings();
  Future<bool> openLocationSettings() => _source.openLocationSettings();

  int _bump(String id) => _revisions[id] = (_revisions[id] ?? 0) + 1;
  bool _current(String uid, int account) =>
      !_disposed &&
      _ownerId == uid &&
      _backend.userId == uid &&
      _accountRevision == account;
  bool _operationCurrent(String uid, int account, String id, int revision) =>
      _current(uid, account) && _revisions[id] == revision;

  /// Call after an account switch. No previous account's consent, pending fix,
  /// or stop request is ever sent using the new account's credentials.
  Future<void> onAccountChanged() async {
    if (_ownerId == _backend.userId) return;
    final initialRestore =
        _ownerId == null && _backend.userId != null && _sessions.isEmpty;
    _accountRevision++;
    _consentRevision++;
    _ownerId = _backend.userId;
    _sessions.clear();
    _restoring.clear();
    _starting.clear();
    _pendingStops.clear();
    _stopJobs.clear();
    _revisions.clear();
    lastFix = null;
    problem = null;
    _stopStream();
    _maintain();
    if (!initialRestore) await _persist();
    notifyListeners();
  }

  Future<T> _ordered<T>(String id, Future<T> Function() action) {
    final result = Completer<T>();
    final previous = _queues[id] ?? Future<void>.value();
    final tail = previous.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    _queues[id] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_queues[id], tail)) _queues.remove(id);
      }),
    );
    return result.future;
  }

  Future<void> start(
    Deal deal, {
    int? minutes,
    bool untilDelivered = false,
  }) async {
    if (_ownerId != _backend.userId) {
      final previousConsent = _consentRevision;
      await onAccountChanged();
      if (_consentRevision != previousConsent + 1) {
        throw const BackendException('BAD_STATE');
      }
    }
    final uid = _ownerId;
    if (uid == null) throw const BackendException('AUTH_REQUIRED');
    if (!LiveRules.dealAllows(deal, uid)) {
      throw const BackendException('BAD_STATE');
    }
    if ((untilDelivered && !LiveRules.canShareUntilDelivered(deal)) ||
        (!untilDelivered &&
            (minutes == null || minutes < 1 || minutes > 1440)) ||
        (untilDelivered && minutes != null)) {
      throw const BackendException('BAD_INPUT', 'Bir paylaşım süresi seçin.');
    }
    final account = _accountRevision;
    final revision = _bump(deal.id);
    _restoring.remove(deal.id);
    _starting[deal.id] = revision;
    void check() {
      if (!_operationCurrent(uid, account, deal.id, revision)) {
        throw const BackendException('BAD_STATE');
      }
    }

    try {
      final access = await _source.check(request: true);
      check();
      if (access != null) throw LocationAccessException(access);
      final fix = await _source.currentFix();
      check();
      if (fix == null || !_fresh(fix)) {
        throw const LocationAccessException(LocationProblem.noFix);
      }
      final expires = await _ordered(deal.id, () async {
        check();
        return _backend.shareLocation(
          deal.id,
          fix,
          minutes: minutes,
          untilDelivered: untilDelivered,
        );
      });
      check();
      if (!expires.isAfter(_clock())) throw const BackendException('BAD_STATE');
      _pendingStops.remove(deal.id);
      _sessions[deal.id] =
          LiveShareSession(
              dealId: deal.id,
              title: deal.title,
              userId: uid,
              counterpartyId: deal.counterpartyId(uid),
              expiresAt: expires,
              untilDelivered: untilDelivered,
            )
            ..lastSentAt = _clock()
            ..lastSentPosition = fix.position;
      lastFix = fix;
      problem = null;
      await _persist();
      _maintain();
      notifyListeners();
    } finally {
      if (_starting[deal.id] == revision) _starting.remove(deal.id);
    }
  }

  /// Device acquisition stops synchronously, before waiting for the network.
  Future<void> stop(String id) async {
    if (_ownerId != _backend.userId) await onAccountChanged();
    if (!_sessions.containsKey(id) &&
        !_restoring.containsKey(id) &&
        !_starting.containsKey(id) &&
        !_pendingStops.containsKey(id)) {
      return;
    }
    _sessions.remove(id);
    _restoring.remove(id);
    _starting.remove(id);
    _pendingStops[id] = _bump(id);
    _maintain();
    notifyListeners();
    final revoke = _queueStop(id);
    await _persist();
    await revoke;
  }

  /// Await this BEFORE clearing a logout token. For a successfully deleted
  /// account the server has already removed its rows, so use server:false.
  Future<void> stopAll({bool server = true}) async {
    // Also cancel a resume which has not finished checking account/permission.
    _consentRevision++;
    if (_ownerId != _backend.userId) await onAccountChanged();
    final ids = {
      ..._sessions.keys,
      ..._restoring.keys,
      ..._starting.keys,
      ..._pendingStops.keys,
    };
    _sessions.clear();
    _restoring.clear();
    _starting.clear();
    for (final id in ids) {
      final revision = _bump(id);
      if (server) _pendingStops[id] = revision;
    }
    if (!server) _pendingStops.clear();
    lastFix = null;
    problem = null;
    _maintain();
    notifyListeners();
    final stops = [
      if (server)
        for (final id in ids) _queueStop(id),
    ];
    await _persist();
    await Future.wait(stops);
  }

  /// Full deal snapshots also remove shares for vanished or blocked parties.
  Future<void> syncAllowedDeals(
    Iterable<Deal> deals, {
    Set<String> blockedUserIds = const {},
  }) async {
    final allowed = {for (final d in deals) d.id: d};
    final ids = {..._sessions.keys, ..._restoring.keys, ..._starting.keys};
    for (final id in ids) {
      final deal = allowed[id];
      final until = (_sessions[id] ?? _restoring[id])?.untilDelivered ?? false;
      if (deal == null ||
          !LiveRules.dealAllows(deal, _backend.userId) ||
          blockedUserIds.contains(deal.counterpartyId(_backend.userId)) ||
          (until && deal.status == DealStatus.delivered)) {
        await stop(id);
      }
    }
  }

  void onDealChanged(Deal deal) {
    final session = _sessions[deal.id] ?? _restoring[deal.id];
    if (!LiveRules.dealAllows(deal, _backend.userId) ||
        (session?.untilDelivered == true &&
            deal.status == DealStatus.delivered)) {
      unawaited(stop(deal.id));
    }
  }

  /// Restore only matching explicit consent whose server-side share is still
  /// active. Starting the app never prompts for location permission.
  Future<void> resume() async {
    if (_ownerId != _backend.userId) {
      final previousConsent = _consentRevision;
      await onAccountChanged();
      // Account adoption increments once; an intervening stop increments
      // again and must cancel this restore before it reads saved consent.
      if (_consentRevision != previousConsent + 1) return;
    }
    final consent = _consentRevision;
    if (_resuming || _disposed || _starting.isNotEmpty) return;
    if (_sessions.isNotEmpty) {
      await tick();
      return;
    }
    final uid = _ownerId;
    final saved = _store.readMap(_key);
    if (uid == null || saved == null) return;
    if (asString(saved['user_id']) != uid) {
      await _store.remove(_key);
      return;
    }
    _resuming = true;
    final account = _accountRevision;
    final candidates = <String, (LiveShareSession, int)>{};
    // Register every candidate before the first permission/network wait. This
    // lets stop, closure and blocking revoke even an unfinished restoration.
    for (final id in asStringList(saved['pending_stops'])) {
      _pendingStops[id] = _bump(id);
    }
    for (final json in asMapList(saved['sessions'])) {
      final session = LiveShareSession.fromJson(json);
      if (session == null ||
          session.userId != uid ||
          !session.expiresAt.isAfter(_clock()) ||
          _pendingStops.containsKey(session.dealId)) {
        continue;
      }
      final revision = _bump(session.dealId);
      _restoring[session.dealId] = session;
      candidates[session.dealId] = (session, revision);
    }
    bool currentCandidate(LiveShareSession session, int revision) =>
        _consentRevision == consent &&
        _operationCurrent(uid, account, session.dealId, revision) &&
        identical(_restoring[session.dealId], session);
    try {
      final access = await _source.check(request: false);
      if (!_current(uid, account) || _consentRevision != consent) return;
      for (final (session, revision) in candidates.values) {
        if (!currentCandidate(session, revision)) continue;
        if (access != null) {
          _restoring.remove(session.dealId);
          _pendingStops[session.dealId] = _bump(session.dealId);
          continue;
        }
        try {
          final rows = await _backend.fetchLiveLocations(session.dealId);
          if (!currentCandidate(session, revision)) continue;
          final own = rows
              .where(
                (r) =>
                    r.userId == uid &&
                    r.dealId == session.dealId &&
                    r.isActiveAt(_clock()),
              )
              .firstOrNull;
          _restoring.remove(session.dealId);
          if (own == null) continue;
          if (own.expiresAt.isBefore(session.expiresAt)) {
            session.expiresAt = own.expiresAt;
          }
          _sessions[session.dealId] = session;
        } catch (_) {
          if (!currentCandidate(session, revision)) continue;
          _restoring.remove(session.dealId);
          _pendingStops[session.dealId] = _bump(session.dealId);
        }
      }
      if (!_current(uid, account) || _consentRevision != consent) return;
      problem = access;
      await _persist();
      _maintain();
      notifyListeners();
      await _flushStops();
    } finally {
      for (final (session, revision) in candidates.values) {
        if (_revisions[session.dealId] == revision &&
            identical(_restoring[session.dealId], session)) {
          _restoring.remove(session.dealId);
        }
      }
      _resuming = false;
    }
  }

  bool _fresh(LocationFix fix) {
    final age = _clock().difference(fix.at);
    return LocationFix.clean(lat: fix.lat, lng: fix.lng, at: fix.at) != null &&
        age >= const Duration(seconds: -30) &&
        age <= const Duration(minutes: 3);
  }

  void _maintain() {
    if (_disposed) return;
    if (_sessions.isNotEmpty || _pendingStops.isNotEmpty) {
      _timer ??= Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(tick()),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
    if (_sessions.isEmpty || problem != null || _ownerId != _backend.userId) {
      _stopStream();
      if (_sessions.isEmpty) lastFix = null;
    } else {
      _startStream();
    }
  }

  void _startStream() {
    if (_sub != null || _disposed) return;
    final uid = _ownerId;
    final account = _accountRevision;
    _sub = _source
        .watch(
          notificationText:
              'Süre bitince veya Durdur seçilince paylaşım sona erer.',
        )
        .listen(
          (fix) {
            if (uid != null && _current(uid, account)) _onFix(fix);
          },
          onError: (Object error) {
            _stopStream();
            if (uid == null || !_current(uid, account)) return;
            problem = error is LocationServiceDisabledException
                ? LocationProblem.serviceOff
                : LocationProblem.noFix;
            notifyListeners();
            unawaited(tick());
          },
          onDone: () {
            _sub = null;
          },
          cancelOnError: true,
        );
  }

  void _stopStream() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _onFix(LocationFix fix) {
    if (!_fresh(fix)) return;
    lastFix = fix;
    problem = null;
    final now = _clock();
    for (final session in _sessions.values.toList()) {
      if (!session.expiresAt.isAfter(now)) continue;
      if (session.pending == null || !fix.at.isBefore(session.pending!.at)) {
        session.pending = fix;
      }
      if (_due(session, now)) unawaited(_send(session));
    }
    notifyListeners();
  }

  bool _due(LiveShareSession session, DateTime now) {
    final fix = session.pending;
    return fix != null &&
        _fresh(fix) &&
        (session.retryAt == null || !now.isBefore(session.retryAt!)) &&
        LiveRules.shouldSend(
          now: now,
          position: fix.position,
          lastSentAt: session.lastSentAt,
          lastSentPosition: session.lastSentPosition,
        );
  }

  @visibleForTesting
  Future<void> tick() async {
    if (_disposed || _ticking) return;
    _ticking = true;
    try {
      await onAccountChanged();
      final uid = _ownerId;
      if (uid == null) return;
      final account = _accountRevision;
      final now = _clock();
      for (final session in _sessions.values.toList()) {
        if (!session.expiresAt.isAfter(now)) {
          await stop(session.dealId);
          continue;
        }
      }
      if (_sessions.isNotEmpty) {
        final access = await _source.check(request: false);
        if (!_current(uid, account)) return;
        if (access == LocationProblem.denied ||
            access == LocationProblem.deniedForever) {
          _emit(
            const AppNotice.warning(
              'Konum izni kapatıldığı için paylaşım durduruldu.',
            ),
          );
          await stopAll();
          return;
        }
        problem = access;
        _maintain();
        if (access == null) {
          for (final session in _sessions.values.toList()) {
            final fix = lastFix;
            if (session.pending == null &&
                fix != null &&
                _fresh(fix) &&
                LiveRules.heartbeatDue(
                  now: now,
                  lastSentAt: session.lastSentAt,
                  lastFixAt: fix.at,
                )) {
              session.pending = fix;
            }
            if (_due(session, now)) await _send(session);
          }
        }
      }
      await _flushStops();
      notifyListeners();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _send(LiveShareSession session) async {
    if (session.sending) return;
    session.sending = true;
    final uid = session.userId;
    final account = _accountRevision;
    final revision = _revisions[session.dealId];
    try {
      await _ordered(session.dealId, () async {
        if (!_current(uid, account) ||
            _revisions[session.dealId] != revision ||
            !identical(_sessions[session.dealId], session) ||
            !session.expiresAt.isAfter(_clock()) ||
            !_due(session, _clock())) {
          return;
        }
        final fix = session.pending!;
        final expires = await _backend.shareLocation(session.dealId, fix);
        if (!_current(uid, account) ||
            !identical(_sessions[session.dealId], session)) {
          return;
        }
        // An update/retry is never permission to extend the original consent.
        if (expires.isBefore(session.expiresAt)) session.expiresAt = expires;
        session.lastSentAt = _clock();
        session.lastSentPosition = fix.position;
        session.failures = 0;
        session.retryAt = null;
        if (identical(session.pending, fix)) session.pending = null;
      });
    } catch (error) {
      if (!_current(uid, account) ||
          !identical(_sessions[session.dealId], session)) {
        return;
      }
      final code = BackendException.from(error).code;
      if (const {
        'EXPIRED',
        'LOCATION_NOT_SHARING',
        'BAD_STATE',
        'NOT_FOUND',
        'FORBIDDEN',
        'BLOCKED',
      }.contains(code)) {
        unawaited(stop(session.dealId));
      } else if (code == 'AUTH_REQUIRED') {
        await stopAll(server: false);
      } else if (code == 'BAD_INPUT') {
        session.pending = null;
      } else {
        session.failures++;
        final exponent = (session.failures - 1).clamp(0, 3);
        session.retryAt = _clock().add(Duration(seconds: 15 << exponent));
      }
    } finally {
      session.sending = false;
    }
  }

  Future<void> _queueStop(String id) {
    if (_stopJobs.containsKey(id)) return _stopJobs[id]!;
    final uid = _ownerId;
    final account = _accountRevision;
    final token = _pendingStops[id];
    final job = _ordered<void>(id, () async {
      if (uid == null ||
          !_current(uid, account) ||
          _pendingStops[id] != token) {
        return;
      }
      try {
        await _backend.stopLocation(id);
        if (_current(uid, account) && _pendingStops[id] == token) {
          _pendingStops.remove(id);
        }
      } catch (error) {
        final code = BackendException.from(error).code;
        if (_current(uid, account) &&
            _pendingStops[id] == token &&
            const {
              'NOT_FOUND',
              'FORBIDDEN',
              'BLOCKED',
              'BAD_STATE',
              'AUTH_REQUIRED',
            }.contains(code)) {
          _pendingStops.remove(id);
        }
      }
    });
    _stopJobs[id] = job;
    unawaited(
      job.then((_) async {
        if (identical(_stopJobs[id], job)) _stopJobs.remove(id);
        await _persist();
        _maintain();
      }),
    );
    return job;
  }

  Future<void> _flushStops() async {
    await Future.wait([
      for (final id in _pendingStops.keys.toList()) _queueStop(id),
    ]);
  }

  Future<void> _persist() {
    final snapshot =
        _sessions.isEmpty && _restoring.isEmpty && _pendingStops.isEmpty
        ? null
        : {
            'user_id': _ownerId,
            'sessions': [
              for (final session in _sessions.values) session.toJson(),
              for (final session in _restoring.values) session.toJson(),
            ],
            'pending_stops': _pendingStops.keys.toList(),
          };
    _persistTail = _persistTail.catchError((Object _) {}).then((_) async {
      if (snapshot == null) {
        await _store.remove(_key);
      } else {
        await _store.writeMap(_key, snapshot);
      }
    });
    return _persistTail;
  }

  void _emit(AppNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _stopStream();
    lastFix = null;
    _notices.close();
    super.dispose();
  }
}
