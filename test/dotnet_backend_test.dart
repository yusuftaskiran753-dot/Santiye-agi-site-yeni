import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/dotnet_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySessions implements ApiSessionStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

const user = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
Map<String, dynamic> session(String access) => {
  'access_token': access,
  'refresh_token': 'refresh',
  'user_id': user,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Parolali giris yanlis parolada oturumu korur ve basarida yeni oturumu kaydeder',
    () async {
      final store = MemorySessions();
      var valid = false;
      final api = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/options')) {
            return http.Response(
              '{"phone_verification_required":false,"password_login_enabled":true}',
              200,
            );
          }
          if (request.url.path.endsWith('/anonymous')) {
            return http.Response(jsonEncode(session('old')), 200);
          }
          if (request.url.path.endsWith('/password/login')) {
            expect(request.headers.containsKey('Authorization'), false);
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['username'], 'local.fixture');
            expect(body['password'], 'local-test-password-123!');
            return valid
                ? http.Response(jsonEncode(session('new')), 200)
                : http.Response('{"error":"AUTH_REQUIRED"}', 401);
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.dispose);
      await api.signInAnonymously();
      final previous = Map<String, String>.from(store.data);
      await api.refreshAuthPolicy();
      expect(api.passwordLoginEnabled, true);
      await expectLater(
        api.signInWithPassword(' local.fixture ', 'local-test-password-123!'),
        throwsA(isA<BackendException>()),
      );
      expect(store.data, previous);
      valid = true;
      await api.signInWithPassword(
        ' local.fixture ',
        'local-test-password-123!',
      );
      expect(store.data.values.single, contains('new'));
      expect(
        store.data.values.single,
        isNot(contains('local-test-password-123!')),
      );
    },
  );
  test(
    'Geç gelen eski oturum yenilemesi yeni hesabın oturumunu değiştiremez',
    () async {
      final entered = Completer<void>();
      final release = Completer<http.Response>();
      var logins = 0;
      const secondUser = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final backend = DotNetBackend(
        baseUrl: 'http://localhost:5080',
        sessions: MemorySessions(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/anonymous')) {
            logins++;
            return http.Response(
              jsonEncode({
                ...session('login-$logins'),
                'user_id': logins == 1 ? user : secondUser,
              }),
              200,
            );
          }
          if (r.url.path.endsWith('/refresh')) {
            entered.complete();
            return release.future;
          }
          if (r.url.path.endsWith('/logout')) return http.Response('', 204);
          return http.Response('{"error":"AUTH_REQUIRED"}', 401);
        }),
      );
      addTearDown(backend.dispose);
      await backend.init();
      await backend.signInAnonymously();
      final oldRequest = expectLater(
        backend.fetchUsage(),
        throwsA(isA<BackendException>()),
      );
      await entered.future;
      await backend.signOut();
      await backend.signInAnonymously();
      release.complete(
        http.Response(jsonEncode(session('late-old-session')), 200),
      );
      await oldRequest;
      expect(backend.userId, secondUser);
      expect(backend.hasSession, true);
    },
  );
  test(
    'Sunucuya ulaşılamayan çıkışta önceki profil ve yerel oturum temizlenir',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final storage = MemorySessions();
      final backend = DotNetBackend(
        baseUrl: 'http://localhost:5080',
        sessions: storage,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/anonymous')) {
            return http.Response(jsonEncode(session('token')), 200);
          }
          return http.Response('{"error":"SERVER"}', 503);
        }),
      );
      final app = AppState(backend, store);
      addTearDown(app.dispose);
      await app.init();
      await backend.signInAnonymously();
      app.me = PublicProfile.fromJson({'id': user, 'name': 'Önceki hesap'});
      await app.signOut();
      expect(app.me, isNull);
      expect(backend.hasSession, false);
      expect(storage.data, isEmpty);
    },
  );
  test(
    'Fotoğraf yükleme oturum yenilemesinde aynı kimlik ve veriyi korur',
    () async {
      final uploads = <http.Request>[];
      const photoId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/anonymous')) {
          return http.Response(jsonEncode(session('old')), 200);
        }
        if (r.url.path.endsWith('/refresh')) {
          return http.Response(jsonEncode(session('new')), 200);
        }
        if (r.url.path.endsWith('/image')) {
          return http.Response.bytes([255, 216, 255], 200);
        }
        uploads.add(r);
        if (r.headers['Authorization'] == 'Bearer old') {
          return http.Response('{"error":"AUTH_REQUIRED"}', 401);
        }
        return http.Response(
          jsonEncode({'id': photoId, 'owner_id': user, 'caption': 'Biten iş'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final backend = DotNetBackend(
        baseUrl: 'http://localhost:5080',
        client: client,
        sessions: MemorySessions(),
      );
      addTearDown(backend.dispose);
      await backend.init();
      await backend.signInAnonymously();
      final photo = await backend.uploadWorkPhoto(
        Uint8List.fromList([1, 2, 3]),
        'Biten iş',
        id: photoId,
      );
      expect(photo.id, photoId);
      expect(uploads, hasLength(2));
      for (final r in uploads) {
        expect(r.body, contains(photoId));
        expect(r.bodyBytes, containsAllInOrder([1, 2, 3]));
      }
      expect(uploads.last.headers['Authorization'], 'Bearer new');
      expect(await backend.fetchWorkPhotoBytes(photoId), [255, 216, 255]);
    },
  );
  test(
    'Süresi dolmuş oturum yenilenir ve aynı işlem kimliğiyle tekrar gönderilir',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.url.path.endsWith('/anonymous')) {
          return http.Response(jsonEncode(session('old')), 200);
        }
        if (r.url.path.endsWith('/refresh')) {
          return http.Response(jsonEncode(session('new')), 200);
        }
        if (r.headers['Authorization'] == 'Bearer old') {
          return http.Response('{"error":"AUTH_REQUIRED"}', 401);
        }
        return http.Response(
          '{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","kind":"makine"}',
          200,
        );
      });
      final backend = DotNetBackend(
        baseUrl: 'http://localhost:5080',
        client: client,
        sessions: MemorySessions(),
      );
      addTearDown(backend.dispose);
      await backend.init();
      await backend.signInAnonymously();
      const op = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      await backend.createRequest(
        const RequestDraft(
          kind: ListingKind.makine,
          listingId: 'id',
          amount: 1,
        ),
        opId: op,
      );
      final attempts = requests
          .where((r) => r.url.path.endsWith('/requests'))
          .toList();
      expect(attempts, hasLength(2));
      expect(
        attempts.map((r) => r.headers['Idempotency-Key']),
        everyElement(op),
      );
      expect(attempts.last.headers['Authorization'], 'Bearer new');
    },
  );
  for (final status in [200, 401]) {
    test(
      'Hesap değişince bekleyen fotoğraf yeni hesaba taşınmaz ($status)',
      () async {
        const secondUser = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
        const photoId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        var logins = 0;
        var uploads = 0;
        var refreshes = 0;
        final backend = DotNetBackend(
          baseUrl: 'http://localhost:5080',
          sessions: MemorySessions(),
          client: MockClient((r) async {
            if (r.url.path.endsWith('/anonymous')) {
              logins++;
              return http.Response(
                jsonEncode({
                  ...session('account-$logins'),
                  'user_id': logins == 1 ? user : secondUser,
                }),
                200,
              );
            }
            if (r.url.path.endsWith('/logout')) return http.Response('', 204);
            if (r.url.path.endsWith('/refresh')) {
              refreshes++;
              return http.Response(
                jsonEncode({...session('refreshed'), 'user_id': secondUser}),
                200,
              );
            }
            uploads++;
            if (uploads == 1) {
              entered.complete();
              return response.future;
            }
            return http.Response(
              jsonEncode({
                'id': photoId,
                'owner_id': secondUser,
                'caption': 'Old photo',
              }),
              200,
            );
          }),
        );
        addTearDown(backend.dispose);
        await backend.init();
        await backend.signInAnonymously();
        final pending = expectLater(
          backend.uploadWorkPhoto(
            Uint8List.fromList([1, 2, 3]),
            'Eski fotoğraf',
            id: photoId,
          ),
          throwsA(
            isA<BackendException>().having(
              (e) => e.code,
              'code',
              'AUTH_REQUIRED',
            ),
          ),
        );
        await entered.future;
        await backend.signOut();
        await backend.signInAnonymously();
        response.complete(
          http.Response(
            status == 200
                ? jsonEncode({
                    'id': photoId,
                    'owner_id': user,
                    'caption': 'Old photo',
                  })
                : '{"error":"AUTH_REQUIRED"}',
            status,
          ),
        );
        await pending;
        expect(uploads, 1);
        expect(refreshes, 0);
        expect(backend.userId, secondUser);
        expect(backend.hasSession, true);
      },
    );
  }
  test('Pazar listesi 300 kayıt sınırı olmadan bütün sayfaları okur', () async {
    final pages = <String?>[];
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/anonymous')) {
        return http.Response(jsonEncode(session('token')), 200);
      }
      pages.add(r.url.queryParameters['page']);
      final second = r.url.queryParameters['page'] == '2';
      return http.Response(
        jsonEncode({
          'items': [
            {
              'id': second ? 'second' : 'first',
              'from_city': 'İstanbul',
              'to_city': 'Ankara',
            },
          ],
          'has_more': !second,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final backend = DotNetBackend(
      baseUrl: 'http://localhost:5080',
      client: client,
      sessions: MemorySessions(),
    );
    addTearDown(backend.dispose);
    await backend.init();
    await backend.signInAnonymously();
    final listings = await backend.fetchListings(ListingKind.yuk);
    expect(pages, ['1', '2']);
    expect(listings.map((x) => x.id), ['first', 'second']);
  });
  test('Oturum kapatma güvenli depodaki oturumu kaldırır', () async {
    final storage = MemorySessions();
    final backend = DotNetBackend(
      baseUrl: 'http://localhost:5080',
      sessions: storage,
      client: MockClient(
        (r) async => r.url.path.endsWith('/anonymous')
            ? http.Response(jsonEncode(session('token')), 200)
            : http.Response('', 204),
      ),
    );
    addTearDown(backend.dispose);
    await backend.init();
    await backend.signInAnonymously();
    expect(storage.data, isNotEmpty);
    await backend.signOut();
    expect(storage.data, isEmpty);
    expect(backend.hasSession, isFalse);
  });
  test('Yerel olmayan HTTP API adresi reddedilir', () async {
    final backend = DotNetBackend(
      baseUrl: 'http://example.com',
      sessions: MemorySessions(),
    );
    addTearDown(backend.dispose);
    await expectLater(backend.init(), throwsA(isA<BackendException>()));
  });

  test('IIS HTML bakım yanıtı geçici hata sayılır ve oturum korunur', () async {
    var maintenance = true;
    final backend = DotNetBackend(
      baseUrl: 'https://example.test',
      sessions: MemorySessions(),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/anonymous')) {
          return http.Response(jsonEncode(session('token')), 200);
        }
        if (maintenance) {
          return http.Response('<html>Guncelleme yapiliyor.</html>', 503);
        }
        return http.Response('{"free_used":1,"free_limit":5,"credits":0}', 200);
      }),
    );
    addTearDown(backend.dispose);
    await backend.signInAnonymously();
    await expectLater(
      backend.fetchUsage(),
      throwsA(
        isA<BackendException>().having((e) => e.isTransient, 'transient', true),
      ),
    );
    expect(backend.hasSession, true);
    maintenance = false;
    expect((await backend.fetchUsage()).freeLeft, 4);
  });

  test(
    'Fotoğraf gönderiminde IIS HTML hatası anlaşılır sunucu hatası verir',
    () async {
      final backend = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: MemorySessions(),
        client: MockClient(
          (r) async => r.url.path.endsWith('/anonymous')
              ? http.Response(jsonEncode(session('token')), 200)
              : http.Response('Service unavailable', 503),
        ),
      );
      addTearDown(backend.dispose);
      await backend.signInAnonymously();
      await expectLater(
        backend.uploadWorkPhoto(
          Uint8List.fromList([1, 2, 3]),
          'Kontrol',
          id: newUuid(),
        ),
        throwsA(
          isA<BackendException>().having((e) => e.code, 'code', 'SERVER'),
        ),
      );
      expect(backend.hasSession, true);
    },
  );
}
