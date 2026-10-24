import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/backend.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Karşı tarafın iletişim bilgilerini gösterir (arama, WhatsApp, kopyalama).
Future<void> showContactSheet(
  BuildContext context, {
  required Future<ContactInfo> Function() load,
  required String whatsappText,
}) => showAppSheet<void>(
  context,
  (ctx) => _ContactSheet(load: load, whatsappText: whatsappText),
);

class _ContactSheet extends StatefulWidget {
  const _ContactSheet({required this.load, required this.whatsappText});

  final Future<ContactInfo> Function() load;
  final String whatsappText;

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late Future<ContactInfo> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: FutureBuilder<ContactInfo>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            // Gerçek nedeni göster (ör. engelleme, hak açılmamış, kayıt silinmiş);
            // "Tekrar dene" yalnızca bağlantı/sunucu kaynaklı geçici hatalarda anlamlıdır.
            final error = BackendException.from(snap.error!);
            return EmptyState(
              icon: error.isTransient
                  ? Icons.wifi_off_rounded
                  : Icons.info_outline_rounded,
              title: 'İletişim bilgisi alınamadı',
              message: error.message,
              actionLabel: error.isTransient ? 'Tekrar dene' : null,
              onAction: error.isTransient
                  ? () => setState(() {
                      _future = widget.load();
                    })
                  : null,
            );
          }
          final c = snap.data!;
          if (!c.hasPhone) {
            return EmptyState(
              icon: Icons.phone_disabled_outlined,
              title: c.name.isEmpty ? 'Telefon bilgisi yok' : c.name,
              message:
                  'Karşı taraf telefon numarası paylaşmamış veya uygulamayı kullanmıyor.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(c.name, radius: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatPhoneDisplay(c.phone),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              c.phoneVerified
                  ? const Pill(
                      'Telefon doğrulandı',
                      color: AppColors.blue,
                      icon: Icons.phone_iphone_rounded,
                    )
                  : const Pill(
                      'Telefon doğrulanmadı',
                      color: AppColors.grey,
                      icon: Icons.phone_disabled_outlined,
                    ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Ara'),
                      onPressed: () => callPhone(context, c.phone),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('WhatsApp'),
                      onPressed: () =>
                          openWhatsApp(context, c.phone, widget.whatsappText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Numarayı kopyala'),
                  onPressed: () => copyText(
                    context,
                    formatPhoneDisplay(c.phone),
                    done: 'Numara kopyalandı',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: AppColors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tanımadığınız kişilere iş başlamadan ödeme yapmayın. Plaka, kimlik ve belgeleri kontrol edin; '
                        'anlaşmayı uygulamada "Anlaşma kaydı" olarak oluşturun.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
