import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../billing/billing_flows.dart';
import '../haul/haul_screen.dart';
import '../listings/cards.dart';
import '../listings/forms/listing_forms.dart';
import '../listings/listing_detail_screen.dart';
import '../loads/backhaul_screen.dart';
import '../market/market_screen.dart';
import '../assistant/assistant_screen.dart';

/// Ana sayfa: selam, arama, kategoriler, yapılacaklar, role göre öneri ve
/// bölgedeki yeni ilanlar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMarket,
    required this.onOpenWork,
    required this.onOpenNotifications,
  });

  final ValueChanged<MarketCategory> onOpenMarket;
  final ValueChanged<int> onOpenWork;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final me = app.me;
    if (me == null) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final firstName = me.name.trim().split(RegExp(r'\s+')).first;

    final counts = {
      MarketCategory.yuk: app.marketLoads.length,
      MarketCategory.makine: app.marketMachines.length,
      MarketCategory.malzeme: app.marketMaterials.length,
      MarketCategory.personel: app.marketJobs.length + app.marketWorkers.length,
    };

    // Bölgedeki yeni ilanlar: kullanıcının ilinden, en yeniler (öne çıkanlar önce).
    final nearby = <Listing>[
      ...app.marketLoads.where(
        (l) => l.fromCity == app.city || l.toCity == app.city,
      ),
      ...app.marketMachines.where((m) => m.city == app.city),
      ...app.marketMaterials.where((m) => m.city == app.city),
      ...app.marketJobs.where((j) => j.city == app.city),
    ]..sort(AppState.compareListings);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            try {
              await app.refreshAll();
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${greeting()}, $firstName',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: muted,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                '${me.city} · ${me.role.label}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Bildirimler',
                    onPressed: onOpenNotifications,
                    icon: Badge(
                      isLabelVisible: app.unreadCount > 0,
                      label: Text('${app.unreadCount}'),
                      child: const Icon(Icons.notifications_none_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (app.usage.announcement.isNotEmpty) ...[
                InfoBanner(
                  text: app.usage.announcement,
                  icon: Icons.campaign_outlined,
                  color: AppColors.brand,
                ),
                const SizedBox(height: 10),
              ],
              if (app.offline || app.pendingSyncCount > 0) ...[
                _SyncBanner(app: app),
                const SizedBox(height: 10),
              ],
              // Müşterinin tasarımındaki tek asistan giriş kartı.
              _AskBox(
                onTap: () => pushPage<void>(context, const AssistantScreen()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final c in MarketCategory.values)
                    Expanded(
                      child: _Shortcut(
                        category: c,
                        count: counts[c] ?? 0,
                        onTap: () => onOpenMarket(c),
                      ),
                    ),
                ],
              ),
              if (app.actionCount > 0) ...[
                const SizedBox(height: 16),
                _TodoLine(
                  pendingIncoming: app.pendingIncoming,
                  dealsNeedingMe: app.dealsNeedingMe,
                  onOpenWork: onOpenWork,
                ),
              ],
              const SizedBox(height: 12),
              _Spotlight(role: me.role, onOpenMarket: onOpenMarket),
              SectionTitle(
                nearby.isEmpty ? 'Son ilanlar' : '${app.city} çevresinde yeni',
                action: 'Tümü',
                onAction: () => onOpenMarket(MarketCategory.yuk),
              ),
              if (nearby.isEmpty && app.marketLoads.isEmpty)
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Henüz ilan yok',
                  message:
                      'İlk ilanı siz verin; bölgenizdeki firmalar size ulaşsın.',
                  actionLabel: 'İlan ver',
                  onAction: () => showPostSheet(context),
                ),
              for (final l
                  in (nearby.isEmpty ? app.marketLoads.cast<Listing>() : nearby)
                      .take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListingRow(
                    listing: l,
                    onTap: () => openListing(context, l),
                  ),
                ),
              // Ücretsiz hak bittiyse hatırlat; aksi hâlde kalabalık etmesin (Profil'de görünür).
              if (!app.isPremium && app.usage.freeLeft == 0) ...[
                const SizedBox(height: 4),
                _PlanStrip(
                  freeLeft: app.usage.freeLeft,
                  freeLimit: app.usage.freeLimit,
                  credits: app.usage.credits,
                ),
              ],
              const SizedBox(height: 10),
              const ResponsibilityNote(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Müşterinin tek giriş kartı asistanı açar; klasik arama İlanlar ekranındadır.
class _AskBox extends StatelessWidget {
  const _AskBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Material(
      key: const Key('home-assistant'),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: primary.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ne lazım? Yazın, bulalım',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "\"Yarın İstanbul'dan Ankara'ya tır\"",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kategori kısayolu: telefonun ana ekranındaki uygulama simgeleri gibi tek sıra.
class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.category,
    required this.count,
    required this.onTap,
  });

  final MarketCategory category;
  final int count;
  final VoidCallback onTap;

  Color get _color => switch (category) {
    MarketCategory.yuk => AppColors.forKind(ListingKind.yuk),
    MarketCategory.makine => AppColors.forKind(ListingKind.makine),
    MarketCategory.malzeme => AppColors.forKind(ListingKind.malzeme),
    MarketCategory.personel => AppColors.forKind(ListingKind.personel),
  };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey('home-category-${category.name}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(category.icon, color: _color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              category.label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              count == 0 ? 'ilan yok' : '$count ilan',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kompakt görünümde iki iş türünün kendi sekmesine erişimi korunur.
class _TodoLine extends StatelessWidget {
  const _TodoLine({
    required this.pendingIncoming,
    required this.dealsNeedingMe,
    required this.onOpenWork,
  });

  final int pendingIncoming;
  final int dealsNeedingMe;
  final ValueChanged<int> onOpenWork;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = pendingIncoming + dealsNeedingMe;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: const EdgeInsets.all(4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$total',
                style: TextStyle(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sizi bekleyen işler',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (pendingIncoming > 0)
                        ActionChip(
                          key: const Key('home-pending-requests'),
                          avatar: const Icon(
                            Icons.mark_email_unread_outlined,
                            size: 16,
                          ),
                          label: Text('$pendingIncoming yeni teklif / talep'),
                          onPressed: () => onOpenWork(0),
                        ),
                      if (dealsNeedingMe > 0)
                        ActionChip(
                          key: const Key('home-pending-deals'),
                          avatar: const Icon(
                            Icons.handshake_outlined,
                            size: 16,
                          ),
                          label: Text('$dealsNeedingMe anlaşma'),
                          onPressed: () => onOpenWork(2),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kullanıcının rolüne göre en faydalı tek öneri.
class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.role, required this.onOpenMarket});

  final UserRole role;
  final ValueChanged<MarketCategory> onOpenMarket;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final (
      IconData icon,
      String title,
      String text,
      VoidCallback onTap,
    ) = switch (role) {
      UserRole.nakliyeci => (
        Icons.u_turn_left_rounded,
        'Boş dönmeyin',
        'Boşaldığınız ilden evinize doğru giden yükleri sıralayalım.',
        () => pushPage<void>(context, const BackhaulScreen()),
      ),
      UserRole.yukSahibi => (
        Icons.local_shipping_rounded,
        'Yükünüz için teklif toplayın',
        'İlan verin; nakliyeciler fiyat teklifiyle size gelsin.',
        () => openListingForm(context, ListingKind.yuk),
      ),
      UserRole.makineSahibi => (
        Icons.construction_rounded,
        app.mine(ListingKind.makine).isEmpty
            ? 'Makinenizi kiraya verin'
            : 'Makinelerinizi güncel tutun',
        app.mine(ListingKind.makine).isEmpty
            ? 'Makinenizi ekleyin; kiralama talepleri doğrudan size gelsin.'
            : 'Müsaitlik ve fiyatı güncel olan makineler daha çok talep alır.',
        () {
          final machines = app.mine(ListingKind.makine);
          if (machines.isEmpty) {
            openListingForm(context, ListingKind.makine);
          } else {
            openListing(context, machines.first);
          }
        },
      ),
      UserRole.muteahhit => (
        Icons.route_rounded,
        'Hafriyatı planlayın',
        'Döküm sahası dağılımı, sefer sayısı, yakıt ve dönüş yükü hesabı.',
        () => pushPage<void>(context, const HaulScreen()),
      ),
      UserRole.tedarikci => (
        Icons.inventory_2_rounded,
        'Fiyatlarınızı yayınlayın',
        'Güncel fiyat ve stok bilgisi olan tedarikçiler karşılaştırmada öne çıkar.',
        () => openListingForm(context, ListingKind.malzeme),
      ),
      UserRole.personel => (
        Icons.engineering_rounded,
        app.myWorkerCard == null
            ? 'Sicil kartınızı oluşturun'
            : 'İş ilanlarına göz atın',
        app.myWorkerCard == null
            ? 'Deneyim ve belgelerinizi ekleyin; firmalar size iş teklif etsin.'
            : 'Bölgenizdeki operatör ve şoför ilanlarına başvurun.',
        () {
          if (app.myWorkerCard == null) {
            openListingForm(context, ListingKind.sicil);
          } else {
            onOpenMarket(MarketCategory.personel);
          }
        },
      ),
    };
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: primary.withValues(alpha: 0.05),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(icon, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      text,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanStrip extends StatelessWidget {
  const _PlanStrip({
    required this.freeLeft,
    required this.freeLimit,
    required this.credits,
  });

  final int freeLeft;
  final int freeLimit;
  final int credits;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: AppColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bu ay $freeLeft/$freeLimit ücretsiz iletişim hakkı · $credits kredi',
                style: TextStyle(color: muted, fontSize: 13.5),
              ),
            ),
            TextButton(
              onPressed: () => openPaywall(context),
              child: const Text('Premium'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Çevrimdışı durumu ve gönderilmeyi bekleyen işlemler.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final pending = app.pendingSyncCount;
    final String text;
    if (app.syncing || app.refreshing) {
      text = pending > 0
          ? '$pending işlem sunucuya gönderiliyor…'
          : 'Bağlanılıyor…';
    } else if (app.offline) {
      final saved = app.lastRefresh;
      text =
          'Çevrimdışısınız. ${saved == null ? 'Son kaydedilen' : '${formatDateTime(saved)} tarihli'} bilgiler gösteriliyor.'
          '${pending > 0 ? ' Yaptığınız $pending işlem cihazınızda saklanıyor; bağlantı gelince otomatik gönderilecek.' : ''}';
    } else {
      text = '$pending işlem gönderilmeyi bekliyor.';
    }
    return InfoBanner(
      text: text,
      icon: app.offline ? Icons.wifi_off_rounded : Icons.cloud_upload_outlined,
      color: pending > 0 ? AppColors.amber : AppColors.grey,
      actionLabel: app.syncing || app.refreshing
          ? null
          : (pending > 0 ? 'Şimdi gönder' : 'Tekrar dene'),
      onAction: () => app.syncNow().catchError((Object e) {
        if (context.mounted) showError(context, e);
      }),
    );
  }
}
