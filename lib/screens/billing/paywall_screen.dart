import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../services/billing_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Premium abonelik ekranı (Google Play / App Store aboneliği).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reason});

  /// Kullanıcıyı bu ekrana getiren durum (ör. "Hafriyat planlama").
  final String? reason;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  PremiumPlan _selected = PremiumPlan.yearly;
  late final BillingService _billing;
  late final AppState _app;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _billing = context.read<BillingService>();
    _app = context.read<AppState>();
    _billing.addListener(_onChange);
    _app.addListener(_onChange);
  }

  @override
  void dispose() {
    _billing.removeListener(_onChange);
    _app.removeListener(_onChange);
    super.dispose();
  }

  // Satın alma sonuçları uygulama genelinde gösterilir (main.dart → AppFeedback);
  // burada yalnızca Premium olunca ekran kapatılır.
  void _onChange() {
    if (!mounted) return;
    if (!_closing && _app.isPremium) {
      _closing = true;
      Navigator.of(context).maybePop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingService>();
    final usage = context.watch<AppState>().usage;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final perMonth = billing.yearlyPerMonth();

    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  const IconBadge(Icons.workspace_premium_rounded, size: 60),
                  const SizedBox(height: 14),
                  Text(
                    widget.reason == null ? 'Sınırsız çalışın, öne çıkın' : '${widget.reason} Premium ile açılır',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ücretsiz üyelikte ayda ${usage.freeLimit} iletişim/teklif hakkınız ve aynı anda '
                    '${usage.freeListingLimit} ilan sınırınız var. Premium ile sınır yok.',
                    style: TextStyle(color: muted, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  const _Benefit(Icons.all_inclusive_rounded, 'Sınırsız iletişim ve teklif',
                      'Yük sahibine, makine sahibine, tedarikçiye istediğiniz kadar ulaşın.'),
                  const _Benefit(Icons.post_add_rounded, 'Sınırsız ilan',
                      'Bütün araçlarınızı, makinelerinizi ve ürünlerinizi yayında tutun.'),
                  const _Benefit(Icons.workspace_premium_outlined, 'Premium rozeti',
                      'Profilinizde ve ilanlarınızda güven veren rozet.'),
                  const _Benefit(Icons.route_rounded, 'Hafriyat planlama',
                      'Döküm sahası dağılımı, sefer, yakıt ve dönüş yükü hesabı.'),
                  const SizedBox(height: 18),
                  _PlanCard(
                    title: 'Yıllık',
                    price: billing.planPrice(PremiumPlan.yearly),
                    period: '/ yıl',
                    note: perMonth.isEmpty ? '12 ay boyunca kesintisiz' : 'Aylık $perMonth karşılığı',
                    badge: billing.yearlySavingPercent > 0 ? '%${billing.yearlySavingPercent} tasarruf' : null,
                    selected: _selected == PremiumPlan.yearly,
                    onTap: () => setState(() => _selected = PremiumPlan.yearly),
                  ),
                  const SizedBox(height: 10),
                  _PlanCard(
                    title: 'Aylık',
                    price: billing.planPrice(PremiumPlan.monthly),
                    period: '/ ay',
                    note: 'İstediğiniz zaman iptal edin',
                    selected: _selected == PremiumPlan.monthly,
                    onTap: () => setState(() => _selected = PremiumPlan.monthly),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ödeme, onayınızla Google Play veya App Store hesabınızdan alınır. Abonelik, dönem bitiminden '
                    'en az 24 saat önce iptal edilmezse aynı süre ve ücretle otomatik yenilenir. Aboneliğinizi '
                    'mağaza hesap ayarlarınızdan yönetebilir ve iptal edebilirsiniz. Premium yalnızca uygulama '
                    'içi dijital özellikleri kapsar; taraflar arasındaki iş bedellerini kapsamaz.',
                    style: TextStyle(fontSize: 12, color: muted, height: 1.45),
                  ),
                  if (billing.product(AppConfig.premiumMonthlyId) == null ||
                      billing.product(AppConfig.premiumYearlyId) == null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Ürün fiyatları henüz alınamadı; gösterilen fiyatlar tahminidir.',
                      style: TextStyle(fontSize: 12, color: AppColors.red.withValues(alpha: 0.9)),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: billing.busy ? null : () => billing.buyPremium(_selected),
                      child: billing.busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(_selected == PremiumPlan.yearly ? 'Yıllık Premium\'a geç' : 'Aylık Premium\'a geç'),
                    ),
                  ),
                  TextButton(
                    onPressed: billing.busy ? null : billing.restore,
                    child: const Text('Satın alımları geri yükle'),
                  ),
                  const LegalLinks(),
                  if (AppConfig.operatorName.isNotEmpty)
                    Text('Hizmet sağlayıcı: ${AppConfig.operatorName}', style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.icon, this.title, this.text);

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.period,
    required this.note,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String price;
  final String period;
  final String note;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? primary : theme.dividerColor, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? primary : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        if (badge != null) Pill(badge!, color: AppColors.green, filled: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(note, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(period, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kredi paketleri ekranı.
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  // Satın alma sonuçları uygulama genelinde gösterilir (main.dart → AppFeedback).

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingService>();
    final usage = context.watch<AppState>().usage;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final packs = AppConfig.creditPacks.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Kredi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const IconBadge(Icons.toll_rounded, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${usage.credits} kredi', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        Text('Mevcut bakiyeniz', style: TextStyle(color: muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Kredi ne işe yarar?'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  const InfoRow('İletişim / teklif hakkı (ücretsiz hak bitince)', '1 kredi', icon: Icons.call_outlined),
                  InfoRow('İlanı 24 saat öne çıkar', '${usage.boostDayCost} kredi', icon: Icons.bolt_rounded),
                  InfoRow('İlanı 7 gün öne çıkar', '${usage.boostWeekCost} kredi', icon: Icons.bolt_rounded),
                ],
              ),
            ),
          ),
          const SectionTitle('Paketler'),
          if (AppConfig.creditPacks.keys.any((id) => billing.product(id) == null))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Ürün fiyatları henüz alınamadı; gösterilen fiyatlar tahminidir.',
                style: TextStyle(fontSize: 12, color: AppColors.red.withValues(alpha: 0.9)),
              ),
            ),
          for (final pack in packs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const IconBadge(Icons.toll_rounded, color: AppColors.amber, size: 42),
                  title: Text('${pack.value} kredi', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  subtitle: Text(_perCredit(billing, pack.key, pack.value)),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(96, 42)),
                    onPressed: billing.busy ? null : () => billing.buyCredits(pack.key),
                    child: Text(billing.priceOf(pack.key)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Krediler yalnızca uygulama içi dijital hizmetlerde (iletişim hakkı, öne çıkarma) kullanılır, '
            'tek seferliktir ve paraya çevrilemez. Taraflar arasındaki iş bedelleri uygulama dışında, '
            'doğrudan taraflar arasında ödenir.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.45),
          ),
          const SizedBox(height: 8),
          const LegalLinks(),
        ],
      ),
    );
  }

  String _perCredit(BillingService billing, String id, int credits) {
    final p = billing.product(id);
    if (p == null || credits <= 0) return 'Tek seferlik paket';
    final per = p.rawPrice / credits;
    final symbol = p.currencySymbol.isNotEmpty ? p.currencySymbol : '₺';
    return 'Kredi başı $symbol${formatNumber(per, decimals: 2)}';
  }
}
