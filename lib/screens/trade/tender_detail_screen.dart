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
import '../listings/contact_sheet.dart';
import 'bid_sheet.dart';
import 'tender_award_screen.dart';

/// İhale ayrıntısı. İhaleyi açan tüm teklifleri görür, telefon paylaşımını
/// onaylar, süre dolunca kazananı seçer. Teklif verenler yalnızca kendi
/// teklifini görür; telefon numaraları onaydan önce kimseye gösterilmez.
class TenderDetailScreen extends StatelessWidget {
  const TenderDetailScreen({super.key, required this.tenderId});

  final String tenderId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tender = app.social.tenderById(tenderId);
    if (tender == null) {
      return Scaffold(
        appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('İhale')),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'İhale bulunamadı',
        ),
      );
    }
    final myId = app.myId ?? '';
    final isOwner = tender.ownerId == myId;
    final bids = app.social.bidsFor(tender.id);
    final myBid = app.social.bidOf(tender.id, myId);
    final canBid = SocialRules.canBid(
      tender: tender,
      profession: app.myIdentity.profession,
      myId: myId,
    );
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('İhale')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              _StatusPill(tender: tender),
              const Spacer(),
              Text(timeAgo(tender.createdAt), style: TextStyle(color: muted, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tender.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            '${app.social.displayName(tender.ownerId, me: app.me)} · ${tender.city}',
            style: TextStyle(color: muted),
          ),
          if (tender.closesAt != null) ...[
            const SizedBox(height: 4),
            Text(
              tender.isExpired()
                  ? 'Teklif süresi doldu (${formatDateTime(tender.closesAt!)})'
                  : 'Son teklif: ${formatDateTime(tender.closesAt!)}',
              style: TextStyle(color: muted),
            ),
          ],
          const SizedBox(height: 16),
          if (tender.detail.trim().isNotEmpty)
            Text(tender.detail, style: const TextStyle(fontSize: 15.5, height: 1.45)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in tender.sectors) Pill(s.label, color: AppColors.blue),
              for (final p in tender.allowedProfessions)
                Pill(p.label, color: AppColors.grey),
            ],
          ),
          const SizedBox(height: 18),
          const LegalNoticeBar(detail: LegalNotices.phoneHidden),
          const SizedBox(height: 22),
          if (isOwner)
            ..._ownerSection(context, app, tender, bids)
          else
            ..._bidderSection(context, app, tender, myBid, canBid, bids.length),
        ],
      ),
    );
  }

  List<Widget> _ownerSection(
    BuildContext context,
    AppState app,
    Tender tender,
    List<TenderBid> bids,
  ) {
    final best = SocialRules.bestBid(bids);
    return [
      if (tender.needsAward())
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoBanner(
                title: 'İhale bitti',
                text: bids.isEmpty
                    ? 'Bu ihaleye teklif gelmedi.'
                    : 'Teklifleri inceleyip en iyi teklifi seçin.',
                icon: Icons.flag_outlined,
                color: AppColors.green,
              ),
              if (bids.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('tender-award'),
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: const Text(
                      'En iyi teklifi seç',
                      style: TextStyle(fontSize: 16),
                    ),
                    onPressed: () => pushPage<void>(
                      context,
                      TenderAwardScreen(tenderId: tender.id),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      if (tender.acceptsBids())
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: AsyncButton(
              label: 'Teklif almayı bitir',
              icon: Icons.stop_circle_outlined,
              outlined: true,
              onPressed: () async {
                final ok = await confirm(
                  context,
                  'Teklif almayı bitir?',
                  message: 'Yeni teklif alınmaz. Sonra en iyi teklifi seçersiniz.',
                  ok: 'Bitir',
                );
                if (ok) await app.closeTender(tender.id);
              },
            ),
          ),
        ),
      SectionTitle(
        'Gelen teklifler (${bids.length})',
        padding: const EdgeInsets.only(bottom: 10),
      ),
      if (bids.isEmpty)
        const EmptyState(
          icon: Icons.inbox_outlined,
          title: 'Henüz teklif yok',
          message: 'Teklifler geldikçe burada görünür.',
        ),
      for (final b in bids)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _OwnerBidCard(
            tender: tender,
            bid: b,
            isBest: b.id == best?.id && bids.length > 1,
          ),
        ),
    ];
  }

  List<Widget> _bidderSection(
    BuildContext context,
    AppState app,
    Tender tender,
    TenderBid? myBid,
    bool canBid,
    int bidCount,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return [
      Text(
        '$bidCount teklif verildi. Diğer tekliflerin tutarı gizlidir.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 16),
      if (myBid != null)
        _MyBidCard(tender: tender, bid: myBid)
      else if (canBid)
        SizedBox(
          height: 56,
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('tender-bid'),
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('Fiyat teklifi ver', style: TextStyle(fontSize: 16)),
            onPressed: () => showBidSheet(context, tender),
          ),
        )
      else
        InfoBanner(
          text: tender.acceptsBids()
              ? 'Bu ihaleye yalnızca şu meslekler teklif verebilir: '
                    '${tender.allowedProfessions.map((p) => p.label).join(', ')}.'
              : 'Bu ihale artık teklif almıyor.',
          icon: Icons.info_outline_rounded,
          color: AppColors.grey,
        ),
    ];
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.tender});
  final Tender tender;

  @override
  Widget build(BuildContext context) {
    if (tender.status == TenderStatus.awarded) {
      return const Pill('Verildi', color: AppColors.green, icon: Icons.check_circle_outline);
    }
    if (tender.needsAward()) {
      return const Pill('Teklifler bitti', color: AppColors.amber, icon: Icons.flag_outlined);
    }
    return const Pill('Teklif alıyor', color: AppColors.blue, icon: Icons.schedule_rounded);
  }
}

