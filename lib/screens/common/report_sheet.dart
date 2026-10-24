import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../utils/validators.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import '../social/block_reason_sheet.dart';

/// Şikâyet formu. [targetType]: ilan türü adı · profil · anlasma
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  String? ownerId,
}) =>
    showAppSheet<void>(
      context,
      (ctx) => _ReportSheet(targetType: targetType, targetId: targetId, ownerId: ownerId),
    );

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.targetType, required this.targetId, this.ownerId});

  final String targetType;
  final String targetId;
  final String? ownerId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = kReportReasons.first;
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();
  bool _alsoBlock = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!validateForm(context, _formKey)) return;
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      await app.report(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: _reason,
        note: Sanitize.block(_note.text),
      );
      final queued = app.lastWriteQueued;
      final owner = widget.ownerId;
      // Engelleme için sebep ve kanıt fotoğrafı sorulur; vazgeçilirse yalnız şikâyet gider.
      if (_alsoBlock && owner != null && owner != app.myId && mounted) {
        await showBlockReasonSheet(context, owner);
      }
      navigator.pop();
      showSaved(
        null,
        'Teşekkürler, şikâyetiniz alındı. Birden fazla şikâyet alan içerik otomatik olarak yayından kaldırılır.',
        queued: queued || app.lastWriteQueued,
      );
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _send);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Şikâyet et', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const LegalNoticeBar(detail: LegalNotices.responsibility),
          const SizedBox(height: 10),
          Text('Şikâyetiniz gizli tutulur; karşı tarafa adınız bildirilmez.', style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v ?? _reason),
            child: Column(
              children: [
                for (final r in kReportReasons)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: r,
                    title: Text(r),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          LabeledField(
            label: 'Açıklama (isteğe bağlı)',
            controller: _note,
            maxLines: 3,
            maxLength: FieldLimits.reportNote,
            // Şikâyet metni uygunsuz ifadeyi alıntılayabilir; süzgeç uygulanmaz.
            validator: Validators.text(label: 'Açıklama', isRequired: false, max: FieldLimits.reportNote, multiline: true, filter: false),
          ),
          if (widget.ownerId != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _alsoBlock,
              onChanged: (v) => setState(() => _alsoBlock = v ?? false),
              title: const Text('Bu kullanıcıyı da engelle'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: 8),
          AsyncButton(label: 'Şikâyeti gönder', icon: Icons.flag_outlined, onPressed: _send),
          if (AppConfig.supportEmail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Acil durumlar ve dolandırıcılık için ayrıca ${AppConfig.supportEmail} adresine yazabilir, '
              'gerekirse emniyet birimlerine başvurabilirsiniz.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ],
        ),
      ),
    );
  }
}
