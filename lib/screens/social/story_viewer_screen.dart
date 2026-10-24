import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/social.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/legal_notices.dart';
import '../../widgets/common.dart';
import '../../widgets/user_avatar.dart';
import 'story_composer_sheet.dart';

/// Tam ekran hikaye görüntüleyici: sağa dokun = sonraki, sola dokun = önceki.
/// Her hikaye 5 saniye görünür; sonunda kapanır.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.userId});

  final String userId;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  static const _perStory = Duration(seconds: 5);
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(_perStory, _next);
  }

  void _next() {
    final count = context.read<AppState>().social.activeStoriesOf(widget.userId).length;
    if (_index + 1 >= count) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() => _index++);
    _restart();
  }

  void _prev() {
    if (_index == 0) {
      _restart();
      return;
    }
    setState(() => _index--);
    _restart();
  }

  Future<void> _delete(AppState app, SocialStory story) async {
    _timer?.cancel();
    final ok = await confirm(
      context,
      'Hikaye silinsin mi?',
      ok: 'Sil',
      danger: true,
    );
    if (!ok) {
      if (mounted) _restart();
      return;
    }
    await app.deleteStory(story.id);
    if (!mounted) return;
    if (app.social.activeStoriesOf(widget.userId).isEmpty) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _index = 0);
      _restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final stories = app.social.activeStoriesOf(widget.userId);
    if (stories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: const Center(
          child: Text('Hikaye bulunamadı veya süresi doldu.', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    final i = _index.clamp(0, stories.length - 1);
    final story = stories[i];
    final isMine = widget.userId == app.myId;
    final name = app.social.displayName(widget.userId, me: app.me);
    final left = story.remaining();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StoryPage(story: story),
            // sol / sağ dokunma alanları
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    key: const Key('story-prev'),
                    behavior: HitTestBehavior.translucent,
                    onTap: _prev,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    key: const Key('story-next'),
                    behavior: HitTestBehavior.translucent,
                    onTap: _next,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var k = 0; k < stories.length; k++)
                        Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: k <= i ? Colors.white : Colors.white38,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      UserAvatar(userId: widget.userId, name: name, radius: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              '${timeAgo(story.createdAt)} · ${left.inHours} sa sonra silinir',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (isMine)
                        IconButton(
                          key: const Key('story-delete'),
                          tooltip: 'Hikayeyi sil',
                          color: Colors.white,
                          onPressed: () => _delete(app, story),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      IconButton(
                        key: const Key('story-close'),
                        tooltip: 'Kapat',
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMine)
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const Key('story-add-more'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        onPressed: () async {
                          _timer?.cancel();
                          await showStoryComposer(context);
                          if (mounted) _restart();
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Yeni hikaye ekle'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    LegalNotices.everyAction,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    LegalNotices.story,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({required this.story});

  final SocialStory story;

  @override
  Widget build(BuildContext context) {
    if (story.photoPath.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(story.photoPath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
          ),
          if (story.caption.isNotEmpty)
            Align(
              alignment: const Alignment(0, 0.55),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  story.caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.35),
                ),
              ),
            ),
        ],
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.brand, AppColors.purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Text(
        story.caption,
        key: const Key('story-text'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
    );
  }
}
