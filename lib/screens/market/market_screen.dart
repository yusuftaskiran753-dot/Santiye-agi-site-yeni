import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../data/cities.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/city_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/map_view.dart';
import '../listings/cards.dart';
import '../listings/forms/listing_forms.dart';
import '../listings/listing_detail_screen.dart';
import '../loads/backhaul_screen.dart';
import '../search/search_screen.dart';

/// Pazar sekmesindeki kategoriler.
enum MarketCategory {
  yuk('Yük', Icons.local_shipping_rounded),
  makine('Makine', Icons.construction_rounded),
  malzeme('Malzeme', Icons.inventory_2_rounded),
  personel('Personel', Icons.engineering_rounded);

  const MarketCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  static MarketCategory of(ListingKind kind) => switch (kind) {
        ListingKind.yuk => MarketCategory.yuk,
        ListingKind.makine => MarketCategory.makine,
        ListingKind.malzeme => MarketCategory.malzeme,
        ListingKind.personel || ListingKind.sicil => MarketCategory.personel,
      };
}

/// İlan pazarı: yük, makine, malzeme ve personel.
class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key, required this.category});

  final ValueNotifier<MarketCategory> category;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MarketCategory>(
      valueListenable: category,
      builder: (context, current, _) => Scaffold(
        appBar: AppBar(
          title: const Text('İlanlar'),
          actions: [
            IconButton(
              tooltip: 'Tüm ilanlarda ara',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => pushPage<void>(context, const SearchScreen()),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: [
                  for (final c in MarketCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(c.icon, size: 18),
                        label: Text(c.label),
                        selected: current == c,
                        onSelected: (_) => category.value = c,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: IndexedStack(
          index: current.index,
          children: const [_LoadsTab(), _MachinesTab(), _MaterialsTab(), _PeopleTab()],
        ),
      ),
    );
  }
}

/// Liste başlığı + öğeler + yenileme.
class _ListShell extends StatelessWidget {
  const _ListShell({
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    required this.onRefresh,
    required this.empty,
  });

  final List<Widget> header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Future<void> Function() onRefresh;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header)),
          if (itemCount == 0)
            SliverToBoxAdapter(child: empty)
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverList.separated(
                itemCount: itemCount,
                itemBuilder: itemBuilder,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _refresh(BuildContext context, List<ListingKind> kinds) async {
  final app = context.read<AppState>();
  try {
    for (final k in kinds) {
      await app.refreshListings(k);
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.count, required this.trailing});

  final int count;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text('$count ilan', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _SortButton<T> extends StatelessWidget {
  const _SortButton({required this.values, required this.selected, required this.labelOf, required this.onSelected});

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: 'Sırala',
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final v in values) CheckedPopupMenuItem<T>(value: v, checked: v == selected, child: Text(labelOf(v))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 18),
            const SizedBox(width: 4),
            Text(labelOf(selected), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════ Yükler ═════════════════════════════

enum _LoadSort {
  smart('Önerilen'),
  newest('En yeni'),
  soonest('Yükleme tarihi'),
  highestPrice('En yüksek navlun'),
  bestPerKm('Km başı en iyi');

  const _LoadSort(this.label);
  final String label;
}

double _pricePerKm(Load l) {
  final km = roadKm(cityLatLng(l.fromCity), cityLatLng(l.toCity));
  return km < 1 ? l.price : l.price / km;
}

class _LoadsTab extends StatefulWidget {
  const _LoadsTab();

  @override
  State<_LoadsTab> createState() => _LoadsTabState();
}

class _LoadsTabState extends State<_LoadsTab> {
  String? _from;
  String? _to;
  VehicleType? _vehicle;
  String _query = '';
  _LoadSort _sort = _LoadSort.smart;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final q = normalizeTr(_query.trim());
    final list = app.marketLoads.where((l) {
      if (_from != null && l.fromCity != _from) return false;
      if (_to != null && l.toCity != _to) return false;
      if (_vehicle != null && l.vehicle != _vehicle) return false;
      if (q.isNotEmpty && !normalizeTr(l.searchText).contains(q)) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _LoadSort.smart:
        // Öne çıkanlar, sonra kullanıcının ilinden çıkan yükler, sonra en yeniler.
        list.sort((a, b) {
          if (a.isBoosted != b.isBoosted) return a.isBoosted ? -1 : 1;
          final aLocal = a.fromCity == app.city, bLocal = b.fromCity == app.city;
          if (aLocal != bLocal) return aLocal ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });
      case _LoadSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _LoadSort.soonest:
        list.sort((a, b) => a.date.compareTo(b.date));
      case _LoadSort.highestPrice:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _LoadSort.bestPerKm:
        list.sort((a, b) => _pricePerKm(b).compareTo(_pricePerKm(a)));
    }

    return _ListShell(
      onRefresh: () => _refresh(context, [ListingKind.yuk]),
      header: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: SearchField(hint: 'Yük cinsi, firma veya il ara…', onChanged: (v) => setState(() => _query = v)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CityField(label: 'Nereden', value: _from, allowAll: true, onChanged: (c) => setState(() => _from = c)),
              ),
              IconButton(
                tooltip: 'Yönü değiştir',
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: () => setState(() {
                  final f = _from;
                  _from = _to;
                  _to = f;
                }),
              ),
              Expanded(
                child: CityField(
                  label: 'Nereye',
                  value: _to,
                  allowAll: true,
                  icon: Icons.flag_outlined,
                  onChanged: (c) => setState(() => _to = c),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ChoiceRow<VehicleType>(
          values: VehicleType.values,
          selected: _vehicle,
          allLabel: 'Tüm araçlar',
          labelOf: (v) => v.label,
          onSelected: (v) => setState(() => _vehicle = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Card(
            child: ListTile(
              leading: const IconBadge(Icons.u_turn_left_rounded, size: 40),
              title: const Text('Boş dönmeyin', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Boşaldığınız ilden eve doğru giden yükleri bulun'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushPage<void>(context, const BackhaulScreen()),
            ),
          ),
        ),
        _CountRow(
          count: list.length,
          trailing: _SortButton<_LoadSort>(
            values: _LoadSort.values,
            selected: _sort,
            labelOf: (s) => s.label,
            onSelected: (s) => setState(() => _sort = s),
          ),
        ),
      ],
      itemCount: list.length,
      itemBuilder: (context, i) => LoadCard(load: list[i], onTap: () => openListing(context, list[i])),
      empty: EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Bu kriterlere uygun yük yok',
        message: 'Filtreleri genişletin ya da ilk ilanı siz verin.',
        actionLabel: 'Yük ilanı ver',
        onAction: () => openListingForm(context, ListingKind.yuk),
      ),
    );
  }
}

// ═════════════════════════════ Makineler ═════════════════════════════

enum _MachineSort {
  nearest('En yakın'),
  cheapest('En ucuz (günlük)'),
  topRated('En yüksek puan');

  const _MachineSort(this.label);
  final String label;
}

class _MachinesTab extends StatefulWidget {
  const _MachinesTab();

  @override
  State<_MachinesTab> createState() => _MachinesTabState();
}

class _MachinesTabState extends State<_MachinesTab> {
  MachineType? _type;
  bool _onlyAvailable = false;
  bool _map = false;
  String _query = '';
  _MachineSort _sort = _MachineSort.nearest;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final me = app.userPosition;
    final q = normalizeTr(_query.trim());
    final list = app.marketMachines.where((m) {
      if (_type != null && m.type != _type) return false;
      if (_onlyAvailable && !m.available) return false;
      if (q.isNotEmpty && !normalizeTr(m.searchText).contains(q)) return false;
      return true;
    }).toList();
    double price(Machine m) => m.daily > 0 ? m.daily : m.hourly * 8;
    switch (_sort) {
      case _MachineSort.nearest:
        list.sort((a, b) {
          if (a.isBoosted != b.isBoosted) return a.isBoosted ? -1 : 1;
          return roadKm(me, a.position).compareTo(roadKm(me, b.position));
        });
      case _MachineSort.cheapest:
        list.sort((a, b) => price(a).compareTo(price(b)));
      case _MachineSort.topRated:
        list.sort((a, b) => b.owner.ratingAvg.compareTo(a.owner.ratingAvg));
    }

    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SearchField(hint: 'Model, firma veya il ara…', onChanged: (v) => setState(() => _query = v)),
      ),
      ChoiceRow<MachineType>(
        values: MachineType.values,
        selected: _type,
        allLabel: 'Tümü',
        labelOf: (t) => t.label,
        onSelected: (t) => setState(() => _type = t),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded), label: Text('Liste')),
                ButtonSegment(value: true, icon: Icon(Icons.map_outlined), label: Text('Harita')),
              ],
              selected: {_map},
              onSelectionChanged: (s) => setState(() => _map = s.first),
            ),
            const Spacer(),
            FilterChip(
              label: const Text('Müsait'),
              selected: _onlyAvailable,
              onSelected: (v) => setState(() => _onlyAvailable = v),
            ),
          ],
        ),
      ),
      _CountRow(
        count: list.length,
        trailing: _SortButton<_MachineSort>(
          values: _MachineSort.values,
          selected: _sort,
          labelOf: (s) => s.label,
          onSelected: (s) => setState(() => _sort = s),
        ),
      ),
    ];

    if (_map) {
      return Column(
        children: [
          ...header,
          Expanded(child: _MachineMap(machines: list)),
        ],
      );
    }
    return _ListShell(
      onRefresh: () => _refresh(context, [ListingKind.makine]),
      header: header,
      itemCount: list.length,
      itemBuilder: (context, i) => MachineCard(machine: list[i], from: me, onTap: () => openListing(context, list[i])),
      empty: EmptyState(
        icon: Icons.construction_rounded,
        title: 'Uygun makine bulunamadı',
        message: 'Filtreyi değiştirin ya da makinenizi ekleyin.',
        actionLabel: 'Makinemi ekle',
        onAction: () => openListingForm(context, ListingKind.makine),
      ),
    );
  }
}

