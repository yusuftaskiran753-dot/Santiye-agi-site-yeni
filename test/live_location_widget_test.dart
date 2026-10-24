import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:santiye_agi/models/live_location.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/screens/deals/live_location_screen.dart';
import 'package:santiye_agi/services/live_location_backend.dart';
import 'package:santiye_agi/services/live_share_service.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:santiye_agi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend extends LocalBackend implements LiveLocationBackend {
  _Backend(super.store) : super(simulate: false);
  String? account = LocalBackend.me;
  final queries = <Completer<List<LiveLocation>>>[];
  @override
  String? get userId => account;
  @override
  Future<List<LiveLocation>> fetchLiveLocations(String dealId) {
    final query = Completer<List<LiveLocation>>();
    queries.add(query);
    return query.future;
  }

  @override
  Future<DateTime> shareLocation(
    String id,
    LocationFix fix, {
    int? minutes,
    bool untilDelivered = false,
  }) => throw StateError('These UI tests must not start GPS');
  @override
  Future<void> stopLocation(String dealId) async {}
  @override
  Stream<List<LiveLocation>> watchLiveLocations(String dealId) =>
      const Stream.empty();
}

Deal _deal() => Deal(
  id: 'local-ui-deal',
  code: 'UITEST',
  kind: DealKind.yuk,
  title: 'Ankara → İstanbul',
  customerId: LocalBackend.me,
  providerId: 'bob',
  providerName: 'Bob',
  status: DealStatus.active,
);

LiveLocation _point() {
  final now = DateTime.now();
  return LiveLocation(
    dealId: 'local-ui-deal',
    userId: 'bob',
    lat: 39.93,
    lng: 32.85,
    startedAt: now,
    updatedAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
  );
}

Future<(AppState, _Backend)> _mount(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  final backend = _Backend(store);
  final app = AppState(backend, store);
  await app.init();
  await app.completeOnboarding(
    name: 'Yerel Konum Test',
    company: 'Yerel Test',
    role: UserRole.yukSahibi,
    city: 'Ankara',
    phone: '+905551234567',
  );
  final share = LiveShareService(backend, store);
  addTearDown(() {
    share.dispose();
    app.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<LiveShareService>.value(value: share),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: LiveLocationCard(deal: _deal())),
      ),
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpAndSettle();
  return (app, backend);
}

void main() {
  testWidgets('Kartın yeni boş yanıtını geç gelen eski konum geri alamaz', (
    tester,
  ) async {
    final (_, backend) = await _mount(tester);
    expect(backend.queries, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
    expect(backend.queries, hasLength(2));

    backend.queries[1].complete([]);
    await tester.pumpAndSettle();
    backend.queries[0].complete([_point()]);
    await tester.pumpAndSettle();

    expect(find.text('Bob konumunu paylaşıyor'), findsNothing);
    expect(find.text('Canlı konum'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hesap değişip geri gelince eski konum yanıtı kullanılmaz', (
    tester,
  ) async {
    final (app, backend) = await _mount(tester);
    expect(backend.queries, hasLength(1));

    backend.account = 'other-local-account';
    app.notifyListeners();
    await tester.pump();
    backend.account = LocalBackend.me;
    app.notifyListeners();
    await tester.pump();
    expect(backend.queries, hasLength(2));
    backend.queries[0].complete([_point()]);
    backend.queries[1].complete([]);
    await tester.pumpAndSettle();

    expect(find.text('Bob konumunu paylaşıyor'), findsNothing);
    expect(find.text('Canlı konum'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
