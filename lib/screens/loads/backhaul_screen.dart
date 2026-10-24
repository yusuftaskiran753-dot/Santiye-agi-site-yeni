import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../logic/load_matcher.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/city_picker.dart';
import '../../widgets/common.dart';
import '../listings/cards.dart';
import '../listings/listing_detail_screen.dart';

/// Boş dönüş eşleştirme: boşaldığı ilden eve doğru giden yükleri sıralar.
class BackhaulScreen extends StatefulWidget {
  const BackhaulScreen({super.key});

  @override
  State<BackhaulScreen> createState() => _BackhaulScreenState();
}

class _BackhaulScreenState extends State<BackhaulScreen> {
  String? _emptyAt;
  String? _home;
  VehicleType? _vehicle = VehicleType.tir;

  /// Son aramanın ölçütleri; sonuçlar her çizimde güncel ilanlardan yeniden
  /// hesaplanır (yeni ilan gelince liste kendiliğinden yenilenir).
  ({String emptyAt, String home, VehicleType? vehicle})? _search;

  @override
  void initState() {
    super.initState();
    _home = context.read<AppState>().city;
  }

  void _find() {
    final emptyAt = _emptyAt;
    final home = _home;
    if (emptyAt == null || home == null) {
      showSnack(context, 'Boşaldığınız ili ve dönmek istediğiniz ili seçin');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _search = (emptyAt: emptyAt, home: home, vehicle: _vehicle));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final app = context.watch<AppState>();
    final search = _search;
    final results = search == null
        ? null
        : matchLoads(
            loads: app.marketLoads,
            emptyAt: search.emptyAt,
            home: search.home,
            vehicle: search.vehicle,
            excludeOwnerId: app.myId,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Boş dönüş eşleştirme')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yükü nerede boşalttığınızı ve hangi ile döneceğinizi seçin; sizi en az boş yolla eve yaklaştıran '
                    'yükleri sıralayalım.',
                    style: TextStyle(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  CityField(label: 'Boşaldığım il', value: _emptyAt, onChanged: (c) => setState(() => _emptyAt = c)),
                  const SizedBox(height: 12),
                  CityField(
                    label: 'Dönmek istediğim il',
                    value: _home,
                    icon: Icons.home_outlined,
                    onChanged: (c) => setState(() => _home = c),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Aracım'),
                  ChoiceWrap<VehicleType?>(
                    values: [null, ...VehicleType.values],
                    selected: _vehicle,
                    labelOf: (v) => v?.label ?? 'Fark etmez',
                    onSelected: (v) => setState(() => _vehicle = v),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _find,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Uygun yükleri bul'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (results != null) ...[
            SectionTitle('${results.length} uygun yük'),
            if (results.isEmpty)
              const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Yakında uygun yük bulunamadı',
                message: 'Araç tipini "Fark etmez" yapmayı deneyin.',
              ),
            for (final m in results)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LoadCard(
                  load: m.load,
                  onTap: () => openListing(context, m.load),
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ScoreBadge(m),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Yüke boş gidiş ${formatKm(m.emptyKm)} · '
                            '${m.closerToHomeKm >= 0 ? 'Eve ${formatKm(m.closerToHomeKm)} yaklaştırır' : 'Evden ${formatKm(-m.closerToHomeKm)} uzaklaştırır'}'
                            '${m.load.price > 0 ? ' · km başı ${formatTL(m.pricePerKm, decimals: 1)}' : ''}',
                            style: TextStyle(fontSize: 12.5, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge(this.match);

  final LoadMatch match;

  @override
  Widget build(BuildContext context) {
    final color = match.score >= 75
        ? AppColors.green
        : match.score >= 50
            ? AppColors.brand
            : AppColors.grey;
    return Pill('%${match.score} · ${match.label}', color: color);
  }
}
