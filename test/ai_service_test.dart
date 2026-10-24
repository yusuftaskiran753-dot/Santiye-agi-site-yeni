import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/services/ai_backend.dart';
import 'package:santiye_agi/services/ai_service.dart';

class FakeAi implements AiBackend {
  int calls = 0;
  bool fail = false;
  @override
  Future<bool> aiAvailable() async => true;
  @override
  Future<Map<String, dynamic>> understandText(
    String text, {
    required String city,
  }) async {
    calls++;
    if (fail) throw StateError('offline');
    return {
      'intent': 'ilan_ver',
      'kategori': 'yuk',
      'nereden': 'İstanbul',
      'nereye': 'Ankara',
      'yuk_cinsi': 'Demir',
      'ton': 24,
      'gun': 0,
      'ozet': 'Yük taslağı',
    };
  }
}

void main() {
  test(
    'Remote processing requires explicit consent; local parsing never calls provider',
    () async {
      final backend = FakeAi();
      final result = await AiService.instance.understand(
        'İstanbul’dan Ankara’ya tır lazım',
        myCity: 'Ankara',
        backend: backend,
      );
      expect(backend.calls, 0);
      expect(result.source, AiSource.local);
      expect(result.toCity, 'Ankara');
      final remote = await AiService.instance.understand(
        'Demir göndereceğim',
        myCity: 'Ankara',
        backend: backend,
        useRemote: true,
      );
      expect(backend.calls, 1);
      expect(remote.source, AiSource.gemini);
      expect(remote.cargo, 'Demir');
      expect(remote.dayOffset, 0);
    },
  );
  test(
    'Failure and oversized input safely fall back without further paid requests',
    () async {
      final backend = FakeAi()..fail = true;
      final result = await AiService.instance.understand(
        'İstanbul tır lazım',
        myCity: 'Ankara',
        backend: backend,
        useRemote: true,
      );
      expect(result.source, AiSource.local);
      expect(backend.calls, 1);
      await AiService.instance.understand(
        List.filled(401, 'a').join(),
        myCity: 'Ankara',
        backend: backend,
        useRemote: true,
      );
      expect(backend.calls, 1);
    },
  );
  test('Malformed numbers cannot crash or populate a valid date', () {
    final result = AiResult.fromJson({
      'ton': double.infinity,
      'fiyat': double.nan,
      'gun': double.infinity,
    });
    expect(result.tons, isNull);
    expect(result.price, isNull);
    expect(result.dayOffset, isNull);
  });
}
