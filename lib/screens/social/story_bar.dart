import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/user_avatar.dart';
import 'story_composer_sheet.dart';
import 'story_viewer_screen.dart';

/// Akışın üstündeki hikaye çubuğu: önce "Hikayen", sonra başkalarının
/// hikayeleri (halkalı avatar). Hikayeler 24 saat sonra silinir.
class StoryBar extends StatelessWidget {
  const StoryBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final myId = app.myId ?? '';
    final mine = app.social.activeStoriesOf(myId);
    final others = app.storyAuthorIds;
    return SizedBox(
      height: 112,
      child: ListView(
        key: const Key('story-bar'),
        scrollDirection: Axis.horizontal,
        children: [
          _StoryItem(
            key: const Key('story-mine'),
            userId: myId,
            name: app.me?.displayName ?? 'Ben',
            label: 'Hikayen',
            ring: mine.isNotEmpty,
            showPlus: true,
            onTap: () => mine.isEmpty
                ? showStoryComposer(context)
                : pushPage<void>(context, StoryViewerScreen(userId: myId)),
            onPlus: () => showStoryComposer(context),
          ),
          for (final id in others)
            _StoryItem(
              key: Key('story-$id'),
              userId: id,
              name: app.social.displayName(id, me: app.me),
              label: app.social.displayName(id, me: app.me),
              ring: true,
              onTap: () => pushPage<void>(context, StoryViewerScreen(userId: id)),
            ),
        ],
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  const _StoryItem({
    super.key,
    required this.userId,
    required this.name,
    required this.label,
    required this.ring,
    required this.onTap,
    this.showPlus = false,
    this.onPlus,
  });

  final String userId;
  final String name;
  final String label;
  final bool ring;
  final bool showPlus;
  final VoidCallback onTap;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: ring
                        ? UserAvatar(userId: userId, name: name, radius: 31, ring: true)
                        : Container(
                            padding: const EdgeInsets.all(4.5),
                            child: UserAvatar(userId: userId, name: name, radius: 31),
                          ),
                  ),
                  if (showPlus)
                    Positioned(
                      right: -2,
                      bottom: 0,
                      child: GestureDetector(
                        key: const Key('story-plus'),
                        onTap: onPlus,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