class _OwnerBidCard extends StatelessWidget {
  const _OwnerBidCard({
    required this.tender,
    required this.bid,
    required this.isBest,
  });

  final Tender tender;
  final TenderBid bid;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final name = app.social.displayName(bid.bidderId, me: app.me);
    final profession = app.social.identityOf(bid.bidderId)?.profession.label;
    final canSeePhone = SocialRules.canRevealPhone(
      tender: tender,
      bid: bid,
      viewerId: app.myId ?? '',
    );
    return Container(
      key: Key('bid-card-${bid.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: bid.decision == BidStatus.selected
              ? AppColors.green
              : scheme.outlineVariant,
          width: bid.decision == BidStatus.selected ? 2 : 1,
        ),
      ),
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
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (profession != null)
                      Text(profession, style: TextStyle(color: muted, fontSize: 13)),
                  ],
                ),
              ),
              if (bid.decision != BidStatus.pending)
                Pill(
                  bid.decision.label,
                  color: bid.decision == BidStatus.selected ? AppColors.green : AppColors.grey,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                formatTL(bid.amount),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              if (isBest)
                const Pill('En düşük teklif', color: AppColors.green),
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
          const SizedBox(height: 14),
          if (canSeePhone)
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton.icon(
                key: Key('bid-phone-${bid.id}'),
                icon: const Icon(Icons.phone_outlined),
                label: const Text('Telefonu göster', style: TextStyle(fontSize: 16)),
                onPressed: () => showContactSheet(
                  context,
                  load: () => app.contactForTenderBid(tender, bid),
                  whatsappText: 'Merhaba, "${tender.title}" ihalesi hakkında yazıyorum.',
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Telefon gizli. Onaylarsanız bu kişiyle numaralar paylaşılır.',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: AsyncButton(
                key: Key('bid-approve-${bid.id}'),
                label: 'Telefon paylaşımını onayla',
                icon: Icons.verified_user_outlined,
                outlined: true,
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    '$name ile numaralar paylaşılsın mı?',
                    message: 'Onaylarsanız iki taraf da birbirinin telefonunu görür.',
                    ok: 'Onayla',
                  );
                  if (ok) await app.approveBidContact(tender.id, bid.id);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MyBidCard extends StatelessWidget {
  const _MyBidCard({required this.tender, required this.bid});

  final Tender tender;
  final TenderBid bid;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final canSeePhone = SocialRules.canRevealPhone(
      tender: tender,
      bid: bid,
      viewerId: app.myId ?? '',
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Teklifiniz',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Pill(
                bid.decision.label,
                color: switch (bid.decision) {
                  BidStatus.selected => AppColors.green,
                  BidStatus.notSelected => AppColors.grey,
                  BidStatus.pending => AppColors.blue,
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatTL(bid.amount),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(bid.note, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 12),
          if (canSeePhone)
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.phone_outlined),
                label: const Text('İhaleyi açanın telefonu', style: TextStyle(fontSize: 16)),
                onPressed: () => showContactSheet(
                  context,
                  load: () => app.contactForTenderBid(tender, bid),
                  whatsappText: 'Merhaba, "${tender.title}" ihalesi için teklif veren firmayım.',
                ),
              ),
            )
          else
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Telefonunuz gizli. İhaleyi açan onaylarsa numaralar paylaşılır.',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
