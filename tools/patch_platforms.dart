// Flutter'ın ürettiği platform iskeletine projeye özel ayarları uygular.
// tools/prepare_platforms.sh ve .bat bu aracı otomatik çalıştırır.
//
// * Android: release derlemesi yalnızca android/key.properties içindeki gerçek
//   yükleme anahtarıyla imzalanır; anahtar yoksa Gradle derlemeyi durdurur.
// * iOS: Ana ekrandaki uygulama adı "Şantiye Ağı" olur ve standart HTTPS
//   dışında şifreleme kullanılmadığı beyan edilir (App Store'da her
//   yüklemede sorulan ihracat sorusu çıkmaz).
//
// Elle çalıştırma (proje kökünde): dart tools/patch_platforms.dart
// Tekrar çalıştırmak güvenlidir: ayar zaten uygulanmışsa dosyaya dokunulmaz.

import 'dart:io';

const String _appName = 'Şantiye Ağı';
const String _marker = 'santiye-agi: release imzası';

final List<String> _manualSteps = <String>[];

void main() {
  // Betik nereden çağrılırsa çağrılsın proje kökünde çalış.
  Directory.current = File.fromUri(Platform.script).parent.parent;
  _patchAndroidSigning();
  _patchLocationPermissions();
  _patchIosInfoPlist();
  _copyKeyPropertiesExample();
  if (_manualSteps.isEmpty) {
    stdout.writeln(
      'Platform ayarları uygulandı (Android release imzası, iOS uygulama adı).',
    );
    return;
  }
  stderr.writeln('UYARI: Bazı ayarlar otomatik uygulanamadı; elle yapın:');
  for (final step in _manualSteps) {
    stderr.writeln('  - $step');
  }
}

const String _debugSigning =
    'signingConfig = signingConfigs.getByName("debug")';

const String _imports = '''
import java.io.FileInputStream
import java.util.Properties

''';

const String _keystoreLoader =
    '''

// $_marker: android/key.properties varsa yükleme anahtarı kullanılır.
// Dosya biçimi için android/key.properties.example dosyasına bakın.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
''';

const String _signingConfigs = '''
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

''';

const String _releaseSigning =
    'signingConfig = signingConfigs.getByName("release")';

// Debug kurulumu release anahtarı istemez. Eksik anahtar release görevi
// seçildiğinde, görevler çalıştırılmadan önce açık bir hatayla bildirilir.
const String _releaseGuard = '''

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") } &&
        !keystorePropertiesFile.exists()) {
        throw GradleException("Yayın derlemesi için android/key.properties ve gerçek upload keystore zorunludur. YAYIN_REHBERI.md dosyasına bakın.")
    }
}
''';

void _patchAndroidSigning() {
  final file = File('android/app/build.gradle.kts');
  if (!file.existsSync()) {
    _manualSteps.add(
      'android/app/build.gradle.kts bulunamadı; release imzasını YAYIN_REHBERI.md (3. bölüm) adımlarıyla ekleyin.',
    );
    return;
  }
  final text = file.readAsStringSync().replaceAll('\r\n', '\n');
  if (text.contains(_marker)) return;

  final plugins = RegExp(
    r'^plugins \{[\s\S]*?^\}\n',
    multiLine: true,
  ).firstMatch(text);
  final android = RegExp(r'^android \{\n', multiLine: true).firstMatch(text);
  if (plugins == null ||
      android == null ||
      android.start < plugins.end ||
      !text.contains(_debugSigning)) {
    _manualSteps.add(
      'android/app/build.gradle.kts beklenen Flutter şablonunda değil; release imzasını elle ekleyin.',
    );
    return;
  }

  final patched = StringBuffer()
    ..write(_imports)
    ..write(text.substring(0, plugins.end))
    ..write(_keystoreLoader)
    ..write(text.substring(plugins.end, android.end))
    ..write(_signingConfigs)
    ..write(text.substring(android.end));
  file.writeAsStringSync(
    '${patched.toString().replaceFirst(_debugSigning, _releaseSigning)}$_releaseGuard',
  );
}

void _patchIosInfoPlist() {
  final file = File('ios/Runner/Info.plist');
  if (!file.existsSync()) {
    _manualSteps.add(
      'ios/Runner/Info.plist bulunamadı; Xcode\'da Display Name alanını "$_appName" yapın.',
    );
    return;
  }
  var text = file.readAsStringSync();
  final original = text;

  final displayName = RegExp(
    r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
  );
  if (displayName.hasMatch(text)) {
    text = text.replaceFirstMapped(
      displayName,
      (m) => '${m.group(1)}$_appName${m.group(2)}',
    );
  } else {
    _manualSteps.add(
      'ios/Runner/Info.plist: CFBundleDisplayName değerini "$_appName" yapın.',
    );
  }

  if (!text.contains('ITSAppUsesNonExemptEncryption')) {
    final end = text.lastIndexOf('</dict>');
    if (end >= 0) {
      text =
          '${text.substring(0, end)}\t<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>\n${text.substring(end)}';
    }
  }

  if (text != original) file.writeAsStringSync(text);
}

void _patchLocationPermissions() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var text = manifest.readAsStringSync();
    for (final name in [
      'ACCESS_COARSE_LOCATION',
      'ACCESS_FINE_LOCATION',
      'FOREGROUND_SERVICE',
      'FOREGROUND_SERVICE_LOCATION',
    ]) {
      if (!text.contains('android.permission.$name')) {
        text = text.replaceFirst(
          '<application',
          '<uses-permission android:name="android.permission.$name"/>\n    <application',
        );
      }
    }
    if (text != manifest.readAsStringSync()) manifest.writeAsStringSync(text);
  }
  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    var text = plist.readAsStringSync();
    if (!text.contains('NSLocationWhenInUseUsageDescription')) {
      text = text.replaceFirst(
        '</dict>',
        '<key>NSLocationWhenInUseUsageDescription</key>\n<string>Başlattığınız süreli konum paylaşımında konumunuz yalnız anlaşmanın diğer tarafına gösterilir. İstediğiniz an durdurabilirsiniz.</string>\n</dict>',
      );
    }
    if (!text.contains('<string>location</string>')) {
      if (text.contains('<key>UIBackgroundModes</key>')) {
        text = text.replaceFirstMapped(
          RegExp(r'(<key>UIBackgroundModes</key>\s*<array>)'),
          (m) => '${m[1]}\n<string>location</string>',
        );
      } else {
        text = text.replaceFirst(
          '</dict>',
          '<key>UIBackgroundModes</key>\n<array><string>location</string></array>\n</dict>',
        );
      }
    }
    if (text != plist.readAsStringSync()) plist.writeAsStringSync(text);
  }
}

void _copyKeyPropertiesExample() {
  final source = File('tools/android/key.properties.example');
  final target = File('android/key.properties.example');
  if (source.existsSync() &&
      Directory('android').existsSync() &&
      !target.existsSync()) {
    source.copySync(target.path);
  }
}
