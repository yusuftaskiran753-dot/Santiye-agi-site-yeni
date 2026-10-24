import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../deals/deal_form_screen.dart';
import '../deals/deal_widgets.dart';
import '../listings/cards.dart';
import '../listings/forms/listing_forms.dart';
import '../listings/listing_detail_screen.dart';
import 'request_tile.dart';

/// İşlerim: gelen ve giden teklifler, anlaşmalar ve ilanlarım.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key, required this.tab, required this.onOpenMarket});

  /// Dışarıdan açılacak sekme (0: Gelen, 1: Giden, 2: Anlaşmalar, 3: İlanlarım).
  final ValueNotifier<int> tab;
  final VoidCallback onOpenMarket;

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.tab.value.clamp(0, 3).toInt());

  @override
  void initState() {
    super.initState();
    widget.tab.addListener(_onExternalTab);
  }

  @override
  void dispose() {
    widget.tab.removeListener(_onExternalTab);
    _tabs.dispose();
    super.dispose();
  }

  void _onExternalTab() {
    final i = widget.tab.value.clamp(0, 3).toInt();
    if (_tabs.index != i) _tabs.animateTo(i);
  }

  Future<void> _refresh() async {
    try {
      await context.read<AppState>().refreshAll();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _badge(String label, int count) => Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        offset: const Offset(14, -6),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final incoming = app.incomingRequests
      ..sort((a, b) {
        if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    final outgoing = app.outgoingRequests..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final mine = app.allMine
      ..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('İşlerim'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(child: _badge('Gelen', app.pendingIncoming)),
            const Tab(text: 'Giden'),
            Tab(child: _badge('Anlaşmalar', app.dealsNeedingMe)),
            const Tab(text: 'İlanlarım'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _RefreshList(
            onRefresh: _refresh,
            children: [
              if (incoming.isEmpty)
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Henüz gelen teklif yok',
                  message: 'İlan verdiğinizde gelen teklif ve talepler burada listelenir.',
                  actionLabel: 'İlan ver',
                  onAction: () => showPostSheet(context),
                ),
              for (final r in incoming)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: RequestTile(request: r)),
            ],
          ),
          _RefreshList(
            onRefresh: _refresh,
            children: [
              if (outgoing.isEmpty)
                EmptyState(
                  icon: Icons.outbox_outlined,
                  title: 'Henüz teklif göndermediniz',
                  message: 'İlanlara göz atın; teklif ve talepleriniz burada takip edilir.',
                  actionLabel: 'İlanlara göz at',
                  onAction: widget.onOpenMarket,
                ),
              for (final r in outgoing)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: RequestTile(request: r)),
            ],
          ),
          _DealsTab(onRefresh: _refresh),
          _RefreshList(
            onRefresh: _refresh,
            children: [
              if (mine.isEmpty)
                EmptyState(
                  icon: Icons.post_add_rounded,
                  title: 'Henüz ilanınız yok',
                  message: 'Yük, makine, malzeme veya personel ilanı verin; teklifler size gelsin.',
                  actionLabel: 'İlan ver',
                  onAction: () => showPostSheet(context),
                ),
              for (final l in mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListingRow(listing: l, onTap: () => openListing(context, l)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RefreshList extends StatelessWidget {
  const _RefreshList({required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: children,
      ),
    );
  }
}

class _DealsTab extends StatelessWidget {
  const _DealsTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final waiting = app.deals.where(app.dealNeedsMe).toList();
    final open = app.deals.where((d) => d.status.isOpen && !app.dealNeedsMe(d)).toList();
    final closed = app.deals.where((d) => !d.status.isOpen && !app.dealNeedsMe(d)).toList();

    return _RefreshList(
      onRefresh: onRefresh,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Yeni kayıt'),
                onPressed: () => pushPage<void>(context, const DealFormScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.key_rounded),
                label: const Text('Kodla katıl'),
                onPressed: () => showJoinDealSheet(context),
              ),
            ),
          ],
        ),
        if (app.deals.isEmpty)
          const EmptyState(
            icon: Icons.handshake_outlined,
            title: 'Henüz anlaşma kaydınız yok',
            message: 'Bir teklif kabul edildiğinde anlaşma kaydı otomatik oluşur. İlan dışındaki işleriniz için '
                '"Yeni kayıt" ile kendiniz oluşturabilirsiniz.',
          ),
        if (waiting.isNotEmpty) ...[
          const SectionTitle('Sizi bekleyenler'),
          for (final d in waiting) Padding(padding: const EdgeInsets.only(bottom: 10), child: DealCard(deal: d)),
        ],
        if (open.isNotEmpty) ...[
          const SectionTitle('Devam edenler'),
          for (final d in open) Padding(padding: const EdgeInsets.only(bottom: 10), child: DealCard(deal: d)),
        ],
        if (closed.isNotEmpty) ...[
          const SectionTitle('Tamamlanan ve iptal edilenler'),
          for (final d in closed) Padding(padding: const EdgeInsets.only(bottom: 10), child: DealCard(deal: d)),
        ],
      ],
    );
  }
}
