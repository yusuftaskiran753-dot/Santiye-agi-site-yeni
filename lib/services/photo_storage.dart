import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Kamera / galeriden fotoğraf alır ve uygulamanın kalıcı klasörüne kopyalar.
///
/// image_picker'ın verdiği yol geçici (önbellek) klasördedir ve sistem tarafından
/// silinebilir; profil, kapak, gönderi ve hikaye fotoğrafları bu yüzden
/// `social_media/` altına kopyalanır.
class PhotoStorage {
  const PhotoStorage._();

  static const _folder = 'social_media';

  /// Testlerde gerçek kamera / galeri yerine kullanılır.
  static Future<String?> Function(ImageSource source)? debugPick;

  /// [source]'tan bir fotoğraf seçtirir; vazgeçilirse null döner.
  static Future<String?> pick(ImageSource source, {double maxWidth = 1600}) async {
    final fake = debugPick;
    if (fake != null) return fake(source);
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: maxWidth,
      imageQuality: 88,
    );
    if (file == null) return null;
    return persist(file.path);
  }

  /// [path]'taki dosyayı kalıcı klasöre kopyalar. Kopyalanamazsa özgün yolu döner.
  static Future<String> persist(String path) async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/$_folder');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dot = path.lastIndexOf('.');
      final ext = dot > path.lastIndexOf('/') && dot >= 0 ? path.substring(dot) : '.jpg';
      final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}$ext';
      await File(path).copy(dest);
      return dest;
    } catch (_) {
      return path;
    }
  }

  /// Yalnızca kendi kalıcı klasörümüzdeki dosyayı siler (başkasının dosyasına dokunmaz).
  static Future<void> deleteOwned(String path) async {
    if (path.isEmpty || !path.contains('/$_folder/')) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Silinemeyen dosya sessizce bırakılır.
    }
  }
}
