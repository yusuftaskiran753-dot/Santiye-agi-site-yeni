// Gerçek yerel API ile kontrol:
// flutter test test/integration/net_api_smoke_test.dart --dart-define=API_BASE_URL=http://localhost:5080 --dart-define=LOCAL_TEST_DATABASE_NAME=santiye_test_bu_calismaya_ait_veritabani
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/config.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/dotnet_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySession implements ApiSessionStore {
  String? value;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String v) async {
    value = v;
  }

  @override
  Future<void> delete(String key) async {
    value = null;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Mobil durum katmanı gerçek PostgreSQL/.NET API ile profil, ilan ve teklif akışını kullanır',
    () => HttpOverrides.runWithHttpOverrides(() async {
      if (!AppConfig.usesDotNet) {
        fail('API_BASE_URL geliştirme adresi verilmelidir.');
      }
      final uri = Uri.parse(AppConfig.apiBaseUrl);
      if (!['localhost', '127.0.0.1'].contains(uri.host) ||
          !const String.fromEnvironment(
            'LOCAL_TEST_DATABASE_NAME',
          ).startsWith('santiye_test_')) {
        fail(
          'Yalnız localhost üzerinde bu çalışma için oluşturulan santiye_test_* veritabanı kullanılabilir.',
        );
      }
      final prefix = DateTime.now().millisecondsSinceEpoch % 9999998;
      final apps = <AppState>[];
      Future<AppState> create(int suffix, String name) async {
        final phone = '+90555${(prefix + suffix).toString().padLeft(7, '0')}';
        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final api = DotNetBackend(sessions: _MemorySession());
        final app = AppState(api, store);
        apps.add(app);
        await app.init();
        await app.sendPhoneCode(phone);
        final code = app.developmentPhoneCode;
        expect(code, isNotNull);
        await app.verifyPhoneCode(phone, code!);
        await app.completeOnboarding(
          name: name,
          company: '',
          role: UserRole.makineSahibi,
          city: 'İstanbul',
          phone: phone,
        );
        expect(app.me?.name, name);
        expect(app.me?.phoneVerified, true);
        return app;
      }

      try {
        final owner = await create(0, 'API test sahibi');
        final requester = await create(1, 'API test müşterisi');
        final machine = await owner.saveListing(
          Machine(
            id: '',
            owner: owner.me!,
            type: MachineType.ekskavator,
            model: 'API test makinesi',
            capacity: '',
            city: 'İstanbul',
            lat: 41,
            lng: 29,
            hourly: 500,
            daily: 3000,
          ),
          isNew: true,
        );
        await requester.refreshAll();
        expect(requester.marketMachines.any((x) => x.id == machine.id), true);
        expect((await requester.unlock(machine)).ok, true);
        expect(
          (await requester.backend.contactFor('makine', machine.id)).phone,
          owner.myPhone,
        );
        final request = await requester.backend.createRequest(
          RequestDraft(
            kind: ListingKind.makine,
            listingId: machine.id,
            amount: 3000,
            quantity: 1,
            unit: 'gün',
          ),
        );
        final dealId = await owner.backend.respondRequest(
          request.id,
          accept: true,
        );
        expect(dealId, isNotNull);
        await owner.refreshAll();
        await requester.refreshAll();
        expect(owner.deals.any((x) => x.id == dealId), true);
        expect(requester.deals.any((x) => x.id == dealId), true);
        final cancelRequest = await owner.dealAction(
          owner.deals.firstWhere((x) => x.id == dealId),
          DealAction.cancel,
        );
        expect(cancelRequest.status, DealStatus.active);
        expect(cancelRequest.cancelRequestedBy, owner.myId);
        await requester.refreshAll();
        final cancelled = await requester.dealAction(
          requester.deals.firstWhere((x) => x.id == dealId),
          DealAction.cancel,
        );
        expect(cancelled.status, DealStatus.cancelled);
      } finally {
        for (final app in apps.reversed) {
          if (app.backend.hasSession) await app.backend.deleteAccount();
          app.dispose();
        }
      }
    }, _RealHttpOverrides()),
    skip: !AppConfig.usesDotNet
        ? 'Yerel .NET API için API_BASE_URL verilmedi.'
        : false,
  );
}
