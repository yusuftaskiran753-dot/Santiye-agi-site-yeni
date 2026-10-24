import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/models/trade.dart';
import 'package:santiye_agi/screens/common/report_sheet.dart';
import 'package:santiye_agi/screens/profile/profile_screen.dart';
import 'package:santiye_agi/screens/profile/public_profile_screen.dart';
import 'package:santiye_agi/screens/social/block_reason_sheet.dart';
import 'package:santiye_agi/screens/social/comments_sheet.dart';
import 'package:santiye_agi/screens/social/composer_screen.dart';
import 'package:santiye_agi/screens/social/feed_screen.dart';
import 'package:santiye_agi/screens/social/photo_source_sheet.dart';
import 'package:santiye_agi/screens/social/post_detail_screen.dart';
import 'package:santiye_agi/screens/social/story_composer_sheet.dart';
import 'package:santiye_agi/screens/social/story_viewer_screen.dart';
import 'package:santiye_agi/screens/trade/bid_sheet.dart';
import 'package:santiye_agi/screens/trade/tender_award_screen.dart';
import 'package:santiye_agi/screens/trade/tender_create_screen.dart';
import 'package:santiye_agi/screens/trade/tender_detail_screen.dart';
import 'package:santiye_agi/screens/trade/tender_list_screen.dart';
import 'package:santiye_agi/models/social.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:santiye_agi/theme.dart';
import 'package:santiye_agi/utils/legal_notices.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Mesajlar 24 saat içinde silinir, hakaret yasaktır." uyarısı sosyal akış,
/// hikaye, profil ve ihale ekranlarının hepsinde görünmeli.
Future<AppState> _app() async {
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
    profession: TradeProfession.muteahhit,
    sectors: const [WorkSector.hafriyat, WorkSector.altyapi],
  );
  app.social.stories = [SocialStory(id: 's1', authorId: app.myId!, caption: 'Merhaba')];
  return app;
}

Future<void> _mount(WidgetTester t, AppState app, Widget home) async {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(
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
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _openSheet(WidgetTester t, AppState app, Future<void> Function(BuildContext) open) async {
  await _mount(
    t,
    app,
    Builder(
      builder: (c) => Scaffold(
        body: Center(child: FilledButton(onPressed: () => open(c), child: const Text('aç'))),
      ),
    ),
  );
  await t.tap(find.text('aç'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screens = <String, Widget Function(AppState)>{
    'Şantiye Akışı': (_) => const FeedScreen(),
    'Gönderi yaz': (_) => const ComposerScreen(),
    'Gönderi detayı': (_) => const PostDetailScreen(postId: 'sp-1'),
    'İhale listesi': (_) => const TenderListScreen(),
    'İhale detayı': (_) => const TenderDetailScreen(tenderId: 'tn-1'),
    'İhale açma': (_) => const TenderCreateScreen(),
    'En iyi teklifi seç': (_) => const TenderAwardScreen(tenderId: 'tn-1'),
    'Profilim (herkese açık)': (a) => PublicProfileScreen(userId: a.myId!, initial: a.me),
    'Başkasının profili': (_) => const PublicProfileScreen(userId: 'demo-u8'),
    'Profil': (_) => const ProfileScreen(),
    'Hikaye görüntüleyici': (a) => StoryViewerScreen(userId: a.myId!),
  };
  for (final e in screens.entries) {
    testWidgets('yasal uyarı görünür: ${e.key}', (t) async {
      final app = await _app();
      await _mount(t, app, e.value(app));
      await t.dragUntilVisible(
        find.text(LegalNotices.everyAction).first,
        find.byType(Scrollable).first,
        const Offset(0, -200),
      ).catchError((_) {});
      expect(find.text(LegalNotices.everyAction), findsWidgets, reason: e.key);
    });
  }

  final sheets = <String, Future<void> Function(BuildContext, AppState)>{
    'Yorumlar': (c, a) => showCommentsSheet(c, a.social.posts.first),
    'Teklif ver': (c, a) => showBidSheet(c, a.social.tenders.first),
    'Engelle': (c, a) => showBlockReasonSheet(c, 'demo-u8'),
    'Fotoğraf kaynağı': (c, _) => showPhotoSourceSheet(c, title: 'Profil fotoğrafı'),
    'Hikaye ekle': (c, _) => showStoryComposer(c),
    'Şikâyet': (c, _) => showReportSheet(c, targetType: 'profil', targetId: 'demo-u8', ownerId: 'demo-u8'),
  };
  for (final e in sheets.entries) {
    testWidgets('yasal uyarı görünür (pencere): ${e.key}', (t) async {
      final app = await _app();
      await _openSheet(t, app, (c) => e.value(c, app));
      expect(find.text(LegalNotices.everyAction), findsWidgets, reason: e.key);
    });
  }

  test('uyarı metni istenen cümledir', () {
    expect(LegalNotices.everyAction, 'Mesajlar 24 saat içinde silinir, hakaret yasaktır.');
    expect(LegalNotices.withEveryAction('x'), startsWith(LegalNotices.everyAction));
  });
}
