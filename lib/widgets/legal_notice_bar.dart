import 'package:flutter/material.dart';

import '../utils/legal_notices.dart';

/// Her işlemde (yorum, paylaşım, teklif, mesaj, engelleme…) görünen yasal
/// uyarı çubuğu. Üst satır hep aynıdır: "Mesajlar 24 saat içinde silinir,
/// hakaret yasaktır." [detail] işleme özel ek açıklamadır.
class LegalNoticeBar extends StatelessWidget {
  const LegalNoticeBar({super.key, this.detail = ''});

  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Container(
      key: const Key('legal-notice-bar'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel_rounded, size: 18, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  LegalNotices.everyAction,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: TextStyle(fontSize: 12, height: 1.4, color: muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
