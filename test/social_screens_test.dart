import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/models/social.dart';
import 'package:santiye_agi/models/trade.dart';
import 'package:santiye_agi/screens/social/block_reason_sheet.dart';
import 'package:santiye_agi/screens/social/feed_screen.dart';
import 'package:santiye_agi/screens/trade/tender_award_screen.dart';
import 'package:santiye_agi/screens/trade/tender_detail_screen.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:santiye_agi/theme.dart';
import 'package:santiye_agi/utils/legal_notices.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _app(TradeProfession profession) async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  final app = AppState(LocalBackend(store, simulate: false), store);
  await app.init();
  await app.completeOnboarding(
    name: 'Ahmet Yılmaz',
    company: 'Yılmaz İnşaat',
    role: UserRole.muteahhit,
    city: 'Ankara',
    phone: '+905551234567',
    profession: profession,
    sectors: const [WorkSector.hafriyat, WorkSector.altyapi],
  );
  return app;
}

Future<void> _mount(WidgetTester tester, AppState app, Widget home) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Düğme işlem bitene kadar dönen gösterge çıkarır (AsyncButton); bu yüzden
/// pumpAndSettle yerine kısa süre bekleyip devam edilir.
Future<void> _tapAsync(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('akış: beyaz zemin, yasal uyarı ve paylaşımlar görünür', (tester) async {
    final app = await _app(TradeProfession.taseron);
    await _mount(tester, app, const FeedScreen());
    expect(find.text(LegalNotices.everyAction), findsOneWidget);
    expect(find.byKey(const Key('post-sp-1')), findsOneWidget);
    expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, Colors.white);
    // büyük (en az 48 px yüksek) eylem düğmeleri
    final like = tester.getSize(find.byKey(const Key('like-sp-1')));
    expect(like.height, greaterThanOrEqualTo(48));
  });

  testWidgets('yorum: çalışma sorusu yanıtlanmadan, küfürle ve kanıtsız Hayır ile gönderilmez', (tester) async {
    final app = await _app(TradeProfession.taseron);
    await _mount(tester, app, const FeedScreen());
    await _tap(tester, find.byKey(const Key('comment-sp-1')));

    expect(find.text(LegalNotices.everyAction), findsWidgets);
    expect(find.text('Bu kişiyle çalıştınız mı?'), findsOneWidget);

    // 1) Yanıtsız
    await tester.enterText(find.byKey(const Key('comment-text')), 'Güzel iş çıkarmışsınız');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('comment-send')));
    expect(find.textContaining('sorusunu yanıtlayın'), findsOneWidget);

    // 2) Hayır + kanıtsız
    await _tap(tester, find.byKey(const Key('worked-no')));
    expect(find.byKey(const Key('evidence-pick')), findsOneWidget); // kanıt istenir
    await _tap(tester, find.byKey(const Key('comment-send')));
    expect(find.byKey(const Key('comment-error')), findsOneWidget);
    expect(find.textContaining('kanıt'), findsWidgets);
    expect(app.social.publishedComments('sp-1'), isEmpty);

    // 3) Küfür: anında uyarı + gönder düğmesi kapalı
    await tester.enterText(find.byKey(const Key('comment-text')), 'sen s.k adamsın');
    await tester.pump();
    expect(find.textContaining('küfür'), findsWidgets);
    final send = tester.widget<FilledButton>(find.byKey(const Key('comment-send')));
    expect(send.onPressed, isNull);

    // 4) Evet + temiz yorum yayınlanır
    await tester.enterText(find.byKey(const Key('comment-text')), 'Güzel iş çıkarmışsınız');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('worked-yes')));
    await _tap(tester, find.byKey(const Key('comment-send')));
    expect(app.social.publishedComments('sp-1').length, 1);
    expect(app.social.publishedComments('sp-1').first.workedTogether, isTrue);
  });

  testWidgets('teklif: açıklamasız gönderilmez; verilince telefon gizli kalır', (tester) async {
    final app = await _app(TradeProfession.taseron);
    await _mount(tester, app, const TenderDetailScreen(tenderId: 'tn-1'));
    await _tap(tester, find.byKey(const Key('tender-bid')));
    expect(find.text(LegalNotices.everyAction), findsWidgets);

    final fields = find.byType(TextFormField); // tutar, açıklama, referans
    await tester.enterText(fields.at(0), '125000');
    await tester.pump();
    await _tapAsync(tester, find.text('Teklifi gönder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Açıklama zorunlu'), findsOneWidget);
    expect(app.social.bids, isEmpty);

    await tester.enterText(fields.at(1), 'Malzeme ve işçilik dâhil, 10 günde teslim');
    await tester.pump();
    await _tapAsync(tester, find.text('Teklifi gönder'));
    await tester.pumpAndSettle();
    expect(app.social.bids.length, 1);
    expect(find.text('Teklifiniz'), findsOneWidget);
    expect(
      find.text('Telefonunuz gizli. İhaleyi açan onaylarsa numaralar paylaşılır.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tender-bid')), findsNothing);
  });

  testWidgets('ihaleyi açan: onaylamadan telefon yok, bitince en iyi teklifi seçer', (tester) async {
    final app = await _app(TradeProfession.muteahhit);
    final tender = await app.createTender(
      title: 'Altyapı hattı kazısı',
      detail: 'Saha kazısı ve dolgu işi',
      city: 'Ankara',
      sectors: const [WorkSector.altyapi],
      allowed: const [TradeProfession.taseron],
    );
    app.social.bids.addAll([
      TenderBid(id: 'b1', tenderId: tender.id, bidderId: 'demo-w3', amount: 90000, note: 'Malzeme dâhil, 12 gün sürer'),
      TenderBid(id: 'b2', tenderId: tender.id, bidderId: 'demo-w2', amount: 80000, note: 'Malzeme hariç, 9 gün sürer'),
    ]);
    await _mount(tester, app, TenderDetailScreen(tenderId: tender.id));

    expect(find.byKey(const Key('bid-phone-b1')), findsNothing);
    expect(find.byKey(const Key('tender-award')), findsNothing); // ihale hâlâ açık
    await _tapAsync(tester, find.byKey(const Key('bid-approve-b1')));
    await tester.pump(const Duration(milliseconds: 600));
    await _tapAsync(tester, find.text('Onayla'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('bid-phone-b1')), findsOneWidget);
    expect(find.byKey(const Key('bid-phone-b2')), findsNothing);

    await app.closeTender(tender.id);
    await tester.pump(const Duration(milliseconds: 600));
    await _tapAsync(tester, find.byKey(const Key('tender-award')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('En iyi teklifi seç'), findsWidgets);
    expect(find.text('En düşük teklif'), findsOneWidget);

    await _tapAsync(tester, find.text('Seçili teklifi kazanan yap'));
    await tester.pump(const Duration(milliseconds: 600));
    await _tapAsync(tester, find.text('Kazananı seç'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(app.social.tenderById(tender.id)!.status, TenderStatus.awarded);
    expect(app.social.tenderById(tender.id)!.awardedBidId, 'b2');
  });

  testWidgets('award ekranı teklifsiz ihalede kazanan düğmesi göstermez', (tester) async {
    final app = await _app(TradeProfession.muteahhit);
    final tender = await app.createTender(
      title: 'Boş ihale deneme',
      detail: 'Teklif gelmeyen ihale',
      city: 'Ankara',
      sectors: const [WorkSector.altyapi],
      allowed: const [TradeProfession.taseron],
    );
    await app.closeTender(tender.id);
    await _mount(tester, app, TenderAwardScreen(tenderId: tender.id));
    expect(find.text('Bu ihaleye teklif gelmedi'), findsOneWidget);
    expect(find.text('Seçili teklifi kazanan yap'), findsNothing);
  });

  testWidgets('engelleme: sebep ve kanıt fotoğrafı olmadan engellenmez', (tester) async {
    final app = await _app(TradeProfession.taseron);
    await _mount(
      tester,
      app,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showBlockReasonSheet(context, 'demo-u8'),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('aç'));
    expect(find.text(LegalNotices.everyAction), findsWidgets);
    await _tapAsync(tester, find.text('Engelle').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Engellemek için bir sebep seçin.'), findsOneWidget);
    expect(find.text('Engellemek için kanıt fotoğrafı eklemelisiniz.'), findsOneWidget);
    expect(app.isBlocked('demo-u8'), isFalse);

    await _tap(tester, find.text('Hakaret / küfür'));
    await _tapAsync(tester, find.text('Engelle').last);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Engellemek için bir sebep seçin.'), findsNothing);
    expect(app.isBlocked('demo-u8'), isFalse); // fotoğraf hâlâ yok
  });
}
