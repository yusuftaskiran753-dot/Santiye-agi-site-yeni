import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/ai_matcher.dart';
import '../../models/models.dart';
import '../../services/ai_service.dart';
import '../../services/ai_backend.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../listings/cards.dart';
import '../listings/forms/listing_forms.dart';
import '../listings/forms/load_form.dart';
import '../listings/listing_detail_screen.dart';

/// "Ne lazım? Yazın" ekranı. Kullanıcı tek cümle yazar; yapay zekâ (Gemini)
/// ne istediğini anlar, uygun ilanları getirir ya da ilan formunu doldurur.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.initialText, this.posting = false});

  /// Ana sayfadan yazılıp gelinen metin (varsa hemen çalışır).
  final String? initialText;

  /// "İlan ver" menüsünden açıldıysa örnekler ve ipuçları ilan vermeye göre gösterilir.
  final bool posting;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  AiResult? _result;
  String _asked = '';
  bool _remoteAvailable = false;
  bool _consent = false;
  String? _account;
  int _accountRevision = 0;

  static const _searchExamples = [
    "Yarın İstanbul'dan Ankara'ya tır lazım",
    "İstanbul'da günlük ekskavatör",
    'Kocaeli C30 beton fiyatı',
    'Silindir operatörü arıyorum',
  ];
  static const _postExamples = [
    "Kocaeli'den İzmir'e 25 ton torbalı çimento taşıtacağım, yarın",
    "Ankara'da kiralık CAT D6 dozerim var, günlüğü 20 bin",
    'Asfalt ekibi için silindir operatörü arıyorum',
  ];

  @override
  void initState() {
    super.initState();
    _account = context.read<AppState>().myId;
    _loadOptions();
    final t = widget.initialText?.trim() ?? '';
    if (t.isNotEmpty) {
      _controller.text = t;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }
  }

  Future<void> _loadOptions() async {
    final app = context.read<AppState>();
    final backend = app.backend;
    final revision = _accountRevision;
    if (backend is! AiBackend) return;
    try {
      final enabled = await (backend as AiBackend).aiAvailable();
      if (mounted && app.myId == _account && _accountRevision == revision) {
        setState(() => _remoteAvailable = enabled);
      }
    } catch (_) {
      /* Older/disabled server: private on-device mode. */
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<AppState>().myId;
    if (_account != account) {
      _accountRevision++;
      _account = account;
      _result = null;
      _asked = '';
      _controller.clear();
      _consent = false;
      _remoteAvailable = false;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ask([String? text]) async {
    if (text != null) _controller.text = text;
    final q = _controller.text.trim();
    if (q.length < 3 || _busy) return;
    _focus.unfocus();
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _asked = q;
    });
    final account = app.myId;
    final revision = _accountRevision;
    final backend = app.backend;
    final r = await AiService.instance.understand(
      q,
      myCity: app.city,
      backend: backend is AiBackend ? backend as AiBackend : null,
      useRemote: _remoteAvailable && _consent,
    );
    if (!mounted || app.myId != account || revision != _accountRevision) return;
    setState(() {
      _busy = false;
      _result = r;
    });
  }

  void _postFromResult(AiResult r) {
    if (r.category == ListingKind.yuk || r.category == null) {
      pushPage<void>(context, LoadFormScreen(draft: r));
    } else {
      final kind =
          r.category == ListingKind.personel && r.intent != AiIntent.ilanVer
          ? ListingKind.sicil
          : r.category!;
      openListingForm(context, kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final r = _result;
    final match = r == null
        ? null
        : matchListings(
            r,
            myCity: app.city,
            loads: app.marketLoads,
            machines: app.marketMachines,
            materials: app.marketMaterials,
            jobs: app.marketJobs,
            workers: app.marketWorkers,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.posting ? 'Anlatın, biz dolduralım' : 'Ne lazım?'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Yazma kutusu ──
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: widget.initialText == null,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 400,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _ask(),
                      style: const TextStyle(fontSize: 16.5),
                      decoration: InputDecoration(
                        hintText: widget.posting
                            ? 'Ne yayınlamak istiyorsunuz? Kısaca anlatın…'
                            : 'Ne arıyorsunuz? Kısaca yazın…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Gönder',
                    onPressed: _busy ? null : _ask,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Klavyedeki mikrofonla sesli de yazabilirsiniz.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          const SizedBox(height: 12),
          if (_remoteAvailable)
            CheckboxListTile(
              value: _consent,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _consent = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Gemini ile daha ayrıntılı anla',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Seçersem yazdığım metin ve seçili il Google Gemini’ye gönderilir. Google, hizmet planına göre içerikleri saklayabilir; ücretsiz hizmette geliştirme ve insan incelemesi için kullanabilir. Kişisel veya gizli bilgi yazmayacağım. Seçmeden de kullanabilirim.',
              ),
            ),

          if (_busy) ...[
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 10),
            Text('Anlamaya çalışıyorum…', style: TextStyle(color: muted)),
          ] else if (r == null) ...[
            Text(
              widget.posting ? 'Örneğin' : 'Şunları deneyin',
              style: TextStyle(color: muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e
                    in widget.posting ? _postExamples : _searchExamples)
                  ActionChip(label: Text(e), onPressed: () => _ask(e)),
              ],
            ),
          ] else ...[
            _Understood(result: r, asked: _asked),
            if ((r.answer ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              InfoBanner(
                text: r.answer!,
                icon: Icons.lightbulb_outline_rounded,
                color: AppColors.blue,
              ),
            ],
            const SizedBox(height: 12),
            if (r.intent == AiIntent.ilanVer ||
                (match != null && match.items.isEmpty && r.category != null))
              FilledButton.icon(
                onPressed: () => _postFromResult(r),
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(
                  r.intent == AiIntent.ilanVer
                      ? 'Bu bilgilerle ilan ver'
                      : 'İlan verin, size teklif gelsin',
                ),
              ),
            if (match != null && match.items.isNotEmpty) ...[
              SectionTitle(
                match.exact
                    ? '${match.items.length} uygun ilan'
                    : 'Tam eşleşme yok · yakın ${match.items.length} ilan',
              ),
              for (final l in match.items.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListingRow(
                    listing: l,
                    onTap: () => openListing(context, l),
                  ),
                ),
            ] else if (match != null &&
                r.category != null &&
                r.intent != AiIntent.ilanVer)
              const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Şu an uygun ilan yok',
                message:
                    'İlan verirseniz bölgedeki firmalar size teklifle ulaşır.',
              )
            else if (r.category == null && (r.answer ?? '').isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ne aradığınızı tam anlayamadım. Nereden nereye, hangi makine ya da hangi malzeme olduğunu yazar mısınız?',
                  style: TextStyle(color: muted),
                ),
              ),
          ],

          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.privacy_tip_outlined, size: 15, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _remoteAvailable && _consent
                      ? 'Gemini sonuçları hatalı olabilir. İlanı yayınlamadan önce bilgileri kontrol edin.'
                      : 'Yerel mod: yazdıklarınız yalnız bu cihazda çözümlenir. İlanlar otomatik yayınlanmaz.',
                  style: TextStyle(fontSize: 12, color: muted, height: 1.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Şunu anladım" kartı: özet cümle + anlaşılan alanlar.
class _Understood extends StatelessWidget {
  const _Understood({required this.result, required this.asked});

  final AiResult result;
  final String asked;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final chips = <Widget>[
      if (r.category != null)
        Pill(_kindLabel(r.category!), color: AppColors.forKind(r.category!)),
      if (r.fromCity != null || r.toCity != null)
        Pill(
          '${r.fromCity ?? '?'} → ${r.toCity ?? '?'}',
          color: AppColors.grey,
          icon: Icons.route_rounded,
        ),
      if (r.city != null)
        Pill(r.city!, color: AppColors.grey, icon: Icons.location_on_outlined),
      if (r.vehicle != null) Pill(r.vehicle!.label, color: AppColors.grey),
      if (r.machine != null) Pill(r.machine!.label, color: AppColors.grey),
      if (r.material != null) Pill(r.material!, color: AppColors.grey),
      if (r.workerRole != null)
        Pill(r.workerRole!.label, color: AppColors.grey),
      if (r.tons != null)
        Pill(
          '${formatNumber(r.tons!, decimals: 1)} ton',
          color: AppColors.grey,
        ),
      if (r.price != null) Pill(formatTL(r.price!), color: AppColors.grey),
      if (r.date != null)
        Pill(
          friendlyDay(r.date!),
          color: AppColors.grey,
          icon: Icons.event_outlined,
        ),
    ];
    return Card(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.summary.isNotEmpty ? r.summary : '"$asked"',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ],
            const SizedBox(height: 8),
            Text(
              r.source == AiSource.gemini
                  ? 'Yanlış anladıysam cümleyi değiştirip tekrar gönderin.'
                  : 'Yerel mod · yanlışsa cümleyi değiştirin. Gemini seçiliyse bağlantı veya günlük sınır nedeniyle yerel mod kullanılmış olabilir.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(ListingKind k) => switch (k) {
    ListingKind.yuk => 'Yük',
    ListingKind.makine => 'Makine',
    ListingKind.malzeme => 'Malzeme',
    ListingKind.personel || ListingKind.sicil => 'Personel',
  };
}
