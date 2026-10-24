import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/dotnet_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Sessions implements ApiSessionStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SMS ayari sunucudan acilip kapanir ve eski API zorunlu kabul edilir',
    () async {
      var status = 200;
      var required = false;
      final api = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: _Sessions(),
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({'phone_verification_required': required}),
            status,
          ),
        ),
      );
      addTearDown(api.dispose);
      await api.refreshAuthPolicy();
      expect(api.requiresPhoneVerification, false);
      required = true;
      await api.refreshAuthPolicy();
      expect(api.requiresPhoneVerification, true);
      status = 404;
      await api.refreshAuthPolicy();
      expect(api.requiresPhoneVerification, true);
    },
  );
  test('Bozuk sunucu ayari SMS zorunlulugunu kendiliginden kapatmaz', () async {
    final api = DotNetBackend(
      baseUrl: 'https://example.test',
      sessions: _Sessions(),
      client: MockClient((r) async => http.Response('{}', 200)),
    );
    addTearDown(api.dispose);
    await expectLater(
      api.refreshAuthPolicy(),
      throwsA(isA<BackendException>()),
    );
    expect(api.requiresPhoneVerification, true);
  });
  test(
    'Sunucu SMS istediginde acik misafir profili temizlenip girise donulur',
    () async {
      const user = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      SharedPreferences.setMockInitialValues({});
      final api = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: _Sessions(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/options')) {
            return http.Response('{"phone_verification_required":false}', 200);
          }
          if (r.url.path.endsWith('/anonymous')) {
            return http.Response(
              jsonEncode({
                'access_token': 'token',
                'refresh_token': 'refresh',
                'user_id': user,
              }),
              200,
            );
          }
          return http.Response('{"error":"PHONE_REQUIRED"}', 403);
        }),
      );
      final app = AppState(
        api,
        LocalStore(await SharedPreferences.getInstance()),
      );
      addTearDown(app.dispose);
      await app.init();
      expect(app.requiresPhoneVerification, false);
      await api.signInAnonymously();
      app.me = PublicProfile.fromJson({'id': user, 'name': 'Guest'});
      await expectLater(
        api.fetchUsage(),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            'PHONE_REQUIRED',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(app.me, isNull);
      expect(app.requiresPhoneVerification, true);
      expect(app.offline, false);
    },
  );
}
