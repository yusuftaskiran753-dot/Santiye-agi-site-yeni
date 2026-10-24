import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'screens/onboarding/onboarding_screens.dart';
import 'screens/shell.dart';
import 'services/backend.dart';
import 'services/billing_service.dart';
import 'services/local_backend.dart';
import 'services/local_store.dart';
import 'services/dotnet_backend.dart';
import 'services/supabase_backend.dart';
import 'services/push_notification_service.dart';
import 'services/live_location_backend.dart';
import 'services/live_share_service.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/feedback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();
  final prefs = await SharedPreferences.getInstance();
  final store = LocalStore(prefs);

  // Sunucu bilgileri config.dart'ta tanımlıysa canlı mod, değilse Demo modu.
  final Backend backend = AppConfig.usesDotNet
      ? DotNetBackend()
      : AppConfig.isLive
      ? SupabaseBackend()
      : LocalBackend(store);
  final app = AppState(backend, store);
  final billing = BillingService(
    store,
    verify: app.verifyPurchase,
    userId: () => app.myId,
    allowDebugGrant: !AppConfig.isLive,
  );
  final push = PushNotificationService(app);
  final liveShare = backend is LiveLocationBackend
      ? LiveShareService(backend as LiveLocationBackend, store)
      : null;
  if (liveShare != null) {
    app.beforeSignOut = () => liveShare.stopAll();
    app.afterAccountDeleted = () => liveShare.stopAll(server: false);
    bool reconciling = false;
    bool dirty = false;
    Future<void> reconcile() async {
      dirty = true;
      if (reconciling) return;
      reconciling = true;
      try {
        while (dirty) {
          dirty = false;
          await liveShare.onAccountChanged();
          if (app.ready && app.me != null && !app.refreshing) {
            await liveShare.resume();
            await liveShare.syncAllowedDeals(
              app.deals,
              blockedUserIds: app.blocked,
            );
          }
        }
      } finally {
        reconciling = false;
      }
    }

    app.addListener(() => unawaited(reconcile()));
    AppFeedback.listen(liveShare.notices);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<BillingService>.value(value: billing),
        ChangeNotifierProvider<PushNotificationService>.value(value: push),
        if (liveShare != null)
          ChangeNotifierProvider<LiveShareService>.value(value: liveShare),
      ],
      child: const SantiyeApp(),
    ),
  );

  // Servislerin arka plan sonuçları (çevrimdışı işlemlerin gönderilmesi,
  // satın alma doğrulaması) hangi ekranda olunursa olsun gösterilir.
  AppFeedback.listen(app.notices);
  AppFeedback.listen(billing.notices);
  // Bağlantı geri gelince bekleyen satın alma doğrulamalarını tamamla.
  app.connectivityRestored.listen((_) => unawaited(billing.retryPending()));

  await app.init();
  unawaited(billing.init());
  unawaited(push.init());
}

/// Yakalanmamış hatalar uygulamayı çökertmez: kaydedilir ve kullanıcıya
/// tek, sakin bir mesaj gösterilir (aynı mesaj üst üste tekrarlanmaz).
void _installErrorHandlers() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    // Çizim/yerleşim hataları geliştirme sırasında zaten kırmızı ekranla görünür.
    if (!kDebugMode &&
        details.library != 'rendering library' &&
        details.library != 'widgets library') {
      AppFeedback.unexpected(details.exception);
    }
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Yakalanmamış hata: $error\n$stack');
    AppFeedback.unexpected(error);
    return true;
  };
}

class SantiyeApp extends StatelessWidget {
  const SantiyeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      scaffoldMessengerKey: AppFeedback.messengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Çok büyük sistem yazı boyutlarında düzenin bozulmaması için üst sınır.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _Root(),
    );
  }
}

/// Açılış → (hata) → tanıtım ve profil → ana ekran.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final (ready, signedIn, error) = context
        .select<AppState, (bool, bool, String?)>(
          (s) => (s.ready, s.me != null, s.loadError),
        );
    if (!ready) return const SplashScreen();
    if (!signedIn && error != null) return StartupErrorScreen(message: error);
    if (!signedIn) return const WelcomeScreen();
    return const MainShell();
  }
}
