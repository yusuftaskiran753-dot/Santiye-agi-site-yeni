import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

/// Engellerken gerekçe zorunlu.
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
  String _reason = kBlockReasons.first;
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!validateForm(context, _formKey)) return;
    final extra = Sanitize.line(_note.text);
    final full = extra.isEmpty ? _reason : '$_reason · $extra';
    final app = context.read<AppState>();
    try {
      await app.block(widget.userId, reason: full);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Engelle',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              LegalNotices.block,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const FieldLabel('Gerekçe (zorunlu)'),
            ChoiceWrap<String>(
              values: kBlockReasons,
              selected: _reason,
              labelOf: (s) => s,
              onSelected: (s) => setState(() => _reason = s),
            ),
            const SizedBox(height: 8),
            LabeledField(
              label: 'Kısa açıklama',
              controller: _note,
              maxLength: 140,
              validator: Validators.text(
                label: 'Açıklama',
                isRequired: false,
                max: 140,
              ),
            ),
            AsyncButton(label: 'Engelle', onPressed: _submit),
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
