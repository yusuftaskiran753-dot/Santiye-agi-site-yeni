import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/models/live_location.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/live_location_backend.dart';
import 'package:santiye_agi/services/live_share_service.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clock {
  DateTime now = DateTime.utc(2030, 1, 1, 12);
  void advance(Duration duration) => now = now.add(duration);
}

class _Gps implements LocationSource {
  _Gps(this.clock) {
    controller = StreamController<LocationFix>.broadcast(
      onListen: () => activeWatches++,
      onCancel: () => activeWatches--,
    );
  }

  final _Clock clock;
  late final StreamController<LocationFix> controller;
  LocationProblem? access;
  LocationFix? initial;
  Completer<LocationFix?>? currentGate;
  int activeWatches = 0;
  int permissionRequests = 0;
  int checks = 0;

  LocationFix fix({double lat = 39.93, double lng = 32.85}) =>
      LocationFix(lat: lat, lng: lng, at: clock.now, accuracy: 8);

  void emit({double lat = 39.94, double lng = 32.85}) =>
      controller.add(fix(lat: lat, lng: lng));

  @override
  Future<LocationProblem?> check({required bool request}) async {
    checks++;
    if (request) permissionRequests++;
    return access;
  }

  @override
  Future<LocationFix?> currentFix() async =>
      currentGate == null ? initial ?? fix() : await currentGate!.future;

  @override
  Future<bool> isPrecise() async => true;
  @override
  Future<bool> openAppSettings() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
  @override
  Stream<LocationFix> watch({required String notificationText}) =>
      controller.stream;
}

class _Upload {
  const _Upload(this.userId, this.dealId, this.fix, this.minutes, this.until);
  final String userId;
  final String dealId;
  final LocationFix fix;
  final int? minutes;
  final bool until;
}

/// Each operation captures the authenticated user at invocation, like an HTTP
/// request. A delayed upload can finish after a local stop/account switch.
class _Backend implements LiveLocationBackend {
  _Backend(this.clock);
  final _Clock clock;
  @override
  String? userId = 'alice';
  final uploads = <_Upload>[];
  final stops = <(String, String)>[];
  final rows = <String, LiveLocation>{};
  bool offline = false;
  bool extendUpdates = false;
  Completer<void>? nextUpdateGate;
  Completer<void>? updateEntered;
  Completer<void>? nextFetchGate;
  Completer<void>? fetchEntered;

  String _key(String uid, String id) => '$uid/$id';

  @override
  Future<DateTime> shareLocation(
    String dealId,
    LocationFix fix, {
    int? minutes,
    bool untilDelivered = false,
  }) async {
    final uid = userId!;
    uploads.add(_Upload(uid, dealId, fix, minutes, untilDelivered));
    if (offline) throw const BackendException('NETWORK');
    if (minutes == null && !untilDelivered) {
      final gate = nextUpdateGate;
      nextUpdateGate = null;
      if (gate != null) {
        updateEntered?.complete();
        await gate.future;
      }
    }
    final key = _key(uid, dealId);
    final previous = rows[key];
    final starts = minutes != null || untilDelivered;
    if (!starts && previous == null) {
      throw const BackendException('EXPIRED');
    }
    final expires = starts
        ? clock.now.add(Duration(minutes: untilDelivered ? 1440 : minutes!))
        : extendUpdates
        ? clock.now.add(const Duration(hours: 8))
        : previous!.expiresAt;
    rows[key] = LiveLocation(
      dealId: dealId,
      userId: uid,
      lat: fix.lat,
      lng: fix.lng,
      accuracy: fix.accuracy,
      updatedAt: fix.at,
      startedAt: starts ? clock.now : previous!.startedAt,
      expiresAt: expires,
      untilDelivered: starts ? untilDelivered : previous!.untilDelivered,
    );
    return expires;
  }

  @override
  Future<void> stopLocation(String dealId) async {
    final uid = userId!;
    stops.add((uid, dealId));
    if (offline) throw const BackendException('NETWORK');
    rows.remove(_key(uid, dealId));
  }

