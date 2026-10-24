import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../data/cities.dart';
import '../../logic/live_route.dart';
import '../../models/models.dart';
import '../../models/live_location.dart';
import '../../services/live_location_backend.dart';
import '../../services/live_share_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/map_view.dart';
import '../listings/contact_sheet.dart';

/// WhatsApp'taki gibi canlı konum: karşı tarafın (ör. şoförün) yeri haritada
/// canlı görünür; kullanıcı kendi konumunu da süreli paylaşabilir.
class LiveLocationScreen extends StatefulWidget {
  const LiveLocationScreen({super.key, required this.dealId});

  final String dealId;

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  final _map = MapController();
  final Map<String, LiveLocation> _locations = {};
  StreamSubscription<List<LiveLocation>>? _sub;
  Timer? _clock;
  late final AppLifecycleListener _lifecycle;

  bool _mapReady = false;
  bool _follow = true;

  /// Haritanın ilk kez çerçevelendiği kişi (karşı taraf sonradan paylaşmaya başlarsa ona geçilir).
  String? _framedFor;
  bool _loading = true;
  bool _loadFailed = false;
  bool _realtimeDown = false;

  LiveLocationBackend get _backend =>
      context.read<AppState>().backend as LiveLocationBackend;
  String? _account;
  String? _observedAccount;
  int _subscriptionRevision = 0;

