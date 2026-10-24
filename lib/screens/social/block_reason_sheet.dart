import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import 'evidence_photo_box.dart';

/// Engellerken sebep seçimi ve kanıt fotoğrafı zorunlu.
Future<bool> showBlockReasonSheet(BuildContext context, String userId) async {
  final ok = await showAppSheet<bool>(
    context,
    (ctx) => _BlockReasonSheet(userId: userId),
  );
  return ok == true;
}

class _BlockReasonSheet extends StatefulWidget {
  const _BlockReasonSheet({required this.userId});
  final String userId;

  @override
  State<_BlockReasonSheet> createState() => _BlockReasonSheetState();
}

class _BlockReasonSheetState extends State<_BlockReasonSheet> {
  /// Sebep seçilmeden engellenemez (varsayılan seçili gelmez).
  String? _reason;
  String _photo = '';
  bool _tried = false;
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
    );
    if (file != null && mounted) setState(() => _photo = file.path);
  }

  Future<void> _submit() async {
    setState(() => _tried = true);
    if (!validateForm(context, _formKey)) return;
    if (_reason == null || _photo.isEmpty) return;
    final extra = Sanitize.line(_note.text);
    final full = extra.isEmpty ? _reason! : '$_reason · $extra';
    final app = context.read<AppState>();
    try {
      await app.blockWithProof(
        widget.userId,
        reason: full,
        evidencePhotoPath: _photo,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final error = Theme.of(context).colorScheme.error;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Engelle',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const LegalNoticeBar(detail: LegalNotices.blockEvidence),
            const SizedBox(height: 8),
            Text(
              LegalNotices.block,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Sebep (zorunlu)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in kBlockReasons)
                  ChoiceChip(
                    label: Text(r),
                    selected: _reason == r,
                    onSelected: (_) => setState(() => _reason = r),
                  ),
              ],
            ),
            if (_tried && _reason == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Engellemek için bir sebep seçin.',
                  style: TextStyle(color: error, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 16),
            const FieldLabel('Kanıt fotoğrafı (zorunlu)'),
            EvidencePhotoBox(
              path: _photo,
              label: 'Kanıt fotoğrafı ekle',
              onPick: _pick,
              onClear: () => setState(() => _photo = ''),
              errorText: _tried && _photo.isEmpty
                  ? 'Engellemek için kanıt fotoğrafı eklemelisiniz.'
                  : null,
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: 'Kısa açıklama (isteğe bağlı)',
              controller: _note,
              maxLength: 140,
              validator: Validators.text(
                label: 'Açıklama',
                isRequired: false,
                max: 140,
              ),
            ),
            SizedBox(
              height: 54,
              child: AsyncButton(
                label: 'Engelle',
                icon: Icons.block_rounded,
                color: Theme.of(context).colorScheme.error,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const List<String> kBlockReasons = [
  'Hakaret / küfür',
  'Karalama / asılsız iddia',
  'Spam veya rahatsız etme',
  'Dolandırıcılık şüphesi',
  'İş dışı taciz',
  'Diğer',
];
