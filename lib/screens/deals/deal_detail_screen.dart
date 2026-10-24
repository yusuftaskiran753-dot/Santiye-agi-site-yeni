import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../common/report_sheet.dart';
import '../listings/contact_sheet.dart';
import 'deal_widgets.dart';
import '../../services/live_share_service.dart';
import 'live_location_screen.dart';

/// Anlaşma kaydı: taraflar, bedel, ödeme takibi, durum ve işlem geçmişi.
class DealDetailScreen extends StatelessWidget {
  const DealDetailScreen({super.key, required this.dealId});

  final String dealId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = app.dealById(dealId);
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Anlaşma')),
        body: EmptyState(
          icon: Icons.handshake_outlined,
          title: 'Anlaşma yükleniyor veya bulunamadı',
          actionLabel: 'Yenile',
          onAction: () => app.refreshRequestsAndDeals().catchError((Object e) {
            if (context.mounted) showError(context, e);
          }),
        ),
      );
    }
    final me = app.myId;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anlaşma kaydı'),
        actions: [
          IconButton(
            tooltip: 'Özeti paylaş',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => shareOnWhatsApp(context, dealSummaryText(d)),
          ),
          _DealMenu(deal: d),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => app.refreshRequestsAndDeals().catchError((Object e) {
          if (context.mounted) showError(context, e);
        }),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill(d.status.label, color: dealStatusColor(d.status)),
                Pill(
                  d.kind.label,
                  color: AppColors.grey,
                  icon: dealKindIcon(d.kind),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              d.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Kayıt kodu: ', style: TextStyle(color: muted)),
                SelectableText(
                  d.code,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                IconButton(
                  tooltip: 'Kopyala',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () =>
                      copyText(context, d.code, done: 'Kod kopyalandı'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _NextStep(deal: d),
            if (context.read<LiveShareService?>() != null)
              LiveLocationCard(deal: d),
            if (d.cancelRequestedBy != null)
              InfoBanner(
                title: 'İptal onayı bekleniyor',
                text: d.cancelRequestedBy == app.myId
                    ? 'İptal talebiniz karşı tarafa iletildi.'
                    : 'Karşı taraf iptal istedi. Kabul ediyorsanız menüden "İptali onayla" seçin.',
                icon: Icons.pending_actions,
              ),
            const SectionTitle('Taraflar'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    InfoRow(
                      'İşi veren / alıcı',
                      '${d.customerName.isEmpty ? 'Henüz katılmadı' : d.customerName}${d.isCustomer(me) ? ' (siz)' : ''}',
                      icon: Icons.person_outline,
                    ),
                    InfoRow(
                      'Hizmet veren / satıcı',
                      '${d.providerName.isEmpty ? 'Henüz katılmadı' : d.providerName}${d.isProvider(me) ? ' (siz)' : ''}',
                      icon: Icons.engineering_outlined,
                    ),
                    if (d.counterpartyId(me) != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: Text('${d.counterpartyName(me)} ile iletişim'),
                          onPressed: () => showContactSheet(
                            context,
                            load: () => app.contactForDeal(d),
                            whatsappText:
                                'Merhaba, ${AppConfig.appName}\'ndaki "${d.title}" anlaşmamız hakkında yazıyorum.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SectionTitle('Bedel ve ödeme'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    InfoRow(
                      'Toplam bedel',
                      d.amount > 0 ? formatTL(d.amount) : 'Belirtilmedi',
                      icon: Icons.payments_outlined,
                    ),
                    InfoRow(
                      'Ödeme şekli',
                      d.paymentMethod.label,
                      icon: Icons.account_balance_outlined,
                    ),
                    if (d.paymentTerms.isNotEmpty)
                      InfoRow(
                        'Ödeme koşulu',
                        d.paymentTerms,
                        icon: Icons.rule_rounded,
                      ),
                    if (d.startDate != null)
                      InfoRow(
                        'Başlangıç',
                        formatDate(d.startDate!),
                        icon: Icons.event_outlined,
                      ),
                    if (d.plannedTotal > 0) ...[
                      InfoRow(
                        'Ödendi bildirilen',
                        formatTL(d.paidTotal),
                        icon: Icons.outbox_outlined,
                      ),
                      InfoRow(
                        'Tahsil edilen',
                        formatTL(d.receivedTotal),
                        icon: Icons.task_alt_rounded,
                        valueColor: AppColors.green,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (d.milestones.isNotEmpty) ...[
              const SectionTitle('Ödeme takibi'),
              Text(
                'Para uygulama üzerinden geçmez. Ödemeyi yapan "Ödedim", alan "Tahsil ettim" der; kayıt iki tarafça da görülür.',
                style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < d.milestones.length; i++)
                _MilestoneTile(deal: d, index: i),
            ],
            if (d.details.isNotEmpty) ...[
              const SectionTitle('Detaylar'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(d.details, style: const TextStyle(height: 1.45)),
                ),
              ),
            ],
            const SectionTitle('İşlem geçmişi'),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final l in d.log.reversed)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.circle,
                          size: 10,
                          color: dealStatusColor(d.status),
                        ),
                        title: Text(l.text),
                        subtitle: Text('${l.by} · ${formatDateTime(l.at)}'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const ResponsibilityNote(
              text:
                  'Bu kayıt taraflar arasındaki anlaşmanın dijital özetidir. İşin yapılması, teslimi ve ödemesi '
                  'tarafların sorumluluğundadır; uygulama ödemeye aracılık etmez ve sözleşmenin tarafı değildir. '
                  'Fatura/irsaliye düzenleme yükümlülüğü taraflara aittir.',
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> runDealAction(
  BuildContext context,
  Deal deal,
  DealAction action, {
  int? index,
  String? note,
  String? success,
}) async {
  final app = context.read<AppState>();
  try {
    await app.dealAction(deal, action, index: index, note: note);
    if (success != null) showSaved(null, success, queued: app.lastWriteQueued);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Durumuna göre kullanıcının yapması gereken bir sonraki adım.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = deal;
    final me = app.myId;
    final creator = d.createdBy == me;
    final canC = d.canActAsCustomer(me);
    final canP = d.canActAsProvider(me);

    switch (d.status) {
      case DealStatus.pending:
        if (creator && d.awaitingCounterparty) {
          final invite =
              'Merhaba, ${AppConfig.appName}\'nda aramızdaki "${d.title}" işi için anlaşma kaydı oluşturdum. '
              'Uygulamada İşlerim → Anlaşmalar → "Kodla katıl" bölümüne ${d.code} kodunu girerek onaylayabilirsin.';
          return _StepCard(
            color: AppColors.amber,
            icon: Icons.group_add_outlined,
            title: 'Karşı tarafı davet edin',
            text:
                'Karşı taraf uygulamadaysa ${d.code} koduyla katılıp onaylar. Uygulamayı kullanmıyorsa kaydı kendiniz başlatıp '
                'ödemeleri tek taraflı takip edebilirsiniz.',
            actions: [
              AsyncButton(
                icon: Icons.chat_rounded,
                label: 'WhatsApp ile davet et',
                onPressed: () => shareOnWhatsApp(context, invite),
              ),
              const SizedBox(height: 8),
              AsyncButton(
                outlined: true,
                label: 'Kendi kaydım olarak başlat',
                onPressed: () async {
                  if (!await confirm(
                    context,
                    'Kayıt başlatılsın mı?',
                    message:
                        'Karşı tarafın onayı olmadan, yalnızca kendi takibiniz için başlatılır. '
                        'Karşı taraf daha sonra kodla katılabilir.',
                    ok: 'Başlat',
                  )) {
                    return;
                  }
                  if (context.mounted) {
                    await runDealAction(
                      context,
                      d,
                      DealAction.confirm,
                      success: 'Kayıt başlatıldı',
                    );
                  }
                },
              ),
            ],
          );
        }
        if (creator) {
          return const _StepCard(
            color: AppColors.amber,
            icon: Icons.hourglass_top_rounded,
            title: 'Karşı tarafın onayı bekleniyor',
            text:
                'Karşı taraf kayda katıldı; onayladığında bildirim alacaksınız.',
          );
        }
        return _StepCard(
          color: AppColors.amber,
          icon: Icons.fact_check_outlined,
          title: 'Onayınız bekleniyor',
          text:
              'Bilgileri kontrol edin. Onaylarsanız kayıt iki taraf için de geçerli olur.',
          actions: [
            Row(
              children: [
                Expanded(
                  child: AsyncButton(
                    outlined: true,
                    color: AppColors.red,
                    label: 'Reddet',
                    onPressed: () => runDealAction(
                      context,
                      d,
                      DealAction.reject,
                      success: 'Anlaşma reddedildi',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AsyncButton(
                    color: AppColors.green,
                    label: 'Onayla',
                    onPressed: () => runDealAction(
                      context,
                      d,
                      DealAction.confirm,
                      success: 'Anlaşma onaylandı',
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case DealStatus.active:
        return _StepCard(
          color: AppColors.blue,
          icon: Icons.play_circle_outline_rounded,
          title: 'Anlaşma devam ediyor',
          text: canP && !canC
              ? 'İşi tamamladığınızda "Teslim ettim" deyin; karşı taraf onaylayınca anlaşma tamamlanır.'
              : canC && !canP
              ? 'İş teslim edildiğinde "Teslim aldım" ile anlaşmayı tamamlayın.'
              : 'İş bittiğinde anlaşmayı tamamlayın.',
          actions: [
            if (canP && !canC)
              AsyncButton(
                icon: Icons.local_shipping_outlined,
                label: 'İşi tamamladım / teslim ettim',
                onPressed: () => runDealAction(
                  context,
                  d,
                  DealAction.deliver,
                  success: 'Karşı tarafa bildirildi',
                ),
              ),
            if (canC)
              AsyncButton(
                color: AppColors.green,
                icon: Icons.task_alt_rounded,
                label: 'Teslim aldım, tamamla',
                onPressed: () async {
                  if (!await confirm(
                    context,
                    'Anlaşma tamamlansın mı?',
                    message:
                        'İşin teslim alındığını onaylıyorsunuz. Sonrasında karşı tarafı puanlayabilirsiniz.',
                    ok: 'Tamamla',
                  )) {
                    return;
                  }
                  if (context.mounted) {
                    await runDealAction(
                      context,
                      d,
                      DealAction.complete,
                      success: 'Anlaşma tamamlandı',
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
            _DisputeButton(deal: d),
          ],
        );
      case DealStatus.delivered:
        if (canC) {
          return _StepCard(
            color: AppColors.teal,
            icon: Icons.inventory_outlined,
            title: 'Teslim bildirildi',
            text:
                '${d.providerName} işi tamamladığını bildirdi. Kontrol edip onaylayın.',
            actions: [
              AsyncButton(
                color: AppColors.green,
                icon: Icons.task_alt_rounded,
                label: 'Teslim aldım, tamamla',
                onPressed: () => runDealAction(
                  context,
                  d,
                  DealAction.complete,
                  success: 'Anlaşma tamamlandı',
                ),
              ),
              const SizedBox(height: 8),
              _DisputeButton(deal: d),
            ],
          );
        }
        return const _StepCard(
          color: AppColors.teal,
          icon: Icons.hourglass_top_rounded,
          title: 'Teslim onayı bekleniyor',
          text: 'Karşı taraf teslimi onayladığında anlaşma tamamlanır.',
        );
      case DealStatus.disputed:
        final lastIssue =
            d.log.where((l) => l.text.startsWith('Sorun')).lastOrNull?.text ??
            'Sorun bildirildi';
        return _StepCard(
          color: AppColors.red,
          icon: Icons.report_gmailerrorred_rounded,
          title: 'Sorun bildirildi',
          text:
              '$lastIssue\n\nSorunu karşı tarafla görüşerek çözün. Çözüldüğünde aşağıdan işaretleyin. '
              'Anlaşmazlıklarda uygulama taraf değildir; tüketici hakem heyeti veya mahkemeler yetkilidir.',
          actions: [
            if (!AppConfig.usesDotNet || d.isSolo(me) || d.disputedBy == me)
              AsyncButton(
                outlined: true,
                label: 'Sorun çözüldü',
                onPressed: () => runDealAction(
                  context,
                  d,
                  DealAction.resolve,
                  success: 'Sorun çözüldü olarak işaretlendi',
                ),
              ),
          ],
        );
      case DealStatus.completed:
        final canRate =
            d.counterpartyId(me) != null &&
            !app.ratedDeals.contains(d.id) &&
            (d.isCustomer(me) || d.isProvider(me));
        return _StepCard(
          color: AppColors.green,
          icon: Icons.verified_rounded,
          title: 'Anlaşma tamamlandı',
          text: canRate
              ? 'Karşı tarafı puanlayın; puanlar yalnızca tamamlanan anlaşmalardan gelir ve herkesin güvenle çalışmasını sağlar.'
              : 'Teşekkürler! Bu anlaşma tamamlandı.',
          actions: [
            if (canRate)
              AsyncButton(
                icon: Icons.star_rounded,
                label: '${d.counterpartyName(me)} için puan ver',
                onPressed: () =>
                    showAppSheet<void>(context, (ctx) => _RateSheet(deal: d)),
              ),
          ],
        );
      case DealStatus.cancelled:
        return const _StepCard(
          color: AppColors.grey,
          icon: Icons.block_rounded,
          title: 'Anlaşma iptal edildi',
          text: 'Bu kayıt artık işlem görmez; geçmişi aşağıda duruyor.',
        );
    }
  }
}

class _DisputeButton extends StatelessWidget {
  const _DisputeButton({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context) {
    return AsyncButton(
      outlined: true,
      color: AppColors.red,
      icon: Icons.report_gmailerrorred_rounded,
      label: 'Sorun bildir',
      onPressed: () async {
        final note = await promptText(
          context,
          title: 'Sorun nedir?',
          hint: 'Örn. Eksik sefer yapıldı, malzeme hasarlı geldi…',
          mandatory: true,
        );
        if (note == null || !context.mounted) return;
        await runDealAction(
          context,
          deal,
          DealAction.dispute,
          note: note,
          success: 'Sorun karşı tarafa bildirildi',
        );
      },
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
    this.actions = const [],
  });

  final Color color;
  final IconData icon;
  final String title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.4)),
          if (actions.isNotEmpty) ...[const SizedBox(height: 12), ...actions],
        ],
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({required this.deal, required this.index});

  final Deal deal;
  final int index;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final me = app.myId;
    final d = deal;
    final m = d.milestones[index];
    final open =
        d.status != DealStatus.pending && d.status != DealStatus.cancelled;
    final (Color color, IconData icon, String label) = m.received
        ? (AppColors.green, Icons.check_circle_rounded, 'Tahsil edildi')
        : m.paid
        ? (AppColors.blue, Icons.outbox_rounded, 'Ödendi bildirildi')
        : (AppColors.amber, Icons.hourglass_empty_rounded, 'Bekliyor');

    final actions = <Widget>[
      if (open && !m.paid && d.canActAsCustomer(me))
        Expanded(
          child: AsyncButton(
            outlined: true,
            label: 'Ödedim',
            onPressed: () async {
              if (!await confirm(
                context,
                '"${m.title}" ödendi olarak işaretlensin mi?',
                message:
                    'Bu yalnızca bir kayıttır; ödemeyi ${d.paymentMethod.label.toLowerCase()} ile kendiniz yapmalısınız. '
                    'Karşı taraf tahsil ettiğini onaylayınca satır tamamlanır.',
                ok: 'İşaretle',
              )) {
                return;
              }
              if (context.mounted) {
                await runDealAction(
                  context,
                  d,
                  DealAction.markPaid,
                  index: index,
                );
              }
            },
          ),
        ),
      if (open && !m.received && d.canActAsProvider(me))
        Expanded(
          child: AsyncButton(
            color: AppColors.green,
            label: 'Tahsil ettim',
            onPressed: () async {
              if (!await confirm(
                context,
                '${formatTL(m.amount)} tahsil edildi mi?',
                ok: 'Evet, tahsil ettim',
              )) {
                return;
              }
              if (context.mounted) {
                await runDealAction(
                  context,
                  d,
                  DealAction.markReceived,
                  index: index,
                );
              }
            },
          ),
        ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        m.received
                            ? '$label · ${formatDate(m.receivedAt!)}'
                            : m.paid
                            ? '$label · ${formatDate(m.paidAt!)}'
                            : label,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatTL(m.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    actions[i],
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DealMenu extends StatelessWidget {
  const _DealMenu({required this.deal});

  final Deal deal;

  Future<void> _onSelected(BuildContext context, String value) async {
    final d = deal;
    switch (value) {
      case 'note':
        final note = await promptText(
          context,
          title: 'Not ekle',
          hint: 'Örn. 3. sefer yapıldı, kantar fişi alındı',
          mandatory: true,
        );
        if (note == null || !context.mounted) return;
        await runDealAction(
          context,
          d,
          DealAction.note,
          note: note,
          success: 'Not eklendi',
        );
      case 'cancel':
        final reason = await promptText(
          context,
          title: 'İptal nedeni',
          hint: 'Kısaca nedenini yazın',
          ok: d.cancelRequestedBy != null ? 'İptali onayla' : 'İptal iste',
        );
        if (reason == null || !context.mounted) return;
        await runDealAction(
          context,
          d,
          DealAction.cancel,
          note: reason,
          success:
              AppConfig.usesDotNet &&
                  d.status != DealStatus.pending &&
                  !d.isSolo(context.read<AppState>().myId) &&
                  d.cancelRequestedBy == null
              ? 'İptal talebi gönderildi'
              : 'Anlaşma iptal edildi',
        );
      case 'copy':
        await copyText(context, dealSummaryText(d), done: 'Özet kopyalandı');
      case 'report':
        await showReportSheet(context, targetType: 'anlasma', targetId: d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = deal;
    return PopupMenuButton<String>(
      tooltip: 'Diğer',
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (_) => [
        if (d.status.isOpen)
          const PopupMenuItem(value: 'note', child: Text('Not ekle')),
        const PopupMenuItem(value: 'copy', child: Text('Özeti kopyala')),
        if ((d.status == DealStatus.pending ||
                d.status == DealStatus.active ||
                d.status == DealStatus.disputed) &&
            d.cancelRequestedBy != context.read<AppState>().myId)
          PopupMenuItem(
            value: 'cancel',
            child: Text(
              d.cancelRequestedBy != null
                  ? 'İptali onayla'
                  : 'Anlaşmayı iptal et',
            ),
          ),
        const PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
      ],
    );
  }
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.deal});

  final Deal deal;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _stars = 5;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  final _formKey = GlobalKey<FormState>();

  Future<void> _save() async {
    if (!validateForm(context, _formKey)) return;
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      await app.rateDeal(widget.deal, _stars, Sanitize.block(_comment.text));
      navigator.pop();
      showSaved(
        null,
        'Teşekkürler, değerlendirmeniz kaydedildi',
        queued: app.lastWriteQueued,
      );
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _save);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.deal.counterpartyName(context.read<AppState>().myId);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name için puanınız',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i yıldız',
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(
                      i <= _stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFF5A623),
                      size: 38,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LabeledField(
              label: 'Yorum (isteğe bağlı, herkese görünür)',
              controller: _comment,
              maxLines: 3,
              maxLength: FieldLimits.ratingComment,
              hint: 'Zamanında geldi mi, ödeme sorunsuz muydu?',
              // Yorum herkese açık profilde görünür: uygunsuz ifade süzülür.
              validator: Validators.text(
                label: 'Yorum',
                isRequired: false,
                max: FieldLimits.ratingComment,
                multiline: true,
              ),
            ),
            AsyncButton(label: 'Kaydet', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
