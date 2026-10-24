import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import 'post_card.dart';

/// Tek gönderi (profildeki ızgaradan açılır): fotoğraf, beğeni, yorum, paylaş.
class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final SocialPost? post = app.social.posts.where((p) => p.id == postId).firstOrNull;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Gönderi'),
      ),
      body: post == null
          ? const EmptyState(icon: Icons.search_off_rounded, title: 'Gönderi bulunamadı')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const LegalNoticeBar(detail: LegalNotices.post),
                const SizedBox(height: 16),
                PostCard(post: post),
              ],
            ),
    );
  }
}
