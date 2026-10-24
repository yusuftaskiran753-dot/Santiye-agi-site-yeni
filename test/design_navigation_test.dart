import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/screens/home/home_screen.dart';
import 'package:santiye_agi/screens/market/market_screen.dart';
import 'package:santiye_agi/screens/search/search_screen.dart';
import 'package:santiye_agi/screens/assistant/assistant_screen.dart';
import 'package:santiye_agi/screens/listings/forms/load_form.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:santiye_agi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real local-backend records exercise the existing request/deal counters;
/// these tests never contact the live API or use account credentials.
Future<AppState> _localApp({bool requests = true, bool deals = true}) async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  final app = AppState(LocalBackend(store, simulate: false), store);
  await app.init();
  await app.completeOnboarding(
    name: 'Tasarım Kontrol',
    company: 'Yerel Test',
    role: UserRole.yukSahibi,
    city: 'Ankara',
    phone: '+905551234567',
  );
  await app.setShowDemo(false);
  await store.writeMaps('v2_requests', [
    if (requests)
      TradeRequest(
        id: 'design-pending-request',
        kind: ListingKind.yuk,
        listingId: 'design-load',
        listingTitle: 'Ankara → İstanbul',
        ownerId: app.myId!,
        requesterId: 'demo-u9',
      ).toJson(),
  ]);
  await store.writeMaps('v2_deals', [
    if (deals)
      Deal(
        id: 'design-delivered-deal',
        code: 'DESIGN1',
        kind: DealKind.yuk,
        title: 'Teslim onayı bekleyen nakliye',
        customerId: app.myId,
        providerId: 'demo-u9',
        createdBy: app.myId,
        status: DealStatus.delivered,
      ).toJson(),
  ]);
  await app.refreshRequestsAndDeals();
  return app;
}

Future<void> _mountHome(
  WidgetTester tester,
  AppState app, {
  ValueChanged<MarketCategory>? onMarket,
  ValueChanged<int>? onWork,
  VoidCallback? onNotifications,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(brightness),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: HomeScreen(
          onOpenMarket: onMarket ?? (_) {},
          onOpenWork: onWork ?? (_) {},
          onOpenNotifications: onNotifications ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Asistan yük taslağını gösterir, kendiliğinden ilan yayınlamaz', (
    tester,
  ) async {
    final app = await _localApp();
    addTearDown(app.dispose);
    await _mountHome(tester, app);
    final before = app.marketLoads.length;
    await _tapVisible(tester, 'home-assistant');
    expect(find.byType(AssistantScreen), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      "Kocaeli'den İzmir'e 25 ton yük taşıtacağım, yarın",
    );
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bu bilgilerle ilan ver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bu bilgilerle ilan ver'));
    await tester.pumpAndSettle();
    expect(find.byType(LoadFormScreen), findsOneWidget);
    expect(find.text('Kocaeli'), findsOneWidget);
    expect(find.text('İzmir'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(app.marketLoads.length, before);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Dört kategori kısayolu mevcut pazar sekmelerine gider', (
    tester,
  ) async {
    final app = await _localApp();
    addTearDown(app.dispose);
    final opened = <MarketCategory>[];
    await _mountHome(tester, app, onMarket: opened.add);

    for (final category in MarketCategory.values) {
      await _tapVisible(tester, 'home-category-${category.name}');
    }

    expect(opened, MarketCategory.values);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Teklif ve anlaşma kısayolları ayrı iş sekmelerini açar', (
    tester,
  ) async {
    final app = await _localApp();
    addTearDown(app.dispose);
    expect(app.pendingIncoming, 1);
    expect(app.dealsNeedingMe, 1);
    final opened = <int>[];
    await _mountHome(tester, app, onWork: opened.add);

    await _tapVisible(tester, 'home-pending-requests');
    await _tapVisible(tester, 'home-pending-deals');

    expect(opened, [0, 2]);
    expect(tester.takeException(), isNull);
  });

  for (final hasRequests in [true, false]) {
    testWidgets(
      'Yalnız ${hasRequests ? 'teklif' : 'anlaşma'} beklerken doğru kısayol kalır',
      (tester) async {
        final app = await _localApp(requests: hasRequests, deals: !hasRequests);
        addTearDown(app.dispose);
        final opened = <int>[];
        await _mountHome(tester, app, onWork: opened.add);

        final active = hasRequests ? 'requests' : 'deals';
        final absent = hasRequests ? 'deals' : 'requests';
        await _tapVisible(tester, 'home-pending-$active');

        expect(opened, [hasRequests ? 0 : 2]);
        expect(find.byKey(ValueKey('home-pending-$absent')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Tek ana kart asistanı açar; klasik arama İlanlar içinde kalır', (
    tester,
  ) async {
    final app = await _localApp();
    addTearDown(app.dispose);
    await _mountHome(tester, app);
    expect(find.byKey(const Key('home-assistant')), findsOneWidget);
    expect(find.byKey(const Key('home-search')), findsNothing);
    expect(find.text('Ne lazım? Yazın, bulalım'), findsOneWidget);
    expect(find.text('Anlatın, uygun ilanları bulalım'), findsNothing);
    await _tapVisible(tester, 'home-assistant');
    expect(find.byType(AssistantScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(AssistantScreen))).pop();
    await tester.pumpAndSettle();
    final category = ValueNotifier(MarketCategory.yuk);
    addTearDown(category.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          key: UniqueKey(),
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(Brightness.light),
          home: MarketScreen(category: category),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'olmayan yerel ilan');
    await tester.pumpAndSettle();
    expect(find.text('"olmayan yerel ilan" için sonuç yok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '320 px ve büyük yazıda ${brightness.name} ana sayfa taşmadan çalışır',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = await _localApp();
        addTearDown(app.dispose);
        final markets = <MarketCategory>[];
        final workTabs = <int>[];
        var notifications = 0;
        await _mountHome(
          tester,
          app,
          onMarket: markets.add,
          onWork: workTabs.add,
          onNotifications: () => notifications++,
          brightness: brightness,
          textScale: 1.4,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Bildirimler'));
        await tester.pumpAndSettle();
        expect(notifications, 1);
        for (final category in MarketCategory.values) {
          await _tapVisible(tester, 'home-category-${category.name}');
          expect(tester.takeException(), isNull);
        }
        await _tapVisible(tester, 'home-pending-requests');
        expect(tester.takeException(), isNull);
        await _tapVisible(tester, 'home-pending-deals');
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
        await tester.pumpAndSettle();

        expect(markets, MarketCategory.values);
        expect(workTabs, [0, 2]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
