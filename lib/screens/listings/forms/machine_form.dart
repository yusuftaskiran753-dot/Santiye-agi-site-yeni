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

/// Makineyi havuza ekleme veya düzenleme.
class MachineFormScreen extends StatefulWidget {
  const MachineFormScreen({super.key, this.initial});

  final Machine? initial;

  @override
  State<MachineFormScreen> createState() => _MachineFormScreenState();
}

class _MachineFormScreenState extends State<MachineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _model;
  late final TextEditingController _capacity;
  late final TextEditingController _hourly;
  late final TextEditingController _daily;
  late final TextEditingController _note;
  MachineType _type = MachineType.ekskavator;
  bool _withOperator = true;
  bool _available = true;
  late String _city;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final m = widget.initial;
    _type = m?.type ?? MachineType.ekskavator;
    _withOperator = m?.withOperator ?? true;
    _available = m?.available ?? true;
    _city = m?.city ?? app.city;
    _model = TextEditingController(text: m?.model ?? '');
    _capacity = TextEditingController(text: m?.capacity ?? '');
    _hourly = TextEditingController(text: m == null || m.hourly <= 0 ? '' : formatNumber(m.hourly, decimals: 2));
    _daily = TextEditingController(text: m == null || m.daily <= 0 ? '' : formatNumber(m.daily, decimals: 2));
    _note = TextEditingController(text: m?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_model, _capacity, _hourly, _daily, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  // Ücret alanlarından en az biri dolu olmalı; ikisi de geçerli sayı ve sınır içinde.
  late final FieldValidator _dailyCheck = Validators.all([
    Validators.number(label: 'Günlük ücret', isRequired: false, min: 0, max: FieldLimits.maxMachinePrice, unit: '₺'),
    Validators.anyPositive([() => _daily.text, () => _hourly.text], 'Saatlik veya günlük ücret yazın'),
  ]);
  final _dailyKey = GlobalKey<FormFieldState<String>>();
  final _hourlyKey = GlobalKey<FormFieldState<String>>();
  final FieldValidator _hourlyCheck =
      Validators.number(label: 'Saatlik ücret', isRequired: false, min: 0, max: FieldLimits.maxMachinePrice, unit: '₺');

  Future<void> _save() async {
    if (!validateForm(context, _formKey)) return;
    final cityError = Validators.city(_city);
    if (cityError != null) {
      showSnack(context, cityError, kind: NoticeKind.warning);
      return;
    }
    final app = context.read<AppState>();
    final initial = widget.initial;

    // Konum: il değişmediyse eski konum korunur; değiştiyse il merkezine yakın
    // küçük bir sapma verilir (kesin adres ilanda yayınlanmaz).
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

    final machine = Machine(
      id: initial?.id ?? '',
      owner: app.me ?? PublicProfile.unknown,
      type: _type,
      model: Sanitize.line(_model.text),
      capacity: Sanitize.line(_capacity.text),
      city: _city,
      lat: lat,
      lng: lng,
      hourly: parseNumber(_hourly.text),
      daily: parseNumber(_daily.text),
      withOperator: _withOperator,
      available: _available,
      note: Sanitize.block(_note.text),
      status: initial?.status ?? ListingStatus.active,
      createdAt: initial?.createdAt,
    );
    final navigator = Navigator.of(context);
    final ok = await saveListingFlow(
      context,
      machine,
      isNew: !_editing,
      successMessage: _editing ? 'Makine güncellendi' : 'Makineniz yayında',
    );
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: _editing ? 'Makineyi düzenle' : 'Makinemi ekle',
      formKey: _formKey,
      submitLabel: _editing ? 'Değişiklikleri kaydet' : 'Yayınla',
      onSubmit: _save,
      children: [
        const FieldLabel('Makine tipi'),
        ChoiceWrap<MachineType>(
          values: MachineType.values,
          selected: _type,
          labelOf: (t) => t.label,
          onSelected: (t) => setState(() => _type = t),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Marka / model',
          controller: _model,
          hint: 'Örn. Komatsu PC300',
          maxLength: FieldLimits.machineModel,
          validator: Validators.text(label: 'Marka / model', min: 2, max: FieldLimits.machineModel),
        ),
        LabeledField(
          label: 'Kapasite (isteğe bağlı)',
          controller: _capacity,
          hint: 'Örn. 30 ton · 1,6 m³ kova',
          maxLength: FieldLimits.machineCapacity,
          validator: Validators.text(label: 'Kapasite', isRequired: false, max: FieldLimits.machineCapacity),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Günlük ücret',
                controller: _daily,
                suffix: '₺',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                fieldKey: _dailyKey,
                validator: _dailyCheck,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LabeledField(
                label: 'Saatlik ücret',
                controller: _hourly,
                suffix: '₺',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                fieldKey: _hourlyKey,
                validator: _hourlyCheck,
                // Saatlik ücret yazılınca günlük alandaki "en az biri" uyarısı hemen güncellenir.
                onChanged: (_) {
                  if (_dailyKey.currentState?.hasError ?? false) _dailyKey.currentState?.validate();
                },
              ),
            ),
          ],
        ),
        CityField(label: 'Bulunduğu il', value: _city, onChanged: (c) => setState(() => _city = c ?? _city)),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Operatör dahil'),
          value: _withOperator,
          onChanged: (v) => setState(() => _withOperator = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Şu an kiralamaya müsait'),
          value: _available,
          onChanged: (v) => setState(() => _available = v),
        ),
        const SizedBox(height: 6),
        LabeledField(
          label: 'Açıklama (isteğe bağlı)',
          controller: _note,
          maxLines: 3,
          maxLength: FieldLimits.note,
          hint: 'Yakıt, nakliye (lowbed), minimum kiralama süresi…',
          validator: Validators.text(label: 'Açıklama', isRequired: false, max: FieldLimits.note, multiline: true),
        ),
      ],
    );
  }
}
