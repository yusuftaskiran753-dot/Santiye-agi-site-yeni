import 'package:flutter/material.dart';

import '../data/cities.dart';
import 'common.dart';

/// Aranabilir il seçici. [allowAll] verilirse "Tüm Türkiye" seçeneği çıkar (null).
Future<String?> pickCity(BuildContext context, {String? title, bool allowAll = false}) {
  return showAppSheet<String>(
    context,
    (ctx) => _CitySheet(title: title ?? 'İl seçin', allowAll: allowAll),
  );
}

/// "Tüm Türkiye" seçimini ayırt etmek için kullanılan özel değer.
const String kAllCities = '__all__';

class _CitySheet extends StatefulWidget {
  const _CitySheet({required this.title, required this.allowAll});

  final String title;
  final bool allowAll;

  @override
  State<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<_CitySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = normalizeTr(_query);
    final cities = kCityNames.where((c) => q.isEmpty || normalizeTr(c).contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'İl ara…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (widget.allowAll && q.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('Tüm Türkiye', style: TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => Navigator.pop(context, kAllCities),
                  ),
                for (final c in cities)
                  ListTile(
                    title: Text(c),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiketli il seçim alanı. [value] null ise "Tüm Türkiye" gösterilir.
class CityField extends StatelessWidget {
  const CityField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowAll = false,
    this.icon = Icons.location_on_outlined,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowAll;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        PickerBox(
          icon: icon,
          text: value ?? (allowAll ? 'Tüm Türkiye' : 'İl seçin'),
          placeholder: value == null,
          onTap: () async {
            final picked = await pickCity(context, title: label, allowAll: allowAll);
            if (picked == null) return;
            onChanged(picked == kAllCities ? null : picked);
          },
        ),
      ],
    );
  }
}
