import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/cities.dart';
import '../../../models/models.dart';
import '../../../state/app_state.dart';
import '../../../utils/format.dart';
import '../../../utils/validators.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/common.dart';
import 'listing_forms.dart';

const Map<MaterialKind, List<String>> kProductSuggestions = {
  MaterialKind.beton: ['C20/25', 'C25/30', 'C30/37', 'C35/45', 'C40/50'],
  MaterialKind.agrega: ['0-5 Kum', '5-12 Mıcır', '12-22 Mıcır', '22-38 Mıcır', 'Filler'],
  MaterialKind.stabilize: ['Ocak Stabilize', 'Plent-miks Temel (PMT)', 'Alttemel'],
  MaterialKind.asfalt: ['Binder', 'Aşınma', 'BSK Bitümlü Temel', 'Soğuk Asfalt'],
  MaterialKind.cimento: ['CEM I 42,5', 'CEM II 32,5', 'Torba çimento'],
  MaterialKind.celik: ['Nervürlü Ø8-Ø32', 'Hasır çelik', 'Profil'],
  MaterialKind.tugla: ['Tuğla', 'Briket', 'Bims', 'Gazbeton'],
  MaterialKind.yalitim: ['XPS', 'Taş yünü', 'Bitümlü membran', 'Sıva'],
  MaterialKind.elektrikMalzeme: ['Kablo', 'Pano', 'Armatür', 'Buat'],
  MaterialKind.mekanikMalzeme: ['PPRC boru', 'Vana', 'Klima santrali', 'Radyatör'],
  MaterialKind.diger: ['Tuğla', 'Briket', 'Çimento (torba)', 'İnşaat demiri'],
};

const List<String> kUnits = ['ton', 'm³', 'adet', 'kg', 'torba', 'palet'];

/// Tedarikçinin ürün / fiyat ilanı.
class MaterialFormScreen extends StatefulWidget {
  const MaterialFormScreen({super.key, this.initial});

  final MaterialListing? initial;

  @override
  State<MaterialFormScreen> createState() => _MaterialFormScreenState();
}

