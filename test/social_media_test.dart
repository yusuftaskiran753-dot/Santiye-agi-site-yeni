import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/models/social.dart';
import 'package:santiye_agi/models/trade.dart';
import 'package:santiye_agi/screens/profile/public_profile_screen.dart';
import 'package:santiye_agi/screens/social/composer_screen.dart';
import 'package:santiye_agi/screens/social/feed_screen.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/services/photo_storage.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:santiye_agi/theme.dart';
import 'package:santiye_agi/utils/legal_notices.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1x1 şeffaf PNG
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

late Directory _tmp;

/// Uygulamanın kalıcı klasörünü taklit eden `social_media/` altında gerçek dosya.
String _photo(String name) {
  final dir = Directory('${_tmp.path}/social_media')..createSync(recursive: true);
  final f = File('${dir.path}/$name.png')..writeAsBytesSync(_png);
  return f.path;
}

Future<(AppState, LocalStore)> _app({LocalStore? reuse, TradeProfession p = TradeProfession.taseron}) async {
  LocalStore store;
  if (reuse != null) {
    store = reuse;
  } else {
    SharedPreferences.setMockInitialValues({});
    store = LocalStore(await SharedPreferences.getInstance());
  }
  final app = AppState(LocalBackend(store, simulate: false), store);
  await app.init();
  if (app.me == null) {
    await app.completeOnboarding(
      name: 'Ahmet Yılmaz',
      company: 'Yılmaz İnşaat',
      role: UserRole.muteahhit,
      city: 'Ankara',
      phone: '+905551234567',
      profession: p,
      sectors: const [WorkSector.hafriyat, WorkSector.altyapi],
    );
  }
  return (app, store);
}