  @override
  void initState() {
    super.initState();
    _account = context.read<AppState>().myId;
    _observedAccount = _account;
    _subscribe();
    // "20 sn önce" gibi yazılar ve "güncel değil" uyarısı kendiliğinden yenilensin.
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() {});
      _moveCamera(); // kendi konumum da (paylaşıyorsam) takip edilsin
    });
    _lifecycle = AppLifecycleListener(onResume: _subscribe);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<AppState>().myId;
    if (_observedAccount != account) {
      _observedAccount = account;
      _subscriptionRevision++;
      _sub?.cancel();
      _sub = null;
      _locations.clear();
      _framedFor = null;
      _loading = false;
      _realtimeDown = true;
    }
  }

  @override
  void dispose() {
    _subscriptionRevision++;
    _sub?.cancel();
    _clock?.cancel();
    _lifecycle.dispose();
    _map.dispose();
    super.dispose();
  }

  void _replace(List<LiveLocation> rows) {
    final now = DateTime.now();
    final app = context.read<AppState>();
    final deal = app.dealById(widget.dealId);
    setState(() {
      // Complete snapshots replace, rather than retain, removed GPS points.
      _locations.clear();
      for (final row in rows) {
        if (deal != null &&
            LiveRules.dealAllows(deal, app.myId) &&
            !app.blocked.contains(deal.counterpartyId(app.myId)) &&
            row.dealId == widget.dealId &&
            (row.userId == deal.customerId || row.userId == deal.providerId) &&
            row.isActiveAt(now)) {
          _locations[row.userId] = row;
        }
      }
      _loading = false;
      _loadFailed = false;
    });
    _moveCamera();
  }

  void _subscribe() {
    final revision = ++_subscriptionRevision;
    _sub?.cancel();
    _sub = null;
    _realtimeDown = false;
    final account = _account;
    if (!mounted || context.read<AppState>().myId != account) return;
    bool current() =>
        mounted &&
        revision == _subscriptionRevision &&
        context.read<AppState>().myId == account;
    _sub = _backend
        .watchLiveLocations(widget.dealId)
        .listen(
          (rows) {
            if (!current()) return;
            _replace(rows);
          },
          onError: (Object _) {
            if (current()) {
              setState(() {
                _locations.clear();
                _loading = false;
                _loadFailed = true;
                _realtimeDown = true;
              });
            }
          },
          onDone: () {
            if (current()) {
              setState(() {
                _locations.clear();
                _realtimeDown = true;
              });
            }
          },
        );
  }

  // ───────────── Harita ─────────────

  Deal? get _deal => context.read<AppState>().dealById(widget.dealId);

  LatLng? _destination(Deal d) {
    if (d.kind != DealKind.yuk) return null;
    final route = LiveRules.routeFromTitle(d.title);
    return route == null ? null : kCities[route.to];
  }

  LatLng? _origin(Deal d) {
    if (d.kind != DealKind.yuk) return null;
    final route = LiveRules.routeFromTitle(d.title);
    return route == null ? null : kCities[route.from];
  }

  void _moveCamera() {
    if (!_mapReady || !mounted) return;
    final d = _deal;
    if (d == null) return;
    final other = _locations[d.counterpartyId(context.read<AppState>().myId)];
    final target = other ?? _myLocation;
    if (target == null || !target.isActive) return;
    if (_framedFor != target.userId) {
      _framedFor = target.userId;
      final dest = _destination(d);
      if (dest != null && roadKm(target.position, dest) > 1) {
        _map.fitCamera(
          CameraFit.coordinates(
            coordinates: [target.position, dest],
            padding: const EdgeInsets.fromLTRB(56, 72, 56, 56),
            maxZoom: 14,
          ),
        );
      } else {
        _map.move(target.position, 14);
      }
      return;
    }
    if (_follow) _map.move(target.position, _map.camera.zoom);
  }

  LiveLocation? get _myLocation {
    final d = _deal;
    final me = context.read<AppState>().myId;
    if (d == null || me == null) return null;
    final share = context.read<LiveShareService>();
    final fix = share.lastFix;
    if (share.isSharing(d.id) && fix != null) {
      final s = share.sessionFor(d.id)!;
      return LiveLocation(
        dealId: d.id,
        userId: me,
        lat: fix.lat,
        lng: fix.lng,
        accuracy: fix.accuracy,
        heading: fix.heading,
        speed: fix.speed,
        updatedAt: fix.at,
        startedAt: fix.at,
        expiresAt: s.expiresAt,
      );
    }
    final saved = _locations[me];
    return saved?.isActive == true ? saved : null;
  }

  // ───────────── Paylaşım ─────────────

  Future<void> _startSharing(Deal d) async {
    final share = context.read<LiveShareService>();
    final app = context.read<AppState>();
    final choice = await showAppSheet<_ShareChoice>(
      context,
      (ctx) => _ShareSheet(deal: d, counterparty: d.counterpartyName(app.myId)),
    );
    if (choice == null || !mounted) return;
    try {
      await share.start(
        d,
        minutes: choice.minutes,
        untilDelivered: choice.untilDelivered,
      );
      if (!mounted) return;
      _follow = true;
      _moveCamera();
      showSuccess(
        context,
        'Konumunuz ${d.counterpartyName(app.myId)} ile paylaşılıyor',
      );
    } on LocationAccessException catch (e) {
      if (mounted) await showLocationProblem(context, e.problem);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _stopSharing(Deal d) async {
    if (!await confirm(
      context,
      'Konum paylaşımı durdurulsun mu?',
      message:
          '${d.counterpartyName(context.read<AppState>().myId)} konumunuzu artık göremez.',
      ok: 'Durdur',
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    await context.read<LiveShareService>().stop(d.id);
    if (mounted) {
      setState(() => _locations.remove(context.read<AppState>().myId));
      final pending = context.read<LiveShareService>().isStopPending(d.id);
      showSnack(
        context,
        pending
            ? 'Bu cihazda paylaşım durdu. Son konum bağlantı gelince veya süre dolunca kaldırılır.'
            : 'Konum paylaşımı durduruldu',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final share = context.watch<LiveShareService>();
    final d = app.dealById(widget.dealId);
    if (d == null ||
        app.myId != _account ||
        !LiveRules.dealAllows(d, app.myId) ||
        app.blocked.contains(d.counterpartyId(app.myId))) {
      _locations.clear();
      return Scaffold(
        appBar: AppBar(title: const Text('Canlı konum')),
        body: const EmptyState(
          icon: Icons.location_off_outlined,
          title: 'Anlaşma bulunamadı',
        ),
      );
    }
    final me = app.myId;
    final otherId = d.counterpartyId(me);
    final now = DateTime.now();
    final stored = otherId == null ? null : _locations[otherId];
    final other = stored?.isActiveAt(now) == true ? stored : null;
    final mine = _myLocation;
    final otherState = LiveRules.stateOf(other, now);
    final dest = _destination(d);
    final origin = _origin(d);
    final otherColor = switch (otherState) {
      LiveState.live => AppColors.brand,
      LiveState.stale => AppColors.amber,
      _ => AppColors.grey,
    };
    final isTruck = d.kind == DealKind.yuk && otherId == d.providerId;

    final center =
        other?.position ?? mine?.position ?? origin ?? app.userPosition;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Canlı konum'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                d.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                AppMap(
                  controller: _map,
                  center: center,
                  zoom: other != null || mine != null ? 13 : 7,
                  onMapReady: () {
                    _mapReady = true;
                    _moveCamera();
                  },
                  onUserMove: () {
                    if (_follow) setState(() => _follow = false);
                  },
                  layers: [
                    CircleLayer(
                      circles: [
                        for (final (l, c) in [
                          (other, otherColor),
                          (mine, AppColors.blue),
                        ])
                          if (l != null && (l.accuracy ?? 0) > 30)
                            CircleMarker(
                              point: l.position,
                              radius: l.accuracy!,
                              useRadiusInMeter: true,
                              color: c.withValues(alpha: 0.10),
                              borderColor: c.withValues(alpha: 0.35),
                              borderStrokeWidth: 1,
                            ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        if (origin != null)
                          Marker(
                            point: origin,
                            width: 26,
                            height: 26,
                            child: const MapPin(
                              icon: Icons.trip_origin_rounded,
                              color: AppColors.grey,
                              size: 26,
                            ),
                          ),
                        if (dest != null)
                          Marker(
                            point: dest,
                            width: 34,
                            height: 34,
                            child: const MapPin(
                              icon: Icons.flag_rounded,
                              color: AppColors.green,
                              size: 34,
                            ),
                          ),
                        if (mine != null && mine.userId != otherId)
                          Marker(
                            point: mine.position,
                            width: 22,
                            height: 22,
                            child: const _MeDot(),
                          ),
                        if (other != null)
                          Marker(
                            point: other.position,
                            width: 60,
                            height: 60,
                            child: _LivePin(
                              icon: isTruck
                                  ? Icons.local_shipping_rounded
                                  : Icons.person_rounded,
                              color: otherColor,
                              pulsing: otherState == LiveState.live,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (_realtimeDown || _loadFailed)
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: _MapNotice(
                      text: _loadFailed
                          ? 'Konum doğrulanamadı. Bağlantı gelince yeniden yüklenir.'
                          : 'Konum bağlantısı kesildi; yenilemek için ekranı yeniden açın.',
                    ),
                  ),
                if (!_follow && (other != null || mine != null))
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'follow',
                      tooltip: 'Takip et',
                      onPressed: () {
                        setState(() => _follow = true);
                        _moveCamera();
                      },
                      child: const Icon(Icons.my_location_rounded),
                    ),
                  ),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          _Panel(
            deal: d,
            other: other,
            otherState: otherState,
            mine: mine,
            share: share,
            destination: dest,
            blocked: otherId != null && app.blocked.contains(otherId),
            onStart: () => _startSharing(d),
            onStop: () => _stopSharing(d),
          ),
        ],
      ),
    );
  }
}

/// Konuma erişilemediğinde açıklama ve çözüm düğmesi.
Future<void> showLocationProblem(
  BuildContext context,
  LocationProblem problem,
) async {
  final e = LocationAccessException(problem);
  final share = context.read<LiveShareService>();
  final action = switch (problem) {
    LocationProblem.serviceOff => ('Konumu aç', share.openLocationSettings),
    LocationProblem.deniedForever => ('Ayarları aç', share.openAppSettings),
    _ => null,
  };
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.location_off_outlined),
      title: Text(e.title),
      content: Text(e.message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(action == null ? 'Tamam' : 'Vazgeç'),
        ),
        if (action != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(action.$2());
            },
            child: Text(action.$1),
          ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.deal,
    required this.other,
    required this.otherState,
    required this.mine,
    required this.share,
    required this.destination,
    required this.blocked,
    required this.onStart,
    required this.onStop,
  });

  final Deal deal;
  final LiveLocation? other;
  final LiveState otherState;
  final LiveLocation? mine;
  final LiveShareService share;
  final LatLng? destination;
  final bool blocked;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final me = app.myId;
    final d = deal;
    final name = d.counterpartyName(me);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final session = share.sessionFor(d.id);
    final canShare = LiveRules.dealAllows(d, me) && !blocked;

    // ── Karşı taraf ──
    final o = other;
    final Widget otherBlock;
    if (o == null || otherState == LiveState.none) {
      otherBlock = _Line(
        dot: AppColors.grey,
        title: '$name konumunu paylaşmıyor',
        subtitle:
            'Paylaşmaya başladığında burada canlı görünür ve size bildirim gelir.',
        trailing: canShare
            ? TextButton.icon(
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('İste'),
                onPressed: () => shareOnWhatsApp(
                  context,
                  'Merhaba, ${AppConfig.appName}\'ndaki "${d.title}" işi için canlı konumunu paylaşır mısın? '
                  'Uygulamada anlaşma kaydını açıp "Canlı konum" → "Konumumu paylaş"a dokunman yeterli.',
                ),
              )
            : null,
      );
    } else {
      final age = o.ageAt(now);
      final (Color dot, String status) = switch (otherState) {
        LiveState.live => (
          AppColors.green,
          'Canlı · ${LiveRules.formatAge(age)} güncellendi',
        ),
        LiveState.stale => (
          AppColors.amber,
          'Son konum ${LiveRules.formatAge(age)} · bağlantısı zayıf olabilir',
        ),
        _ => (
          AppColors.grey,
          'Paylaşım bitti · son konum ${formatDateTime(o.updatedAt)}',
        ),
      };
      final rest =
          destination == null ||
              otherState == LiveState.ended ||
              o.userId != d.providerId
          ? null
          : LiveRules.remaining(o.position, destination!);
      final speed = otherState == LiveState.live
          ? LiveRules.formatSpeed(o.speed)
          : null;
      otherBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Line(dot: dot, title: name, subtitle: status),
          if (rest != null || speed != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (rest != null)
                  Pill(
                    rest.eta == null
                        ? 'Varış il merkezine yakın'
                        : 'Varışa ≈ ${formatKm(rest.km)} · ≈ ${LiveRules.formatEta(rest.eta!)}',
                    color: AppColors.teal,
                    icon: Icons.flag_rounded,
                  ),
                if (speed != null)
                  Pill(speed, color: AppColors.grey, icon: Icons.speed_rounded),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Ara / yaz'),
                onPressed: () => _contact(context, d),
              ),
              TextButton.icon(
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Haritalarda aç'),
                onPressed: () => openMapAt(context, o.lat, o.lng),
              ),
            ],
          ),
        ],
      );
    }

    // ── Ben ──
    final Widget myBlock;
    if (session != null) {
      final left = session.expiresAt.difference(now);
      final rest = destination == null || mine == null || me != d.providerId
          ? null
          : LiveRules.remaining(mine!.position, destination!);
      myBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(
            dot: share.problem == null ? AppColors.blue : AppColors.amber,
            title: 'Konumunuzu paylaşıyorsunuz',
            subtitle: [
              session.untilDelivered
                  ? 'Teslim bildirilene kadar'
                  : LiveRules.formatLeft(left),
              if (rest?.eta != null) 'varışa ≈ ${formatKm(rest!.km)}',
              if (session.pending != null) 'bağlantı bekleniyor',
            ].join(' · '),
          ),
          if (share.problem != null) ...[
            const SizedBox(height: 8),
            InfoBanner(
              color: AppColors.amber,
              icon: Icons.location_off_outlined,
              text: share.problem == LocationProblem.serviceOff
                  ? 'Telefonunuzun konumu kapalı. Yeni konum gönderilemiyor; son bilinen konum görünebilir.'
                  : 'Yeni konum alınamıyor. Son bilinen konum görünebilir; konum ayarlarını kontrol edin.',
              actionLabel: 'Düzelt',
              onAction: () => showLocationProblem(context, share.problem!),
            ),
          ],
          const SizedBox(height: 10),
          AsyncButton(
            outlined: true,
            color: AppColors.red,
            icon: Icons.stop_circle_outlined,
            label: 'Paylaşımı durdur',
            onPressed: onStop,
          ),
        ],
      );
    } else if (canShare) {
      final iAmDriver = d.kind == DealKind.yuk && me == d.providerId;
      myBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            iAmDriver
                ? 'Konumunuzu paylaşın; $name yükün nerede olduğunu canlı görsün, sizi aramasına gerek kalmasın.'
                : 'İsterseniz siz de konumunuzu $name ile paylaşabilirsiniz.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          AsyncButton(
            icon: Icons.share_location_rounded,
            label: 'Konumumu paylaş',
            onPressed: onStart,
          ),
        ],
      );
    } else {
      myBlock = Text(
        blocked
            ? 'Bu kişiyle konum paylaşılamaz (engelleme var).'
            : 'Konum paylaşımı yalnızca süren anlaşmalarda kullanılabilir.',
        style: TextStyle(color: muted, fontSize: 13),
      );
    }

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                otherBlock,
                const Divider(height: 20),
                myBlock,
                const SizedBox(height: 8),
                Text(
                  'Konum yalnızca bu anlaşmanın iki tarafı arasında, seçilen süre boyunca paylaşılır; geçmiş güzergâh saklanmaz.',
                  style: TextStyle(fontSize: 11.5, color: muted, height: 1.35),
                ),
                if (destination != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Varış tahmini il merkezine göre yaklaşık hesaplanır; trafik bilgisi içermez.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _contact(BuildContext context, Deal d) {
    final app = context.read<AppState>();
    showContactSheet(
      context,
      load: () => app.contactForDeal(d),
      whatsappText:
          'Merhaba, ${AppConfig.appName}\'ndaki "${d.title}" anlaşmamız hakkında yazıyorum.',
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.dot,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final Color dot;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _MapNotice extends StatelessWidget {
  const _MapNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: AppColors.amber,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      ),
    );
  }
}

