import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../data/cities.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../billing/billing_flows.dart';
import '../common/report_sheet.dart';
import '../deals/deal_detail_screen.dart';
import '../profile/public_profile_screen.dart';
import '../work/request_tile.dart';
import 'cards.dart';
import 'contact_sheet.dart';
import 'forms/listing_forms.dart';
import 'request_sheet.dart';

Future<void> openListing(BuildContext context, Listing listing) =>
    pushPage<void>(
      context,
      ListingDetailScreen(kind: listing.kind, id: listing.id, initial: listing),
    );

/// WhatsApp gruplarına / kişilere gönderilecek ilan metni (telefon içermez).
String listingShareText(Listing l) {
  final lines = <String>[
    switch (l) {
      Load x => '🚚 Yük: ${x.fromCity} → ${x.toCity}',
      Machine x => '🏗️ Kiralık ${x.type.label}: ${x.model}',
      MaterialListing x => '🧱 ${x.product} · ${x.plantName}',
      JobPost x => '👷 İş ilanı: ${x.title}',
      WorkerCard x => '👷 ${x.role.label}: ${x.owner.name}',
      _ => l.title,
    },
    ...switch (l) {
      Load x => [
        '${x.cargo} · ${formatNumber(x.tons, decimals: 1)} ton · ${x.vehicle.label}',
        'Yükleme: ${formatDate(x.date)}',
        if (x.price > 0) 'Navlun: ${formatTL(x.price)}',
      ],
      Machine x => [
        '${x.capacity} · ${x.city}${x.withOperator ? ' · operatörlü' : ''}',
        if (x.daily > 0) 'Günlük: ${formatTL(x.daily)}',
        if (x.hourly > 0) 'Saatlik: ${formatTL(x.hourly)}',
      ],
      MaterialListing x => [
        '${formatTL(x.price)} / ${x.unit} (KDV hariç) · ${x.city}',
        x.stock.label,
      ],
      JobPost x => [
        '${x.role.label} · ${x.city}',
        if (x.wage > 0)
          'Ücret: ${formatTL(x.wage)} / ${x.wagePeriod.toLowerCase()}',
        if (x.duration.isNotEmpty) 'Süre: ${x.duration}',
      ],
      WorkerCard x => [
        '${x.years} yıl deneyim · ${x.city}',
        if (x.certificates.isNotEmpty) x.certificates.join(', '),
      ],
      _ => <String>[],
    },
    'İlan sahibi: ${l.owner.displayName}',
    '— ${AppConfig.appName} uygulamasında görüntüleyin',
  ];
  return lines.join('\n');
}

String _primaryLabel(Listing l) => switch (l.kind) {
  ListingKind.yuk => 'Teklif ver',
  ListingKind.makine => 'Kiralama talebi',
  ListingKind.malzeme => 'Sipariş ver',
  ListingKind.personel => 'Başvur',
  ListingKind.sicil => 'İş teklif et',
};

class ListingDetailScreen extends StatelessWidget {
  const ListingDetailScreen({
    super.key,
    required this.kind,
    required this.id,
    this.initial,
  });

