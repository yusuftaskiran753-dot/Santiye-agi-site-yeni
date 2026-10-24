import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/models.dart';
import '../../services/billing_service.dart';
import '../../services/push_notification_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/legal_notice_bar.dart';
import '../../widgets/user_avatar.dart';
import '../billing/billing_flows.dart';
import '../haul/haul_screen.dart';
import '../listings/forms/listing_forms.dart';
import '../loads/backhaul_screen.dart';
import '../onboarding/onboarding_screens.dart';
import '../onboarding/profile_form.dart';
import 'guide_screen.dart';
import 'public_profile_screen.dart';
import 'work_gallery.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _manageSubscription(BuildContext context) => openExternal(
    context,
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions?package=${AppConfig.packageName}',
    failMessage: 'Mağaza abonelik sayfası açılamadı',
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final push = context.watch<PushNotificationService?>();
    final me = app.me;
    final usage = app.usage;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (me == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => pushPage<void>(
                context,
                PublicProfileScreen(userId: me.id, initial: me),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        UserAvatar(userId: me.id, name: me.displayName, radius: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                me.displayName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (me.company.isNotEmpty)
                                Text(me.name, style: TextStyle(color: muted)),
                              const SizedBox(height: 2),
                              Text(
                                '${me.role.label} · ${me.city}',
                                style: TextStyle(fontSize: 13, color: muted),
                              ),
                              const SizedBox(height: 4),
                              RatingStars(
                                me.ratingAvg,
                                count: me.ratingCount,
                                size: 13,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Düzenle',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => pushPage<void>(
                            context,
                            const EditProfileScreen(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TrustBadges(me),
                  ],
                ),
              ),
            ),
          ),
          if (!app.isLive) ...[
            const SizedBox(height: 12),
            const InfoBanner(
              title: 'Demo modu',
              text:
                  'Veriler yalnızca bu cihazda. Örnek firmalar teklif ve taleplere otomatik yanıt verir. '
                  'Gerçek yayın için sunucu bağlantısını yapın (YAYIN_REHBERI.md).',
              icon: Icons.science_outlined,
              color: AppColors.grey,
            ),
          ],
          const SizedBox(height: 12),
          const LegalNoticeBar(detail: LegalNotices.kvkk),
          WorkGallery(userId: me.id),
          const SectionTitle('Üyelik'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        usage.isPremium
                            ? Icons.workspace_premium_rounded
                            : Icons.person_outline_rounded,
                        color: usage.isPremium ? AppColors.amber : muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          usage.isPremium ? 'Premium üye' : 'Ücretsiz üyelik',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (usage.isPremium)
                    InfoRow(
                      'Geçerlilik',
                      '${formatDate(usage.premiumUntil!)} tarihine kadar (otomatik yenilenir)',
                    )
                  else ...[
                    InfoRow(
                      'Bu ay kalan iletişim hakkı',
                      '${usage.freeLeft} / ${usage.freeLimit}',
                    ),
                    InfoRow(
                      'Yayındaki ilanlarınız',
                      '${usage.activeListings} / ${usage.freeListingLimit}',
                    ),
                  ],
                  InfoRow('Kredi bakiyesi', '${usage.credits} kredi'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => openCredits(context),
                          child: const Text('Kredi al'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: usage.isPremium
                            ? OutlinedButton(
                                onPressed: () => _manageSubscription(context),
                                child: const Text('Aboneliği yönet'),
                              )
                            : FilledButton(
                                onPressed: () => openPaywall(context),
                                child: const Text('Premium\'a geç'),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Hesap'),
          Card(
            child: Column(
              children: [
                _MenuTile(
                  Icons.badge_outlined,
                  app.myWorkerCard == null
                      ? 'Sicil kartı oluştur (operatörler için)'
                      : 'Sicil kartım',
                  () => openListingForm(
                    context,
                    ListingKind.sicil,
                    initial: app.myWorkerCard,
                  ),
                ),
                _MenuTile(
                  Icons.block_outlined,
                  'Engellenen kullanıcılar',
                  () => pushPage<void>(context, const BlockedUsersScreen()),
                ),
                if (app.requiresPhoneVerification && !me.phoneVerified)
                  _MenuTile(
                    Icons.phone_iphone_rounded,
                    'Telefonumu doğrula',
                    () => pushPage<void>(context, const PhoneAuthScreen()),
                  ),
              ],
            ),
          ),
          const SectionTitle('Araçlar'),
          Card(
            child: Column(
              children: [
                _MenuTile(
                  Icons.u_turn_left_rounded,
                  'Boş dönüş eşleştirme',
                  () => pushPage<void>(context, const BackhaulScreen()),
                ),
                _MenuTile(
                  Icons.route_rounded,
                  'Hafriyat planlama',
                  () => pushPage<void>(context, const HaulScreen()),
                ),
              ],
            ),
          ),
          const SectionTitle('Yardım ve güven'),
          Card(
            child: Column(
              children: [
                _MenuTile(
                  Icons.help_outline_rounded,
                  'Nasıl çalışır?',
                  () => pushPage<void>(context, const GuideScreen()),
                ),
                _MenuTile(
                  Icons.shield_outlined,
                  'Güvenli ticaret rehberi',
                  () =>
                      pushPage<void>(context, const GuideScreen(initialTab: 1)),
                ),
                if (AppConfig.supportEmail.isNotEmpty)
                  _MenuTile(
                    Icons.support_agent_outlined,
                    'Destek: ${AppConfig.supportEmail}',
                    () => openExternal(
                      context,
                      'mailto:${AppConfig.supportEmail}',
                    ),
                  ),
                _MenuTile(
                  Icons.description_outlined,
                  'Kullanım koşulları',
                  () => openExternal(context, AppConfig.termsUrl),
                ),
                _MenuTile(
                  Icons.privacy_tip_outlined,
                  'Gizlilik politikası',
                  () => openExternal(context, AppConfig.privacyUrl),
                ),
                _MenuTile(
                  Icons.gavel_rounded,
                  'KVKK aydınlatma metni',
                  () => openExternal(context, AppConfig.kvkkUrl),
                ),
                if (AppConfig.accountDeletionUrl.isNotEmpty)
                  _MenuTile(
                    Icons.info_outline,
                    'Hesap ve veri silme bilgileri',
                    () => openExternal(context, AppConfig.accountDeletionUrl),
                  ),
              ],
            ),
          ),
          const SectionTitle('Uygulama'),
          Card(
            child: Column(
              children: [
                if (push != null)
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Bildirim ayarları'),
                    subtitle: Text(push.status),
                    onTap: () => push.enable(),
                  ),
                if (!app.isLive)
                  SwitchListTile(
                    secondary: const Icon(Icons.science_outlined),
                    title: const Text(
                      'Örnek ilanları göster',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text(
                      'Uygulamayla gelen, "Örnek" etiketli ilanlar',
                    ),
                    value: app.showDemo,
                    onChanged: app.setShowDemo,
                  ),
                _MenuTile(
                  Icons.restore_rounded,
                  'Satın alımları geri yükle',
                  () => context.read<BillingService>().restore(),
                ),
                if (!app.isLive)
                  _MenuTile(
                    Icons.delete_sweep_outlined,
                    'Demo verilerini sıfırla',
                    () async {
                      if (!await confirm(
                        context,
                        'Demo verileri sıfırlansın mı?',
                        message:
                            'İlanlarınız, teklifleriniz ve anlaşmalarınız silinir. Profil ve satın alımlar korunur.',
                        ok: 'Sıfırla',
                        danger: true,
                      )) {
                        return;
                      }
                      await app.resetDemoData();
                      if (context.mounted) {
                        showSnack(context, 'Demo verileri sıfırlandı');
                      }
                    },
                  ),
              ],
            ),
          ),
          const SectionTitle('Oturum'),
          Card(
            child: Column(
              children: [
                if (app.isLive &&
                    app.requiresPhoneVerification &&
                    me.phoneVerified)
                  _MenuTile(Icons.logout_rounded, 'Çıkış yap', () async {
                    final pending = app.pendingSyncCount;
                    if (!await confirm(
                      context,
                      'Çıkış yapılsın mı?',
                      message: pending > 0
                          ? 'İnternet yokken yaptığınız $pending işlem henüz sunucuya gönderilmedi. '
                                'Çıkış yaparsanız bu işlemler silinir. Önce bağlantı kurup "Şimdi gönder" demeniz önerilir.'
                          : null,
                      ok: 'Çıkış yap',
                      danger: pending > 0,
                    )) {
                      return;
                    }
                    try {
                      await app.signOut();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  }),
                _MenuTile(
                  Icons.person_remove_outlined,
                  'Hesabımı sil',
                  () => _deleteAccount(context),
                  color: AppColors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '${AppConfig.appName} · sürüm ${AppConfig.version} · ${app.isLive ? 'Canlı' : 'Demo modu'}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          if (AppConfig.operatorName.isNotEmpty)
            Center(
              child: Text(
                'Hizmet sağlayıcı: ${AppConfig.operatorName}',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final app = context.read<AppState>();
    final ok = await confirm(
      context,
      'Hesabınız silinsin mi?',
      message:
          'Profiliniz, ilanlarınız, teklifleriniz ve bildirimleriniz kalıcı olarak silinir. Karşı tarafın kendi '
          'kaydı olarak tutulan anlaşmalarda yalnızca adınız kalır. Aktif aboneliğinizi ayrıca mağaza ayarlarından iptal '
          'etmeniz gerekir. Bu işlem geri alınamaz.',
      ok: 'Hesabımı sil',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await app.deleteAccount();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(this.icon, this.title, this.onTap, {this.color});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final me = app.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Profili düzenle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ProfileForm(
            initial: me,
            initialPhone: app.myPhone,
            phoneLocked: me?.phoneVerified ?? false,
            submitLabel: 'Kaydet',
            onSubmit: (input) async {
              final navigator = Navigator.of(context);
              try {
                await app.saveProfile(
                  name: input.name,
                  company: input.company,
                  role: input.role,
                  city: input.city,
                  phone: input.phone,
                );
                navigator.pop();
                showSaved(
                  null,
                  'Profil güncellendi',
                  queued: app.lastWriteQueued,
                );
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
        ],
      ),
    );
  }
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late Future<List<PublicProfile>> _future = _load();

  Future<List<PublicProfile>> _load() {
    final app = context.read<AppState>();
    return app.fetchProfiles(app.blocked.toList());
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Engellenen kullanıcılar')),
      body: FutureBuilder<List<PublicProfile>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = (snap.data ?? const <PublicProfile>[])
              .where((p) => app.blocked.contains(p.id))
              .toList();
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.block_outlined,
              title: 'Engellediğiniz kimse yok',
              message:
                  'Bir ilanın veya profilin menüsünden kullanıcıları engelleyebilirsiniz.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final p in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Avatar(p.displayName),
                    title: Text(p.displayName),
                    subtitle: Text(p.role.label),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await app.unblock(p.id);
                          if (mounted) {
                            setState(() {
                              _future = _load();
                            });
                          }
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                      child: const Text('Engeli kaldır'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
