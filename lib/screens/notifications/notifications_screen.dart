import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../deals/deal_detail_screen.dart';
import '../listings/listing_detail_screen.dart';

/// Bildirimler: yeni teklifler, kabul/ret, anlaşma güncellemeleri, puanlar.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.onOpenWork});

  /// İşlerim sekmesini açar (0: Gelen, 1: Giden, 2: Anlaşmalar).
  final ValueChanged<int> onOpenWork;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
  }

  @override
  void dispose() {
    // Ekrandan çıkınca hepsini okundu say (yeni gelenler ekranda vurgulu kalır).
    // Ağaç kapanırken dinleyicileri tetiklememek için bir sonraki adıma bırakılır.
    final app = _app;
    Future<void>.microtask(app.markNotificationsRead);
    super.dispose();
  }

  IconData _icon(AppNotification n) => switch (n.type) {
        'request' => Icons.mark_email_unread_outlined,
        'request_accepted' => Icons.check_circle_outline_rounded,
        'request_rejected' => Icons.cancel_outlined,
        'deal' => Icons.handshake_outlined,
        'rating' => Icons.star_outline_rounded,
        'moderation' => Icons.report_gmailerrorred_rounded,
        _ => Icons.notifications_none_rounded,
      };

  Color _color(AppNotification n) => switch (n.type) {
        'request_accepted' || 'rating' => AppColors.green,
        'request_rejected' => AppColors.grey,
        'moderation' => AppColors.red,
        'deal' => AppColors.blue,
        _ => AppColors.brand,
      };

  void _open(AppNotification n) {
    final app = context.read<AppState>();
    final id = n.refId;
    if (id == null) return;
    if (n.refType == 'deal') {
      pushPage<void>(context, DealDetailScreen(dealId: id));
      return;
    }
    if (n.refType == 'request') {
      final r = app.requestById(id);
      if (r != null && r.dealId != null) {
        pushPage<void>(context, DealDetailScreen(dealId: r.dealId!));
        return;
      }
      Navigator.of(context).pop();
      widget.onOpenWork(r == null || r.ownerId == app.myId ? 0 : 1);
      return;
    }
    final kind = ListingKind.values.where((k) => k.name == n.refType).firstOrNull;
    if (kind != null) {
      final listing = app.listingById(kind, id);
      if (listing != null) openListing(context, listing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.notifications;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirimler'),
        actions: [
          if (app.unreadCount > 0)
            TextButton(onPressed: app.markNotificationsRead, child: const Text('Tümünü okundu say')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await app.refreshAll();
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        },
        child: list.isEmpty
            ? ListView(
                children: const [
                  EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Bildirim yok',
                    message: 'Yeni teklifler, kabul edilen talepler ve anlaşma güncellemeleri burada görünür.',
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: list.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final n = list[i];
                  final color = _color(n);
                  return Card(
                    color: n.unread ? color.withValues(alpha: 0.06) : null,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      onTap: () => _open(n),
                      leading: IconBadge(_icon(n), color: color, size: 40),
                      title: Text(n.title, style: TextStyle(fontWeight: n.unread ? FontWeight.w800 : FontWeight.w600)),
                      subtitle: Text('${n.body}${n.body.isEmpty ? '' : '\n'}${timeAgo(n.createdAt)}',
                          style: TextStyle(color: muted, height: 1.35)),
                      isThreeLine: n.body.isNotEmpty,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
