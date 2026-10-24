import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../state/app_state.dart';
import 'push_backend.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  // Arka plandaki görünür bildirimi işletim sistemi gösterir.
  // Token/oturum bilgileri mesaj gövdesinden okunmaz.
  await Firebase.initializeApp();
}

class PushMessage {
  const PushMessage(this.userId);
  final String userId;
}

abstract interface class MobilePushGateway {
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<String?> token();
  Stream<String> get tokenChanges;
  Stream<PushMessage> get messages;
  Stream<PushMessage> get opened;
  Future<PushMessage?> initialMessage();
}

class FirebasePushGateway implements MobilePushGateway {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  @override
  Future<void> initialize() async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    // iOS APNs tokeni oluşmadan FCM tokeni istenemez; bir sonraki açılışta tekrar denenir.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await _messaging.getAPNSToken() == null) {
      return null;
    }
    return _messaging.getToken();
  }

  @override
  Stream<String> get tokenChanges => _messaging.onTokenRefresh;
  @override
  Stream<PushMessage> get messages => FirebaseMessaging.onMessage.map(
    (m) => PushMessage(m.data['user_id'] ?? ''),
  );
  @override
  Stream<PushMessage> get opened => FirebaseMessaging.onMessageOpenedApp.map(
    (m) => PushMessage(m.data['user_id'] ?? ''),
  );
  @override
  Future<PushMessage?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushMessage(message.data['user_id'] ?? '');
  }
}

/// Firebase bilgileri sağlanmadığında mevcut uygulama içi bildirimler çalışır.
/// Servis girişten sonra izin alır; eski hesabın bildirimini yeni hesapta açmaz.
class PushNotificationService extends ChangeNotifier {
  PushNotificationService(this.app, {MobilePushGateway? gateway, bool? enabled})
    : _gateway = gateway ?? FirebasePushGateway(),
      _enabled = enabled ?? AppConfig.pushEnabled;
  final AppState app;
  final MobilePushGateway _gateway;
  final bool _enabled;
  final _opens = StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _initialized = false;
  bool _disposed = false;
  bool _working = false;
  bool _rerun = false;
  bool _pendingOpen = false;
  String? _registeredUser;
  String? _registeredToken;
  String? _latestToken;
  String status = 'Uygulama içi bildirimler açık';
  Stream<void> get opens => _opens.stream;
  PushBackend? get _backend =>
      app.backend is PushBackend ? app.backend as PushBackend : null;
  bool takePendingOpen() {
    final value = _pendingOpen;
    _pendingOpen = false;
    return value;
  }

  Future<void> init() async {
    if (!_enabled || _backend == null || kIsWeb) return;
    try {
      await _gateway.initialize();
      _initialized = true;
      _subscriptions.add(
        _gateway.tokenChanges.listen((token) {
          _latestToken = token;
          _registeredToken = null;
          unawaited(enable());
        }),
      );
      _subscriptions.add(
        _gateway.messages.listen((m) => _receive(m, opened: false)),
      );
      _subscriptions.add(
        _gateway.opened.listen((m) => _receive(m, opened: true)),
      );
      _subscriptions.add(
        app.connectivityRestored.listen((_) => unawaited(enable())),
      );
      app.addListener(_changed);
      final initial = await _gateway.initialMessage();
      if (initial != null) _receive(initial, opened: true);
      await enable();
    } catch (_) {
      _setStatus(
        'Bildirim bağlantısı kurulamadı; profil üzerinden tekrar deneyebilirsiniz.',
      );
    }
  }

  void _changed() {
    if (_registeredUser != app.myId) {
      _registeredToken = null;
      if (app.me != null) {
        unawaited(enable());
      } else {
        _registeredUser = null;
        _pendingOpen = false;
      }
    }
  }

  void _receive(PushMessage message, {required bool opened}) {
    if (_disposed || app.me == null || message.userId != app.myId) return;
    _backend?.receivedPush(opened: opened);
    if (opened) {
      _pendingOpen = true;
      _opens.add(null);
    }
  }

  Future<void> enable() async {
    if (_disposed) return;
    if (_working) {
      _rerun = true;
      return;
    }
    if (!_enabled || _backend == null) {
      _setStatus(
        'Anlık bildirim bağlantısı henüz yapılandırılmadı. Uygulama içi bildirimler açık.',
      );
      return;
    }
    if (!_initialized) {
      await init();
      return;
    }
    if (app.me == null || app.myId == null) return;
    _working = true;
    final user = app.myId;
    try {
      if (!await _gateway.requestPermission()) {
        await _backend!.unregisterPushDevice();
        _registeredUser = user;
        _registeredToken = null;
        _setStatus(
          'Bildirim izni kapalı. Telefonun uygulama ayarlarından açabilirsiniz.',
        );
        return;
      }
      final token = _latestToken ?? await _gateway.token();
      if (token == null || app.myId != user) return;
      if (_registeredUser == user && _registeredToken == token) return;
      await _backend!.registerPushDevice(
        token,
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      );
      if (app.myId != user) return;
      _registeredUser = user;
      _registeredToken = token;
      _setStatus('Anlık bildirimler açık');
    } catch (_) {
      _setStatus('Bildirim bağlantısı kurulamadı; tekrar deneyebilirsiniz.');
    } finally {
      _working = false;
      if (_rerun && !_disposed) {
        _rerun = false;
        unawaited(enable());
      }
    }
  }

  void _setStatus(String value) {
    if (_disposed) return;
    status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_changed);
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(_opens.close());
    super.dispose();
  }
}