  @override
  Future<List<LiveLocation>> fetchLiveLocations(String dealId) async {
    if (offline) throw const BackendException('NETWORK');
    final snapshot = [
      for (final row in rows.values)
        if (row.userId == userId &&
            row.dealId == dealId &&
            row.isActiveAt(clock.now))
          row,
    ];
    final gate = nextFetchGate;
    nextFetchGate = null;
    if (gate != null) {
      fetchEntered?.complete();
      await gate.future;
    }
    return snapshot;
  }

  @override
  Stream<List<LiveLocation>> watchLiveLocations(String dealId) =>
      const Stream.empty();
}

class _Fixture {
  _Fixture(this.clock, this.store, this.gps, this.backend, this.service);
  final _Clock clock;
  final LocalStore store;
  final _Gps gps;
  final _Backend backend;
  final LiveShareService service;
  bool _disposed = false;

  void disposeService() {
    if (!_disposed) service.dispose();
    _disposed = true;
  }
}

Future<_Fixture> _fixture() async {
  SharedPreferences.setMockInitialValues({});
  final clock = _Clock();
  final store = LocalStore(await SharedPreferences.getInstance());
  final gps = _Gps(clock);
  final backend = _Backend(clock);
  final service = LiveShareService(
    backend,
    store,
    source: gps,
    clock: () => clock.now,
  );
  final fixture = _Fixture(clock, store, gps, backend, service);
  addTearDown(() async {
    fixture.disposeService();
    await gps.controller.close();
  });
  return fixture;
}

Deal _deal({DealStatus status = DealStatus.active}) => Deal(
  id: 'deal-1',
  code: 'GPS123',
  kind: DealKind.yuk,
  title: 'Ankara → İstanbul · Yerel test',
  customerId: 'alice',
  providerId: 'bob',
  createdBy: 'alice',
  status: status,
);

