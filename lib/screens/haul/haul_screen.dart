import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../logic/haul_optimizer.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../../widgets/map_view.dart';
import '../billing/billing_flows.dart';

Color haulColor(HaulPointKind k) => switch (k) {
  HaulPointKind.excavation => AppColors.orange,
  HaulPointKind.dump => const Color(0xFF6D4C41),
  HaulPointKind.source => AppColors.green,
};

IconData haulIcon(HaulPointKind k) => switch (k) {
  HaulPointKind.excavation => Icons.construction_rounded,
  HaulPointKind.dump => Icons.terrain_rounded,
  HaulPointKind.source => Icons.landscape_rounded,
};

class HaulScreen extends StatefulWidget {
  const HaulScreen({super.key});

  @override
  State<HaulScreen> createState() => _HaulScreenState();
}

class _HaulScreenState extends State<HaulScreen> {
  final _truckM3 = TextEditingController(text: '18');
  final _trucks = TextEditingController(text: '8');
  final _liters = TextEditingController(text: '45');
  final _fuelPrice = TextEditingController(text: '55');
  final _hours = TextEditingController(text: '10');
  bool _addMode = false;
  HaulPlan? _plan;

  @override
  void dispose() {
    for (final c in [_truckM3, _trucks, _liters, _fuelPrice, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Kullanıcının yazdığı değerler makul aralığa çekilir; anlamsız veya boş
  /// değerde varsayılan kullanılır (ör. 0 kamyon hesabı bozmaz).
  HaulParams _params() => HaulParams(
    truckM3: _inRange(_truckM3.text, 18, min: 1, max: 60),
    trucks: _inRange(_trucks.text, 8, min: 1, max: 500).round(),
    litersPer100Km: _inRange(_liters.text, 45, min: 1, max: 200),
    fuelPrice: _inRange(_fuelPrice.text, 55, min: 1, max: 1000),
    hoursPerDay: _inRange(_hours.text, 10, min: 1, max: 24),
  );

  double _inRange(
    String text,
    double fallback, {
    required double min,
    required double max,
  }) {
    final v = tryParseNumber(text);
    if (v == null || v <= 0) return fallback;
    return v.clamp(min, max).toDouble();
  }

  Future<void> _optimize() async {
    final app = context.read<AppState>();
    final sites = app.haulPoints.where(
      (p) => p.kind == HaulPointKind.excavation,
    );
    final dumps = app.haulPoints.where((p) => p.kind == HaulPointKind.dump);
    if (sites.isEmpty || dumps.isEmpty) {
      showSnack(context, 'En az bir kazı sahası ve bir döküm sahası ekleyin');
      return;
    }
    if (!await ensurePremium(context, feature: 'Hafriyat rota optimizasyonu')) {
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _plan = optimizeHaul(app.haulPoints, _params()));
  }

  Future<void> _onMapTap(LatLng point) async {
    if (!_addMode) return;
    setState(() => _addMode = false);
    final created = await showAppSheet<HaulPoint>(
      context,
      (ctx) => _PointSheet(position: point),
    );
    if (created == null || !mounted) return;
    try {
      await context.read<AppState>().addHaulPoint(created);
      if (mounted) setState(() => _plan = null);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final points = app.haulPoints;
    final center = points.isEmpty
        ? app.userPosition
        : LatLng(
            points.map((p) => p.lat).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.lng).reduce((a, b) => a + b) / points.length,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hafriyat Planlama'),
        actions: [
          if (!app.isLive)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'demo') {
                  await app.restoreDemoHaulPoints();
                  if (mounted) setState(() => _plan = null);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'demo',
                  child: Text('Örnek sahaları yükle'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                AppMap(
                  center: center,
                  zoom: 10,
                  onTap: _onMapTap,
                  layers: [
                    if (_plan != null)
                      PolylineLayer(
                        polylines: [
                          for (final a in _plan!.assignments)
                            Polyline(
                              points: [a.site.position, a.dump.position],
                              color: AppColors.orange.withValues(alpha: 0.8),
                              strokeWidth: 4,
                            ),
                          for (final b in _plan!.backhauls) ...[
                            Polyline(
                              points: [
                                b.dump.position,
                                b.source.position,
                                b.site.position,
                              ],
                              color: AppColors.green.withValues(alpha: 0.85),
                              strokeWidth: 3,
                            ),
                          ],
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final p in points)
                          Marker(
                            point: p.position,
                            width: 36,
                            height: 36,
                            child: Tooltip(
                              message: p.name,
                              child: MapPin(
                                icon: haulIcon(p.kind),
                                color: haulColor(p.kind),
                                size: 34,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (_addMode)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Card(
                      color: AppColors.orange,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            const Icon(Icons.touch_app, color: Colors.white),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Eklemek istediğiniz konuma dokunun',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _addMode = false),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                SectionTitle(
                  'Sahalar (${points.length})',
                  action: _addMode ? null : 'Nokta ekle',
                  onAction: () => setState(() => _addMode = true),
                ),
                if (points.isEmpty)
                  const EmptyState(
                    icon: Icons.add_location_alt_outlined,
                    title: 'Henüz saha yok',
                    message:
                        '"Nokta ekle" ile haritadan kazı ve döküm sahalarını işaretleyin.',
                  ),
                for (final kind in HaulPointKind.values)
                  for (final p in points.where((x) => x.kind == kind))
                    _PointTile(
                      point: p,
                      onChanged: () => setState(() => _plan = null),
                    ),
                const SectionTitle('Filo ve maliyet'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: LabeledField(
                                label: 'Kamyon hacmi',
                                controller: _truckM3,
                                suffix: 'm³',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LabeledField(
                                label: 'Kamyon sayısı',
                                controller: _trucks,
                                suffix: 'adet',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: LabeledField(
                                label: 'Yakıt tüketimi',
                                controller: _liters,
                                suffix: 'L/100km',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LabeledField(
                                label: 'Motorin',
                                controller: _fuelPrice,
                                suffix: '₺/L',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        LabeledField(
                          label: 'Günlük çalışma',
                          controller: _hours,
                          suffix: 'saat',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _optimize,
                    icon: const Icon(Icons.auto_graph_rounded),
                    label: const Text('Rotayı Optimize Et'),
                  ),
                ),
                if (_plan != null) _PlanResult(plan: _plan!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PointTile extends StatelessWidget {
  const _PointTile({required this.point, required this.onChanged});

  final HaulPoint point;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final String detail = switch (p.kind) {
      HaulPointKind.excavation =>
        '${formatNumber(p.volume)} m³ hafriyat${p.needM3 > 0 ? ' · ${formatNumber(p.needM3)} m³ dolgu ihtiyacı' : ''}',
      HaulPointKind.dump =>
        '${formatNumber(p.volume)} m³ kapasite · ${formatTL(p.feePerM3)}/m³',
      HaulPointKind.source => '${p.material} · ${formatTL(p.feePerM3)}/m³',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: IconBadge(
          haulIcon(p.kind),
          color: haulColor(p.kind),
          size: 40,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                p.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (p.demo) ...[const SizedBox(width: 6), const DemoTag()],
          ],
        ),
        subtitle: Text('${p.kind.label} · $detail'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (await confirm(context, '"${p.name}" silinsin mi?')) {
              if (!context.mounted) return;
              try {
                await context.read<AppState>().removeHaulPoint(p.id);
                onChanged();
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            }
          },
        ),
      ),
    );
  }
}

class _PlanResult extends StatelessWidget {
  const _PlanResult({required this.plan});

  final HaulPlan plan;

  @override
  Widget build(BuildContext context) {
    final p = plan.params;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Optimum plan',
          action: 'Kopyala',
          onAction: () => copyText(
            context,
            plan.summaryText(),
            done: 'Plan özeti panoya kopyalandı',
          ),
        ),
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: formatNumber(plan.totalTrips),
                label: 'Toplam sefer',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '${formatNumber(plan.days, decimals: 1)} gün',
                label: '${p.trucks} kamyonla süre',
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: formatTL(plan.totalCost),
                label: 'Yakıt + döküm',
                color: AppColors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                InfoRow(
                  'Taşınacak hafriyat',
                  '${formatNumber(plan.totalVolume)} m³',
                ),
                InfoRow('Toplam yol', formatKm(plan.totalKm)),
                InfoRow(
                  'Yakıt',
                  '${formatNumber(plan.fuelLiters)} L · ${formatTL(plan.fuelCost)}',
                ),
                InfoRow('Döküm ücretleri', formatTL(plan.dumpFees)),
                if (plan.savingsVsNaive > 0)
                  InfoRow(
                    'En yakın dökümle kıyasla tasarruf',
                    formatTL(plan.savingsVsNaive),
                  ),
                if (plan.unassignedM3 > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${formatNumber(plan.unassignedM3)} m³ için döküm kapasitesi yetmiyor. Yeni döküm sahası ekleyin.',
                            style: const TextStyle(color: AppColors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SectionTitle('Saha → döküm dağılımı'),
        for (final a in plan.assignments)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.site.name} → ${a.dump.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatNumber(a.volume)} m³ · ${a.trips(p)} sefer · tek yön ${formatKm(a.oneWayKm)} · '
                    'sefer ${formatNumber(a.tripMinutes(p))} dk',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Maliyet: ${formatTL(a.total(p))}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        if (plan.backhauls.isNotEmpty) ...[
          SectionTitle(
            'Dönüş yükü fırsatları · ${formatTL(plan.backhaulSavings)} tasarruf',
          ),
          for (final b in plan.backhauls)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: AppColors.green.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.u_turn_left_rounded,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${b.dump.name} → ${b.source.name} → ${b.site.name}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Dökümden dönen kamyon ocaktan ${formatNumber(b.m3)} m³ '
                            '${b.source.material.toLowerCase()} alıp şantiyeye dolu döner. '
                            '${b.trips} seferde ${formatKm(b.savedKm)} boş yol ve ${formatTL(b.savedCost)} yakıt tasarrufu.',
                            style: const TextStyle(height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.share_outlined),
            label: const Text('Planı WhatsApp ile paylaş'),
            onPressed: () => shareOnWhatsApp(context, plan.summaryText()),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Dağıtım, döküm kapasiteleri içinde toplam yakıt + döküm maliyetini en aza indirir. '
          'Mesafeler kuş uçuşu × ${kRoadFactor.toString().replaceAll('.', ',')} ile tahmin edilir; '
          'navigasyon servisi bağlandığında gerçek yol mesafesi kullanılır.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }
}

class _PointSheet extends StatefulWidget {
  const _PointSheet({required this.position});

  final LatLng position;

  @override
  State<_PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends State<_PointSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _volume = TextEditingController();
  final _fee = TextEditingController();
  final _need = TextEditingController();
  final _material = TextEditingController(text: 'Stabilize');
  HaulPointKind _kind = HaulPointKind.excavation;

  @override
  void dispose() {
    for (final c in [_name, _volume, _fee, _need, _material]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!validateForm(context, _formKey)) return;
    Navigator.pop(
      context,
      HaulPoint(
        id: context.read<AppState>().isLive ? newUuid() : newLocalId(),
        name: Sanitize.line(_name.text),
        kind: _kind,
        lat: widget.position.latitude,
        lng: widget.position.longitude,
        volume: parseNumber(_volume.text),
        // Alan bu türde gösterilmiyorsa eski değer taşınmaz.
        feePerM3: _kind == HaulPointKind.excavation
            ? 0
            : parseNumber(_fee.text),
        needM3: _kind == HaulPointKind.excavation ? parseNumber(_need.text) : 0,
        material: _kind == HaulPointKind.source
            ? Sanitize.line(_material.text)
            : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final volumeLabel = switch (_kind) {
      HaulPointKind.excavation => 'Çıkacak hafriyat',
      HaulPointKind.dump => 'Kalan döküm kapasitesi',
      HaulPointKind.source => 'Stok',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yeni nokta',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            ChoiceWrap<HaulPointKind>(
              values: HaulPointKind.values,
              selected: _kind,
              labelOf: (k) => k.label,
              onSelected: (k) => setState(() => _kind = k),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Ad',
              controller: _name,
              hint: 'Örn. Pendik Okul İnşaatı',
              maxLength: FieldLimits.haulPointName,
              validator: Validators.text(
                label: 'Ad',
                min: 2,
                max: FieldLimits.haulPointName,
                filter: false,
              ),
            ),
            LabeledField(
              label: volumeLabel,
              controller: _volume,
              suffix: 'm³',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.number(
                label: 'Miktar',
                positive: true,
                max: FieldLimits.maxHaulVolume,
                unit: 'm³',
              ),
            ),
            if (_kind == HaulPointKind.excavation)
              LabeledField(
                label: 'Geri dolgu ihtiyacı (isteğe bağlı)',
                controller: _need,
                suffix: 'm³',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: Validators.number(
                  label: 'Dolgu ihtiyacı',
                  isRequired: false,
                  min: 0,
                  max: FieldLimits.maxHaulVolume,
                  unit: 'm³',
                ),
              ),
            if (_kind != HaulPointKind.excavation)
              LabeledField(
                label: _kind == HaulPointKind.dump
                    ? 'Döküm ücreti'
                    : 'Malzeme fiyatı',
                controller: _fee,
                suffix: '₺/m³',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: Validators.number(
                  label: 'Ücret',
                  isRequired: false,
                  min: 0,
                  max: FieldLimits.maxHaulFee,
                  unit: '₺/m³',
                ),
              ),
            if (_kind == HaulPointKind.source)
              LabeledField(
                label: 'Malzeme',
                controller: _material,
                maxLength: FieldLimits.haulMaterial,
                validator: Validators.text(
                  label: 'Malzeme',
                  max: FieldLimits.haulMaterial,
                  filter: false,
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('Ekle')),
            ),
          ],
        ),
      ),
    );
  }
}