/// Karşı tarafın işareti: canlıyken dalga efekti (WhatsApp'taki gibi).
class _LivePin extends StatefulWidget {
  const _LivePin({
    required this.icon,
    required this.color,
    required this.pulsing,
  });

  final IconData icon;
  final Color color;
  final bool pulsing;

  @override
  State<_LivePin> createState() => _LivePinState();
}

class _LivePinState extends State<_LivePin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _LivePin old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.pulsing && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.pulsing)
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, _) => Container(
              width: 34 + 26 * _pulse.value,
              height: 34 + 26 * _pulse.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(
                  alpha: 0.28 * (1 - _pulse.value),
                ),
              ),
            ),
          ),
        MapPin(icon: widget.icon, color: widget.color, size: 38),
      ],
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
      ),
    );
  }
}

// ───────────── Süre seçimi ─────────────

class _ShareChoice {
  const _ShareChoice({this.minutes, this.untilDelivered = false});

  final int? minutes;
  final bool untilDelivered;
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.deal, required this.counterparty});

  final Deal deal;
  final String counterparty;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late _ShareChoice _choice;
  late final List<(_ShareChoice, String, String?)> _options;
  bool _precise = true;

  @override
  void initState() {
    super.initState();
    final untilOk = LiveRules.canShareUntilDelivered(widget.deal);
    _options = [
      if (untilOk)
        (
          const _ShareChoice(untilDelivered: true),
          'Teslim edilene kadar',
          'Teslim bildirince kendiliğinden durur · en çok 24 saat',
        ),
      for (final m in LiveRules.durations)
        (_ShareChoice(minutes: m), '${m ~/ 60} saat', null),
    ];
    _choice = _options.first.$1;
    context
        .read<LiveShareService>()
        .isPrecise()
        .then((v) {
          if (mounted && !v) setState(() => _precise = false);
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Canlı konumu paylaş',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Konumunuzu yalnızca ${widget.counterparty} görür. Uygulama arka plandayken de seçtiğiniz süre boyunca paylaşılır; '
            'istediğiniz an durdurabilirsiniz.',
            style: TextStyle(color: muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          RadioGroup<_ShareChoice>(
            groupValue: _choice,
            onChanged: (v) {
              if (v != null) setState(() => _choice = v);
            },
            child: Column(
              children: [
                for (final (c, title, sub) in _options)
                  RadioListTile<_ShareChoice>(
                    value: c,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: sub == null ? null : Text(sub),
                  ),
              ],
            ),
          ),
          if (!_precise) ...[
            const SizedBox(height: 8),
            const InfoBanner(
              color: AppColors.amber,
              icon: Icons.gps_not_fixed_rounded,
              text:
                  'Telefonunuz "yaklaşık konum" veriyor; karşı taraf sizi birkaç km sapmayla görür. '
                  'Ayarlar → Konum → "Hassas konum"u açabilirsiniz.',
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _choice),
            icon: const Icon(Icons.share_location_rounded),
            label: const Text('Paylaş'),
          ),
        ],
      ),
    );
  }
}

