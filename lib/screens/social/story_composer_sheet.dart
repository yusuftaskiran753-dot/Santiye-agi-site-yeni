import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../utils/profanity_filter.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import 'evidence_photo_box.dart';
import 'photo_source_sheet.dart';

/// Hikaye ekleme penceresi: kamera / galeri fotoğrafı ve/veya kısa yazı.
Future<bool> showStoryComposer(BuildContext context) async {
  final ok = await showAppSheet<bool>(context, (_) => const _StoryComposer());
  return ok == true;
}

class _StoryComposer extends StatefulWidget {
  const _StoryComposer();

  @override
  State<_StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends State<_StoryComposer> {
  final _caption = TextEditingController();
  String _photo = '';
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final path = await choosePhoto(
      context,
      title: 'Hikaye fotoğrafı',
      canRemove: _photo.isNotEmpty,
    );
    if (path == null || !mounted) return;
    setState(() => _photo = path);
  }

  Future<void> _share() async {
    final app = context.read<AppState>();
    setState(() => _error = null);
    if (_photo.isEmpty && _caption.text.trim().isEmpty) {
      setState(() => _error = 'Fotoğraf ekleyin veya bir şeyler yazın.');
      return;
    }
    await app.addStory(photoPath: _photo, caption: _caption.text);
    if (!mounted) return;
    Navigator.pop(context, true);
    showSuccess(context, 'Hikayen paylaşıldı. 24 saat sonra silinir.');
  }

  @override
  Widget build(BuildContext context) {
    final warning = ProfanityFilter.validate(_caption.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hikaye ekle', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const LegalNoticeBar(detail: LegalNotices.story),
          const SizedBox(height: 16),
          EvidencePhotoBox(
            path: _photo,
            label: 'Fotoğraf ekle (kamera / galeri)',
            onPick: _pick,
            onClear: () => setState(() => _photo = ''),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('story-caption'),
            controller: _caption,
            maxLength: 140,
            maxLines: 3,
            minLines: 2,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(hintText: 'Kısa bir yazı ekleyin…', errorText: warning),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const Key('story-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: AsyncButton(
              key: const Key('story-share'),
              label: 'Hikayeni paylaş',
              icon: Icons.auto_stories_outlined,
              onPressed: warning == null ? _share : null,
            ),
          ),
        ],
      ),
    );
  }
}
