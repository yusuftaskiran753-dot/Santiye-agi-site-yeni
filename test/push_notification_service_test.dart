import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/services/push_backend.dart';
import 'package:santiye_agi/services/push_notification_service.dart';
import 'package:santiye_agi/state/app_state.dart';

class PushDemoBackend extends LocalBackend implements PushBackend {
  PushDemoBackend(super.store) : super(simulate: false);
  int registered = 0, removed = 0, received = 0;
  Future<void> Function()? registering;
  @override
  Future<void> registerPushDevice(String token, String platform) async {
    registered++;
    await registering?.call();
  }

  @override
  Future<void> unregisterPushDevice() async {
    removed++;
  }

  @override
  void receivedPush({bool opened = false}) {
    received++;
  }
}

class FakePushGateway implements MobilePushGateway {
  bool allowed = true;
  int initialized = 0;
  final changes = StreamController<String>.broadcast();
  final incoming = StreamController<PushMessage>.broadcast();
  final taps = StreamController<PushMessage>.broadcast();
  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<String?> token() async => 'test-device-token';
  @override
  Future<PushMessage?> initialMessage() async => null;
  @override
  Stream<String> get tokenChanges => changes.stream;
  @override
  Stream<PushMessage> get messages => incoming.stream;
  @override
  Stream<PushMessage> get opened => taps.stream;
  Future<void> dispose() async {
    await changes.close();
    await incoming.close();
    await taps.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late PushDemoBackend backend;
  late FakePushGateway gateway;
  late PushNotificationService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    backend = PushDemoBackend(store);
    app = AppState(backend, store);
    await app.init();
    await app.completeOnboarding(
      name: 'Bildirim Testi',
      company: '',
      role: UserRole.nakliyeci,
      city: 'Ankara',
      phone: '+905551234567',
    );
    gateway = FakePushGateway();
    service = PushNotificationService(app, gateway: gateway, enabled: true);
  });
  tearDown(() async {
    service.dispose();
    app.dispose();
    await gateway.dispose();
  });
  test(
    'Kayıt sürerken yenilenen token sonrasında yeniden kaydedilir',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      backend.registering = () async {
        if (backend.registered == 1) {
          entered.complete();
          await release.future;
        }
      };
      final start = service.init();
      await entered.future;
      gateway.changes.add('new-token');
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await start;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(backend.registered, 2);
    },
  );
  test(
    'Cihaz kaydı tekrarlanmaz; başka hesabın bildirimi ve tıklaması işlenmez',
    () async {
      await service.init();
      await service.enable();
      expect(backend.registered, 1);
      gateway.incoming.add(const PushMessage('different-account'));
      gateway.taps.add(const PushMessage('different-account'));
      await Future<void>.delayed(Duration.zero);
      expect(backend.received, 0);
      expect(service.takePendingOpen(), false);
      gateway.taps.add(PushMessage(app.myId!));
      await Future<void>.delayed(Duration.zero);
      expect(backend.received, 1);
      expect(service.takePendingOpen(), true);
      expect(service.takePendingOpen(), false);
    },
  );
  test(
    'İzin kapatıldığında kayıt kaldırılır ve token değişiminde yeniden kaydedilir',
    () async {
      await service.init();
      gateway.allowed = false;
      await service.enable();
      expect(backend.removed, 1);
      gateway.allowed = true;
      gateway.changes.add('rotated');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(backend.registered, 2);
    },
  );
}
