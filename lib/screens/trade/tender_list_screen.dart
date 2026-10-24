import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import 'tender_create_screen.dart';
import 'tender_detail_screen.dart';

/// İhaleler: açık ve biten ihaleler. İhale açma yetkisi olanlar (müteahhit,
/// şantiye şefi) "İhale aç" düğmesini görür.
class TenderListScreen extends StatelessWidget {
  const TenderListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tenders = [
      for (final t in app.social.tenders)
        if (!app.isBlocked(t.ownerId)) t,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final canOpen = app.myIdentity.profession.canOpenTender;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('İhaleler')),
      floatingActionButton: canOpen
          ? FloatingActionButton.extended(
              key: const Key('tender-create'),
              onPressed: () => pushPage<void>(context, const TenderCreateScreen()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('İhale aç'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          const LegalNoticeBar(detail: LegalNotices.tender),
          const SizedBox(height: 18),
          if (tenders.isEmpty)
            const EmptyState(
              icon: Icons.gavel_outlined,
              title: 'Henüz ihale yok',
              message: 'Açılan ihaleler burada görünür.',
            ),
          for (final t in tenders)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _TenderCard(tender: t),
            ),
        ],
      ),
    );
  }
}

class _TenderCard extends StatelessWidget {
  const _TenderCard({required this.tender});
  final Tender tender;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final mine = tender.ownerId == app.myId;
    final bidCount = app.social.bidsFor(tender.id).length;
    final (label, color) = tender.status == TenderStatus.awarded
        ? ('Verildi', AppColors.green)
        : tender.needsAward()
        ? ('Teklifler bitti', AppColors.amber)
        : ('Teklif alıyor', AppColors.blue);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        key: Key('tender-card-${tender.id}'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => pushPage<void>(context, TenderDetailScreen(tenderId: tender.id)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Pill(label, color: color),
                  if (mine) ...[
                    const SizedBox(width: 8),
                    const Pill('Sizin ihaleniz', color: AppColors.purple),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                tender.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25),
              ),
              const SizedBox(height: 6),
              Text(
                '${app.social.displayName(tender.ownerId, me: app.me)} · ${tender.city}',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.request_quote_outlined, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Text('$bidCount teklif', style: TextStyle(color: muted)),
                  if (tender.closesAt != null) ...[
                    const SizedBox(width: 14),
                    Icon(Icons.schedule_rounded, size: 16, color: muted),
                    const SizedBox(width: 6),
                    Text(formatShortDate(tender.closesAt!), style: TextStyle(color: muted)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
