import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// "Nasıl çalışır?" ve "Güvenli ticaret" rehberi.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<AppState>().usage;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rehber'),
          bottom: const TabBar(tabs: [Tab(text: 'Nasıl çalışır?'), Tab(text: 'Güvenli ticaret')]),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const _Step(1, Icons.post_add_rounded, 'İlan verin veya ilanlara göz atın',
                    'Yük, makine, malzeme ve personel ilanları ücretsizdir. İlanınızda telefonunuz görünmez.'),
                _Step(2, Icons.call_rounded, 'İletişim / teklif',
                    'Bir ilan sahibine ulaşmak ya da teklif vermek için iletişim hakkı açarsınız. Her ay '
                        '${usage.freeLimit} hak ücretsizdir; sonrasında 1 kredi kullanılır ya da Premium ile sınırsızdır.'),
                const _Step(3, Icons.handshake_rounded, 'Anlaşma kaydı',
                    'İlan sahibi teklifi kabul edince iki taraf arasında dijital bir anlaşma kaydı oluşur. '
                        'Bedel, ödeme planı ve teslim durumu buradan takip edilir.'),
                const _Step(4, Icons.account_balance_wallet_outlined, 'Ödeme doğrudan',
                    'Ödemeyi taraflar kendi aralarında (havale, nakit, çek) yapar ve kayıtta "Ödedim / Tahsil ettim" olarak işaretler. '
                        'Uygulama paranıza dokunmaz, komisyon kesmez.'),
                const _Step(5, Icons.star_rounded, 'Puanlama',
                    'İş tamamlanınca taraflar birbirini puanlar. Puanlar yalnızca gerçek anlaşmalardan gelir.'),
                const SizedBox(height: 10),
                const InfoBanner(
                  title: 'Uygulamanın rolü',
                  text: '${AppConfig.appName} bir ilan ve buluşma platformudur. Taşıma, kiralama, satış ve iş ilişkilerinin '
                      'tarafı değildir; işin yapılması, ödenmesi, fatura ve yasal izinler (K belgesi, SRC, MYK vb.) tarafların '
                      'sorumluluğundadır.',
                  icon: Icons.info_outline_rounded,
                ),
                const SizedBox(height: 12),
                const SectionTitle('Premium ve kredi'),
                Text(
                  'Premium (aylık/yıllık) sınırsız iletişim, sınırsız ilan, Premium rozeti ve hafriyat planlama sunar. '
                  'Krediler; ücretsiz hak bittiğinde iletişim açmak ve ilanınızı öne çıkarmak için kullanılır '
                  '(24 saat: ${usage.boostDayCost} kredi, 7 gün: ${usage.boostWeekCost} kredi). Satın alımlar Google Play '
                  'veya App Store hesabınız üzerinden yapılır.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45),
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: const [
                _Tip(Icons.verified_user_outlined, 'Profili inceleyin',
                    'Puan, tamamlanan iş sayısı, "Telefon doğrulandı" ve "Onaylı firma" rozetlerine bakın. Yeni üyelerde ekstra dikkatli olun.'),
                _Tip(Icons.money_off_rounded, 'Peşin ödemeden kaçının',
                    'Tanımadığınız kişiye iş başlamadan para göndermeyin. "Kapora/sigorta için önce ödeme" isteyenlere şüpheyle yaklaşın.'),
                _Tip(Icons.receipt_long_outlined, 'Anlaşmayı kayda alın',
                    'Teklifi uygulama üzerinden kabul edin; böylece bedel ve ödeme planı iki taraf için de kayıt altında olur.'),
                _Tip(Icons.badge_outlined, 'Belgeleri kontrol edin',
                    'Nakliyede plaka, ruhsat, K belgesi ve SRC; makinede operatör belgesi (MYK, G sınıfı) ve sigortayı sorun.'),
                _Tip(Icons.description_outlined, 'Evrak isteyin',
                    'Fatura, irsaliye, kantar fişi ve teslim tutanağı alın; fotoğrafını saklayın.'),
                _Tip(Icons.flag_outlined, 'Şüpheliyi bildirin',
                    'Sahte ilan veya dolandırıcılık şüphesinde ilan menüsünden "Şikâyet et"i kullanın. Birden fazla şikâyet alan '
                        'ilan otomatik olarak yayından kalkar. Gerekirse emniyet birimlerine başvurun.'),
                SizedBox(height: 8),
                ResponsibilityNote(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.icon, this.title, this.text);

  final int number;
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.brand,
            child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.title, this.text);

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon, color: AppColors.teal, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
