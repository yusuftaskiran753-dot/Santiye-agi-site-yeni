import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../common/report_sheet.dart';
import '../listings/cards.dart';
import '../listings/listing_detail_screen.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/legal_notice_bar.dart';
import '../../widgets/user_avatar.dart';
import '../social/block_reason_sheet.dart';
import '../social/composer_screen.dart';
import '../social/post_detail_screen.dart';
import '../social/profile_photo_actions.dart';
import 'work_gallery.dart';

/// Bir kullanıcının herkese açık profili: rozetler, puanlar, yorumlar, ilanları.
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.userId, this.initial});

  final String userId;
  final PublicProfile? initial;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late Future<(PublicProfile?, List<Rating>)> _future = _load();

  Future<(PublicProfile?, List<Rating>)> _load() async {
    final app = context.read<AppState>();
    final results = await Future.wait<Object?>([
      app.fetchProfile(widget.userId),
      app.fetchRatingsFor(widget.userId),
    ]);
    return (results[0] as PublicProfile?, results[1]! as List<Rating>);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isMe = widget.userId == app.myId;
    final blocked = app.isBlocked(widget.userId);
    final listings = [
      for (final k in ListingKind.values)
        ...(isMe ? app.mine(k) : app.market(k)).where((l) => l.ownerId == widget.userId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(isMe ? 'Profilim (herkese görünen)' : 'Profil'),
        actions: [
          if (!isMe)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'report') {
                  await showReportSheet(context, targetType: 'profil', targetId: widget.userId, ownerId: widget.userId);
                } else if (v == 'block') {
                  try {
                    if (blocked) {
                      await app.unblock(widget.userId);
                    } else {
                      // Sebep seçimi ve kanıt fotoğrafı zorunlu.
                      if (!await showBlockReasonSheet(context, widget.userId)) return;
                    }
                    if (context.mounted) showSnack(context, blocked ? 'Engel kaldırıldı' : 'Kullanıcı engellendi');
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
                PopupMenuItem(value: 'block', child: Text(blocked ? 'Engeli kaldır' : 'Engelle')),
              ],
            ),
        ],
      ),
      body: FutureBuilder<(PublicProfile?, List<Rating>)>(
        future: _future,
        builder: (context, snap) {
          final profile = snap.data?.$1 ?? widget.initial;
          final ratings = snap.data?.$2 ?? const <Rating>[];
          if (snap.hasError && profile == null) {
            return EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Profil yüklenemedi',
              actionLabel: 'Tekrar dene',
              onAction: () => setState(() { _future = _load(); }),
            );
          }
          if (profile == null) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _ProfileHeader(profile: profile, isMe: isMe),
              if (!isMe && !blocked) _FollowButton(userId: widget.userId),
              WorkGallery(userId: widget.userId),
              _PostsGrid(userId: widget.userId, isMe: isMe),
              if (blocked) ...[
                const SizedBox(height: 12),
                const InfoBanner(text: 'Bu kullanıcıyı engellediniz.', icon: Icons.block, color: AppColors.red),
              ],
              const SectionTitle('Değerlendirmeler'),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              else if (ratings.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Henüz değerlendirme yok. Puanlar yalnızca uygulamada tamamlanan anlaşmalardan sonra verilebilir.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                for (final r in ratings.take(30)) _RatingTile(rating: r),
              if (listings.isNotEmpty) ...[
                SectionTitle('İlanları (${listings.length})'),
                for (final l in listings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ListingRow(listing: l, onTap: () => openListing(context, l)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.isMe});

  final PublicProfile profile;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final since = p.memberMonths;
    final cover = app.social.coverOf(p.id);
    final posts = app.wallOf(p.id).length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 172,
            child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 130,
                child: Container(
                key: const Key('profile-cover'),
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.brand, AppColors.purple],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: cover.isEmpty
                    ? null
                    : Image.file(
                        File(cover),
                        key: ValueKey('cover-$cover'),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
              )),
              if (isMe)
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton.filledTonal(
                    key: const Key('cover-edit'),
                    tooltip: 'Kapak fotoğrafını değiştir',
                    onPressed: () => changeCoverPhoto(context),
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                ),
              Positioned(
                left: 16,
                top: 88,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: UserAvatar(
                        userId: p.id,
                        name: p.displayName,
                        radius: 40,
                        ring: app.social.activeStoriesOf(p.id).isNotEmpty,
                      ),
                    ),
                    if (isMe)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: IconButton.filled(
                          key: const Key('avatar-edit'),
                          tooltip: 'Profil fotoğrafını değiştir',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => changeProfilePhoto(context),
                          icon: const Icon(Icons.photo_camera_outlined, size: 20),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          )),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (p.company.isNotEmpty) Text(p.name, style: TextStyle(color: muted)),
                const SizedBox(height: 2),
                Text(
                  '${p.role.label}${p.city.isEmpty ? '' : ' · ${p.city}'}',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _Count(key: const Key('count-posts'), value: posts, label: 'Gönderi')),
                    Expanded(child: _Count(key: const Key('count-followers'), value: app.social.followerCount(p.id), label: 'Takipçi')),
                    Expanded(child: _Count(key: const Key('count-following'), value: app.social.followingCount(p.id), label: 'Takip')),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        value: p.ratingCount == 0 ? '—' : p.ratingAvg.toStringAsFixed(1).replaceAll('.', ','),
                        label: '${p.ratingCount} değerlendirme',
                        icon: Icons.star_rounded,
                        color: const Color(0xFFF5A623),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        value: '${p.dealsCompleted}',
                        label: 'tamamlanan iş',
                        icon: Icons.task_alt_rounded,
                        color: AppColors.green,
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        value: since <= 0 ? 'Yeni' : (since >= 12 ? '${since ~/ 12} yıl' : '$since ay'),
                        label: 'üyelik',
                        icon: Icons.calendar_month_outlined,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TrustBadges(p),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({super.key, required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Başkasının profilinde büyük "Takip et / Takiptesin" düğmesi.
class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final following = app.following.contains(userId);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: AsyncButton(
          key: const Key('follow-button'),
          label: following ? 'Takiptesin' : 'Takip et',
          icon: following ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
          outlined: following,
          onPressed: () => following ? app.unfollow(userId) : app.follow(userId),
        ),
      ),
    );
  }
}

