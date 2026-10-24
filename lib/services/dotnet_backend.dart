import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import 'backend.dart';
import '../models/work_photo.dart';
import 'portfolio_backend.dart';
import 'push_backend.dart';
import 'ai_backend.dart';
import 'live_location_backend.dart';
import '../models/live_location.dart';

abstract interface class ApiSessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureApiSessionStore implements ApiSessionStore {
  const SecureApiSessionStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Mevcut mobil modelleri kullanan .NET 10 HTTP veri katmanı.
class DotNetBackend
    implements
        Backend,
        DevelopmentPhoneCode,
        PortfolioBackend,
        PushBackend,
        RuntimeAuthPolicy,
        PasswordLoginBackend,
        HaulBackend,
        AiBackend,
        LiveLocationBackend {
  DotNetBackend({
    String? baseUrl,
    http.Client? client,
    ApiSessionStore? sessions,
  }) : _url = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/$'), ''),
       _client = client ?? http.Client(),
       _sessions = sessions ?? const SecureApiSessionStore();
  final String _url;
  final http.Client _client;
  final ApiSessionStore _sessions;
  final _events = StreamController<BackendEvent>.broadcast();
  final Map<String, int> _locationRevisions = {};
  String _access = '';
  String _refresh = '';
  String? _userId;
  String? _installationId;
  int _identityRevision = 0;
  String? _developmentPhoneCode;
  @override
  String? get developmentPhoneCode => _developmentPhoneCode;
  bool _disposed = false;
  bool _requiresPhoneVerification = true;
  @override
  bool passwordLoginEnabled = false;
  @override
  bool get requiresPhoneVerification => _requiresPhoneVerification;
  @override
  Future<bool> aiAvailable() async =>
      asMap(await _request('GET', '/ai/options'))['enabled'] == true;

  @override
  Future<Map<String, dynamic>> understandText(
    String text, {
    required String city,
  }) async => asMap(
    asMap(
      await _request(
        'POST',
        '/ai/understand',
        body: {'text': text, 'city': city},
      ),
    )['result'],
  );

  @override
  Future<DateTime> shareLocation(
    String dealId,
    LocationFix fix, {
    int? minutes,
    bool untilDelivered = false,
  }) async {
    final identity = _identityRevision;
    final revision = _locationRevisions[dealId] ?? 0;
    String? generation;
    if (minutes != null || untilDelivered) {
      generation = asString(
        asMap(
          await _request(
            'POST',
            '/deals/${Uri.encodeComponent(dealId)}/location/prepare',
          ),
        )['generation'],
      );
      if (generation.isEmpty) throw const BackendException('SERVER');
      if (identity != _identityRevision ||
          revision != (_locationRevisions[dealId] ?? 0)) {
        throw const BackendException('LOCATION_NOT_SHARING');
      }
    }
    final result = asMap(
      await _request(
        'PUT',
        '/deals/${Uri.encodeComponent(dealId)}/location',
        body: {
          'lat': fix.lat,
          'lng': fix.lng,
          'at': fix.at.toUtc().toIso8601String(),
          'accuracy': fix.accuracy,
          'heading': fix.heading,
          'speed': fix.speed,
          'minutes': ?minutes,
          'until_delivered': untilDelivered,
          'generation': ?generation,
        },
      ),
    );
    return asDateOrNull(result['expires_at']) ??
        (throw const BackendException('SERVER'));
  }

  @override
  Future<void> stopLocation(String dealId) async {
    _locationRevisions[dealId] = (_locationRevisions[dealId] ?? 0) + 1;
    await _request('DELETE', '/deals/${Uri.encodeComponent(dealId)}/location');
  }

  @override
  Future<List<LiveLocation>> fetchLiveLocations(String dealId) async => [
    for (final row in asMapList(
      await _request('GET', '/deals/${Uri.encodeComponent(dealId)}/locations'),
    ))
      LiveLocation.fromJson(row),
  ];

  @override
  Stream<List<LiveLocation>> watchLiveLocations(String dealId) async* {
    final identity = _identityRevision;
    while (!_disposed && hasSession && _identityRevision == identity) {
      try {
        final rows = await fetchLiveLocations(dealId);
        if (_disposed || _identityRevision != identity) return;
        yield rows;
      } catch (error) {
        if (_disposed || _identityRevision != identity) return;
        // Removed/inaccessible points must disappear immediately, even on failure.
        yield const [];
        if (const {
          'AUTH_REQUIRED',
          'FORBIDDEN',
          'NOT_FOUND',
          'BLOCKED',
        }.contains(BackendException.from(error).code)) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Future<List<HaulPoint>> fetchHaulPoints() async => [
    for (final row in asMapList(await _request('GET', '/haul-points')))
      HaulPoint.fromJson(row),
  ];

  @override
  Future<HaulPoint> saveHaulPoint(HaulPoint point) async => HaulPoint.fromJson(
    asMap(
      await _request('PUT', '/haul-points/${point.id}', body: point.toJson()),
    ),
  );

  @override
  Future<void> deleteHaulPoint(String id) async {
    await _request('DELETE', '/haul-points/$id');
  }

  @override
  Future<void> refreshAuthPolicy() async {
    final response = await _client
        .get(Uri.parse('$_url/api/v1/auth/options'))
        .timeout(const Duration(seconds: 20));
    // Önceki API sürümünde seçenek ucu yoktur; telefon zorunluluğu korunur.
    if (response.statusCode == 404) {
      _requiresPhoneVerification = true;
      passwordLoginEnabled = false;
      return;
    }
    if (response.statusCode != 200) throw const BackendException('SERVER');
    final options = asMap(_responseJson(response));
    final required = options['phone_verification_required'];
    if (required is! bool) throw const BackendException('SERVER');
    _requiresPhoneVerification = required;
    passwordLoginEnabled = options['password_login_enabled'] == true;
  }

  Timer? _poll;
  bool _polling = false;
  String _notificationVersion = '';
  Future<void>? _refreshing;
  String get _sessionKey =>
      'dotnet_session_${base64Url.encode(utf8.encode(_url))}';
  @override
  bool get isLive => true;
  @override
  String? get userId => _userId;
  @override
  bool get hasSession => _access.isNotEmpty && _userId != null;
  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  Future<void> init() async {
    final uri = Uri.tryParse(_url);
    final devHost =
        uri != null &&
        ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(kDebugMode && uri.scheme == 'http' && devHost))) {
      throw const BackendException(
        'BAD_INPUT',
        'API bağlantısı HTTPS olmalı; geliştirmede yalnız yerel adresler kullanılabilir.',
      );
    }
    final saved = await _sessions.read(_sessionKey);
    if (saved != null) {
      final json = asMap(jsonDecode(saved));
      _access = asString(json['access_token']);
      _refresh = asString(json['refresh_token']);
      _userId = asString(json['user_id']);
    }
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    if (hasSession) {
      _poll = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(_pollNotifications()),
      );
    }
  }

  Future<void> _pollNotifications() async {
    if (_polling || _disposed || !hasSession) return;
    _polling = true;
    try {
      final rows = asMapList(await _request('GET', '/notifications'));
      final version = jsonEncode(
        rows.map((r) => [r['id'], r['read_at']]).toList(),
      );
      if (version != _notificationVersion && !_disposed) {
        _events.add(const BackendEvent('refresh'));
      }
      _notificationVersion = version;
    } catch (_) {
      /* Bağlantı hataları normal yenileme/senkron akışında ele alınır. */
    } finally {
      _polling = false;
    }
  }

  Future<void> _saveSession(
    Map<String, dynamic> json, {
    bool replacing = true,
  }) async {
    if (replacing) _identityRevision++;
    _access = asString(json['access_token']);
    _refresh = asString(json['refresh_token']);
    _userId = asString(json['user_id']);
    if (_access.isEmpty || _refresh.isEmpty || !isUuid(_userId ?? '')) {
      throw const BackendException('SERVER');
    }
    await _sessions.write(_sessionKey, jsonEncode(json));
    _startPolling();
  }

  Future<void> _renew() =>
      _refreshing ??= _renewSession().whenComplete(() => _refreshing = null);
  Future<void> _renewSession() async {
    if (_refresh.isEmpty) throw const BackendException('AUTH_REQUIRED');
    final identity = _identityRevision;
    final refresh = _refresh;
    try {
      final json = asMap(
        await _request(
          'POST',
          '/auth/refresh',
          body: {'refresh_token': refresh},
          auth: false,
        ),
      );
      if (identity != _identityRevision) {
        throw const BackendException('AUTH_REQUIRED');
      }
      await _saveSession(json, replacing: false);
    } on BackendException catch (e) {
      if (e.code == 'AUTH_REQUIRED' && identity == _identityRevision) {
        await _clearSession();
      }
      rethrow;
    }
  }

  Future<void> _clearSession() async {
    _identityRevision++;
    _locationRevisions.clear();
    _access = '';
    _refresh = '';
    _userId = null;
    _poll?.cancel();
    _notificationVersion = '';
    await _sessions.delete(_sessionKey);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool retry = true,
    String? opId,
    bool binary = false,
  }) async {
    final identity = _identityRevision;
    try {
      final request = http.Request(method, Uri.parse('$_url/api/v1$path'));
      request.headers['Accept'] = 'application/json';
      if (auth) {
        if (!hasSession) throw const BackendException('AUTH_REQUIRED');
        request.headers['Authorization'] = 'Bearer $_access';
      }
      if (opId != null) request.headers['Idempotency-Key'] = opId;
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 20));
      if (auth && identity != _identityRevision) {
        throw const BackendException('AUTH_REQUIRED');
      }
      dynamic data;
      if (response.bodyBytes.isNotEmpty &&
          (!binary || response.statusCode >= 400)) {
        data = _responseJson(response);
      }
      if (response.statusCode == 401 && auth && retry) {
        await _renew();
        if (identity != _identityRevision) {
          throw const BackendException('AUTH_REQUIRED');
        }
        return await _request(
          method,
          path,
          body: body,
          auth: auth,
          retry: false,
          opId: opId,
          binary: binary,
        );
      }
      if (response.statusCode == 403 &&
          asMap(data)['error'] == 'PHONE_REQUIRED') {
        _requiresPhoneVerification = true;
        if (!_disposed) _events.add(const BackendEvent('phone_required'));
      }
      if (response.statusCode >= 400) {
        final error = asString(asMap(data)['error']);
        throw BackendException(
          error.isNotEmpty ? error : _httpError(response.statusCode),
          asString(asMap(data)['detail']),
        );
      }
      return binary ? response.bodyBytes : data;
    } on BackendException {
      rethrow;
    } catch (e) {
      throw BackendException.from(e);
    }
  }

  // IIS bakim sayfasi ve proxy hatalari JSON olmayabilir. HTTP durumunu
  // koru; 503 hatasini kalici bir veri hatasi sayip bekleyen kaydi dusurme.
  static String _httpError(int status) => switch (status) {
    401 => 'AUTH_REQUIRED',
    403 => 'FORBIDDEN',
    404 => 'NOT_FOUND',
    409 => 'DUPLICATE',
    429 => 'RATE_LIMIT',
    >= 500 => 'SERVER',
    _ => 'BAD_INPUT',
  };

  static dynamic _responseJson(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw BackendException(
        response.statusCode >= 400 ? _httpError(response.statusCode) : 'SERVER',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _pages(String path) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final data = asMap(
        await _request(
          'GET',
          '$path${path.contains('?') ? '&' : '?'}page=$page',
        ),
      );
      rows.addAll(asMapList(data['items']));
      if (!asBool(data['has_more'])) return rows;
      page++;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _client.close();
    unawaited(_events.close());
  }

  @override
  Future<void> signInAnonymously() async {
    if (!hasSession) {
      await _saveSession(
        asMap(await _request('POST', '/auth/anonymous', auth: false)),
      );
    }
  }

  @override
  Future<void> sendPhoneCode(String phoneE164) async {
    final data = asMap(
      await _request(
        'POST',
        '/auth/phone/request',
        body: {'phone': phoneE164},
        auth: false,
      ),
    );
    final code = asString(data['development_code']);
    _developmentPhoneCode = kDebugMode && code.isNotEmpty ? code : null;
    if (kDebugMode && code.isNotEmpty && !_disposed) {
      _events.add(BackendEvent('info', 'Geliştirme doğrulama kodu: $code'));
    }
  }

  @override
  Future<void> signInWithPassword(String username, String password) async {
    final data = asMap(
      await _request(
        'POST',
        '/auth/password/login',
        body: {'username': username.trim(), 'password': password},
        auth: false,
      ),
    );
    await _saveSession(data);
  }

  @override
  Future<void> verifyPhoneCode(String phoneE164, String code) async =>
      _saveSession(
        asMap(
          await _request(
            'POST',
            '/auth/phone/verify',
            body: {'phone': phoneE164, 'code': code.trim()},
            auth: false,
          ),
        ),
      );
  @override
  Future<void> signOut() async {
    try {
      if (hasSession) {
        // Sunucu da oturuma bağlı cihazları temizler; istemci açıkça kaldırmayı dener.
        try {
          await unregisterPushDevice();
        } catch (_) {}
        await _request('POST', '/auth/logout');
      }
    } finally {
      await _clearSession();
    }
  }

  @override
  Future<void> deleteAccount() async {
    await _request('DELETE', '/account');
    await _clearSession();
  }

  @override
  Future<PublicProfile?> fetchMyProfile() async {
    if (!hasSession) return null;
    final r = await _request('GET', '/profiles/me');
    return r == null ? null : PublicProfile.fromJson(asMap(r));
  }

  @override
  Future<List<WorkPhoto>> fetchWorkPhotos(String userId) async => asMapList(
    await _request('GET', '/profiles/$userId/portfolio'),
  ).map(WorkPhoto.fromJson).toList();

  @override
  Future<Uint8List> fetchWorkPhotoBytes(String id) async =>
      await _request('GET', '/portfolio/$id/image', binary: true) as Uint8List;

  @override
  Future<void> deleteWorkPhoto(String id) async {
    await _request('DELETE', '/portfolio/$id');
  }

  @override
  Future<WorkPhoto> uploadWorkPhoto(
    Uint8List bytes,
    String caption, {
    required String id,
  }) async {
    if (!hasSession) throw const BackendException('AUTH_REQUIRED');
    final identity = _identityRevision;
    if (bytes.isEmpty ||
        bytes.length > 8 * 1024 * 1024 ||
        caption.length > 200 ||
        !isUuid(id)) {
      throw const BackendException(
        'BAD_INPUT',
        'Fotoğraf en fazla 8 MB, açıklama 200 karakter olmalı.',
      );
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      if (identity != _identityRevision || !hasSession) {
        throw const BackendException('AUTH_REQUIRED');
      }
      final request =
          http.MultipartRequest('POST', Uri.parse('$_url/api/v1/portfolio'))
            ..headers['Authorization'] = 'Bearer $_access'
            ..fields['id'] = id
            ..fields['caption'] = caption
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                bytes,
                filename: 'work-photo.jpg',
              ),
            );
      try {
        final response = await http.Response.fromStream(
          await _client.send(request).timeout(const Duration(seconds: 40)),
        ).timeout(const Duration(seconds: 40));
        if (identity != _identityRevision) {
          throw const BackendException('AUTH_REQUIRED');
        }
        if (response.statusCode == 401 && attempt == 0) {
          await _renew();
          continue;
        }
        final data = asMap(_responseJson(response));
        if (response.statusCode >= 400) {
          throw BackendException(
            asString(data['error'], 'SERVER'),
            asString(data['detail']),
          );
        }
        return WorkPhoto.fromJson(data);
      } on BackendException {
        rethrow;
      } catch (e) {
        throw BackendException.from(e);
      }
    }
    throw const BackendException('AUTH_REQUIRED');
  }

  @override
  Future<String> fetchMyPhone() async =>
      asString(asMap(await _request('GET', '/profiles/me/phone'))['phone']);
  @override
  Future<PublicProfile> saveMyProfile({
    required String name,
    required String company,
    required UserRole role,
    required String city,
    required String phone,
  }) async => PublicProfile.fromJson(
    asMap(
      await _request(
        'PUT',
        '/profiles/me',
        body: {
          'name': name,
          'company': company,
          'role': role.name,
          'city': city,
          'phone': phone,
        },
      ),
    ),
  );
  @override
  Future<PublicProfile?> fetchProfile(String userId) async {
    final r = await _request('GET', '/profiles/$userId');
    return r == null ? null : PublicProfile.fromJson(asMap(r));
  }

  @override
  Future<List<PublicProfile>> fetchProfiles(List<String> ids) async {
    final result = <PublicProfile>[];
    for (var i = 0; i < ids.length; i += 200) {
      final end = i + 200 < ids.length ? i + 200 : ids.length;
      result.addAll(
        asMapList(
          await _request(
            'POST',
            '/profiles/query',
            body: {'ids': ids.sublist(i, end)},
          ),
        ).map(PublicProfile.fromJson),
      );
    }
    return result;
  }

  @override
  Future<List<Rating>> fetchRatingsFor(String userId) async => asMapList(
    await _request('GET', '/profiles/$userId/ratings'),
  ).map(Rating.fromJson).toList();
  @override
  Future<Set<String>> fetchMyRatedDealIds() async =>
      (await _request('GET', '/ratings/mine') as List)
          .map((x) => x.toString())
          .toSet();
  @override
  Future<UsageInfo> fetchUsage() async =>
      UsageInfo.fromJson(asMap(await _request('GET', '/usage')));
  @override
  Future<List<Listing>> fetchListings(ListingKind kind) async => (await _pages(
    '/listings/${kind.name}',
  )).map((r) => Listing.fromJson(kind, r)).toList();
  @override
  Future<Listing> saveListing(Listing listing, {required bool isNew}) async {
    final id = isUuid(listing.id) ? listing.id : newUuid();
    return Listing.fromJson(
      listing.kind,
      asMap(
        await _request(
          'PUT',
          '/listings/${listing.kind.name}/$id',
          body: listing.toRow(),
        ),
      ),
    );
  }

  @override
  Future<void> setListingStatus(
    ListingKind kind,
    String id,
    ListingStatus status,
  ) async {
    await _request(
      'PUT',
      '/listings/${kind.name}/$id/status',
      body: {'status': status.name},
    );
  }

  @override
  Future<void> deleteListing(ListingKind kind, String id) async {
    await _request('DELETE', '/listings/${kind.name}/$id');
  }

  @override
  Future<void> setMachineAvailable(String id, bool available) async {
    await _request(
      'PUT',
      '/machines/$id/availability',
      body: {'available': available},
    );
  }

  @override
  Future<DateTime> boostListing(
    ListingKind kind,
    String id,
    BoostOption option,
  ) async => asDate(
    asMap(
      await _request(
        'POST',
        '/listings/${kind.name}/$id/boost',
        body: {'option': option.name},
        opId: newUuid(),
      ),
    )['boosted_until'],
  );
  @override
  Future<Set<String>> fetchUnlockedKeys() async =>
      (await _request('GET', '/unlocks') as List)
          .map((x) => x.toString())
          .toSet();
  @override
  Future<UnlockResult> unlock(
    ListingKind kind,
    String id, {
    bool useCredit = false,
  }) async => UnlockResult.fromJson(
    asMap(
      await _request(
        'POST',
        '/listings/${kind.name}/$id/unlock',
        body: {'use_credit': useCredit},
        opId: newUuid(),
      ),
    ),
  );
  @override
  Future<ContactInfo> contactFor(String refType, String refId) async =>
      ContactInfo.fromJson(
        asMap(await _request('GET', '/contacts/$refType/$refId')),
      );
  @override
  Future<List<TradeRequest>> fetchRequests() async =>
      (await _pages('/requests')).map(TradeRequest.fromJson).toList();
  @override
  Future<TradeRequest> createRequest(
    RequestDraft draft, {
    String? opId,
  }) async => TradeRequest.fromJson(
    asMap(
      await _request(
        'POST',
        '/requests',
        body: draft.toJson(),
        opId: opId ?? newUuid(),
      ),
    ),
  );
  @override
  Future<String?> respondRequest(
    String id, {
    required bool accept,
    String? opId,
  }) async =>
      asMap(
            await _request(
              'POST',
              '/requests/$id/respond',
              body: {'accept': accept},
              opId: opId ?? newUuid(),
            ),
          )['deal_id']
          as String?;
  @override
  Future<void> withdrawRequest(String id) async {
    await _request('POST', '/requests/$id/withdraw', opId: newUuid());
  }

  @override
  Future<List<Deal>> fetchDeals() async =>
      (await _pages('/deals')).map(Deal.fromJson).toList();
  @override
  Future<Deal> createDeal(DealDraft draft) async => Deal.fromJson(
    asMap(
      await _request(
        'POST',
        '/deals',
        body: {
          'title': draft.title,
          'i_am_customer': draft.iAmCustomer,
          'counterparty_name': draft.counterpartyName,
          'amount': draft.amount,
          'payment_method': draft.paymentMethod.name,
          'details': draft.details,
          'payment_terms': draft.paymentTerms,
          'start_date': draft.startDate == null
              ? null
              : dateOnly(draft.startDate!),
          'milestones': draft.milestones
              .map((m) => {'title': m.title, 'amount': m.amount})
              .toList(),
        },
        opId: newUuid(),
      ),
    ),
  );
  @override
  Future<Deal> joinDeal(String code) async => Deal.fromJson(
    asMap(
      await _request(
        'POST',
        '/deals/join',
        body: {'code': code.trim().toUpperCase()},
        opId: newUuid(),
      ),
    ),
  );
  @override
  Future<Deal> dealAction(
    String id,
    DealAction action, {
    int? index,
    String? note,
    String? opId,
  }) async => Deal.fromJson(
    asMap(
      await _request(
        'POST',
        '/deals/$id/actions',
        body: {'action': action.wire, 'index': index, 'note': note ?? ''},
        opId: opId ?? newUuid(),
      ),
    ),
  );
  @override
  Future<void> rateDeal(
    String dealId,
    int stars,
    String comment, {
    String? opId,
  }) async {
    await _request(
      'POST',
      '/deals/$dealId/ratings',
      body: {'stars': stars, 'comment': comment},
      opId: opId ?? newUuid(),
    );
  }

  @override
  Future<void> report(
    String targetType,
    String targetId,
    String reason,
    String note,
  ) async {
    await _request(
      'POST',
      '/reports',
      body: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'note': note,
      },
      opId: newUuid(),
    );
  }

  @override
  Future<Set<String>> fetchBlockedIds() async =>
      (await _request('GET', '/blocks') as List)
          .map((x) => x.toString())
          .toSet();
  @override
  Future<void> block(String userId) async {
    await _request('PUT', '/blocks/$userId');
  }

  @override
  Future<void> unblock(String userId) async {
    await _request('DELETE', '/blocks/$userId');
  }

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    final rows = <AppNotification>[];
    for (var page = 1; ; page++) {
      final batch = asMapList(
        await _request('GET', '/notifications?page=$page'),
      );
      rows.addAll(batch.map(AppNotification.fromJson));
      if (batch.length < 100) return rows;
    }
  }

  @override
  Future<void> markNotificationsRead() async {
    await _request('POST', '/notifications/read');
  }

  @override
  Future<VerifyResult> verifyPurchase(StoreClaim claim) async {
    try {
      final r = asMap(
        await _request('POST', '/billing/verify', body: claim.toJson()),
      );
      return VerifyResult(
        ok: asBool(r['ok']),
        error: asString(r['error']),
        premiumUntil: asDateOrNull(r['premium_until']),
        credits: r['credits'] == null ? null : asInt(r['credits']),
      );
    } on BackendException catch (e) {
      return VerifyResult(ok: false, error: e.code);
    }
  }

  @override
  Future<void> resetLocalData() async {}

  Future<String> _installation() async {
    if (_installationId != null) return _installationId!;
    final key = '${_sessionKey}_installation';
    final saved = await _sessions.read(key);
    final id = saved != null && isUuid(saved) ? saved : newUuid();
    await _sessions.write(key, id);
    return _installationId = id;
  }

  @override
  Future<void> registerPushDevice(String token, String platform) async {
    await _request(
      'PUT',
      '/push/devices/${await _installation()}',
      body: {'token': token, 'platform': platform},
    );
  }

  @override
  Future<void> unregisterPushDevice() async {
    if (hasSession) {
      final id =
          _installationId ??
          await _sessions.read('${_sessionKey}_installation');
      if (id != null && isUuid(id)) {
        await _request('DELETE', '/push/devices/$id');
      }
    }
  }

  @override
  void receivedPush({bool opened = false}) {
    if (!_disposed) _events.add(const BackendEvent('refresh'));
  }
}