class _MaterialFormScreenState extends State<MaterialFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _product;
  late final TextEditingController _price;
  late final TextEditingController _plant;
  late final TextEditingController _minQty;
  late final TextEditingController _note;
  MaterialKind _kind = MaterialKind.beton;
  String _unit = 'm³';
  StockLevel _stock = StockLevel.bol;
  bool _delivery = true;
  late String _city;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final m = widget.initial;
    _kind = m?.materialKind ?? MaterialKind.beton;
    _unit = m?.unit ?? _kind.defaultUnit;
    _stock = m?.stock ?? StockLevel.bol;
    _delivery = m?.delivery ?? true;
    _city = m?.city ?? app.city;
    _product = TextEditingController(text: m?.product ?? '');
    _price = TextEditingController(text: m == null ? '' : formatNumber(m.price, decimals: 2));
    _plant = TextEditingController(text: m?.plantName ?? (app.me?.company ?? ''));
    _minQty = TextEditingController(text: m == null || m.minQty <= 0 ? '' : formatNumber(m.minQty, decimals: 2));
    _note = TextEditingController(text: m?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_product, _price, _plant, _minQty, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!validateForm(context, _formKey)) return;
    final cityError = Validators.city(_city);
    if (cityError != null) {
      showSnack(context, cityError, kind: NoticeKind.warning);
      return;
    }
    final app = context.read<AppState>();
    final initial = widget.initial;
    final double lat;
    final double lng;
    if (initial != null && initial.city == _city) {
      lat = initial.lat;
      lng = initial.lng;
    } else {
      final base = cityLatLng(_city);
      final rnd = math.Random();
      lat = base.latitude + (rnd.nextDouble() - 0.5) * 0.08;
      lng = base.longitude + (rnd.nextDouble() - 0.5) * 0.08;
    }
    final listing = MaterialListing(
      id: initial?.id ?? '',
      owner: app.me ?? PublicProfile.unknown,
      materialKind: _kind,
      product: Sanitize.line(_product.text),
      unit: _unit,
      price: parseNumber(_price.text),
      stock: _stock,
      plantName: Sanitize.line(_plant.text),
      city: _city,
      lat: lat,
      lng: lng,
      delivery: _delivery,
      minQty: parseNumber(_minQty.text),
      note: Sanitize.block(_note.text),
      status: initial?.status ?? ListingStatus.active,
      createdAt: initial?.createdAt,
    );
    final navigator = Navigator.of(context);
    final ok = await saveListingFlow(
      context,
      listing,
      isNew: !_editing,
      successMessage: _editing ? 'Fiyat güncellendi' : 'Ürününüz yayında',
    );
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = kProductSuggestions[_kind] ?? const <String>[];
    return FormPage(
      title: _editing ? 'Ürünü düzenle' : 'Ürün / fiyat ekle',
      formKey: _formKey,
      submitLabel: _editing ? 'Değişiklikleri kaydet' : 'Yayınla',
      onSubmit: _save,
      children: [
        const FieldLabel('Malzeme türü'),
        ChoiceWrap<MaterialKind>(
          values: MaterialKind.values,
          selected: _kind,
          labelOf: (k) => k.label,
          onSelected: (k) => setState(() {
            _kind = k;
            _unit = k.defaultUnit;
          }),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Ürün',
          controller: _product,
          hint: suggestions.isEmpty ? null : 'Örn. ${suggestions.first}',
          maxLength: FieldLimits.product,
          validator: Validators.text(label: 'Ürün', min: 2, max: FieldLimits.product),
        ),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => setState(() => _product.text = s),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Birim fiyat (KDV hariç)',
                controller: _price,
                suffix: '₺',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.number(
                  label: 'Fiyat',
                  positive: true,
                  max: FieldLimits.maxMaterialPrice,
                  unit: '₺',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: DropdownButton<String>(
                value: kUnits.contains(_unit) ? _unit : kUnits.first,
                underline: const SizedBox.shrink(),
                items: [for (final u in kUnits) DropdownMenuItem(value: u, child: Text('/ $u'))],
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
            ),
          ],
        ),
        const FieldLabel('Stok durumu'),
        ChoiceWrap<StockLevel>(
          values: StockLevel.values,
          selected: _stock,
          labelOf: (s) => s.label,
          onSelected: (s) => setState(() => _stock = s),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Tesis / plent adı',
          controller: _plant,
          hint: 'Örn. Yılmaz Hazır Beton – Tuzla',
          maxLength: FieldLimits.plantName,
          validator: Validators.text(label: 'Tesis adı', min: 2, max: FieldLimits.plantName),
        ),
        CityField(label: 'Tesisin bulunduğu il', value: _city, onChanged: (c) => setState(() => _city = c ?? _city)),
        const SizedBox(height: 14),
        LabeledField(
          label: 'En az sipariş (isteğe bağlı)',
          controller: _minQty,
          suffix: _unit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: Validators.all([
            Validators.number(label: 'En az sipariş', isRequired: false, min: 0, max: FieldLimits.maxMinQty, unit: _unit),
            // Adet, torba, palet gibi birimler bölünemez.
            if (const ['adet', 'torba', 'palet'].contains(_unit))
              Validators.number(label: 'En az sipariş', isRequired: false, integer: true),
          ]),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Nakliye sağlıyoruz'),
          subtitle: const Text('Kapalıysa alıcı kendi aracını ayarlar'),
          value: _delivery,
          onChanged: (v) => setState(() => _delivery = v),
        ),
        const SizedBox(height: 6),
        LabeledField(
          label: 'Açıklama (isteğe bağlı)',
          controller: _note,
          maxLines: 3,
          maxLength: FieldLimits.note,
          hint: 'Pompa hizmeti, teslim saatleri, ödeme şartları…',
          validator: Validators.text(label: 'Açıklama', isRequired: false, max: FieldLimits.note, multiline: true),
        ),
      ],
    );
  }
}