/// Instagram profili gibi 3 sütunlu gönderi ızgarası.
class _PostsGrid extends StatelessWidget {
  const _PostsGrid({required this.userId, required this.isMe});

  final String userId;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final posts = app.wallOf(userId);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('Gönderiler (${posts.length})'),
        const LegalNoticeBar(detail: LegalNotices.photo),
        const SizedBox(height: 12),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Henüz gönderi yok.', style: TextStyle(color: muted)),
                if (isMe) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('first-post'),
                      onPressed: () => pushPage<void>(context, const ComposerScreen()),
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('İlk gönderini paylaş', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final p in posts)
                InkWell(
                  key: Key('grid-post-${p.id}'),
                  onTap: () => pushPage<void>(context, PostDetailScreen(postId: p.id)),
                  child: p.photoPath.isNotEmpty
                      ? Image.file(
                          File(p.photoPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _TextTile(text: p.caption),
                        )
                      : _TextTile(text: p.caption),
                ),
            ],
          ),
      ],
    );
  }
}

class _TextTile extends StatelessWidget {
  const _TextTile({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: AppColors.brand.withValues(alpha: 0.08),
      child: Text(
        text,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, height: 1.3),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, required this.icon, required this.color});

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final r = rating;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(r.fromName, style: const TextStyle(fontWeight: FontWeight.w700))),
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= r.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 16,
                    color: const Color(0xFFF5A623),
                  ),
              ],
            ),
            if (r.comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.comment, style: const TextStyle(height: 1.4)),
            ],
            const SizedBox(height: 4),
            Text(formatDate(r.createdAt), style: TextStyle(fontSize: 12, color: muted)),
          ],
        ),
      ),
    );
  }
}
