import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../services/backend.dart';
import '../../../state/app_state.dart';
import '../../../theme.dart';
import '../../../widgets/common.dart';
import '../../billing/billing_flows.dart';
import '../../deals/deal_form_screen.dart';
import '../../assistant/assistant_screen.dart';
import 'job_form.dart';
import 'load_form.dart';
import 'machine_form.dart';
import 'material_form.dart';
import 'worker_form.dart';

/// İlan türüne göre ekleme / düzenleme formunu açar.
Future<void> openListingForm(
  BuildContext context,
  ListingKind kind, {
  Listing? initial,
}) {
  final Widget page = switch (kind) {
    ListingKind.yuk => LoadFormScreen(
      initial: initial is Load ? initial : null,
    ),
    ListingKind.makine => MachineFormScreen(
      initial: initial is Machine ? initial : null,
    ),
    ListingKind.malzeme => MaterialFormScreen(
      initial: initial is MaterialListing ? initial : null,
    ),
    ListingKind.personel => JobFormScreen(
      initial: initial is JobPost ? initial : null,
    ),
    ListingKind.sicil => WorkerFormScreen(
      initial: initial is WorkerCard ? initial : null,
    ),
  };
  return pushPage<void>(context, page);
}

/// İlanı kaydeder; ücretsiz ilan sınırı dolduysa Premium seçeneği sunar.
/// Kaydedildiyse (veya internet yokken cihaza kaydedilip gönderim sırasına
/// alındıysa) true döner ve [successMessage] gösterilir.
Future<bool> saveListingFlow(
  BuildContext context,
  Listing listing, {
  required bool isNew,
  String? successMessage,
}) async {
  final app = context.read<AppState>();
  try {
    await app.saveListing(listing, isNew: isNew);
    // Sayfa birazdan kapanacağı için mesaj uygulama genelinde gösterilir.
    if (successMessage != null) {
      showSaved(null, successMessage, queued: app.lastWriteQueued);
    }
    return true;
  } catch (e) {
    final error = BackendException.from(e);
    if (!context.mounted) return false;
    if (error.code == 'LISTING_LIMIT') {
      final upgrade = await confirm(
        context,
        'İlan sınırına ulaştınız',
        message:
            'Ücretsiz üyelikte aynı anda en fazla ${app.usage.freeListingLimit} ilan yayında olabilir. '
            'İlanlarım bölümünden eski bir ilanı yayından kaldırabilir veya Premium ile sınırsız ilan verebilirsiniz.',
        ok: 'Premium\'u incele',
        cancel: 'Tamam',
      );
      if (upgrade &&
          context.mounted &&
          await openPaywall(context) &&
          context.mounted) {
        return saveListingFlow(
          context,
          listing,
          isNew: isNew,
          successMessage: successMessage,
        );
      }
      return false;
    }
    showError(
      context,
      error,
      onRetry: () => saveListingFlow(
        context,
        listing,
        isNew: isNew,
        successMessage: successMessage,
      ),
    );
    return false;
  }
}

/// Ortak form iskeleti: başlık, kaydırılabilir alanlar, altta kaydet düğmesi.
class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final String submitLabel;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: formKey,
        // İlk denemeden sonra alanlar yazdıkça yeniden doğrulanır.
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: children,
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: AsyncButton(label: submitLabel, onPressed: onSubmit),
        ),
      ),
    );
  }
}

/// "+" düğmesi: ne yayınlamak istediğini seçtirir.
Future<void> showPostSheet(BuildContext context) =>
    showAppSheet<void>(context, (ctx) => const _PostSheet());

class _PostOption {
  const _PostOption(
    this.icon,
    this.color,
    this.title,
    this.subtitle,
    this.onTap,
  );

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Future<void> Function(BuildContext context) onTap;
}

class _PostSheet extends StatelessWidget {
  const _PostSheet();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = app.me?.role;
    final hasCard = app.myWorkerCard != null;
    final options = <UserRole, _PostOption>{
      UserRole.yukSahibi: _PostOption(
        Icons.local_shipping_rounded,
        AppColors.brand,
        'Yük ilanı ver',
        'Taşınacak yükünüz için nakliyecilerden teklif alın',
        (c) => openListingForm(c, ListingKind.yuk),
      ),
      UserRole.makineSahibi: _PostOption(
        Icons.construction_rounded,
        AppColors.blue,
        'Makinemi ekle',
        'İş makinenizi kiraya verin, talepleri toplayın',
        (c) => openListingForm(c, ListingKind.makine),
      ),
      UserRole.tedarikci: _PostOption(
        Icons.inventory_2_rounded,
        AppColors.green,
        'Ürün / fiyat ekle',
        'Beton, agrega, asfalt fiyatlarınızı yayınlayın, sipariş alın',
        (c) => openListingForm(c, ListingKind.malzeme),
      ),
      UserRole.muteahhit: _PostOption(
        Icons.work_rounded,
        AppColors.purple,
        'Personel ilanı ver',
        'Operatör, şoför, usta arayın',
        (c) => openListingForm(c, ListingKind.personel),
      ),
      UserRole.personel: _PostOption(
        Icons.engineering_rounded,
        AppColors.teal,
        hasCard ? 'Sicil kartımı düzenle' : 'Sicil kartımı oluştur',
        'Operatörseniz firmalar sizi bulsun',
        (c) => openListingForm(c, ListingKind.sicil, initial: app.myWorkerCard),
      ),
    };
    final ordered = <_PostOption>[
      _PostOption(
        Icons.auto_awesome_rounded,
        AppColors.brand,
        'Anlatın, taslak hazırlayalım',
        'Yükünüzü kısaca anlatın; formu kontrol ederek yayınlayın',
        (c) => pushPage<void>(c, const AssistantScreen(posting: true)),
      ),
      if (role != null && options[role] != null) options[role]!,
      for (final e in options.entries)
        if (e.key != role) e.value,
      _PostOption(
        Icons.handshake_rounded,
        AppColors.grey,
        'Anlaşma kaydı oluştur',
        'İlan dışında anlaştığınız bir işi kayda alın, ödemeleri takip edin',
        (c) => pushPage<void>(c, const DealFormScreen()),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Ne yayınlamak istersiniz?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          for (final o in ordered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  leading: IconBadge(o.icon, color: o.color, size: 42),
                  title: Text(
                    o.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(o.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final nav = Navigator.of(context);
                    final parent = nav.context;
                    nav.pop();
                    o.onTap(parent);
                  },
                ),
              ),
            ),
          if (!app.isPremium) ...[
            const SizedBox(height: 4),
            Text(
              'Ücretsiz üyelikte aynı anda ${app.usage.freeListingLimit} ilan yayında olabilir '
              '(şu an ${app.usage.activeListings}).',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
