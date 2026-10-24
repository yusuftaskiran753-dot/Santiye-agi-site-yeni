import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:santiye_agi/main.dart';
import 'package:santiye_agi/screens/billing/paywall_screen.dart';
import 'package:santiye_agi/services/billing_service.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app(void Function(AppState app) onReady) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = LocalStore(prefs);
  final app = AppState(LocalBackend(store, simulate: false), store);
  await app.init();
  onReady(app);
  final billing = BillingService(store, verify: app.verifyPurchase, userId: () => app.myId);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      ChangeNotifierProvider<BillingService>.value(value: billing),
    ],
    child: const SantiyeApp(),
  );
}

/// Animasyonları belirli bir süre ilerletir (sonsuz animasyonlarda takılmaz).
Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.scrollUntilVisible(finder.hitTestable(), 120, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder.hitTestable());
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('Mağaza fiyatı yokken Premium tahmini fiyatı açıklar, indirim uydurmaz', (tester) async {
    await tester.pumpWidget(await _app((_) {}));
    await _settle(tester, frames: 3);
    final context = tester.element(find.byType(Scaffold).first);
    // StoreKit erişilebilir olsa da ürün sorgusu henüz fiyat döndürmemiş olabilir.
    context.read<BillingService>().storeAvailable = true;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PaywallScreen()));
    await _settle(tester, frames: 3);

    expect(find.textContaining('tasarruf'), findsNothing);
    final warning = find.text('Ürün fiyatları henüz alınamadı; gösterilen fiyatlar tahminidir.');
    await _reveal(tester, warning);
    expect(warning, findsOneWidget);
    expect(find.text('Satın alımları geri yükle'), findsOneWidget);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(PaywallScreen))).push(
      MaterialPageRoute<void>(builder: (_) => const CreditsScreen()),
    );
    await _settle(tester, frames: 3);
    await _reveal(tester, warning);
    expect(warning, findsOneWidget);
    expect(find.text('15 kredi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Koşullar kabul edilmeden başlanamaz', (tester) async {
    await tester.pumpWidget(await _app((_) {}));
    await _settle(tester, frames: 3);

    expect(find.text('Şantiyenin pazar yeri.'), findsOneWidget);
    final start = find.widgetWithText(FilledButton, 'Başla');
    await _reveal(tester, start);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    final terms = find.byType(CheckboxListTile);
    await _reveal(tester, terms);
    await tester.tap(terms);
    await tester.pump();
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
  });

  testWidgets('Tanıtım → profil → ana ekran', (tester) async {
    late AppState app;
    await tester.pumpWidget(await _app((a) => app = a));
    await _settle(tester, frames: 3);

    final terms = find.byType(CheckboxListTile);
    await _reveal(tester, terms);
    await tester.tap(terms);
    await tester.pump();
    final start = find.widgetWithText(FilledButton, 'Başla');
    await _reveal(tester, start);
    await tester.tap(start);
    await _settle(tester, frames: 8);
    expect(find.text('Sizi tanıyalım'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.ensureVisible(fields.at(0));
    await tester.enterText(fields.at(0), 'Ahmet Yılmaz');
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), '0555 123 45 67');

    final save = find.text('Kaydet ve başla');
    await _reveal(tester, save);
    await tester.pump();
    await tester.tap(save);
    await _settle(tester);

    expect(app.me?.name, 'Ahmet Yılmaz');
    expect(app.myPhone, '+905551234567');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('İlanlar'), findsWidgets);
  });

  testWidgets('Geçersiz telefonla profil kaydedilmez', (tester) async {
    late AppState app;
    await tester.pumpWidget(await _app((a) => app = a));
    await _settle(tester, frames: 3);

    final terms = find.byType(CheckboxListTile);
    await _reveal(tester, terms);
    await tester.tap(terms);
    await tester.pump();
    final start = find.widgetWithText(FilledButton, 'Başla');
    await _reveal(tester, start);
    await tester.tap(start);
    await _settle(tester, frames: 8);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ahmet Yılmaz');
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), '12345');
    final save = find.text('Kaydet ve başla');
    await _reveal(tester, save);
    await tester.tap(save);
    await _settle(tester, frames: 5);

    expect(app.me, isNull);
    expect(find.text('Geçerli bir telefon numarası yazın'), findsOneWidget);
  });
}