// ───────────── Anlaşma ekranındaki kart ─────────────

/// Anlaşma kaydında "Canlı konum" kartı: karşı taraf paylaşıyorsa canlı
/// durumu gösterir, dokununca harita açılır.
class LiveLocationCard extends StatefulWidget {
  const LiveLocationCard({super.key, required this.deal});

  final Deal deal;

  @override
  State<LiveLocationCard> createState() => _LiveLocationCardState();
}

class _LiveLocationCardState extends State<LiveLocationCard> {
  LiveLocation? _other;
  Timer? _timer;
  String? _account;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _account = context.read<AppState>().myId;
    _check();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void didUpdateWidget(covariant LiveLocationCard old) {
    super.didUpdateWidget(old);
    if (old.deal.id != widget.deal.id ||
        old.deal.status != widget.deal.status ||
        old.deal.customerId != widget.deal.customerId ||
        old.deal.providerId != widget.deal.providerId) {
      _requestSerial++;
      _other = null;
      unawaited(_check());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<AppState>().myId;
    if (_account != account) {
      _account = account;
      _requestSerial++;
      _other = null;
      unawaited(_check());
    }
  }

  @override
  void dispose() {
    _requestSerial++;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final request = ++_requestSerial;
    final app = context.read<AppState>();
    final dealId = widget.deal.id;
    final otherId = widget.deal.counterpartyId(app.myId);
    if (otherId == null ||
        !LiveRules.dealAllows(widget.deal, app.myId) ||
        app.blocked.contains(otherId)) {
      if (mounted) setState(() => _other = null);
      return;
    }
    final account = app.myId;
    bool current() =>
        mounted &&
        request == _requestSerial &&
        app.myId == account &&
        widget.deal.id == dealId &&
        widget.deal.counterpartyId(account) == otherId;
    try {
      final list = await (app.backend as LiveLocationBackend)
          .fetchLiveLocations(dealId);
      if (!current()) return;
      if (!LiveRules.dealAllows(widget.deal, account) ||
          app.blocked.contains(otherId)) {
        setState(() => _other = null);
        return;
      }
      setState(
        () => _other = list
            .where(
              (l) => l.dealId == dealId && l.userId == otherId && l.isActive,
            )
            .firstOrNull,
      );
    } catch (_) {
      if (current()) setState(() => _other = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final share = context.watch<LiveShareService>();
    final d = widget.deal;
    final me = app.myId;
    final sharing = share.sessionFor(d.id);
    if (!LiveRules.dealAllows(d, me) ||
        app.blocked.contains(d.counterpartyId(me))) {
      _other = null;
      return const SizedBox.shrink();
    }
    final name = d.counterpartyName(me);
    final now = DateTime.now();
    final o = _other?.isActiveAt(now) == true ? _other : null;
    final state = LiveRules.stateOf(o, now);
    final iAmDriver = d.kind == DealKind.yuk && me == d.providerId;

    final (
      Color color,
      String title,
      String text,
    ) = o != null && state != LiveState.ended
        ? (
            state == LiveState.live ? AppColors.green : AppColors.amber,
            '$name konumunu paylaşıyor',
            state == LiveState.live
                ? 'Canlı · ${LiveRules.formatAge(o.ageAt(now))} güncellendi. Haritada görmek için dokunun.'
                : 'Son konum ${LiveRules.formatAge(o.ageAt(now))}. Haritada görmek için dokunun.',
          )
        : sharing != null
        ? (
            AppColors.blue,
            'Konumunuzu paylaşıyorsunuz',
            sharing.untilDelivered
                ? 'Teslim bildirilene kadar sürer.'
                : LiveRules.formatLeft(sharing.expiresAt.difference(now)),
          )
        : (
            AppColors.teal,
            'Canlı konum',
            iAmDriver
                ? 'Konumunuzu paylaşın; $name yükün nerede olduğunu haritada canlı görsün.'
                : d.kind == DealKind.yuk
                ? 'Yükünüzün nerede olduğunu haritada görün. Şoför konumunu paylaşınca burada çıkar.'
                : 'Karşı tarafın nerede olduğunu haritada görün veya konumunuzu paylaşın.',
          );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await pushPage<void>(context, LiveLocationScreen(dealId: d.id));
            if (mounted) unawaited(_check());
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                IconBadge(Icons.share_location_rounded, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────── Ana iskeletteki şerit ─────────────

/// Paylaşım sürerken her ekranda altta görünen ince şerit (unutulmasın diye).
class LiveSharingBar extends StatelessWidget {
  const LiveSharingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<LiveShareService>();
    if (!share.isSharingAny) return const SizedBox.shrink();
    final sessions = share.sessions.toList();
    final first = sessions.first;
    final warn = share.problem != null;
    final color = warn ? AppColors.amber : AppColors.blue;
    return Material(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () =>
            pushPage<void>(context, LiveLocationScreen(dealId: first.dealId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Icon(
                warn
                    ? Icons.location_off_outlined
                    : Icons.share_location_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  warn
                      ? 'Konum alınamıyor · paylaşım duraklatıldı'
                      : sessions.length == 1
                      ? 'Konumunuz paylaşılıyor · ${first.title}'
                      : 'Konumunuz ${sessions.length} anlaşmada paylaşılıyor',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
