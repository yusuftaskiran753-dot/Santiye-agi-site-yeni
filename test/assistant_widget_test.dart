import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/screens/assistant/assistant_screen.dart';
import 'package:santiye_agi/services/ai_backend.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:santiye_agi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Request {
  const _Request(this.userId, this.text, this.city);
  final String? userId;
  final String text;
  final String city;
}

/// Real local listing/profile operations plus an in-memory remote-AI boundary.
/// No provider key, HTTP request or live account is used by these tests.
class _AiLocalBackend extends LocalBackend implements AiBackend {
  _AiLocalBackend(super.store) : super(simulate: false);

  String? currentUserId = LocalBackend.me;
  final requests = <_Request>[];
  Completer<Map<String, dynamic>>? response;

  @override
  String? get userId => currentUserId;
  @override
  Future<bool> aiAvailable() async => true;

  @override
  Future<Map<String, dynamic>> understandText(
    String text, {
    required String city,
  }) async {
    requests.add(_Request(userId, text, city));
    if (response != null) return response!.future;
    return {
      'intent': 'soru',
      'ozet': 'Uzak servis test yanıtı',
      'cevap': 'Yalnız açık onayla gelen uzak yanıt.',
    };
  }
}

Future<(AppState, _AiLocalBackend)> _app() async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  final backend = _AiLocalBackend(store);
  final app = AppState(backend, store);
  await app.init();
  await app.completeOnboarding(
    name: 'Asistan Yerel Test',
    company: 'Yerel Test',
    role: UserRole.yukSahibi,
    city: 'Ankara',
    phone: '+905551234567',
  );
  await app.setShowDemo(false);
  addTearDown(app.dispose);
  return (app, backend);
}

Future<void> _mount(
  WidgetTester tester,
  AppState app, {
  String? initialText,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AssistantScreen(initialText: initialText),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _toggleConsent(WidgetTester tester) async {
  final consent = find.byType(CheckboxListTile);
  await tester.ensureVisible(consent);
  await tester.pumpAndSettle();
  await tester.tap(consent);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String text) async {
  final field = find.byType(TextField);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.tap(find.byTooltip('Gönder'));
  await tester.pump();
}

void main() {
  testWidgets('Gemini açık olsa da kutu işaretlenmeden metin dışarı gitmez', (
    tester,
  ) async {
    final (app, backend) = await _app();
    await _mount(tester, app);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );

    await _submit(tester, "Ankara'dan İstanbul'a tır lazım");
    await tester.pumpAndSettle();

    expect(backend.requests, isEmpty);
    await tester.scrollUntilVisible(
      find.textContaining('Yerel mod:'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Yerel mod:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Açık onaydan sonra gönderilen metin yalnız bir kez uzakta çözümlenir',
    (tester) async {
      final (app, backend) = await _app();
      await _mount(tester, app);
      await _toggleConsent(tester);
      const prompt = 'Nakliyede yük bağlama hakkında bilgi';

      await _submit(tester, prompt);
      await tester.pumpAndSettle();

      expect(backend.requests, hasLength(1));
      expect(backend.requests.single.text, prompt);
      expect(backend.requests.single.city, 'Ankara');
      expect(find.text('Yalnız açık onayla gelen uzak yanıt.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Onay geri alındığında sonraki gönderim yerelde kalır', (
    tester,
  ) async {
    final (app, backend) = await _app();
    await _mount(tester, app);
    await _toggleConsent(tester);
    await _submit(tester, 'Ankara nakliye bilgisi');
    await tester.pumpAndSettle();
    expect(backend.requests, hasLength(1));

    await _toggleConsent(tester);
    await _submit(tester, "İstanbul'dan Ankara'ya tır lazım");
    await tester.pumpAndSettle();

    expect(backend.requests, hasLength(1));
    await tester.scrollUntilVisible(
      find.textContaining('Yerel mod:'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Yerel mod:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dışarıdan gelen ilk metin onay olmadan Gemini çağırmaz', (
    tester,
  ) async {
    final (app, backend) = await _app();
    final before = app.mine(ListingKind.yuk).length;
    await _mount(
      tester,
      app,
      initialText: "Kocaeli'den İzmir'e 25 ton yük taşıtacağım, yarın",
    );

    expect(backend.requests, isEmpty);
    expect(app.mine(ListingKind.yuk).length, before);
    expect(find.text('Bu bilgilerle ilan ver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Metin alanı uzak gönderimden önce 400 karakterde sınırlar', (
    tester,
  ) async {
    final (app, backend) = await _app();
    await _mount(tester, app);
    await _toggleConsent(tester);

    await _submit(tester, List.filled(401, 'a').join());
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
      400,
    );
    expect(backend.requests, hasLength(1));
    expect(backend.requests.single.text.length, 400);
    expect(tester.takeException(), isNull);
  });

  for (final switchBack in [false, true]) {
    testWidgets(
      'Hesap ${switchBack ? 'değişip geri gelse de' : 'değişince'} bekleyen uzak yanıt gösterilmez',
      (tester) async {
        final (app, backend) = await _app();
        await _mount(tester, app);
        await _toggleConsent(tester);
        final response = Completer<Map<String, dynamic>>();
        backend.response = response;
        await _submit(tester, 'Ankara nakliye bilgisi');
        expect(backend.requests, hasLength(1));
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        backend.currentUserId = 'other-local-user';
        app.notifyListeners();
        await tester.pump();
        if (switchBack) {
          backend.currentUserId = LocalBackend.me;
          app.notifyListeners();
          await tester.pump();
        }
        response.complete({
          'intent': 'soru',
          'ozet': 'Eski isteğin özeti',
          'cevap': 'Eski hesap isteğinin özel yanıtı',
        });
        await tester.pumpAndSettle();

        expect(find.text('Eski hesap isteğinin özel yanıtı'), findsNothing);
        expect(find.text('Eski isteğin özeti'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