Future<void> _drain() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Onay olmadan GPS başlamaz; yalnız süre ve onay kaydedilir', () async {
    final f = await _fixture();
    expect(f.gps.checks, 0);
    expect(f.gps.activeWatches, 0);
    expect(f.backend.uploads, isEmpty);

    await f.service.start(_deal(), minutes: 60);

    expect(f.gps.permissionRequests, 1);
    expect(f.gps.activeWatches, 1);
    expect(f.service.isSharing('deal-1'), isTrue);
    expect(f.backend.uploads.single.minutes, 60);
    final state = f.store.readMap('live_share_v2')!;
    expect(state['user_id'], 'alice');
    final session = (state['sessions'] as List).single as Map;
    expect(session['consent_version'], 1);
    expect(session.containsKey('lat'), isFalse);
    expect(session.containsKey('lng'), isFalse);
    expect(session.containsKey('pending'), isFalse);
  });

  test('Konum izni reddedilirse sunucuya ölçüm gönderilmez', () async {
    final f = await _fixture();
    f.gps.access = LocationProblem.deniedForever;

    await expectLater(
      f.service.start(_deal(), minutes: 60),
      throwsA(isA<LocationAccessException>()),
    );

    expect(f.backend.uploads, isEmpty);
    expect(f.gps.activeWatches, 0);
    expect(f.service.isSharingAny, isFalse);
  });

  test('Kapalı anlaşmada GPS izni bile istenmez', () async {
    final f = await _fixture();
    await expectLater(
      f.service.start(_deal(status: DealStatus.completed), minutes: 60),
      throwsA(isA<BackendException>()),
    );
    expect(f.gps.permissionRequests, 0);
    expect(f.backend.uploads, isEmpty);
  });

  test(
    'Geç tamamlanan yüklemeden sonra Durdur sunucuda da son işlemdir',
    () async {
      final f = await _fixture();
      await f.service.start(_deal(), minutes: 60);
      final gate = Completer<void>();
      f.backend.nextUpdateGate = gate;
      f.backend.updateEntered = Completer<void>();
      f.clock.advance(const Duration(seconds: 11));
      f.gps.emit();
      await f.backend.updateEntered!.future;

      final stopped = f.service.stop('deal-1');
      await _drain();
      expect(f.service.isSharingAny, isFalse);
      expect(f.gps.activeWatches, 0);
      gate.complete();
      await stopped;
      await _drain();

      expect(f.backend.rows, isEmpty);
      expect(f.backend.stops, [('alice', 'deal-1')]);
      expect(f.service.lastFix, isNull);
      expect(f.store.readMap('live_share_v2'), isNull);
    },
  );

  test('İlk GPS beklenirken durdurmak geç gelen onayı başlatmaz', () async {
    final f = await _fixture();
    final gate = Completer<LocationFix?>();
    f.gps.currentGate = gate;
    final starting = f.service.start(_deal(), minutes: 60);
    final rejected = expectLater(starting, throwsA(isA<BackendException>()));
    await _drain();

    await f.service.stop('deal-1');
    gate.complete(f.gps.fix());
    await rejected;

    expect(f.backend.uploads, isEmpty);
    expect(f.service.isSharingAny, isFalse);
    expect(f.gps.activeWatches, 0);
  });

  test('Güncelleme yanıtı paylaşımın onaylanan süresini uzatamaz', () async {
    final f = await _fixture();
    await f.service.start(_deal(), minutes: 1);
    final consentExpiry = f.service.sessionFor('deal-1')!.expiresAt;
    f.backend.extendUpdates = true;
    f.clock.advance(const Duration(seconds: 11));
    f.gps.emit();
    await _drain();

    expect(f.backend.uploads.last.minutes, isNull);
    expect(f.backend.uploads.last.until, isFalse);
    expect(f.service.sessionFor('deal-1')!.expiresAt, consentExpiry);
    f.clock.advance(const Duration(seconds: 50));
    await f.service.tick();

    expect(f.service.isSharingAny, isFalse);
    expect(f.gps.activeWatches, 0);
    expect(f.backend.rows, isEmpty);
  });

  test(
    'Çevrimdışında geçmiş yerine en son ölçüm ve özgün zamanı denenir',
    () async {
      final f = await _fixture();
      await f.service.start(_deal(), minutes: 60);
      f.backend.offline = true;
      f.clock.advance(const Duration(seconds: 11));
      f.gps.emit(lat: 39.94);
      await _drain();
      expect(f.backend.uploads, hasLength(2));
      f.clock.advance(const Duration(seconds: 2));
      f.gps.emit(lat: 39.95);
      f.clock.advance(const Duration(seconds: 2));
      final measuredAt = f.clock.now;
      f.gps.emit(lat: 39.96);
      await _drain();
      expect(f.backend.uploads, hasLength(2));

      f.backend.offline = false;
      f.clock.advance(const Duration(seconds: 12));
      await f.service.tick();

      expect(f.backend.uploads, hasLength(3));
      expect(f.backend.uploads.last.fix.lat, 39.96);
      expect(f.backend.uploads.last.fix.at, measuredAt);
      expect(f.backend.uploads.last.minutes, isNull);
      expect(f.service.sessionFor('deal-1')!.pending, isNull);
    },
  );

  test(
    'Hesap değişimi önceki hesabın konumunu ve geç yanıtını temizler',
    () async {
      final f = await _fixture();
      await f.service.start(_deal(), minutes: 60);
      final gate = Completer<void>();
      f.backend.nextUpdateGate = gate;
      f.backend.updateEntered = Completer<void>();
      f.clock.advance(const Duration(seconds: 11));
      f.gps.emit();
      await f.backend.updateEntered!.future;

      f.backend.userId = 'charlie';
      await f.service.onAccountChanged();
      gate.complete();
      await _drain();
      await f.service.tick();

      expect(f.service.isSharingAny, isFalse);
      expect(f.service.lastFix, isNull);
      expect(f.gps.activeWatches, 0);
      expect(f.store.readMap('live_share_v2'), isNull);
      expect(f.backend.uploads.every((u) => u.userId == 'alice'), isTrue);
      expect(f.backend.stops.where((s) => s.$1 == 'charlie'), isEmpty);
    },
  );

  test(
    'Çevrimdışı durdurma saklanır ve aynı hesapta yeniden denenir',
    () async {
      final f = await _fixture();
      await f.service.start(_deal(), minutes: 60);
      f.backend.offline = true;
      await f.service.stop('deal-1');
      expect(f.service.isSharingAny, isFalse);
      expect(f.gps.activeWatches, 0);
      expect(f.service.isStopPending('deal-1'), isTrue);
      expect(f.store.readMap('live_share_v2')!['pending_stops'], ['deal-1']);
      f.disposeService();
      f.backend.offline = false;
      final gps = _Gps(f.clock);
      final resumed = LiveShareService(
        f.backend,
        f.store,
        source: gps,
        clock: () => f.clock.now,
      );
      addTearDown(() async {
        resumed.dispose();
        await gps.controller.close();
      });

      await resumed.resume();
      await _drain();

      expect(resumed.isSharingAny, isFalse);
      expect(resumed.isStopPending('deal-1'), isFalse);
      expect(gps.activeWatches, 0);
      expect(f.backend.rows, isEmpty);
      expect(f.store.readMap('live_share_v2'), isNull);
    },
  );

  test(
    'Süren paylaşım yalnız aynı hesap ve sunucu onayıyla geri alınır',
    () async {
      final f = await _fixture();
      await f.service.start(_deal(), minutes: 60);
      final expiry = f.service.sessionFor('deal-1')!.expiresAt;
      f.disposeService();
      final gps = _Gps(f.clock);
      final resumed = LiveShareService(
        f.backend,
        f.store,
        source: gps,
        clock: () => f.clock.now,
      );
      addTearDown(() async {
        resumed.dispose();
        await gps.controller.close();
      });

      await resumed.resume();

      expect(resumed.isSharing('deal-1'), isTrue);
      expect(
        resumed.sessionFor('deal-1')!.expiresAt.isAtSameMomentAs(expiry),
        isTrue,
      );
      expect(gps.permissionRequests, 0);
      expect(gps.activeWatches, 1);
      expect(
        f.backend.uploads,
        hasLength(1),
        reason: 'Açılış süreyi yenilemez',
      );
      expect(resumed.lastFix, isNull, reason: 'Koordinatlar cihazda saklanmaz');
    },
  );

  test('Başka hesaba ait kaydedilmiş onay GPS başlatmaz', () async {
    final f = await _fixture();
    await f.service.start(_deal(), minutes: 60);
    f.disposeService();
    f.backend.userId = 'charlie';
    final gps = _Gps(f.clock);
    final resumed = LiveShareService(
      f.backend,
      f.store,
      source: gps,
      clock: () => f.clock.now,
    );
    addTearDown(() async {
      resumed.dispose();
      await gps.controller.close();
    });

    await resumed.resume();

    expect(resumed.isSharingAny, isFalse);
    expect(gps.activeWatches, 0);
    expect(gps.checks, 0);
    expect(f.store.readMap('live_share_v2'), isNull);
  });

  test('İzin kaldırılınca GPS ve sunucu paylaşımı kapanır', () async {
    final f = await _fixture();
    await f.service.start(_deal(), minutes: 60);
    f.gps.access = LocationProblem.denied;

    await f.service.tick();

    expect(f.service.isSharingAny, isFalse);
    expect(f.gps.activeWatches, 0);
    expect(f.backend.rows, isEmpty);
  });

  test('Teslimata kadar paylaşım teslim bildirimiyle biter', () async {
    final f = await _fixture();
    await f.service.start(_deal(), untilDelivered: true);

    f.service.onDealChanged(_deal(status: DealStatus.delivered));
    await _drain();

    expect(f.service.isSharingAny, isFalse);
    expect(f.backend.rows, isEmpty);
    expect(f.gps.activeWatches, 0);
  });

  test('Engellenen veya kaybolan anlaşma paylaşımı kaldırılır', () async {
    final f = await _fixture();
    await f.service.start(_deal(), minutes: 60);

    await f.service.syncAllowedDeals([_deal()], blockedUserIds: {'bob'});
    expect(f.service.isSharingAny, isFalse);
    expect(f.backend.rows, isEmpty);

    await f.service.start(_deal(), minutes: 60);
    await f.service.syncAllowedDeals([]);
    expect(f.service.isSharingAny, isFalse);
    expect(f.backend.rows, isEmpty);
  });

  test('Eski ölçüm yeni başlangıçta paylaşılmaz', () async {
    final f = await _fixture();
    f.gps.initial = LocationFix(
      lat: 39.93,
      lng: 32.85,
      at: f.clock.now.subtract(const Duration(minutes: 4)),
    );
    await expectLater(
      f.service.start(_deal(), minutes: 60),
      throwsA(isA<LocationAccessException>()),
    );
    expect(f.backend.uploads, isEmpty);
    expect(f.gps.activeWatches, 0);
  });

  test(
    'Geri yükleme yanıtı beklerken Durdur tümü GPS açılmasını engeller',
    () async {
      final f = await _fixture();
      await f.service.start(_deal(), minutes: 60);
      f.disposeService();
      final gps = _Gps(f.clock);
      final resumed = LiveShareService(
        f.backend,
        f.store,
        source: gps,
        clock: () => f.clock.now,
      );
      addTearDown(() async {
        resumed.dispose();
        await gps.controller.close();
      });
      final gate = Completer<void>();
      f.backend.nextFetchGate = gate;
      f.backend.fetchEntered = Completer<void>();
      final restoring = resumed.resume();
      await f.backend.fetchEntered!.future;

      await resumed.stopAll();
      gate.complete();
      await restoring;

      expect(resumed.isSharingAny, isFalse);
      expect(gps.activeWatches, 0);
      expect(f.backend.rows, isEmpty);
    },
  );

  for (final revoke in ['single-stop', 'blocked', 'closed']) {
    test(
      'Geri yüklemede $revoke geç yanıtı ve koordinat erişimini iptal eder',
      () async {
        final f = await _fixture();
        await f.service.start(_deal(), minutes: 60);
        f.disposeService();
        final gps = _Gps(f.clock);
        final resumed = LiveShareService(
          f.backend,
          f.store,
          source: gps,
          clock: () => f.clock.now,
        );
        addTearDown(() async {
          resumed.dispose();
          await gps.controller.close();
        });
        final gate = Completer<void>();
        f.backend.nextFetchGate = gate;
        f.backend.fetchEntered = Completer<void>();
        final restoring = resumed.resume();
        await f.backend.fetchEntered!.future;

        if (revoke == 'single-stop') {
          await resumed.stop('deal-1');
        } else if (revoke == 'blocked') {
          await resumed.syncAllowedDeals([_deal()], blockedUserIds: {'bob'});
        } else {
          resumed.onDealChanged(_deal(status: DealStatus.completed));
          await _drain();
        }
        gate.complete();
        await restoring;

        expect(resumed.isSharingAny, isFalse);
        expect(gps.activeWatches, 0);
        expect(f.backend.rows, isEmpty);
        expect(f.store.readMap('live_share_v2'), isNull);
      },
    );
  }

  test(
    'Başlangıçta token yüklenmesi geçerli aynı-hesap onayını silmez',
    () async {
      final f = await _fixture();
      await f.service.start(_deal(), minutes: 60);
      f.disposeService();
      f.backend.userId = null;
      final gps = _Gps(f.clock);
      final resumed = LiveShareService(
        f.backend,
        f.store,
        source: gps,
        clock: () => f.clock.now,
      );
      addTearDown(() async {
        resumed.dispose();
        await gps.controller.close();
      });
      f.backend.userId = 'alice';

      await resumed.resume();

      expect(resumed.isSharing('deal-1'), isTrue);
      expect(gps.activeWatches, 1);
      expect(gps.permissionRequests, 0);
      expect(f.backend.uploads, hasLength(1));
    },
  );

  test('Başlat hemen ardından Durdur tümü ilk onayı iptal eder', () async {
    final f = await _fixture();
    final starting = f.service.start(_deal(), minutes: 60);
    final rejected = expectLater(starting, throwsA(isA<BackendException>()));

    await f.service.stopAll();
    await rejected;

    expect(f.service.isSharingAny, isFalse);
    expect(f.gps.activeWatches, 0);
    expect(f.backend.uploads, isEmpty);
    expect(f.backend.rows, isEmpty);
  });
}
