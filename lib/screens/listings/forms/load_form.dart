import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../services/ai_service.dart';
import '../../../state/app_state.dart';
import '../../../utils/format.dart';
import '../../../utils/validators.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/common.dart';
import 'listing_forms.dart';

/// Yük ilanı verme veya [initial] verilirse düzenleme.
class LoadFormScreen extends StatefulWidget {
  const LoadFormScreen({super.key, this.initial, this.draft});

  final Load? initial;
  final AiResult? draft;

  @override
  State<LoadFormScreen> createState() => _LoadFormScreenState();
}

class _LoadFormScreenState extends State<LoadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cargo;
  late final TextEditingController _tons;
  late final TextEditingController _price;
  late final TextEditingController _note;
  String? _from;
  String? _to;
  VehicleType _vehicle = VehicleType.tir;
  DateTime _date = DateTime.now();

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final l = widget.initial;
    final draft = l == null ? widget.draft : null;
    _from = l?.fromCity ?? draft?.fromCity ?? app.city;
    _to = l?.toCity ?? draft?.toCity;
    _vehicle = l?.vehicle ?? draft?.vehicle ?? VehicleType.tir;
    _date = l == null
        ? draft?.date ?? DateTime.now()
        : l.isExpired
        ? DateTime.now()
        : l.date;
    _cargo = TextEditingController(text: l?.cargo ?? draft?.cargo ?? '');
    final tons = l?.tons ?? draft?.tons;
    final price = l?.price ?? draft?.price;
    _tons = TextEditingController(
      text: tons == null ? '' : formatNumber(tons, decimals: 1),
    );
    _price = TextEditingController(
      text: price == null || price <= 0 ? '' : formatNumber(price, decimals: 2),
    );
    _note = TextEditingController(text: l?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_cargo, _tons, _price, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Yükleme / teslim ili ve tarih (metin alanı olmayan seçimler) için hata.
  String? _selectionError() {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return 'Yükleme ve teslim ilini seçin';
    if (Validators.city(from) != null || Validators.city(to) != null) {
      return 'İlleri listeden seçin';
    }
    final today = startOfToday();
    if (DateTime(_date.year, _date.month, _date.day).isBefore(today)) {
      return 'Yükleme tarihi geçmiş olamaz';
    }
    if (_date.isAfter(today.add(const Duration(days: 366)))) {
      return 'Yükleme tarihi en fazla bir yıl sonrası olabilir';
    }
    return null;
  }

  Future<void> _save() async {
    final formOk = validateForm(context, _formKey);
    final selectionError = _selectionError();
    if (selectionError != null) {
      showSnack(context, selectionError, kind: NoticeKind.warning);
      return;
    }
    if (!formOk) return;
    final app = context.read<AppState>();
    final initial = widget.initial;
    final load = Load(
      id: initial?.id ?? '',
      owner: app.me ?? PublicProfile.unknown,
      fromCity: _from!,
      toCity: _to!,
      cargo: Sanitize.line(_cargo.text),
      tons: parseNumber(_tons.text),
      vehicle: _vehicle,
      price: parseNumber(_price.text),
      date: _date,
      note: Sanitize.block(_note.text),
      // Düzenleme kapalı (ör. anlaşması yapılmış) ilanı kendiliğinden yeniden yayına sokmaz.
      status: initial?.status ?? ListingStatus.active,
      createdAt: initial?.createdAt,
    );
    final navigator = Navigator.of(context);
    final ok = await saveListingFlow(
      context,
      load,
      isNew: !_editing,
      successMessage: _editing
          ? 'İlan güncellendi'
          : 'İlanınız yayında. Gelen teklifler "İşlerim" sekmesinde.',
    );
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: _editing ? 'Yük ilanını düzenle' : 'Yük ilanı ver',
      formKey: _formKey,
      submitLabel: _editing ? 'Değişiklikleri kaydet' : 'İlanı yayınla',
      onSubmit: _save,
      children: [
        if (!_editing && widget.draft != null)
          const InfoBanner(
            text:
                'Anlattıklarınızla taslak dolduruldu. Bilgileri kontrol edip yayınlayın; henüz ilan oluşturulmadı.',
            icon: Icons.auto_awesome,
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CityField(
                label: 'Yükleme ili',
                value: _from,
                onChanged: (c) => setState(() => _from = c),
              ),
            ),
            IconButton(
              tooltip: 'Yer değiştir',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: () => setState(() {
                final f = _from;
                _from = _to;
                _to = f;
              }),
            ),
            Expanded(
              child: CityField(
                label: 'Teslim ili',
                value: _to,
                icon: Icons.flag_outlined,
                onChanged: (c) => setState(() => _to = c),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Yük cinsi',
          controller: _cargo,
          hint: 'Örn. Paletli seramik, inşaat demiri',
          maxLength: FieldLimits.cargo,
          validator: Validators.text(
            label: 'Yük cinsi',
            min: 2,
            max: FieldLimits.cargo,
            needsLetter: true,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Ağırlık',
                controller: _tons,
                suffix: 'ton',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: Validators.number(
                  label: 'Ağırlık',
                  positive: true,
                  max: FieldLimits.maxTons,
                  unit: 'ton',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: 'Navlun (isteğe bağlı)',
                controller: _price,
                suffix: '₺',
                hint: 'Boşsa teklif usulü',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: Validators.number(
                  label: 'Navlun',
                  isRequired: false,
                  min: 0,
                  max: FieldLimits.maxLoadPrice,
                  unit: '₺',
                ),
              ),
            ),
          ],
        ),
        const FieldLabel('Araç tipi'),
        ChoiceWrap<VehicleType>(
          values: VehicleType.values,
          selected: _vehicle,
          labelOf: (v) => v.label,
          onSelected: (v) => setState(() => _vehicle = v),
        ),
        const SizedBox(height: 14),
        DateBox(
          label: 'Yükleme tarihi',
          value: _date,
          onChanged: (d) => setState(() => _date = d),
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Açıklama (isteğe bağlı)',
          controller: _note,
          maxLines: 3,
          maxLength: FieldLimits.note,
          hint: 'Yükleme saati, rampa, forklift, ödeme şekli…',
          validator: Validators.text(
            label: 'Açıklama',
            isRequired: false,
            max: FieldLimits.note,
            multiline: true,
          ),
        ),
        const ResponsibilityNote(
          text:
              'Telefon numaranız ilanda görünmez; yalnızca iletişim hakkı açan kişilerle paylaşılır. '
              'Navlun ödemesi taraflar arasında doğrudan yapılır.',
        ),
      ],
    );
  }
}
