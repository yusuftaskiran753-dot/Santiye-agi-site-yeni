// Render existing app artwork and vector layout for Google Play; no app data is changed.
// flutter test tools/generate_play_assets_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Google Play icon and feature graphic export', () async {
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
    final fontDirectory =
        Platform.environment['PLAY_ASSET_FONT_DIR'] ?? r'C:\Windows\Fonts';
    final fonts = FontLoader('PlaySans');
    for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
      fonts.addFont(
        Future.value(
          ByteData.sublistView(
            await File('$fontDirectory/$name').readAsBytes(),
          ),
        ),
      );
    }
    await fonts.load();

    void text(
      Canvas canvas,
      String value,
      Offset position, {
      double size = 20,
      Color color = AppColors.ink,
      FontWeight weight = FontWeight.w400,
      double width = 600,
      double spacing = 0,
      double height = 1.2,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'PlaySans',
            fontSize: size,
            color: color,
            fontWeight: weight,
            letterSpacing: spacing,
            height: height,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      painter.paint(canvas, position);
      painter.dispose();
    }

    void icon(
      Canvas canvas,
      IconData value,
      Offset center,
      double size,
      Color color,
    ) {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(value.codePoint),
          style: TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: size,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
      painter.dispose();
    }

    Future<void> render(
      String path,
      int width,
      int height,
      void Function(Canvas) paint,
    ) async {
      final recorder = ui.PictureRecorder();
      paint(Canvas(recorder));
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path)..parent.createSync(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    }

    await render('output/google-play/01-uygulama-simgesi-512.png', 512, 512, (
      canvas,
    ) {
      canvas.drawColor(AppColors.brand, BlendMode.src);
      icon(
        canvas,
        Icons.engineering_rounded,
        const Offset(256, 256),
        512 * .62,
        Colors.white,
      );
    });
    await render(
      'output/google-play/02-ozellik-grafigi-1024x500.png',
      1024,
      500,
      (canvas) {
        canvas.drawColor(const Color(0xFFF7F4EF), BlendMode.src);
        final panel = Path()
          ..moveTo(705, 0)
          ..lineTo(1024, 0)
          ..lineTo(1024, 500)
          ..lineTo(626, 500)
          ..close();
        canvas.drawPath(panel, Paint()..color = AppColors.brand);
        canvas.save();
        canvas.clipPath(panel);
        for (var i = 0; i < 9; i++) {
          canvas.drawLine(
            Offset(590 + i * 66.0, 0),
            Offset(510 + i * 66.0, 500),
            Paint()
              ..color = const Color(0x13FFFFFF)
              ..strokeWidth = 1,
          );
        }
        for (var i = 0; i < 9; i++) {
          canvas.drawLine(
            Offset(600, i * 66.0),
            Offset(1024, i * 66.0),
            Paint()
              ..color = const Color(0x13FFFFFF)
              ..strokeWidth = 1,
          );
        }
        canvas.drawCircle(
          const Offset(914, 122),
          184,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x22FFFFFF),
        );
        canvas.drawCircle(
          const Offset(914, 122),
          218,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x15FFFFFF),
        );
        canvas.restore();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(56, 45, 48, 48),
            const Radius.circular(13),
          ),
          Paint()..color = AppColors.brand,
        );
        icon(
          canvas,
          Icons.engineering_rounded,
          const Offset(80, 69),
          33,
          Colors.white,
        );
        text(
          canvas,
          'Şantiye Ağı',
          const Offset(118, 45),
          size: 32,
          weight: FontWeight.w700,
        );
        text(
          canvas,
          'İNŞAAT VE NAKLİYE PLATFORMU',
          const Offset(58, 119),
          size: 12,
          color: const Color(0xFF806853),
          spacing: 1.6,
          weight: FontWeight.w700,
        );
        text(
          canvas,
          'Şantiyenin\npazar yeri.',
          const Offset(54, 156),
          size: 55,
          weight: FontWeight.w700,
          height: 1.03,
          width: 530,
        );
        text(
          canvas,
          'Yük, makine, malzeme ve personel.\nİlan verin, teklifleri yönetin.',
          const Offset(58, 294),
          size: 21,
          height: 1.4,
          color: const Color(0xFF5E6875),
          width: 545,
        );
        var x = 56.0;
        const labels = ['Yük', 'Makine', 'Malzeme', 'Personel'];
        const symbols = [
          Icons.local_shipping_rounded,
          Icons.construction_rounded,
          Icons.inventory_2_rounded,
          Icons.engineering_rounded,
        ];
        const widths = [88.0, 106.0, 118.0, 116.0];
        for (var i = 0; i < labels.length; i++) {
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 400, widths[i], 42),
            const Radius.circular(21),
          );
          canvas.drawRRect(rect, Paint()..color = Colors.white);
          canvas.drawRRect(
            rect,
            Paint()
              ..color = const Color(0xFFE6DDD3)
              ..style = PaintingStyle.stroke,
          );
          icon(canvas, symbols[i], Offset(x + 23, 421), 19, AppColors.brand);
          text(
            canvas,
            labels[i],
            Offset(x + 40, 410),
            size: 14,
            weight: FontWeight.w700,
          );
          x += widths[i] + 10;
        }
        icon(
          canvas,
          Icons.engineering_rounded,
          const Offset(840, 249),
          248,
          Colors.white,
        );
        text(
          canvas,
          'İLAN  ·  TEKLİF  ·  ANLAŞMA',
          const Offset(715, 405),
          size: 13,
          color: Colors.white,
          spacing: 1.1,
          weight: FontWeight.w700,
          width: 280,
        );
      },
    );
  });
}
