import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import '../../widgets/user_avatar.dart';
import '../profile/public_profile_screen.dart';
import '../trade/tender_detail_screen.dart';
import 'block_reason_sheet.dart';
import 'comments_sheet.dart';

/// Akıştaki tek paylaşım kartı: sade, geniş boşluklu, büyük düğmeli.
/// Beğen, yorum, paylaş; fotoğrafa çift dokunma ile beğeni.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});

  final SocialPost post;

  Future<void> _share(BuildContext context, String author) {
    final text =
        '$author: ${post.caption}\n\n${AppConfig.appName} · Şantiye Akışı';
    return showAppSheet<void>(
      context,
      (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gönderiyi paylaş',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const LegalNoticeBar(),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('share-whatsapp'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    shareOnWhatsApp(context, text);
                  },
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('WhatsApp\'ta paylaş', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('share-copy'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    copyText(context, text, done: 'Gönderi metni kopyalandı');
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Metni kopyala', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, AppState app) async {
    final ok = await confirm(
      context,
      'Gönderi silinsin mi?',
      message: 'Gönderi, yorumları ve beğenileriyle birlikte silinir.',
      ok: 'Sil',
      danger: true,
    );
    if (ok) await app.deletePost(post.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final name = app.social.displayName(post.authorId, me: app.me);
    final profession = app.social.identityOf(post.authorId)?.profession.label;
    final isMine = post.authorId == app.myId;
    final liked = app.social.likedBy(post.id, app.myId ?? '');
    final likes = app.social.likeCount(post.id);
    final comments = app.social.publishedComments(post.id).length;
    final tender = app.social.tenderById(post.tenderId);
    void openProfile() =>
        pushPage<void>(context, PublicProfileScreen(userId: post.authorId));
    return Container(
      key: Key('post-${post.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              children: [
                InkWell(
                  key: Key('post-author-${post.id}'),
                  borderRadius: BorderRadius.circular(30),
                  onTap: openProfile,
                  child: UserAvatar(
                    userId: post.authorId,
                    name: name,
                    radius: 22,
                    ring: app.social.activeStoriesOf(post.authorId).isNotEmpty,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: openProfile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [?profession, post.kind.label, timeAgo(post.createdAt)].join(' · '),
                          style: TextStyle(color: muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  key: Key('post-menu-${post.id}'),
                  tooltip: 'Daha fazla',
                  onSelected: (v) async {
                    if (v == 'block') {
                      final done = await showBlockReasonSheet(context, post.authorId);
                      if (done && context.mounted) {
                        showSnack(context, 'Kullanıcı engellendi');
                      }
                    } else if (v == 'delete') {
                      await _delete(context, app);
                    }
                  },
                  itemBuilder: (_) => [
                    if (isMine && post.tenderId == null)
                      const PopupMenuItem(value: 'delete', child: Text('Gönderiyi sil')),
                    if (!isMine) const PopupMenuItem(value: 'block', child: Text('Engelle')),
                  ],
                ),
              ],
            ),
          ),
          if (post.photoPath.isNotEmpty)
            GestureDetector(
              key: Key('post-photo-${post.id}'),
              onDoubleTap: () {
                if (!liked) app.toggleLike(post.id);
              },
              child: Image.file(
                File(post.photoPath),
                width: double.infinity,
                height: 320,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                ActionPill(
                  key: Key('like-${post.id}'),
                  icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? AppColors.red : null,
                  label: likes == 0 ? 'Beğen' : '$likes',
                  onTap: () => app.toggleLike(post.id),
                ),
                ActionPill(
                  key: Key('comment-${post.id}'),
                  icon: Icons.chat_bubble_outline_rounded,
                  label: comments == 0 ? 'Yorum' : '$comments',
                  onTap: () => showCommentsSheet(context, post),
                ),
                ActionPill(
                  key: Key('share-${post.id}'),
                  icon: Icons.send_outlined,
                  label: 'Paylaş',
                  onTap: () => _share(context, name),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(post.caption, style: const TextStyle(fontSize: 15.5, height: 1.45)),
          ),
          if (post.sectors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in post.sectors)
                    Text(
                      '#${s.label.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '')}',
                      style: const TextStyle(
                        color: AppColors.blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          if (tender != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton.icon(
                  key: Key('post-tender-${post.id}'),
                  icon: const Icon(Icons.gavel_rounded),
                  label: Text(
                    tender.acceptsBids() ? 'İhaleyi gör ve teklif ver' : 'İhaleyi gör',
                    style: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () => pushPage<void>(
                    context,
                    TenderDetailScreen(tenderId: tender.id),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Beğen / Yorum / Paylaş gibi büyük (en az 52 px) eylem düğmesi.
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52, minWidth: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
