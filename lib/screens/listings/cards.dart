import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../data/cities.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// İlanın üst köşesindeki durum etiketleri.
class ListingTags extends StatelessWidget {
  const ListingTags(this.listing, {super.key, this.extra = const []});

  final Listing listing;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = listing;
    final mine = app.isMine(l);
    final request = mine ? null : app.myLatestRequestFor(l);
    final pending = mine ? app.pendingCountFor(l) : 0;
    // Çevrimdışıyken yapılan değişiklik (ilan veya bu ilana teklif) henüz gönderilmedi.
    final unsynced = app.isPendingSync(l.id);
    final children = <Widget>[
      if (unsynced) const SyncPendingTag(),
      if (l.isBoosted) const BoostTag(),
      if (l.demo) const DemoTag(),
      if (mine && l.hidden)
        const Pill('İncelemede', color: AppColors.red, icon: Icons.visibility_off_outlined)
      else if (mine && l.status == ListingStatus.closed)
        const Pill('Kapalı', color: AppColors.grey)
      else if (mine && l is Load && l.isExpired)
        const Pill('Süresi geçti', color: AppColors.grey, icon: Icons.event_busy_outlined)
      else if (mine)
        const Pill('İlanım', color: AppColors.blue),
      if (pending > 0) Pill('$pending yeni talep', color: AppColors.brand, filled: true),
      if (request != null)
        Pill(
          request.isPending ? 'Teklif verildi' : request.status.label,
          color: switch (request.status) {
            RequestStatus.accepted => AppColors.green,
            RequestStatus.pending => AppColors.blue,
            _ => AppColors.grey,
          },
          icon: request.status == RequestStatus.accepted ? Icons.check_circle : Icons.schedule,
        ),
      ...extra,
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: children);
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.onTap, this.highlight});

  final Widget child;
  final VoidCallback onTap;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: highlight == null
          ? null
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: highlight!, width: 1.6)),
      child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: child)),
    );
  }
}

class _OwnerMini extends StatelessWidget {
  const _OwnerMini(this.profile);

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            profile.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: muted, fontWeight: FontWeight.w600),
          ),
        ),
        if (profile.companyVerified) ...[
          const SizedBox(width: 3),
          const Icon(Icons.verified_rounded, size: 14, color: AppColors.green),
        ],
        const SizedBox(width: 6),
        RatingStars(profile.ratingAvg, count: profile.ratingCount, size: 12),
      ],
    );
  }
}

// ───────────────────────── Yük ─────────────────────────

class LoadCard extends StatelessWidget {
  const LoadCard({super.key, required this.load, required this.onTap, this.footer});

  final Load load;
  final VoidCallback onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final km = roadKm(cityLatLng(load.fromCity), cityLatLng(load.toCity));
    return _CardShell(
      onTap: onTap,
      highlight: load.isBoosted ? AppColors.brand.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: load.fromCity),
                    TextSpan(text: '  →  ', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                    TextSpan(text: load.toCity),
                  ]),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                load.price > 0 ? formatTL(load.price) : 'Teklif usulü',
                style: TextStyle(
                  fontSize: load.price > 0 ? 17 : 14,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${load.cargo} · ${formatNumber(load.tons, decimals: 1)} ton · ${load.vehicle.label}',
            style: TextStyle(color: muted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 16, color: muted),
              const SizedBox(width: 4),
              Text(friendlyDay(load.date), style: TextStyle(fontSize: 13, color: muted)),
              const SizedBox(width: 12),
              Icon(Icons.straighten, size: 16, color: muted),
              const SizedBox(width: 4),
              Text('~${formatKm(km)}', style: TextStyle(fontSize: 13, color: muted)),
              const Spacer(),
              Flexible(flex: 3, child: _OwnerMini(load.owner)),
            ],
          ),
          const SizedBox(height: 8),
          ListingTags(load),
          ?footer,
        ],
      ),
    );
  }
}

// ───────────────────────── Makine ─────────────────────────

class MachineCard extends StatelessWidget {
  const MachineCard({super.key, required this.machine, required this.onTap, this.from});

  final Machine machine;
  final VoidCallback onTap;

  /// Mesafe hesaplanacak konum (kullanıcının ili).
  final LatLng? from;

