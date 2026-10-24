import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/social_rules.dart';
import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../utils/legal_notices.dart';
import '../../utils/profanity_filter.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';

/// Fiyat teklifi penceresi. Açıklama zorunludur; telefon numarası görünmez,
/// ihaleyi açan onaylarsa paylaşılır.
Future<bool> showBidSheet(BuildContext context, Tender tender) async {
  final ok = await showAppSheet<bool>(context, (_) => _BidSheet(tender: tender));
  return ok == true;
}

class _BidSheet extends StatefulWidget {
  const _BidSheet({required this.tender});
  final Tender tender;

  @override
  State<_BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends State<_BidSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _reference = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!validateForm(context, _formKey)) return;
    final app = context.read<AppState>();
    await app.bidTender(
      tender: widget.tender,
      amount: parseNumber(_amount.text),
      note: _note.text,
      referenceNote: _reference.text,
    );
    if (!mounted) return;
    Navigator.pop(context, true);
    showSuccess(context, 'Teklifiniz iletildi. Telefonunuz gizli kalır.');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fiyat teklifi ver',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              widget.tender.title,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            const LegalNoticeBar(detail: LegalNotices.bid),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Teklif tutarı (₺)',
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textCapitalization: TextCapitalization.none,
              validator: (v) {
                final n = tryParseNumber(v ?? '');
                if (n == null || n <= 0) return 'Teklif tutarını girin';
                return null;
              },
            ),
            LabeledField(
              label: 'Açıklama (zorunlu)',
              controller: _note,
              maxLines: 4,
              maxLength: FieldLimits.note,
              helper: 'Fiyata neyin dâhil olduğunu, süreyi ve ödeme beklentinizi yazın.',
              validator: Validators.all([
                Validators.text(
                  label: 'Açıklama',
                  min: SocialRules.minBidNoteLength,
                  max: FieldLimits.note,
                  multiline: true,
                ),
                ProfanityFilter.validate,
              ]),
            ),
            LabeledField(
              label: 'Referans / geçmiş iş (isteğe bağlı)',
              controller: _reference,
              maxLines: 2,
              maxLength: 200,
              validator: Validators.all([
                Validators.text(
                  label: 'Referans',
                  isRequired: false,
                  max: 200,
                  multiline: true,
                ),
                ProfanityFilter.validate,
              ]),
            ),
            SizedBox(
              height: 54,
              child: AsyncButton(
                label: 'Teklifi gönder',
                icon: Icons.send_rounded,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
