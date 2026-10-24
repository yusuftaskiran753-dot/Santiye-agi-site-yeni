import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:santiye_agi/models/live_location.dart';
import 'package:santiye_agi/services/dotnet_backend.dart';
import 'package:santiye_agi/services/backend.dart';
import 'dotnet_backend_test.dart' show MemorySessions, session;

void main() {
  test(
    'Late preparation cannot send a start after stop or malformed coordinates',
    () async {
      final prepared = Completer<http.Response>();
      final entered = Completer<void>();
      var puts = 0;
      final api = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: MemorySessions(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/anonymous')) {
            return http.Response(jsonEncode(session('fixture-access')), 200);
          }
          if (r.url.path.endsWith('/prepare')) {
            entered.complete();
            return prepared.future;
          }
          if (r.method == 'PUT') puts++;
          return http.Response('', 204);
        }),
      );
      addTearDown(api.dispose);
      await api.signInAnonymously();
      final pending = api.shareLocation(
        'deal-id',
        LocationFix(lat: 41, lng: 29, at: DateTime.now()),
        minutes: 60,
      );
      final rejected = expectLater(
        pending,
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            'LOCATION_NOT_SHARING',
          ),
        ),
      );
      await entered.future;
      await api.stopLocation('deal-id');
      prepared.complete(
        http.Response('{"generation":"fixture-generation"}', 200),
      );
      await rejected;
      expect(puts, 0);
      expect(
        () => LiveLocation.fromJson({'deal_id': 'deal', 'user_id': 'other'}),
        throwsFormatException,
      );
    },
  );
  test(
    'Authenticated .NET adapter preserves fix capture time, duration and AI envelope',
    () async {
      final fixTime = DateTime.utc(2026, 10, 20, 10);
      final expiry = fixTime.add(const Duration(hours: 1));
      var updates = 0;
      var deleted = false;
      final api = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: MemorySessions(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/anonymous')) {
            return http.Response(jsonEncode(session('fixture-access')), 200);
          }
          expect(r.headers['Authorization'], 'Bearer fixture-access');
          if (r.url.path.endsWith('/location/prepare')) {
            return http.Response('{"generation":"fixture-generation"}', 200);
          }
          if (r.url.path.endsWith('/ai/options')) {
            return http.Response('{"enabled":true}', 200);
          }
          if (r.url.path.endsWith('/ai/understand')) {
            expect(jsonDecode(r.body), {'text': 'Tır lazım', 'city': 'Ankara'});
            return http.Response(
              '{"result":{"intent":"ara","kategori":"yuk"},"source":"gemini"}',
              200,
            );
          }
          if (r.method == 'PUT') {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            expect(body['at'], fixTime.toIso8601String());
            expect(body['lat'], 41.1);
            expect(body['until_delivered'], false);
            if (updates++ == 0) {
              expect(body['minutes'], 60);
              expect(body['generation'], 'fixture-generation');
            } else {
              expect(body.containsKey('minutes'), false);
              expect(body.containsKey('generation'), false);
            }
            return http.Response(
              jsonEncode({'expires_at': expiry.toIso8601String()}),
              200,
            );
          }
          if (r.method == 'DELETE') {
            deleted = true;
            return http.Response('', 204);
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(api.dispose);
      await api.signInAnonymously();
      expect(await api.aiAvailable(), true);
      expect(
        (await api.understandText('Tır lazım', city: 'Ankara'))['kategori'],
        'yuk',
      );
      final fix = LocationFix(lat: 41.1, lng: 29.1, at: fixTime);
      expect(
        (await api.shareLocation(
          'deal-id',
          fix,
          minutes: 60,
        )).isAtSameMomentAs(expiry),
        true,
      );
      expect(
        (await api.shareLocation('deal-id', fix)).isAtSameMomentAs(expiry),
        true,
      );
      expect(await api.fetchLiveLocations('deal-id'), isEmpty);
      await api.stopLocation('deal-id');
      expect(deleted, true);
    },
  );

  test(
    'Location watcher replaces missing points and stops polling after cancellation',
    () async {
      var reads = 0;
      final now = DateTime.now().toUtc();
      final api = DotNetBackend(
        baseUrl: 'https://example.test',
        sessions: MemorySessions(),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/anonymous')) {
            return http.Response(jsonEncode(session('fixture-access')), 200);
          }
          if (r.url.path.endsWith('/locations')) {
            reads++;
            if (reads > 1) return http.Response('[]', 200);
            return http.Response(
              jsonEncode([
                {
                  'deal_id': 'deal-id',
                  'user_id': 'other',
                  'lat': 41.1,
                  'lng': 29.1,
                  'updated_at': now.toIso8601String(),
                  'started_at': now.toIso8601String(),
                  'expires_at': now
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                },
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(api.dispose);
      await api.signInAnonymously();
      final snapshots = await api
          .watchLiveLocations('deal-id')
          .take(2)
          .toList();
      expect(snapshots.first.single.userId, 'other');
      expect(snapshots.last, isEmpty);
      expect(reads, 2);
    },
  );
}