  @override
  Widget build(BuildContext context) {
    final m = machine;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final km = from == null ? null : roadKm(from!, m.position);
    return _CardShell(
      onTap: onTap,
      highlight: m.isBoosted ? AppColors.brand.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(machineIcon(m.type), color: m.available ? AppColors.blue : AppColors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [if (m.capacity.isNotEmpty) m.capacity, m.city, if (km != null) formatKm(km)].join(' · '),
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (m.daily > 0) ...[
                    Text(formatTL(m.daily), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('günlük', style: TextStyle(fontSize: 11, color: muted)),
                  ],
                  if (m.hourly > 0)
                    Text('${formatTL(m.hourly)}/sa', style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              m.available ? const Pill('Müsait', color: AppColors.green) : const Pill('Çalışıyor', color: AppColors.grey),
              const SizedBox(width: 6),
              if (m.withOperator) const Pill('Operatörlü', color: AppColors.teal),
              const Spacer(),
              Flexible(flex: 3, child: _OwnerMini(m.owner)),
            ],
          ),
          const SizedBox(height: 8),
          ListingTags(m),
        ],
      ),
    );
  }
}

// ───────────────────────── Malzeme ─────────────────────────

/// "Teslim dahil" tahmini birim fiyat.
double deliveredUnitPrice(MaterialListing m, double km) => m.price + km * AppConfig.transportPerUnitKm;

class MaterialCard extends StatelessWidget {
  const MaterialCard({super.key, required this.material, required this.onTap, this.km, this.isBest = false});

  final MaterialListing material;
  final VoidCallback onTap;
  final double? km;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    final m = material;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final stockColor = switch (m.stock) {
      StockLevel.bol => AppColors.green,
      StockLevel.az => AppColors.amber,
      StockLevel.yok => AppColors.red,
    };
    return _CardShell(
      onTap: onTap,
      highlight: isBest ? AppColors.green : (m.isBoosted ? AppColors.brand.withValues(alpha: 0.6) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.product, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [m.plantName, m.city, if (km != null) formatKm(km!)].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${formatTL(m.price)} / ${m.unit}', style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  if (km != null)
                    Text('teslim ~${formatTL(deliveredUnitPrice(m, km!))}', style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pill(m.stock.label, color: stockColor),
              if (isBest) const Pill('En avantajlı', color: AppColors.green, icon: Icons.thumb_up_alt_outlined),
              if (m.delivery) const Pill('Nakliye var', color: AppColors.teal),
              _OwnerMini(m.owner),
            ],
          ),
          const SizedBox(height: 8),
          ListingTags(m),
        ],
      ),
    );
  }
}

// ───────────────────────── Personel ─────────────────────────

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, required this.onTap});

  final JobPost job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return _CardShell(
      onTap: onTap,
      highlight: job.isBoosted ? AppColors.brand.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(Icons.work_outline_rounded, color: AppColors.purple, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${job.owner.displayName} · ${job.city} · ${timeAgo(job.createdAt)}',
                        style: TextStyle(fontSize: 13, color: muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (job.wage > 0) Pill('${formatTL(job.wage)} / ${job.wagePeriod.toLowerCase()}', color: AppColors.green),
              if (job.duration.isNotEmpty) Pill(job.duration, color: AppColors.blue),
              for (final r in job.requirements.take(3)) Pill(r, color: AppColors.grey),
            ],
          ),
          const SizedBox(height: 8),
          ListingTags(job),
        ],
      ),
    );
  }
}

class WorkerTile extends StatelessWidget {
  const WorkerTile({super.key, required this.worker, required this.onTap});

  final WorkerCard worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = worker;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return _CardShell(
      onTap: onTap,
      highlight: w.isBoosted ? AppColors.brand.withValues(alpha: 0.6) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(w.owner.name, radius: 24, color: AppColors.teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.owner.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${w.role.label} · ${w.city} · ${w.years} yıl', style: TextStyle(fontSize: 13, color: muted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RatingStars(w.owner.ratingAvg, count: w.owner.ratingCount, size: 13),
                    w.available ? const Pill('Müsait', color: AppColors.green) : const Pill('Çalışıyor', color: AppColors.grey),
                    for (final c in w.certificates.take(2)) Pill(c, color: AppColors.blue, icon: Icons.verified_outlined),
                    ListingTags(w),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Liste ve aramalar için kısa satır görünümü (her ilan türü).
class ListingRow extends StatelessWidget {
  const ListingRow({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  String _price() => switch (listing) {
        Load l => l.price > 0 ? formatTL(l.price) : '',
        Machine m => m.daily > 0 ? '${formatTL(m.daily)}/gün' : '',
        MaterialListing x => '${formatTL(x.price)}/${x.unit}',
        JobPost j => j.wage > 0 ? '${formatTL(j.wage)}/${j.wagePeriod.toLowerCase()}' : '',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final price = _price();
    return _CardShell(
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(kindIcon(listing.kind), color: AppColors.forKind(listing.kind), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(listing.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: muted)),
                const SizedBox(height: 6),
                ListingTags(listing),
              ],
            ),
          ),
          if (price.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(price, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}
