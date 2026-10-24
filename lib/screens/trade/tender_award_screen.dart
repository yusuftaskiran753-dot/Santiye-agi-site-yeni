import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/social_rules.dart';
import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';

/// İhale bitince "En iyi teklifi seç" ekranı: teklifler en düşük tutardan
/// yükseğe sıralanır, en düşük teklif önerilir; ihaleyi açan kazananı seçer.
class TenderAwardScreen extends StatefulWidget {
  const TenderAwardScreen({super.key, required this.tenderId});

  final String tenderId;

  @override
  State<TenderAwardScreen> createState() => _TenderAwardScreenState();
}

class _TenderAwardScreenState extends State<TenderAwardScreen> {
  String? _selected;

  Future<void> _award(Tender tender, TenderBid bid) async {
    final app = context.read<AppState>();
    final name = app.social.displayName(bid.bidderId, me: app.me);
    final ok = await confirm(
      context,
      'Kazanan: $name',
      message:
          '${formatTL(bid.amount)} teklifi seçilecek ve ihale kapanacak. '
          'Seçilen kişiyle telefon paylaşımı da onaylanır. Bu işlem geri alınamaz.',
      ok: 'Kazananı seç',
    );
    if (!ok || !mounted) return;
    await app.awardTender(tender.id, bid.id);
    if (!mounted) return;
    Navigator.pop(context, true);
    showSuccess(context, 'İhale $name firmasına verildi.');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tender = app.social.tenderById(widget.tenderId);
    if (tender == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('En iyi teklifi seç')),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'İhale bulunamadı',
        ),
      );
    }
    final bids = app.social.bidsFor(tender.id); // en düşük tutar önce
    final best = SocialRules.bestBid(bids);
    final selectedId = _selected ?? best?.id;
    final selected = bids.where((b) => b.id == selectedId).firstOrNull;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('En iyi teklifi seç')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            tender.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${bids.length} teklif · En düşük teklif önerilir; açıklamaları okuyup '
            'kararı siz verirsiniz.',
            style: TextStyle(color: muted, height: 1.35),
          ),
          const SizedBox(height: 14),
          const LegalNoticeBar(detail: LegalNotices.award),
          const SizedBox(height: 18),
          if (bids.isEmpty)
            const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Bu ihaleye teklif gelmedi',
              message: 'Teklif olmadığı için kazanan seçilemez.',
            ),
          for (final b in bids)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _BidChoice(
                bid: b,
                isBest: b.id == best?.id,
                selected: b.id == selectedId,
                onTap: () => setState(() => _selected = b.id),
              ),
            ),
        ],
      ),
      bottomNavigationBar: selected == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 56,
                  child: AsyncButton(
                    label: 'Seçili teklifi kazanan yap',
                    icon: Icons.emoji_events_outlined,
                    onPressed: () => _award(tender, selected),
                  ),
                ),
              ),
            ),
    );
  }
}

class _BidChoice extends StatelessWidget {
  const _BidChoice({
    required this.bid,
    required this.isBest,
    required this.selected,
    required this.onTap,
  });

  final TenderBid bid;
  final bool isBest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final name = app.social.displayName(bid.bidderId, me: app.me);
    final profession = app.social.identityOf(bid.bidderId)?.profession.label;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: Key('award-bid-${bid.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(name, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (profession != null)
                          Text(profession, style: TextStyle(color: muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? scheme.primary : muted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    formatTL(bid.amount),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isBest)
                    const Pill(
                      'En düşük teklif',
                      color: AppColors.green,
                      icon: Icons.thumb_up_alt_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(bid.note, style: const TextStyle(height: 1.4)),
              if (bid.referenceNote.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Referans: ${bid.referenceNote}',
                  style: TextStyle(color: muted, fontSize: 13, height: 1.35),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    bid.contactApproved
                        ? 'Telefon paylaşımı onaylı'
                        : 'Telefon gizli',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
