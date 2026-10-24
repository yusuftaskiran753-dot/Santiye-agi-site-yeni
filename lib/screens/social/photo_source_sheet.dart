import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/photo_storage.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';

enum PhotoChoice { camera, gallery, remove }

/// "Kamera / Galeri / Kaldır" seçim penceresi.
Future<PhotoChoice?> showPhotoSourceSheet(
  BuildContext context, {
  required String title,
  bool canRemove = false,
}) => showAppSheet<PhotoChoice>(
  context,
  (ctx) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const LegalNoticeBar(detail: LegalNotices.photo),
          const SizedBox(height: 16),
          _Option(
            key: const Key('photo-camera'),
            icon: Icons.photo_camera_outlined,
            label: 'Kamera ile çek',
            onTap: () => Navigator.pop(ctx, PhotoChoice.camera),
          ),
          const SizedBox(height: 10),
          _Option(
            key: const Key('photo-gallery'),
            icon: Icons.photo_library_outlined,
            label: 'Galeriden seç',
            onTap: () => Navigator.pop(ctx, PhotoChoice.gallery),
          ),
          if (canRemove) ...[
            const SizedBox(height: 10),
            _Option(
              key: const Key('photo-remove'),
              icon: Icons.delete_outline_rounded,
              label: 'Fotoğrafı kaldır',
              danger: true,
              onTap: () => Navigator.pop(ctx, PhotoChoice.remove),
            ),
          ],
        ],
      ),
    ),
  ),
);

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: danger ? OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color!)) : null,
        icon: Icon(icon, size: 26),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}

/// Kullanıcıya kaynak sorar ve seçilen fotoğrafı kalıcı klasöre alır.
/// Vazgeçilirse null; "kaldır" seçilirse boş metin ('') döner.
Future<String?> choosePhoto(
  BuildContext context, {
  required String title,
  bool canRemove = false,
}) async {
  final choice = await showPhotoSourceSheet(context, title: title, canRemove: canRemove);
  if (choice == null) return null;
  if (choice == PhotoChoice.remove) return '';
  try {
    return await PhotoStorage.pick(
      choice == PhotoChoice.camera ? ImageSource.camera : ImageSource.gallery,
    );
  } catch (_) {
    if (context.mounted) {
      showSnack(
        context,
        choice == PhotoChoice.camera
            ? 'Kamera açılamadı. Galeriden seçmeyi deneyin.'
            : 'Fotoğraf seçilemedi.',
      );
    }
    return null;
  }
}
