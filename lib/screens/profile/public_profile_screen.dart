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
                      if (!await confirm(context, 'Kullanıcı engellensin mi?',
                          message: 'İlanlarını görmezsiniz ve birbirinize teklif gönderemezsiniz.', ok: 'Engelle', danger: true)) {
                        return;
                      }
                      await app.block(widget.userId);
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
              _ProfileHeader(profile: profile),
              WorkGallery(userId: widget.userId),
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
  const _ProfileHeader({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final since = p.memberMonths;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(p.displayName, radius: 30),
                const SizedBox(width: 14),
                Expanded(
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
                    ],
                  ),
                ),
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
