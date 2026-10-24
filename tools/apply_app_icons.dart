import 'dart:io';

void main() {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final android = Directory('assets/app_icon/android');
  if (android.existsSync() &&
      Directory('android/app/src/main/res').existsSync()) {
    for (final file in android.listSync(recursive: true).whereType<File>()) {
      final relative = file.path.substring(android.path.length + 1);
      final target = File('android/app/src/main/res/$relative');
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
    }
  }
  final ios = Directory('assets/app_icon/ios');
  final target = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  if (ios.existsSync() && target.existsSync()) {
    for (final file in ios.listSync().whereType<File>()) {
      file.copySync('${target.path}/${file.uri.pathSegments.last}');
    }
  }
  stdout.writeln('Mevcut platformlara Şantiye Ağı ikonları uygulandı.');
}
