import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:santiye_agi/models/work_photo.dart';
import 'package:santiye_agi/screens/profile/work_gallery.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/services/portfolio_backend.dart';
import 'package:santiye_agi/state/app_state.dart';

class GalleryBackend extends LocalBackend implements PortfolioBackend {
  GalleryBackend(super.store) : super(simulate: false);
  final photos = [
    const WorkPhoto(
      id: 'photo',
      ownerId: 'me',
      caption: 'Tamamlanan temel işi',
    ),
  ];
  bool failOnce = false;
  int deleted = 0;
  @override
  Future<List<WorkPhoto>> fetchWorkPhotos(String userId) async {
    if (failOnce) {
      failOnce = false;
      throw Exception('Offline');
    }
    return List.of(photos);
  }

  @override
  Future<Uint8List> fetchWorkPhotoBytes(String id) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1cAAAAASUVORK5CYII=',
  );
  @override
  Future<void> deleteWorkPhoto(String id) async {
    deleted++;
    photos.removeWhere((p) => p.id == id);
  }

  @override
  Future<WorkPhoto> uploadWorkPhoto(
    Uint8List bytes,
    String caption, {
    required String id,
  }) async => throw UnimplementedError();
}

Future<GalleryBackend> mount(
  WidgetTester tester, {
  String profile = 'me',
  bool fail = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  final backend = GalleryBackend(store)..failOnce = fail;
  final app = AppState(backend, store);
  addTearDown(app.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: WorkGallery(userId: profile)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  testWidgets(
    'Ziyaretçi fotoğrafı ve açıklamayı görür; değiştirme düğmeleri yoktur',
    (tester) async {
      await mount(tester, profile: 'other');
      expect(find.text('Tamamlanan temel işi'), findsOneWidget);
      expect(find.byTooltip('Fotoğrafı sil'), findsNothing);
      expect(find.text('İş fotoğrafı ekle'), findsNothing);
    },
  );
  testWidgets(
    'Sahibi fotoğraf silmeyi iptal edebilir ve onaylayınca galeri yenilenir',
    (tester) async {
      final backend = await mount(tester);
      await tester.tap(find.byTooltip('Fotoğrafı sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(backend.deleted, 0);
      await tester.tap(find.byTooltip('Fotoğrafı sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
      await tester.pumpAndSettle();
      expect(backend.deleted, 1);
      expect(find.text('Henüz iş fotoğrafı paylaşılmadı.'), findsOneWidget);
    },
  );
  testWidgets('Bağlantı hatasında tekrar dene fotoğrafları yeniden yükler', (
    tester,
  ) async {
    await mount(tester, fail: true);
    expect(find.text('İş fotoğrafları yüklenemedi.'), findsOneWidget);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Tamamlanan temel işi'), findsOneWidget);
  });
}
