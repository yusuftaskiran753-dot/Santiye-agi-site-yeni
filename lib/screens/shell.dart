import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/billing_service.dart';
import '../services/push_notification_service.dart';
import '../services/live_share_service.dart';
import 'deals/live_location_screen.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'home/home_screen.dart';
import 'listings/forms/listing_forms.dart';
import 'market/market_screen.dart';
import 'notifications/notifications_screen.dart';
import 'profile/profile_screen.dart';
import 'work/work_screen.dart';

/// Alt menülü ana iskelet: Ana Sayfa · İlanlar · (+) İlan ver · İşlerim · Profil
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _page = 0;
  final _market = ValueNotifier<MarketCategory>(MarketCategory.yuk);
  final _workTab = ValueNotifier<int>(0);
  StreamSubscription<String>? _flashSub;
  StreamSubscription<void>? _pushSub;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _flashSub = app.flashes.listen((message) {
      if (!mounted) return;
      showSnack(
        context,
        message,
        actionLabel: 'Gör',
        onAction: _openNotifications,
      );
    });
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    // Oturum açılmadan önce doğrulanamamış satın alımlar varsa şimdi tamamla.
    unawaited(context.read<BillingService>().retryPending());
    final push = context.read<PushNotificationService?>();
    _pushSub = push?.opens.listen((_) {
      if (mounted && push.takePendingOpen()) _openNotifications();
    });
    if (push?.takePendingOpen() ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openNotifications();
      });
    }
  }

  @override
  void dispose() {
    _flashSub?.cancel();
    _pushSub?.cancel();
    _lifecycle.dispose();
    _market.dispose();
    _workTab.dispose();
    super.dispose();
  }

  /// Uygulama öne gelince verileri yeniler: çevrimdışı kalmış veya
  /// gönderilmeyi bekleyen işlem varsa hemen, yoksa en az bir dakika geçtiyse.
  void _onResume() {
    unawaited(context.read<LiveShareService?>()?.resume());
    unawaited(context.read<PushNotificationService?>()?.enable());
    final app = context.read<AppState>();
    final last = app.lastRefresh;
    final Future<void> Function() action;
    if (app.offline || app.pendingSyncCount > 0) {
      action = app.syncNow;
    } else if (last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 1)) {
      action = app.refreshAll;
    } else {
      return;
    }
    action().catchError((Object _) {
      // Arka plan yenilemesi; hata çevrimdışı bandıyla gösterilir.
    });
  }

  void _openMarket(MarketCategory c) {
    _market.value = c;
    setState(() => _page = 1);
  }

  void _openWork(int tab) {
    _workTab.value = tab;
    setState(() => _page = 2);
  }

  void _openNotifications() {
    pushPage<void>(context, NotificationsScreen(onOpenWork: _openWork));
  }

  /// Alt menü sırası: 0 Ana Sayfa · 1 İlanlar · 2 (+) · 3 İşlerim · 4 Profil
  int get _navIndex => switch (_page) {
    0 => 0,
    1 => 1,
    2 => 3,
    _ => 4,
  };

  void _onNav(int i) {
    if (i == 2) {
      showPostSheet(context);
      return;
    }
    setState(
      () => _page = switch (i) {
        0 => 0,
        1 => 1,
        3 => 2,
        _ => 3,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final actionCount = context.select<AppState, int>((s) => s.actionCount);
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return PopScope<Object?>(
      // Android geri tuşu: başka sekmedeyken önce Ana Sayfa'ya döner.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _page = 0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _page,
          children: [
            HomeScreen(
              onOpenMarket: _openMarket,
              onOpenWork: _openWork,
              onOpenNotifications: _openNotifications,
            ),
            MarketScreen(category: _market),
            WorkScreen(
              tab: _workTab,
              onOpenMarket: () => _openMarket(_market.value),
            ),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (context.read<LiveShareService?>() != null)
              const LiveSharingBar(),
            NavigationBar(
              selectedIndex: _navIndex,
              onDestinationSelected: _onNav,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Ana Sayfa',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.storefront_outlined),
                  selectedIcon: Icon(Icons.storefront_rounded),
                  label: 'İlanlar',
                ),
                NavigationDestination(
                  icon: Container(
                    width: 46,
                    height: 32,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add_rounded, color: onPrimary),
                  ),
                  label: 'İlan ver',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: actionCount > 0,
                    label: Text('$actionCount'),
                    child: const Icon(Icons.work_outline_rounded),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: actionCount > 0,
                    label: Text('$actionCount'),
                    child: const Icon(Icons.work_rounded),
                  ),
                  label: 'İşlerim',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profil',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
