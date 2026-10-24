import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../utils/profanity_filter.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';
import 'evidence_photo_box.dart';

Future<void> showCommentsSheet(BuildContext context, SocialPost post) =>
    showAppSheet<void>(context, (_) => CommentsSheet(post: post));

class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.post});
  final SocialPost post;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _text = TextEditingController();
  final _evidence = TextEditingController();
  bool _negative = false;

  /// "Bu kişiyle çalıştınız mı?" yanıtı: null = henüz yanıtlanmadı.
  bool? _worked;
  String _photo = '';
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _evidence.dispose();
    super.dispose();
  }

  /// Yazarken küfür varsa anında uyarır (gönderim yine de sunucuda denetlenir).
  String? get _liveWarning => ProfanityFilter.validate(_text.text);

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
    );
    if (file != null && mounted) setState(() => _photo = file.path);
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    setState(() => _error = null);
    try {
      final review = await app.addComment(
        postId: widget.post.id,
        text: _text.text,
        negative: _negative,
        workedTogether: _worked ?? false,
        workedAnswered: _worked != null,
        evidenceNote: _evidence.text,
        evidencePhotoPath: _worked == false || _negative ? _photo : '',
      );
      if (!mounted) return;
      if (review.verdict == CommentVerdict.filtered ||
          review.verdict == CommentVerdict.evidenceRequired) {
        setState(() => _error = review.message);
        return;
      }
      _text.clear();
      _evidence.clear();
      setState(() {
        _negative = false;
        _worked = null;
        _photo = '';
      });
      if (review.verdict == CommentVerdict.pendingModeration) {
        showSnack(context, review.message);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final comments = app.social.publishedComments(widget.post.id);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final needsEvidence = _worked == false || _negative;
    final warning = _liveWarning;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yorumlar',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const LegalNoticeBar(detail: LegalNotices.comments),
          const SizedBox(height: 16),
          if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Henüz yorum yok.', style: TextStyle(color: muted)),
            )
          else
            for (final c in comments.take(40)) _CommentTile(comment: c),
          const SizedBox(height: 12),
          TextField(
            key: const Key('comment-text'),
            controller: _text,
            maxLines: 3,
            minLines: 2,
            maxLength: 300,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              hintText: 'Yorum yazın…',
              errorText: warning,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bu kişiyle çalıştınız mı?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AnswerButton(
                  key: const Key('worked-yes'),
                  label: 'Evet',
                  icon: Icons.handshake_outlined,
                  selected: _worked == true,
                  onTap: () => setState(() {
                    _worked = true;
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AnswerButton(
                  key: const Key('worked-no'),
                  label: 'Hayır',
                  icon: Icons.person_search_outlined,
                  selected: _worked == false,
                  onTap: () => setState(() {
                    _worked = false;
                    _error = null;
                  }),
                ),
              ),
            ],
          ),
          if (_worked == null) ...[
            const SizedBox(height: 6),
            Text(
              LegalNotices.workedTogether,
              style: TextStyle(fontSize: 12, height: 1.4, color: muted),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bu bir olumsuz / eleştiri yorumu'),
            value: _negative,
            onChanged: (v) => setState(() => _negative = v),
          ),
          if (needsEvidence) ...[
            InfoBanner(
              text: _worked == false
                  ? 'Bu kişiyle çalışmadığınız için kanıt gerekli. Fotoğraf '
                        'ekleyin veya bu kişiyi nereden bildiğinizi yazın.'
                  : 'Olumsuz yorum için birlikte çalışma kanıtı gerekir; '
                        'kanıtsız olumsuz yorum incelemeye düşer.',
              icon: Icons.fact_check_outlined,
              color: Colors.deepOrange,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('comment-evidence'),
              controller: _evidence,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Kanıt açıklaması (sözleşme, tarih, şantiye…)',
              ),
            ),
            const SizedBox(height: 10),
            EvidencePhotoBox(
              path: _photo,
              label: 'Kanıt fotoğrafı ekle',
              onPick: _pickPhoto,
              onClear: () => setState(() => _photo = ''),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('comment-error'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const Key('comment-send'),
              onPressed: warning == null ? _send : null,
              child: const Text('Yorumu gönder', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 52,
      child: selected
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontSize: 16)),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: primary.withValues(alpha: 0.4)),
              ),
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontSize: 16)),
            ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final SocialComment comment;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final name = app.social.displayName(comment.authorId, me: app.me);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(name, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(comment.text, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 4),
                Text(
                  comment.workedTogether
                      ? 'Birlikte çalıştı'
                      : comment.hasEvidence
                      ? 'Kanıt eklendi'
                      : '',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