  final ListingKind kind;
  final String id;
  final Listing? initial;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.listingById(kind, id) ?? initial;
    if (l == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'İlan bulunamadı',
          message: 'Silinmiş olabilir.',
        ),
      );
    }
    final mine = app.isMine(l);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.kind.listingLabel),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => shareOnWhatsApp(context, listingShareText(l)),
          ),
          _MoreMenu(listing: l, mine: mine),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Header(listing: l),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(children: _facts(context, l)),
            ),
          ),
          ..._extras(context, l, mine),
          SectionTitle(mine ? 'İlan sahibi (siz)' : 'İlan sahibi'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OwnerLine(
                    l.owner,
                    onTap: () => pushPage<void>(
                      context,
                      PublicProfileScreen(userId: l.ownerId, initial: l.owner),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TrustBadges(l.owner),
                ],
              ),
            ),
          ),
          if (mine)
            _IncomingRequests(listing: l)
          else
            _MyRequestStatus(listing: l),
          const SizedBox(height: 18),
          const ResponsibilityNote(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: mine ? _OwnerBar(listing: l) : _VisitorBar(listing: l),
        ),
      ),
    );
  }

  List<Widget> _facts(BuildContext context, Listing l) {
    final app = context.read<AppState>();
    switch (l) {
      case Load x:
        final km = roadKm(cityLatLng(x.fromCity), cityLatLng(x.toCity));
        return [
          InfoRow(
            'Navlun',
            x.price > 0 ? formatTL(x.price) : 'Teklif usulü',
            icon: Icons.payments_outlined,
          ),
          if (x.price > 0)
            InfoRow(
              'Km başı',
              '${formatTL(x.price / (km < 1 ? 1 : km), decimals: 1)}/km',
              icon: Icons.speed,
            ),
          InfoRow('Yük', x.cargo, icon: Icons.inventory_outlined),
          InfoRow(
            'Ağırlık',
            '${formatNumber(x.tons, decimals: 1)} ton',
            icon: Icons.scale_outlined,
          ),
          InfoRow('Araç', x.vehicle.label, icon: Icons.local_shipping_outlined),
          InfoRow(
            'Yükleme',
            '${friendlyDay(x.date)} · ${formatDate(x.date)}',
            icon: Icons.event_outlined,
          ),
          InfoRow('Tahmini mesafe', formatKm(km), icon: Icons.straighten),
          InfoRow('Yayın', timeAgo(x.createdAt), icon: Icons.schedule),
        ];
      case Machine x:
        return [
          InfoRow('Tür', x.type.label, icon: machineIcon(x.type)),
          if (x.capacity.isNotEmpty)
            InfoRow('Kapasite', x.capacity, icon: Icons.scale_outlined),
          InfoRow(
            'Konum',
            '${x.city} · ${formatKm(roadKm(app.userPosition, x.position))}',
            icon: Icons.location_on_outlined,
          ),
          if (x.daily > 0)
            InfoRow('Günlük', formatTL(x.daily), icon: Icons.today_outlined),
          if (x.hourly > 0)
            InfoRow('Saatlik', formatTL(x.hourly), icon: Icons.schedule),
          InfoRow(
            'Operatör',
            x.withOperator ? 'Dahil' : 'Dahil değil',
            icon: Icons.engineering_outlined,
          ),
          InfoRow(
            'Durum',
            x.available ? 'Müsait' : 'Şu an çalışıyor',
            icon: Icons.circle,
            valueColor: x.available ? AppColors.green : AppColors.grey,
          ),
        ];
      case MaterialListing x:
        final km = roadKm(app.userPosition, x.position);
        return [
          InfoRow(
            'Ürün',
            '${x.materialKind.label} · ${x.product}',
            icon: Icons.inventory_2_outlined,
          ),
          InfoRow(
            'Birim fiyat (KDV hariç)',
            '${formatTL(x.price)} / ${x.unit}',
            icon: Icons.payments_outlined,
          ),
          InfoRow(
            'Teslim dahil (tahmini)',
            '${formatTL(deliveredUnitPrice(x, km))} / ${x.unit}',
            icon: Icons.local_shipping_outlined,
          ),
          InfoRow('Stok', x.stock.label, icon: Icons.warehouse_outlined),
          if (x.minQty > 0)
            InfoRow(
              'En az sipariş',
              '${formatNumber(x.minQty)} ${x.unit}',
              icon: Icons.low_priority_rounded,
            ),
          InfoRow(
            'Nakliye',
            x.delivery ? 'Satıcı sağlıyor' : 'Alıcı ayarlar',
            icon: Icons.fire_truck_outlined,
          ),
          InfoRow(
            'Tesis',
            '${x.plantName} · ${x.city} · ${formatKm(km)}',
            icon: Icons.factory_outlined,
          ),
          InfoRow('Yayın', timeAgo(x.createdAt), icon: Icons.schedule),
        ];
      case JobPost x:
        return [
          InfoRow('Pozisyon', x.role.label, icon: Icons.badge_outlined),
          InfoRow('Yer', x.city, icon: Icons.location_on_outlined),
          if (x.wage > 0)
            InfoRow(
              'Ücret',
              '${formatTL(x.wage)} / ${x.wagePeriod.toLowerCase()}',
              icon: Icons.payments_outlined,
            ),
          if (x.duration.isNotEmpty)
            InfoRow('Süre', x.duration, icon: Icons.timelapse_rounded),
          InfoRow('Yayın', timeAgo(x.createdAt), icon: Icons.schedule),
        ];
      case WorkerCard x:
        return [
          InfoRow('Pozisyon', x.role.label, icon: Icons.badge_outlined),
          InfoRow(
            'Deneyim',
            '${x.years} yıl',
            icon: Icons.workspace_premium_outlined,
          ),
          InfoRow('İl', x.city, icon: Icons.location_on_outlined),
          InfoRow(
            'Durum',
            x.available ? 'İş arıyor (müsait)' : 'Şu an çalışıyor',
            icon: Icons.circle,
            valueColor: x.available ? AppColors.green : AppColors.grey,
          ),
          InfoRow(
            'Tamamlanan iş',
            '${x.owner.dealsCompleted}',
            icon: Icons.task_alt_rounded,
          ),
        ];
      default:
        return const [];
    }
  }

  List<Widget> _extras(BuildContext context, Listing l, bool mine) {
    final widgets = <Widget>[];
    final text = switch (l) {
      Load x => x.note,
      Machine x => x.note,
      MaterialListing x => x.note,
      JobPost x => x.note,
      WorkerCard x => x.about,
      _ => '',
    };
    if (l is JobPost && l.requirements.isNotEmpty) {
      widgets.addAll([
        const SectionTitle('Aranan şartlar'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in l.requirements) Pill(r, color: AppColors.blue),
          ],
        ),
      ]);
    }
    if (l is WorkerCard && l.certificates.isNotEmpty) {
      widgets.addAll([
        const SectionTitle('Belgeler'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in l.certificates)
              Pill(c, color: AppColors.blue, icon: Icons.verified_outlined),
          ],
        ),
      ]);
    }
    if (text.trim().isNotEmpty) {
      widgets.addAll([
        SectionTitle(l is WorkerCard ? 'Hakkında' : 'Açıklama'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(text, style: const TextStyle(height: 1.45)),
          ),
        ),
      ]);
    }
    if (l is Load) {
      widgets.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.directions_outlined),
            label: const Text('Google Haritalar\'da yol tarifi'),
            onPressed: () => openDirections(
              context,
              origin: '${l.fromCity}, Türkiye',
              destination: '${l.toCity}, Türkiye',
            ),
          ),
        ),
      );
    }
    if (l is Machine) {
      widgets.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Konumu haritada aç'),
            onPressed: () => openMapAt(context, l.lat, l.lng),
          ),
        ),
      );
      if (mine) {
        widgets.add(
          Card(
            child: SwitchListTile(
              title: const Text(
                'Kiralamaya müsait',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Kapatırsanız listede "Çalışıyor" görünür ve talep alınmaz.',
              ),
              value: l.available,
              onChanged: (v) async {
                try {
                  await context.read<AppState>().setMachineAvailable(l, v);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(
          l is Machine ? machineIcon(l.type) : kindIcon(l.kind),
          color: AppColors.forKind(l.kind),
          size: 52,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(l.subtitle, style: TextStyle(color: muted, fontSize: 15)),
              const SizedBox(height: 8),
              ListingTags(l),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.listing, required this.mine});

  final Listing listing;
  final bool mine;

  Future<void> _onSelected(BuildContext context, String value) async {
    final app = context.read<AppState>();
    final l = listing;
    try {
      switch (value) {
        case 'edit':
          await openListingForm(context, l.kind, initial: l);
        case 'boost':
          await showBoostSheet(context, l);
        case 'close':
          await app.setListingStatus(l, ListingStatus.closed);
          if (context.mounted) {
            showSaved(
              context,
              'İlan yayından kaldırıldı',
              queued: app.lastWriteQueued,
            );
          }
        case 'open':
          await app.setListingStatus(l, ListingStatus.active);
          if (context.mounted) {
            showSaved(
              context,
              'İlan yeniden yayında',
              queued: app.lastWriteQueued,
            );
          }
        case 'delete':
          if (!await confirm(
            context,
            'İlan silinsin mi?',
            message:
                'Bekleyen teklifler otomatik olarak kapatılır. Bu işlem geri alınamaz.',
            ok: 'Sil',
            danger: true,
          )) {
            return;
          }
          await app.deleteListing(l);
          if (context.mounted) {
            Navigator.of(context).pop();
            showSaved(context, 'İlan silindi', queued: app.lastWriteQueued);
          }
        case 'report':
          await showReportSheet(
            context,
            targetType: l.kind.name,
            targetId: l.id,
            ownerId: l.ownerId,
          );
        case 'block':
          if (!await confirm(
            context,
            '${l.owner.displayName} engellensin mi?',
            message:
                'Bu kullanıcının ilanlarını görmezsiniz ve birbirinize teklif gönderemezsiniz. '
                'Profil → Engellenen kullanıcılar bölümünden kaldırabilirsiniz.',
            ok: 'Engelle',
            danger: true,
          )) {
            return;
          }
          await app.block(l.ownerId);
          if (context.mounted) {
            Navigator.of(context).pop();
            showSaved(
              context,
              'Kullanıcı engellendi',
              queued: app.lastWriteQueued,
            );
          }
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = listing;
    return PopupMenuButton<String>(
      tooltip: 'Diğer',
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (_) => mine
          ? [
              const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
              if (l.isOpen)
                const PopupMenuItem(value: 'boost', child: Text('Öne çıkar')),
              if (l.status == ListingStatus.active)
                const PopupMenuItem(
                  value: 'close',
                  child: Text('Yayından kaldır'),
                )
              else
                const PopupMenuItem(
                  value: 'open',
                  child: Text('Yeniden yayınla'),
                ),
              const PopupMenuItem(value: 'delete', child: Text('Sil')),
            ]
          : [
              const PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
              const PopupMenuItem(
                value: 'block',
                child: Text('Kullanıcıyı engelle'),
              ),
            ],
    );
  }
}

class _VisitorBar extends StatelessWidget {
  const _VisitorBar({required this.listing});

  final Listing listing;

  Future<void> _contact(BuildContext context) async {
    final l = listing;
    if (!await ensureUnlocked(context, l)) return;
    if (!context.mounted) return;
    final app = context.read<AppState>();
    await showContactSheet(
      context,
      load: () => app.contactForListing(l),
      whatsappText:
          'Merhaba, ${AppConfig.appName}\'ndaki "${l.title}" ilanınız için yazıyorum.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = listing;
    final latest = app.myLatestRequestFor(l);
    final dealId = latest != null && latest.status == RequestStatus.accepted
        ? latest.dealId
        : null;
    final unavailable = !l.isOpen || (l is Machine && !l.available);
    final unlocked = app.isUnlocked(l);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: Icon(unlocked ? Icons.call_rounded : Icons.lock_open_rounded),
            label: Text(unlocked ? 'İletişim' : 'Numarayı göster'),
            onPressed: () => _contact(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: dealId != null
              ? FilledButton.icon(
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Anlaşmayı aç'),
                  onPressed: () =>
                      pushPage<void>(context, DealDetailScreen(dealId: dealId)),
                )
              : FilledButton(
                  onPressed: unavailable
                      ? null
                      : () => sendRequestFlow(context, l),
                  child: Text(
                    unavailable
                        ? (l is Machine && !l.available
                              ? 'Şu an çalışıyor'
                              : 'Yayında değil')
                        : (app.myPendingRequestFor(l) != null
                              ? 'Teklifi güncelle'
                              : _primaryLabel(l)),
                  ),
                ),
        ),
      ],
    );
  }
}

class _OwnerBar extends StatelessWidget {
  const _OwnerBar({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Düzenle'),
            onPressed: () => openListingForm(context, l.kind, initial: l),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Öne çıkar'),
            onPressed: l.isOpen ? () => showBoostSheet(context, l) : null,
          ),
        ),
      ],
    );
  }
}

class _IncomingRequests extends StatelessWidget {
  const _IncomingRequests({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final list = context.watch<AppState>().incomingFor(listing)
      ..sort((a, b) {
        if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Gelen ${listing.kind.requestsLabel.toLowerCase()} (${list.length})',
        ),
        if (list.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                listing.isOpen
                    ? 'Henüz talep yok. İlanınızı paylaşarak veya öne çıkararak daha çok kişiye ulaşın.'
                    : 'İlan yayında değil.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RequestTile(request: r),
          ),
      ],
    );
  }
}

class _MyRequestStatus extends StatelessWidget {
  const _MyRequestStatus({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final r = context.watch<AppState>().myLatestRequestFor(listing);
    if (r == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('${listing.kind.requestLabel} durumunuz'),
        RequestTile(request: r),
      ],
    );
  }
}
