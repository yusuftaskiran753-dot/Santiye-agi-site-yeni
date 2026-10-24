import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/santiye_constants.dart';
import '../../models/social.dart';
import '../../models/trade.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import '../trade/tender_detail_screen.dart';
import '../trade/tender_list_screen.dart';
import 'block_reason_sheet.dart';
import 'comments_sheet.dart';
import 'composer_screen.dart';

/// Şantiye Akışı: sade, beyaz zeminli, bol boşluklu (Instagram benzeri) akış.
/// Kendi sektörünüzdeki ve takip ettiklerinizin paylaşımları görünür.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  SocialPostKind? _kind;

  Future<void> _newPost() async {
    final kind = await showAppSheet<SocialPostKind>(
      context,
      (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ne paylaşmak istersiniz?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              for (final k in const [
                SocialPostKind.work,
                SocialPostKind.jobSeek,
                SocialPostKind.machineSeek,
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, k),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(k.label, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (kind != null && mounted) {
      await pushPage<void>(context, ComposerScreen(kind: kind));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final posts = [
      for (final p in app.feedPosts)
        if (_kind == null || p.kind == _kind) p,
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Şantiye Akışı'),
        actions: [
          IconButton(
            key: const Key('feed-tenders'),
            tooltip: 'İhaleler',
            iconSize: 28,
            onPressed: () => pushPage<void>(context, const TenderListScreen()),
            icon: const Icon(Icons.gavel_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('feed-new-post'),
        onPressed: _newPost,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Paylaş', style: TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          const LegalNoticeBar(detail: LegalNotices.post),
          const SizedBox(height: 16),
          _IdentityStrip(app: app),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ChoiceRow<SocialPostKind>(
              padding: EdgeInsets.zero,
              values: SocialPostKind.values,
              selected: _kind,
              allLabel: 'Tümü',
              labelOf: (k) => k.label,
              onSelected: (k) => setState(() => _kind = k),
            ),
          ),
          const SizedBox(height: 24),
          if (posts.isEmpty)
            const EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'Akış boş',
              message:
                  'Sektörünüzdeki paylaşımlar burada görünür. İlk paylaşımı siz yapın.',
            ),
          for (final p in posts)
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: PostCard(post: p),
            ),
        ],
      ),
    );
  }
}

class _IdentityStrip extends StatelessWidget {
  const _IdentityStrip({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final id = app.myIdentity;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                id.profession.label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                id.sectors.isEmpty
                    ? 'Sektör seçilmemiş'
                    : id.sectors.map((s) => s.label).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
        TextButton(
          key: const Key('feed-identity'),
          onPressed: () => showAppSheet<void>(context, (_) => const _IdentitySheet()),
          child: const Text('Düzenle'),
        ),
      ],
    );
  }
}

/// Akıştaki tek paylaşım kartı: sade, geniş boşluklu, büyük düğmeli.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});

  final SocialPost post;

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
                Avatar(name, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          ?profession,
                          post.kind.label,
                          timeAgo(post.createdAt),
                        ].join(' · '),
                        style: TextStyle(color: muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (!isMine)
                  PopupMenuButton<String>(
                    tooltip: 'Daha fazla',
                    onSelected: (v) async {
                      if (v == 'block') {
                        final done = await showBlockReasonSheet(context, post.authorId);
                        if (done && context.mounted) {
                          showSnack(context, 'Kullanıcı engellendi');
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'block', child: Text('Engelle')),
                    ],
                  ),
              ],
            ),
          ),
          if (post.photoPath.isNotEmpty)
            ClipRRect(
              child: Image.file(
                File(post.photoPath),
                width: double.infinity,
                height: 300,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                _ActionButton(
                  key: Key('like-${post.id}'),
                  icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? AppColors.red : null,
                  label: likes == 0 ? 'Beğen' : '$likes',
                  onTap: () => app.toggleLike(post.id),
                ),
                _ActionButton(
                  key: Key('comment-${post.id}'),
                  icon: Icons.chat_bubble_outline_rounded,
                  label: comments == 0 ? 'Yorum' : '$comments',
                  onTap: () => showCommentsSheet(context, post),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              post.caption,
              style: const TextStyle(fontSize: 15.5, height: 1.45),
            ),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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
              Text(
                label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Meslek ve sektör seçimi (akışta kimlerle karşılaşacağınızı belirler).
class _IdentitySheet extends StatefulWidget {
  const _IdentitySheet();

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  late TradeProfession _profession;
  late Set<WorkSector> _sectors;

  @override
  void initState() {
    super.initState();
    final id = context.read<AppState>().myIdentity;
    _profession = id.profession;
    _sectors = {...id.sectors};
  }

  Future<void> _save() async {
    if (_sectors.isEmpty) {
      showSnack(context, 'En az bir sektör seçin.');
      return;
    }
    await context.read<AppState>().updateMyIdentity(
      profession: _profession,
      sectors: _sectors.toList(),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mesleğim ve sektörüm',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          for (final g in kMeslekGruplari.entries) ...[
            FieldLabel(g.key),
            ChoiceWrap<TradeProfession>(
              values: g.value,
              selected: _profession,
              labelOf: (p) => p.label,
              onSelected: (p) => setState(() => _profession = p),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          const FieldLabel('Sektör'),
          MultiChoiceWrap<WorkSector>(
            values: [...kSektorler, ...WorkSector.values.where((s) => !kSektorler.contains(s))],
            selected: _sectors,
            labelOf: (s) => s.label,
            onChanged: (s) => setState(() => _sectors = s),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: AsyncButton(label: 'Kaydet', onPressed: _save),
          ),
        ],
      ),
    );
  }
}
