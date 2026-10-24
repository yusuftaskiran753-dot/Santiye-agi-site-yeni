import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/social.dart';
import '../../models/trade.dart';
import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

class ComposerScreen extends StatefulWidget {
  const ComposerScreen({super.key, this.kind = SocialPostKind.work});

  final SocialPostKind kind;

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _caption = TextEditingController();
  late Set<WorkSector> _sectors;
  String _photo = '';

  @override
  void initState() {
    super.initState();
    _sectors = {...context.read<AppState>().myIdentity.sectors};
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (file == null) return;
    setState(() => _photo = file.path);
  }

  Future<void> _submit() async {
    if (!validateForm(context, _formKey)) return;
    if (_sectors.isEmpty) {
      showSnack(context, 'En az bir sektör seçin.');
      return;
    }
    final app = context.read<AppState>();
    try {
      await app.createPost(
        kind: widget.kind,
        caption: _caption.text,
        sectors: _sectors.toList(),
        photoPath: _photo,
      );
      if (mounted) Navigator.pop(context);
      showSaved(null, 'Paylaşıldı', queued: false);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(widget.kind.label)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(LegalNotices.comments, style: TextStyle(fontSize: 12, color: muted, height: 1.35)),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Ne yaptınız / ne arıyorsunuz?',
              controller: _caption,
              maxLength: FieldLimits.note,
              maxLines: 5,
              validator: Validators.text(label: 'Metin', min: 4, max: FieldLimits.note),
            ),
            const FieldLabel('Sektör'),
            MultiChoiceWrap<WorkSector>(
              values: WorkSector.values,
              selected: _sectors,
              labelOf: (s) => s.label,
              onChanged: (s) => setState(() => _sectors = s),
            ),
            const SizedBox(height: 12),
            // TODO: ızgara duvarı, filtreler, kapak kırpma.
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.photo_outlined),
              label: Text(_photo.isEmpty ? 'Fotoğraf ekle' : 'Fotoğraf seçildi'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton(onPressed: _submit, child: const Text('Paylaş')),
          ),
        ),
      ),
    );
  }
}
