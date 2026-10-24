import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import 'deal_detail_screen.dart';

Color dealStatusColor(DealStatus s) => switch (s) {
      DealStatus.pending => AppColors.amber,
      DealStatus.active => AppColors.blue,
      DealStatus.delivered => AppColors.teal,
      DealStatus.completed => AppColors.green,
      DealStatus.cancelled => AppColors.grey,
      DealStatus.disputed => AppColors.red,
    };

IconData dealKindIcon(DealKind k) => switch (k) {
      DealKind.yuk => Icons.local_shipping_rounded,
      DealKind.makine => Icons.construction_rounded,
      DealKind.malzeme => Icons.inventory_2_rounded,
      DealKind.personel => Icons.work_rounded,
      DealKind.sicil => Icons.engineering_rounded,
      DealKind.diger => Icons.handshake_rounded,
    };

/// Anlaşmayı paylaşılabilir düz metne çevirir.
String dealSummaryText(Deal d) {
  final b = StringBuffer()
    ..writeln('ANLAŞMA ÖZETİ · ${AppConfig.appName}')
    ..writeln('Kod: ${d.code}')
    ..writeln('İş: ${d.title}')
    ..writeln('İşi veren / alıcı: ${d.customerName.isEmpty ? '-' : d.customerName}')
    ..writeln('Hizmet veren / satıcı: ${d.providerName.isEmpty ? '-' : d.providerName}');
  if (d.amount > 0) b.writeln('Bedel: ${formatTL(d.amount)} · Ödeme şekli: ${d.paymentMethod.label}');
  if (d.paymentTerms.isNotEmpty) b.writeln('Ödeme koşulu: ${d.paymentTerms}');
  if (d.startDate != null) b.writeln('Başlangıç: ${formatDate(d.startDate!)}');
  if (d.milestones.isNotEmpty) {
    b.writeln('Ödeme planı:');
    for (final m in d.milestones) {
      final state = m.received ? 'tahsil edildi' : (m.paid ? 'ödendi bildirildi' : 'bekliyor');
      b.writeln(' • ${m.title}: ${formatTL(m.amount)} ($state)');
    }
  }
  if (d.details.isNotEmpty) b.writeln('Detay: ${d.details.replaceAll('\n', ' · ')}');
  b
    ..writeln('Durum: ${d.status.label} · Oluşturma: ${formatDate(d.createdAt)}')
    ..writeln()
    ..write('Bu metin, taraflarca ${AppConfig.appName} uygulamasında tutulan kaydın özetidir. '
        '${AppConfig.appName} ödemeye aracılık etmez ve sözleşmenin tarafı değildir.');
  return b.toString();
}

/// Anlaşma listesi kartı.
class DealCard extends StatelessWidget {
  const DealCard({super.key, required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = deal;
    final me = app.myId;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final needsMe = app.dealNeedsMe(d);
    final planned = d.plannedTotal;
    final progress = planned <= 0 ? 0.0 : (d.receivedTotal / planned).clamp(0.0, 1.0).toDouble();
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: needsMe
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.6),
            )
          : null,
      child: InkWell(
        onTap: () => pushPage<void>(context, DealDetailScreen(dealId: d.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(dealKindIcon(d.kind), color: dealStatusColor(d.status), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${d.counterpartyName(me)} · ${d.kind.label}',
                            style: TextStyle(color: muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (d.amount > 0)
                    Text(formatTL(d.amount), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                ],
              ),
              if (planned > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: AppColors.green,
                    backgroundColor: muted.withValues(alpha: 0.15),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Pill(d.status.label, color: dealStatusColor(d.status)),
                  if (needsMe) ...[
                    const SizedBox(width: 6),
                    const Pill('Sizi bekliyor', color: AppColors.brand, filled: true),
                  ],
                  const Spacer(),
                  if (planned > 0)
                    Text('Tahsil: ${formatTL(d.receivedTotal)}', style: TextStyle(fontSize: 12.5, color: muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tek satırlık metin isteyen diyalog (not, iptal nedeni, sorun açıklaması).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String ok = 'Gönder',
  bool mandatory = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => _PromptDialog(title: title, hint: hint, ok: ok, mandatory: mandatory),
    );

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.ok, required this.mandatory, this.hint});

  final String title;
  final String? hint;
  final String ok;
  final bool mandatory;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _controller = TextEditingController();
  late final FieldValidator _validator =
      Validators.text(label: 'Metin', isRequired: widget.mandatory, max: 300, multiline: true);
  bool _touched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _validator(_controller.text);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 300,
        // Not, anlaşma geçmişinde karşı tarafa görünür: uygunsuz ifade süzülür.
        decoration: InputDecoration(hintText: widget.hint, errorText: _touched ? error : null),
        onChanged: (_) => setState(() => _touched = true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: error != null ? null : () => Navigator.pop(context, Sanitize.block(_controller.text)),
          child: Text(widget.ok),
        ),
      ],
    );
  }
}