class _MachineMap extends StatelessWidget {
  const _MachineMap({required this.machines});

  final List<Machine> machines;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppMap(
          center: context.read<AppState>().userPosition,
          zoom: 8.5,
          layers: [
            MarkerLayer(
              markers: [
                for (final m in machines)
                  Marker(
                    point: m.position,
                    width: 46,
                    height: 46,
                    child: GestureDetector(
                      onTap: () => openListing(context, m),
                      child: MapPin(icon: machineIcon(m.type), color: m.available ? AppColors.blue : AppColors.grey),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(AppColors.blue),
                  const Text(' Müsait   ', style: TextStyle(fontSize: 12)),
                  _dot(AppColors.grey),
                  const Text(' Çalışıyor', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ═════════════════════════════ Malzeme ═════════════════════════════

enum _MaterialSort {
  delivered('Teslim dahil en ucuz'),
  cheapest('Fiyatı en ucuz'),
  nearest('En yakın');

  const _MaterialSort(this.label);
  final String label;
}

class _MaterialsTab extends StatefulWidget {
  const _MaterialsTab();

  @override
  State<_MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends State<_MaterialsTab> {
  MaterialKind _kind = MaterialKind.beton;
  String? _product;
  _MaterialSort _sort = _MaterialSort.delivered;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final me = app.userPosition;
    final ofKind = app.marketMaterials.where((m) => m.materialKind == _kind).toList();
    final products = <String>{for (final m in ofKind) m.product}.toList()..sort();
    final product = (_product != null && products.contains(_product)) ? _product : null;
    final list = ofKind.where((m) => product == null || m.product == product).toList();
    final km = <String, double>{for (final m in list) m.id: roadKm(me, m.position)};
    switch (_sort) {
      case _MaterialSort.delivered:
        list.sort((a, b) => deliveredUnitPrice(a, km[a.id]!).compareTo(deliveredUnitPrice(b, km[b.id]!)));
      case _MaterialSort.cheapest:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _MaterialSort.nearest:
        list.sort((a, b) => km[a.id]!.compareTo(km[b.id]!));
    }
    // Öne çıkanlar her zaman üstte.
    final boosted = list.where((m) => m.isBoosted).toList();
    final ordered = [...boosted, ...list.where((m) => !m.isBoosted)];
    // "En avantajlı" yalnızca tek ürün seçiliyken anlamlıdır.
    final bestId = product == null || ordered.isEmpty
        ? null
        : (list.toList()..sort((a, b) => deliveredUnitPrice(a, km[a.id]!).compareTo(deliveredUnitPrice(b, km[b.id]!))))
            .first
            .id;

    return _ListShell(
      onRefresh: () => _refresh(context, [ListingKind.malzeme]),
      header: [
        const SizedBox(height: 8),
        ChoiceRow<MaterialKind>(
          values: MaterialKind.values,
          selected: _kind,
          labelOf: (k) => k.label,
          onSelected: (k) => setState(() {
            _kind = k ?? _kind;
            _product = null;
          }),
        ),
        if (products.isNotEmpty) ...[
          const SizedBox(height: 4),
          ChoiceRow<String>(
            values: products,
            selected: product,
            allLabel: 'Tüm ürünler',
            labelOf: (s) => s,
            onSelected: (s) => setState(() => _product = s),
          ),
        ],
        _CountRow(
          count: ordered.length,
          trailing: _SortButton<_MaterialSort>(
            values: _MaterialSort.values,
            selected: _sort,
            labelOf: (s) => s.label,
            onSelected: (s) => setState(() => _sort = s),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Fiyatlar KDV hariç birim fiyattır. "Teslim" tutarı ${app.city} merkezine göre tahmini nakliye içerir; '
            'kesin fiyatı satıcı teyit eder.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
      itemCount: ordered.length,
      itemBuilder: (context, i) {
        final m = ordered[i];
        return MaterialCard(material: m, km: km[m.id], isBest: m.id == bestId, onTap: () => openListing(context, m));
      },
      empty: EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Bu türde ilan yok',
        message: 'Tedarikçiyseniz ürün ve fiyatlarınızı ekleyin, siparişleri toplayın.',
        actionLabel: 'Ürün / fiyat ekle',
        onAction: () => openListingForm(context, ListingKind.malzeme),
      ),
    );
  }
}

// ═════════════════════════════ Personel ═════════════════════════════

class _PeopleTab extends StatefulWidget {
  const _PeopleTab();

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  bool _workers = false;
  WorkerRole? _role;
  bool _onlyMyCity = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final jobs = app.marketJobs
        .where((j) => _role == null || j.role == _role)
        .where((j) => !_onlyMyCity || j.city == app.city)
        .toList();
    final workers = app.marketWorkers
        .where((w) => _role == null || w.role == _role)
        .where((w) => !_onlyMyCity || w.city == app.city)
        .toList()
      ..sort((a, b) {
        if (a.isBoosted != b.isBoosted) return a.isBoosted ? -1 : 1;
        if (a.available != b.available) return a.available ? -1 : 1;
        return b.owner.ratingAvg.compareTo(a.owner.ratingAvg);
      });
    final count = _workers ? workers.length : jobs.length;

    return _ListShell(
      onRefresh: () => _refresh(context, [ListingKind.personel, ListingKind.sicil]),
      header: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('İş ilanları')),
                ButtonSegment(value: true, label: Text('Operatörler')),
              ],
              selected: {_workers},
              onSelectionChanged: (s) => setState(() => _workers = s.first),
            ),
          ),
        ),
        ChoiceRow<WorkerRole>(
          values: WorkerRole.values,
          selected: _role,
          allLabel: 'Tüm pozisyonlar',
          labelOf: (r) => r.label,
          onSelected: (r) => setState(() => _role = r),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              avatar: const Icon(Icons.location_on_outlined, size: 18),
              label: Text('Sadece ${app.city}'),
              selected: _onlyMyCity,
              onSelected: (v) => setState(() => _onlyMyCity = v),
            ),
          ),
        ),
        if (_workers && app.myWorkerCard == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Card(
              child: ListTile(
                leading: const IconBadge(Icons.person_add_alt_1_outlined, color: AppColors.teal, size: 40),
                title: const Text('Operatör müsünüz?', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Sicil kartınızı oluşturun, firmalar size iş teklif etsin.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openListingForm(context, ListingKind.sicil),
              ),
            ),
          ),
        _CountRow(count: count, trailing: const SizedBox(height: 40)),
      ],
      itemCount: count,
      itemBuilder: (context, i) => _workers
          ? WorkerTile(worker: workers[i], onTap: () => openListing(context, workers[i]))
          : JobCard(job: jobs[i], onTap: () => openListing(context, jobs[i])),
      empty: _workers
          ? const EmptyState(icon: Icons.person_search_outlined, title: 'Bu alanda kayıtlı operatör yok')
          : EmptyState(
              icon: Icons.work_off_outlined,
              title: 'Bu alanda iş ilanı yok',
              actionLabel: 'Personel ilanı ver',
              onAction: () => openListingForm(context, ListingKind.personel),
            ),
    );
  }
}