Future<void> _expectCode(Future<Object?> f, String code) async {
  try {
    await f;
    fail('$code bekleniyordu');
  } on BackendException catch (e) {
    expect(e.code, code);
  }
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
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 300));
  await t.tap(f);
  await t.pump(); // yeni sayfa ilk karede offstage başlar
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => _tmp = Directory.systemTemp.createTempSync('santiye_media_'));
  tearDown(() {
    PhotoStorage.debugPick = null;
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  group('Profil ve kapak fotoğrafı', () {
    test('kaydedilir, yeniden açılınca korunur, değişince eski dosya silinir', () async {
      final (app, store) = await _app();
      final a = _photo('a');
      final b = _photo('b');
      await app.setProfilePhoto(a);
      await app.setCoverPhoto(_photo('kapak'));
      expect(app.myAvatarPath, a);

      // Uygulama yeniden açılır.
      final (again, _) = await _app(reuse: store);
      expect(again.myAvatarPath, a);
      expect(again.social.coverOf(again.myId!), contains('kapak'));

      await again.setProfilePhoto(b);
      expect(File(a).existsSync(), isFalse, reason: 'eski profil fotoğrafı silinmeli');
      expect(File(b).existsSync(), isTrue);

      await again.removeProfilePhoto();
      expect(again.myAvatarPath, '');
      expect(File(b).existsSync(), isFalse);
      expect(again.social.coverOf(again.myId!), isNotEmpty, reason: 'kapak etkilenmemeli');
    });

    test('boş yol reddedilir; başkasının dosyasına dokunulmaz', () async {
      final (app, _) = await _app();
      await _expectCode(app.setProfilePhoto('  '), 'BAD_INPUT');
      final outside = File('${_tmp.path}/galeri_foto.png')..writeAsBytesSync(_png);
      await app.setProfilePhoto(outside.path);
      await app.setProfilePhoto(_photo('yeni'));
      expect(outside.existsSync(), isTrue, reason: 'kendi klasörümüz dışındaki dosya silinmez');
    });
  });

  group('Hikaye', () {
    test('fotoğraf veya yazı şart, küfür ve uzun yazı reddedilir', () async {
      final (app, _) = await _app();
      await _expectCode(app.addStory(), 'BAD_INPUT');
      await _expectCode(app.addStory(caption: 's.k'), 'BAD_INPUT');
      await _expectCode(app.addStory(caption: 'a' * 141), 'BAD_INPUT');
      expect(app.social.stories, isEmpty);
      final s = await app.addStory(caption: 'Bugün 3 kamyon çalıştı');
      expect(app.social.activeStoriesOf(app.myId!), [s]);
    });

    test('24 saat sonra silinir (kayıttan ve dosyadan)', () async {
      final (app, store) = await _app();
      final photo = _photo('hikaye');
      final old = SocialStory(
        id: 'eski',
        authorId: app.myId!,
        photoPath: photo,
        createdAt: DateTime.now().subtract(const Duration(hours: 25)),
      );
      final fresh = SocialStory(id: 'yeni', authorId: app.myId!, caption: 'taze');
      app.social.stories = [old, fresh];
      await app.social.persistStories();
      expect(old.isExpired(), isTrue);
      expect(fresh.remaining().inHours, 23);

      final (again, _) = await _app(reuse: store); // açılışta temizlik
      expect(again.social.stories.map((s) => s.id), ['yeni']);
      expect(File(photo).existsSync(), isFalse);
    });

    test('yalnızca sahibi siler; engellenen kişinin hikayesi görünmez', () async {
      final (app, _) = await _app();
      app.social.stories = [
        SocialStory(id: 'x', authorId: 'demo-u8', caption: 'merhaba'),
        SocialStory(id: 'y', authorId: 'demo-w1', caption: 'selam'),
      ];
      expect(app.storyAuthorIds.toSet(), {'demo-u8', 'demo-w1'});
      await _expectCode(app.deleteStory('x'), 'FORBIDDEN');
      await app.blockWithProof('demo-u8', reason: 'Spam veya rahatsız etme', evidencePhotoPath: '/tmp/k.jpg');
      expect(app.storyAuthorIds, ['demo-w1']);
      final mine = await app.addStory(caption: 'benim');
      await app.deleteStory(mine.id);
      expect(app.social.activeStoriesOf(app.myId!), isEmpty);
    });
  });

  group('Gönderi silme ve takip', () {
    test('kendi gönderisini siler (yorum, beğeni, fotoğraf dâhil); başkasınınkini silemez', () async {
      final (app, _) = await _app();
      final photo = _photo('gonderi');
      final post = await app.createPost(
        kind: SocialPostKind.work,
        caption: 'Temel kazısı bitti',
        photoPath: photo,
      );
      await app.toggleLike(post.id);
      await app.addComment(
        postId: post.id,
        text: 'Güzel iş',
        negative: false,
        workedTogether: true,
        evidenceNote: '',
      );
      expect(app.social.likeCount(post.id), 1);
      await app.deletePost(post.id);
      expect(app.social.posts.any((p) => p.id == post.id), isFalse);
      expect(app.social.comments.any((c) => c.postId == post.id), isFalse);
      expect(app.social.likeCount(post.id), 0);
      expect(File(photo).existsSync(), isFalse);

      await _expectCode(app.deletePost('sp-1'), 'FORBIDDEN');
      await _expectCode(app.deletePost('sp-2'), 'FORBIDDEN');
    });

    test('takipçi ve takip sayıları', () async {
      final (app, _) = await _app();
      expect(app.social.followingCount(app.myId!), 0);
      await app.follow('demo-u8');
      expect(app.social.followingCount(app.myId!), 1);
      expect(app.social.followerCount('demo-u8'), 1);
      await app.unfollow('demo-u8');
      expect(app.social.followerCount('demo-u8'), 0);
    });
  });

  group('Ekranlar', () {
    testWidgets('profil: kameradan profil fotoğrafı ve galeriden kapak değişir, hata mesajı çıkar', (t) async {
      final (app, _) = await _app();
      await _mount(t, app, PublicProfileScreen(userId: app.myId!, initial: app.me));
      expect(find.byKey(const Key('count-posts')), findsOneWidget);
      expect(find.byKey(const Key('profile-cover')), findsOneWidget);

      ImageSource? used;
      PhotoStorage.debugPick = (s) async {
        used = s;
        return _photo('avatar-${s.name}');
      };
      await _tap(t, find.byKey(const Key('avatar-edit')));
      expect(find.text(LegalNotices.everyAction), findsWidgets);
      expect(find.byKey(const Key('photo-remove')), findsNothing);
      await _tap(t, find.byKey(const Key('photo-camera')));
      expect(used, ImageSource.camera);
      expect(app.myAvatarPath, contains('avatar-camera'));
      expect(find.byKey(ValueKey('avatar-${app.myId}-${app.myAvatarPath}')), findsOneWidget);

      await _tap(t, find.byKey(const Key('cover-edit')));
      await _tap(t, find.byKey(const Key('photo-gallery')));
      expect(used, ImageSource.gallery);
      expect(app.social.coverOf(app.myId!), contains('avatar-gallery'));

      // Kaldır seçeneği artık var
      await _tap(t, find.byKey(const Key('avatar-edit')));
      await _tap(t, find.byKey(const Key('photo-remove')));
      expect(app.myAvatarPath, '');

      // Kamera açılamazsa anlaşılır mesaj
      PhotoStorage.debugPick = (_) async => throw Exception('kamera yok');
      await _tap(t, find.byKey(const Key('avatar-edit')));
      await _tap(t, find.byKey(const Key('photo-camera')));
      expect(find.textContaining('Kamera açılamadı'), findsOneWidget);
      expect(app.myAvatarPath, '');
    });

    testWidgets('başkasının profili: takip et / takiptesin, düzenleme düğmesi yok', (t) async {
      final (app, _) = await _app();
      await _mount(t, app, const PublicProfileScreen(userId: 'demo-u8'));
      expect(find.byKey(const Key('avatar-edit')), findsNothing);
      expect(find.byKey(const Key('cover-edit')), findsNothing);
      await _tap(t, find.byKey(const Key('follow-button')));
      expect(app.following.contains('demo-u8'), isTrue);
      expect(find.text('Takiptesin'), findsOneWidget);
      expect(
        tester(t, const Key('count-followers')),
        contains('1'),
      );
    });

    testWidgets('profil ızgarası: fotoğraflı gönderi görünür, açılınca beğeni ve yorum var', (t) async {
      final (app, _) = await _app();
      final post = await app.createPost(
        kind: SocialPostKind.work,
        caption: 'Yeni şantiye fotoğrafı',
        photoPath: _photo('izgara'),
      );
      await _mount(t, app, PublicProfileScreen(userId: app.myId!, initial: app.me));
      expect(find.byKey(Key('grid-post-${post.id}')), findsOneWidget);
      expect(find.byKey(const Key('first-post')), findsNothing);
      await _tap(t, find.byKey(Key('grid-post-${post.id}')));
      expect(find.byKey(Key('post-${post.id}')), findsOneWidget);
      expect(find.byKey(Key('post-photo-${post.id}')), findsOneWidget);
      await _tap(t, find.byKey(Key('like-${post.id}')));
      expect(app.social.likeCount(post.id), 1);
    });

    testWidgets('gönderi: kamera ile fotoğraf eklenir, çift dokunuşla beğeni, paylaş penceresi', (t) async {
      final (app, _) = await _app();
      ImageSource? used;
      PhotoStorage.debugPick = (s) async {
        used = s;
        return _photo('gonderi-foto');
      };
      await _mount(t, app, const ComposerScreen());
      await t.enterText(find.byType(TextFormField).first, 'Bugün temel betonu döküldü');
      await t.pump();
      await _tap(t, find.byKey(const Key('evidence-pick')));
      await _tap(t, find.byKey(const Key('photo-camera')));
      expect(used, ImageSource.camera);
      expect(find.byKey(const Key('evidence-clear')), findsOneWidget); // önizleme + kaldır
      await _tap(t, find.text('Paylaş'));
      final post = app.social.posts.first;
      expect(post.caption, 'Bugün temel betonu döküldü');
      expect(post.photoPath, contains('gonderi-foto'));

      await _mount(t, app, const FeedScreen());
      expect(find.byKey(Key('post-photo-${post.id}')), findsOneWidget);
      await t.ensureVisible(find.byKey(Key('post-photo-${post.id}')));
      await t.pump(const Duration(milliseconds: 300));
      final center = t.getCenter(find.byKey(Key('post-photo-${post.id}')));
      await t.tapAt(center);
      await t.pump(const Duration(milliseconds: 50));
      await t.tapAt(center);
      await t.pump(const Duration(milliseconds: 600));
      expect(app.social.likedBy(post.id, app.myId!), isTrue);
      await t.tapAt(center);
      await t.pump(const Duration(milliseconds: 50));
      await t.tapAt(center);
      await t.pump(const Duration(milliseconds: 600));
      expect(app.social.likeCount(post.id), 1, reason: 'çift dokunma beğeniyi geri almaz');

      await _tap(t, find.byKey(Key('share-${post.id}')));
      expect(find.byKey(const Key('share-whatsapp')), findsOneWidget);
      expect(find.byKey(const Key('share-copy')), findsOneWidget);
      expect(find.text(LegalNotices.everyAction), findsWidgets);
    });

    testWidgets('hikaye: ekle, çubukta halka, görüntüle, sil', (t) async {
      final (app, _) = await _app();
      await _mount(t, app, const FeedScreen());
      expect(find.byKey(const Key('story-bar')), findsOneWidget);

      await _tap(t, find.byKey(const Key('story-plus')));
      expect(find.text(LegalNotices.everyAction), findsWidgets);
      // boş hikaye paylaşılmaz
      await _tap(t, find.byKey(const Key('story-share')));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('story-error')), findsOneWidget);
      expect(app.social.stories, isEmpty);

      await t.enterText(find.byKey(const Key('story-caption')), 'Bugün greyder boş');
      await t.pump();
      await _tap(t, find.byKey(const Key('story-share')));
      await t.pump(const Duration(milliseconds: 800));
      expect(app.social.activeStoriesOf(app.myId!).length, 1);

      await _tap(t, find.byKey(const Key('story-mine')));
      expect(find.byKey(const Key('story-text')), findsOneWidget);
      expect(find.textContaining('sa sonra silinir'), findsOneWidget);
      await _tap(t, find.byKey(const Key('story-delete')));
      await _tap(t, find.text('Sil'));
      await t.pump(const Duration(seconds: 1));
      expect(app.social.activeStoriesOf(app.myId!), isEmpty);
    });

    testWidgets('hikaye: başkasının hikayesi çubukta görünür ve açılır; engelleyince kaybolur', (t) async {
      final (app, _) = await _app();
      app.social.stories = [SocialStory(id: 'z', authorId: 'demo-u8', caption: 'Merhaba şantiye')];
      await _mount(t, app, const FeedScreen());
      expect(find.byKey(const Key('story-demo-u8')), findsOneWidget);
      await _tap(t, find.byKey(const Key('story-demo-u8')));
      expect(find.text('Merhaba şantiye'), findsOneWidget);
      expect(find.byKey(const Key('story-delete')), findsNothing, reason: 'başkasının hikayesi silinemez');
      await _tap(t, find.byKey(const Key('story-close')));
      await app.blockWithProof('demo-u8', reason: 'Spam veya rahatsız etme', evidencePhotoPath: '/tmp/k.jpg');
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('story-demo-u8')), findsNothing);
    });
  });
}

/// Test yardımcısı: bir sayaç widget'ının metnini okur.
String tester(WidgetTester t, Key key) {
  final w = t.widget<Column>(find.descendant(of: find.byKey(key), matching: find.byType(Column)).first);
  return w.children.whereType<Text>().map((e) => e.data ?? '').join(' ');
}
