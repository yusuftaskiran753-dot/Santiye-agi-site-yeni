import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Kullanıcının profil fotoğrafını gösterir; yoksa baş harfli [Avatar]'a döner.
/// [ring] true ise etrafında hikaye halkası çizilir.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    this.radius = 20,
    this.ring = false,
  });

  final String userId;
  final String name;
  final double radius;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final path = context.select<AppState, String>((a) => a.social.avatarOf(userId));
    final face = SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Avatar(name, radius: radius),
          if (path.isNotEmpty)
            ClipOval(
              child: Image.file(
                File(path),
                key: ValueKey('avatar-$userId-$path'),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
    if (!ring) return face;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.brand, AppColors.purple],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: face,
      ),
    );
  }
}
