import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/santiye_constants.dart';
import '../../models/social.dart';
import '../../models/trade.dart';
import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import '../trade/tender_list_screen.dart';
import 'composer_screen.dart';
import 'post_card.dart';
import 'story_bar.dart';

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
          const StoryBar(),
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          Text(
            LegalNotices.responsibility,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const LegalLinks(),
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
