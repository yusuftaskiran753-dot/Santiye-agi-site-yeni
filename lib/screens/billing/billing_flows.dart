import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'paywall_screen.dart';

/// Premium ekranını açar; kullanıcı Premium olduysa true döner.
Future<bool> openPaywall(BuildContext context, {String? reason}) async {
  await pushPage<bool>(context, PaywallScreen(reason: reason));
  if (!context.mounted) return false;
  return context.read<AppState>().isPremium;
}

Future<void> openCredits(BuildContext context) => pushPage<void>(context, const CreditsScreen());

/// Premium gerektiren özellikler (ör. hafriyat planlama) için.
Future<bool> ensurePremium(BuildContext context, {required String feature}) async {
  if (context.read<AppState>().isPremium) return true;
  return openPaywall(context, reason: feature);
}

/// İlan sahibine ulaşma / teklif verme hakkını açar.
///
/// Premium: sınırsız. Ücretsiz: ayda belirli sayıda hak. Hak bitince
/// kullanıcıya 1 kredi kullanma, kredi alma veya Premium seçenekleri sunulur.
/// Hak açıldıysa true döner.
Future<bool> ensureUnlocked(BuildContext context, Listing listing) async {
  final app = context.read<AppState>();
  if (app.isUnlocked(listing)) return true;
  if (app.isLive && listing.demo) {
    showSnack(context, const BackendException('DEMO_ITEM').message);
    return false;
  }
  try {
    var result = await app.unlock(listing);
    if (result.ok) {
      if (result.method == 'free' && context.mounted) {
        final left = app.usage.freeLeft;
        showSnack(context, left > 0 ? 'Bu ay $left ücretsiz iletişim hakkınız kaldı' : 'Bu ayki son ücretsiz hakkınızı kullandınız');
      }
      return true;
    }
    if (!context.mounted) return false;
    final choice = await showAppSheet<_UnlockChoice>(context, (ctx) => _UnlockSheet(credits: result.credits));
    if (choice == null || !context.mounted) return false;
    switch (choice) {
      case _UnlockChoice.useCredit:
        result = await app.unlock(listing, useCredit: true);
      case _UnlockChoice.premium:
        if (!await openPaywall(context)) return false;
        result = await app.unlock(listing);
      case _UnlockChoice.buyCredits:
        await openCredits(context);
        if (app.usage.credits < 1) return false;
        result = await app.unlock(listing, useCredit: true);
    }
    if (!result.ok && context.mounted) {
      // Örn. kredi bu arada başka bir cihazda harcanmış.
      showSnack(context, const BackendException('NO_CREDITS').message, kind: NoticeKind.warning);
    }
    return result.ok;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

enum _UnlockChoice { useCredit, premium, buyCredits }

class _UnlockSheet extends StatelessWidget {
  const _UnlockSheet({required this.credits});

  final int credits;

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<AppState>().usage;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ücretsiz haklarınız bitti', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Bu ay ${usage.freeLimit} ücretsiz iletişim/teklif hakkınızı kullandınız. Haklarınız her ayın başında yenilenir. '
            'Hemen devam etmek için bir seçenek belirleyin:',
            style: TextStyle(color: muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (credits > 0) ...[
            AsyncButton(
              icon: Icons.toll_rounded,
              label: '1 kredi kullan (bakiye: $credits)',
              onPressed: () async => Navigator.pop(context, _UnlockChoice.useCredit),
            ),
            const SizedBox(height: 10),
          ],
          AsyncButton(
            icon: Icons.workspace_premium_rounded,
            label: 'Premium\'a geç · sınırsız',
            outlined: credits > 0,
            onPressed: () async => Navigator.pop(context, _UnlockChoice.premium),
          ),
          const SizedBox(height: 10),
          AsyncButton(
            icon: Icons.add_card_rounded,
            label: 'Kredi satın al',
            outlined: true,
            onPressed: () async => Navigator.pop(context, _UnlockChoice.buyCredits),
          ),
        ],
      ),
    );
  }
}

/// İlanı kredi ile öne çıkarma.
Future<void> showBoostSheet(BuildContext context, Listing listing) =>
    showAppSheet<void>(context, (ctx) => _BoostSheet(listing: listing));

class _BoostSheet extends StatelessWidget {
  const _BoostSheet({required this.listing});

  final Listing listing;

  Future<void> _boost(BuildContext context, BoostOption option) async {
    final app = context.read<AppState>();
    final cost = app.usage.boostCost(option);
    if (app.usage.credits < cost) {
      final nav = Navigator.of(context);
      nav.pop();
      await nav.push<void>(MaterialPageRoute<void>(builder: (_) => const CreditsScreen()));
      return;
    }
    try {
      final until = await app.boost(listing, option);
      if (!context.mounted) return;
      Navigator.pop(context);
      // Sayfa kapandığı için mesaj uygulama genelinde gösterilir.
      AppFeedback.success('İlanınız ${formatDateTime(until)} tarihine kadar öne çıkarıldı');
    } catch (e) {
      if (context.mounted) showError(context, e, onRetry: () => _boost(context, option));
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<AppState>().usage;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              IconBadge(Icons.bolt_rounded),
              SizedBox(width: 12),
              Expanded(child: Text('İlanı öne çıkar', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Öne çıkan ilanlar listelerin en üstünde "Öne çıkan" etiketiyle görünür; daha çok teklif alır.',
            style: TextStyle(color: muted, height: 1.4),
          ),
          if (listing.isBoosted) ...[
            const SizedBox(height: 10),
            InfoBanner(
              text: 'Bu ilan ${formatDateTime(listing.boostedUntil!)} tarihine kadar öne çıkarılmış. '
                  'Yeni süre mevcut sürenin üzerine eklenir.',
              color: AppColors.green,
              icon: Icons.check_circle_outline,
            ),
          ],
          const SizedBox(height: 16),
          for (final option in BoostOption.values) ...[
            Card(
              child: ListTile(
                leading: Icon(Icons.bolt_rounded, color: Theme.of(context).colorScheme.primary),
                title: Text(option.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${usage.boostCost(option)} kredi'),
                trailing: AsyncButton(
                  expand: false,
                  label: 'Öne çıkar',
                  onPressed: () => _boost(context, option),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text('Bakiyeniz: ${usage.credits} kredi', style: TextStyle(color: muted))),
              TextButton(onPressed: () => openCredits(context), child: const Text('Kredi al')),
            ],
          ),
        ],
      ),
    );
  }
}
