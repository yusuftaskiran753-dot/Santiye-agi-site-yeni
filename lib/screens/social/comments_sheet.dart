import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/social_rules.dart';
import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

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
  bool _negative = false;
  bool _worked = false;
  final _evidence = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _evidence.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    try {
      final review = await app.addComment(
        postId: widget.post.id,
        text: _text.text,
        negative: _negative,
        workedTogether: _worked,
        evidenceNote: _evidence.text,
      );
      if (!mounted) return;
      if (review.verdict == CommentVerdict.filtered) {
        showSnack(context, review.message);
        return;
      }
      _text.clear();
      _evidence.clear();
      setState(() {
        _negative = false;
        _worked = false;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yorumlar',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(LegalNotices.comments, style: TextStyle(fontSize: 12, height: 1.35, color: muted)),
          const SizedBox(height: 12),
          if (comments.isEmpty)
            Text('Henüz yorum yok.', style: TextStyle(color: muted))
          else
            for (final c in comments.take(40))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(app.social.displayName(c.authorId, me: app.me), radius: 16),
                title: Text(app.social.displayName(c.authorId, me: app.me)),
                subtitle: Text(c.text),
              ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Yorum yaz…'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bu olumsuz / eleştiri yorumu'),
            value: _negative,
            onChanged: (v) => setState(() => _negative = v),
          ),
          if (_negative) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Birlikte çalıştınız mı?'),
              value: _worked,
              onChanged: (v) => setState(() => _worked = v ?? false),
            ),
            TextField(
              controller: _evidence,
              decoration: const InputDecoration(
                hintText: 'Kanıt ekle (fotoğraf / sözleşme notu)',
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(onPressed: _send, child: const Text('Gönder')),
          ),
        ],
      ),
    );
  }
}
