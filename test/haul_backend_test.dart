import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/dotnet_backend.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';

class _Sessions implements ApiSessionStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

class _RemoteHaul extends LocalBackend implements HaulBackend {
  _RemoteHaul(super.store) : super(simulate: false);
  final points = <HaulPoint>[];
  bool fail = false;
  @override
  bool get isLive => true;
  @override
  Future<List<HaulPoint>> fetchHaulPoints() async => [...points];
  @override
  Future<HaulPoint> saveHaulPoint(HaulPoint point) async {
    if (fail) throw const BackendException('NETWORK');
    points.removeWhere((p) => p.id == point.id);
    points.add(point);
    return point;
  }

  @override
  Future<void> deleteHaulPoint(String id) async {
    if (fail) throw const BackendException('NETWORK');
    points.removeWhere((p) => p.id == id);
  }
}

HaulPoint point() => HaulPoint(
  id: newUuid(),
  name: 'Kazı sahası',
  kind: HaulPointKind.excavation,
  lat: 41,
  lng: 29,
  volume: 2000,
  needM3: 300,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Hafriyat alanları mobil modelle API üzerinden kaydedilip okunur',
    () async {
      final p = point();
      final calls = <String>[];
      final api = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: _Sessions(),
        client: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          if (r.url.path.endsWith('/anonymous')) {
            return http.Response(
              '{"access_token":"token","refresh_token":"refresh","user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}',
              200,
            );
          }
          expect(r.headers['Authorization'], 'Bearer token');
          if (r.method == 'PUT') {
            expect(jsonDecode(r.body)['needM3'], 300);
            return http.Response(
              r.body,
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (r.method == 'GET') {
            return http.Response(
              jsonEncode([p.toJson()]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(api.dispose);
      await api.signInAnonymously();
      expect((await api.saveHaulPoint(p)).id, p.id);
      expect((await api.fetchHaulPoints()).single.needM3, 300);
      await api.deleteHaulPoint(p.id);
      expect(calls, contains('DELETE /api/v1/haul-points/${p.id}'));
    },
  );

  test(
    'Canlı mod örnek veriyi almaz; başarısız saha yazımını kaydedildi göstermez',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_show_demo': true,
        'app_haul_points': jsonEncode([point().toJson()]),
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      final backend = _RemoteHaul(store);
      final app = AppState(backend, store);
      addTearDown(app.dispose);
      await app.init();
      expect(app.showDemo, false);
      expect(app.haulPoints, isEmpty);
      await app.completeOnboarding(
        name: 'Saha Sahibi',
        company: '',
        role: UserRole.muteahhit,
        city: 'İstanbul',
        phone: '+905001000001',
      );
      await app.setShowDemo(true);
      await app.restoreDemoHaulPoints();
      expect(app.showDemo, false);
      expect(app.haulPoints, isEmpty);
      final p = point();
      backend.fail = true;
      await expectLater(app.addHaulPoint(p), throwsA(isA<BackendException>()));
      expect(app.haulPoints, isEmpty);
      backend.fail = false;
      await app.addHaulPoint(p);
      await app.refreshAll();
      expect(app.haulPoints.single.id, p.id);
      backend.fail = true;
      await expectLater(
        app.removeHaulPoint(p.id),
        throwsA(isA<BackendException>()),
      );
      expect(app.haulPoints.single.id, p.id);
      backend.fail = false;
      await app.removeHaulPoint(p.id);
      expect(app.haulPoints, isEmpty);
      await app.addHaulPoint(p);
      await app.signOut();
      expect(app.haulPoints, isEmpty);
    },
  );
}
