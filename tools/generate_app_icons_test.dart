// Çalıştırma: flutter test tools/generate_app_icons_test.dart
// Uygulamanın mevcut Material şantiye simgesini launcher ikonlarına aktarır.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:santiye_agi/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Mevcut uygulama simgesinden platform ikonlarını üret', () async {
    final loader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await loader.load();
    Future<void> writeIcon(String path, int size) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(AppColors.brand, BlendMode.src);
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.engineering_rounded.codePoint),
          style: TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: size * 0.62,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset((size - painter.width) / 2, (size - painter.height) / 2),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path)..parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      painter.dispose();
      image.dispose();
      picture.dispose();
    }

    await writeIcon('assets/app_icon/app_icon.png', 1024);
    for (final entry in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      await writeIcon(
        'assets/app_icon/android/mipmap-${entry.key}/ic_launcher.png',
        entry.value,
      );
    }
    for (final size in [20, 29, 40, 60, 76, 83.5, 1024]) {
      for (final scale in size == 1024 ? [1] : [1, 2, 3]) {
        await writeIcon(
          'assets/app_icon/ios/Icon-App-${size.toString().replaceAll('.0', '')}x${size.toString().replaceAll('.0', '')}@$scale'
          'x.png',
          (size * scale).round(),
        );
      }
    }
    expect(File('assets/app_icon/app_icon.png').existsSync(), isTrue);
  });
}
