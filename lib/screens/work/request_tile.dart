import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../deals/deal_detail_screen.dart';
import '../listings/contact_sheet.dart';
import '../listings/listing_detail_screen.dart';
import '../profile/public_profile_screen.dart';

Color requestStatusColor(RequestStatus s) => switch (s) {
  RequestStatus.pending => AppColors.amber,
  RequestStatus.accepted => AppColors.green,
  RequestStatus.rejected => AppColors.grey,
  RequestStatus.withdrawn => AppColors.grey,
};

/// Gelen veya giden bir teklif/talep kartı ve işlemleri.
class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.request,
    this.showListingTitle = true,
  });

  final TradeRequest request;
  final bool showListingTitle;

  Future<void> _respond(BuildContext context, bool accept) async {
    final app = context.read<AppState>();
    final r = request;
    if (accept) {
      final ok = await confirm(
        context,
        'Talep kabul edilsin mi?',
        message:
            'Kabul edince iki taraf arasında bir anlaşma kaydı oluşur. '
            'Teklif veya talep gönderildiğinde taraflar birbirlerinin iletişim bilgilerine erişebilir; '
            'bu erişim kabulden önce başlar ve ret veya geri çekme sonrasında da devam eder.'
            '${r.kind == ListingKind.yuk ? ' Yük ilanınız yayından kalkar, diğer teklifler otomatik reddedilir.' : ''}',
        ok: 'Kabul et',
      );
      if (!ok || !context.mounted) return;
    } else {
      final ok = await confirm(
        context,
        'Talep reddedilsin mi?',
        ok: 'Reddet',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    try {
      final dealId = await app.respond(r, accept: accept);
      if (!context.mounted) return;
      if (app.lastWriteQueued) {
        // İnternet yok: yanıt sırada; anlaşma kaydı gönderimden sonra oluşur.
        showSaved(context, '', queued: true);
      } else if (accept && dealId != null) {
        showSuccess(context, 'Anlaşma kaydı oluşturuldu');
        await pushPage<void>(context, DealDetailScreen(dealId: dealId));
      } else if (accept) {
        showSuccess(context, 'Talep kabul edildi');
      } else {
        showSnack(context, 'Talep reddedildi');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _withdraw(BuildContext context) async {
    if (!await confirm(
      context,
      'Teklif geri çekilsin mi?',
      ok: 'Geri çek',
      danger: true,
    )) {
      return;
    }
    if (!context.mounted) return;
    try {
      final app = context.read<AppState>();
      await app.withdraw(request);
      if (context.mounted) {
        showSaved(
          context,
          'Teklifiniz geri çekildi',
          queued: app.lastWriteQueued,
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  void _contact(BuildContext context) {
    final app = context.read<AppState>();
    showContactSheet(
      context,
      load: () => app.contactForRequest(request),
      whatsappText:
          'Merhaba, ${AppConfig.appName}\'ndaki "${request.listingTitle}" için yazıyorum.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = request;
    final incoming = r.ownerId == app.myId;
    final other = incoming ? r.requester : r.owner;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final listing = app.listingById(r.kind, r.listingId);

    final facts = <String>[
      if (r.amount > 0) formatTL(r.amount),
      if (r.quantity > 0 && r.unit.isNotEmpty)
        '${formatNumber(r.quantity, decimals: 2)} ${r.unit}',
      if (r.startDate != null) formatDate(r.startDate!),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: listing == null ? null : () => openListing(context, listing),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(
                    kindIcon(r.kind),
                    color: AppColors.forKind(r.kind),
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${incoming ? 'Gelen' : 'Gönderilen'} ${r.kind.requestLabel.toLowerCase()}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (showListingTitle)
                          Text(
                            r.listingTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Pill(r.status.label, color: requestStatusColor(r.status)),
                ],
              ),
              if (other != null) ...[
                const SizedBox(height: 6),
                OwnerLine(
                  other,
                  onTap: () => pushPage<void>(
                    context,
                    PublicProfileScreen(userId: other.id, initial: other),
                  ),
                ),
              ],
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  facts.join(' · '),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
              if (r.address.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Adres: ${r.address}',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
              if (r.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '"${r.note}"',
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                timeAgo(r.updatedAt),
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _actions(context, incoming),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, bool incoming) {
    final r = request;
    final contactButton = IconButton.outlined(
      tooltip: 'İletişim',
      onPressed: () => _contact(context),
      icon: const Icon(Icons.call_outlined),
    );
    if (r.status == RequestStatus.accepted && r.dealId != null) {
      return Row(
        children: [
          contactButton,
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Anlaşmayı aç'),
              onPressed: () =>
                  pushPage<void>(context, DealDetailScreen(dealId: r.dealId!)),
            ),
          ),
        ],
      );
    }
    if (!r.isPending) return const SizedBox.shrink();
    if (incoming) {
      return Row(
        children: [
          contactButton,
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: () => _respond(context, false),
              child: const Text('Reddet'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              onPressed: () => _respond(context, true),
              child: const Text('Kabul et'),
            ),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: AppColors.red),
        icon: const Icon(Icons.undo_rounded),
        label: const Text('Geri çek'),
        onPressed: () => _withdraw(context),
      ),
    );
  }
}
