import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/cities.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../listings/cards.dart';
import '../listings/listing_detail_screen.dart';

/// Bütün ilan türlerinde arama.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(String value) {
    _controller.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    setState(() => _query = value);
  }

  static const _suggestions = ['Ekskavatör', 'Silindir', 'C30/37', 'Mıcır', 'Lowbed', 'İnşaat demiri', 'Operatör'];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final q = normalizeTr(_query.trim());
    final groups = <ListingKind, List<Listing>>{};
    if (q.length >= 2) {
      final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      for (final k in ListingKind.values) {
        final hits = app.market(k).where((l) {
          final text = normalizeTr(l.searchText);
          return words.every(text.contains);
        }).toList();
        if (hits.isNotEmpty) groups[k] = hits;
      }
    }
    final total = groups.values.fold<int>(0, (a, l) => a + l.length);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Yük, makine, malzeme, il, firma…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(tooltip: 'Temizle', icon: const Icon(Icons.close), onPressed: () => _set('')),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (q.length < 2) ...[
            const SectionTitle('Sık aranan'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _set(s)),
              ],
            ),
          ] else if (total == 0)
            EmptyState(
              icon: Icons.search_off_rounded,
              title: '"$_query" için sonuç yok',
              message: 'Farklı bir kelime deneyin veya ilan türünü genişletin.',
            )
          else
            for (final e in groups.entries) ...[
              SectionTitle('${e.key.label} (${e.value.length})'),
              for (final l in e.value.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListingRow(listing: l, onTap: () => openListing(context, l)),
                ),
            ],
        ],
      ),
    );
  }
}
