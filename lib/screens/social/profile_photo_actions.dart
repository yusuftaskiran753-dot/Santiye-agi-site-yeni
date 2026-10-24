import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'photo_source_sheet.dart';

/// Profil fotoğrafını kamera / galeri ile değiştirir ya da kaldırır.
Future<void> changeProfilePhoto(BuildContext context) async {
  final app = context.read<AppState>();
  final path = await choosePhoto(
    context,
    title: 'Profil fotoğrafı',
    canRemove: app.myAvatarPath.isNotEmpty,
  );
  if (path == null) return;
  try {
    if (path.isEmpty) {
      await app.removeProfilePhoto();
    } else {
      await app.setProfilePhoto(path);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Kapak fotoğrafını kamera / galeri ile değiştirir ya da kaldırır.
Future<void> changeCoverPhoto(BuildContext context) async {
  final app = context.read<AppState>();
  final path = await choosePhoto(
    context,
    title: 'Kapak fotoğrafı',
    canRemove: app.social.coverOf(app.myId ?? '').isNotEmpty,
  );
  if (path == null) return;
  try {
    if (path.isEmpty) {
      await app.removeCoverPhoto();
    } else {
      await app.setCoverPhoto(path);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
