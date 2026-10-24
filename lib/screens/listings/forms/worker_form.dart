import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../state/app_state.dart';
import '../../../utils/format.dart';
import '../../../utils/validators.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/common.dart';
import 'listing_forms.dart';

/// Operatör / personelin sicil kartı (kişi başı bir kart).
class WorkerFormScreen extends StatefulWidget {
  const WorkerFormScreen({super.key, this.initial});

  final WorkerCard? initial;

  @override
  State<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends State<WorkerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _years;
  late final TextEditingController _certificates;
  late final TextEditingController _about;
  WorkerRole _role = WorkerRole.ekskavatorOp;
  late String _city;
  bool _available = true;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final w = widget.initial ?? app.myWorkerCard;
    _role = w?.role ?? WorkerRole.ekskavatorOp;
    _city = w?.city ?? app.city;
    _available = w?.available ?? true;
    _years = TextEditingController(text: w == null ? '' : '${w.years}');
    _certificates = TextEditingController(text: w == null ? 'MYK belgesi, G sınıfı ehliyet' : w.certificates.join(', '));
    _about = TextEditingController(text: w?.about ?? '');
  }

  @override
  void dispose() {
    _years.dispose();
    _certificates.dispose();
    _about.dispose();
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
    final existing = widget.initial ?? app.myWorkerCard;
    final card = WorkerCard(
      id: existing?.id ?? '',
      owner: app.me ?? PublicProfile.unknown,
      role: _role,
      city: _city,
      years: parseNumber(_years.text).round(),
      certificates: Sanitize.commaList(_certificates.text),
      available: _available,
      about: Sanitize.block(_about.text),
      status: existing?.status ?? ListingStatus.active,
      createdAt: existing?.createdAt,
    );
    final navigator = Navigator.of(context);
    if (await saveListingFlow(context, card, isNew: existing == null, successMessage: 'Sicil kartınız yayında')) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    return FormPage(
      title: widget.initial == null ? 'Sicil kartım' : 'Sicil kartını düzenle',
      formKey: _formKey,
      submitLabel: 'Kaydet',
      onSubmit: _save,
      children: [
        Card(
          child: ListTile(
            leading: Avatar(me?.name ?? '', radius: 20),
            title: Text(me?.name ?? ''),
            subtitle: const Text('Ad ve puanınız profilinizden gelir. Telefonunuz yalnızca iletişim hakkı açanlara gösterilir.'),
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Pozisyon'),
        ChoiceWrap<WorkerRole>(
          values: WorkerRole.values,
          selected: _role,
          labelOf: (r) => r.label,
          onSelected: (r) => setState(() => _role = r),
        ),
        const SizedBox(height: 16),
        CityField(label: 'Çalıştığınız il', value: _city, onChanged: (c) => setState(() => _city = c ?? _city)),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Deneyim',
          controller: _years,
          suffix: 'yıl',
          keyboardType: TextInputType.number,
          maxLength: 2,
          validator: Validators.number(label: 'Deneyim', min: 0, max: FieldLimits.maxYears.toDouble(), integer: true, unit: 'yıl'),
        ),
        LabeledField(
          label: 'Belgeler (virgülle ayırın)',
          controller: _certificates,
          maxLines: 2,
          maxLength: FieldLimits.listItems * (FieldLimits.listItemLength + 2),
          validator: Validators.commaList(label: 'Belgeler'),
        ),
        LabeledField(
          label: 'Hakkımda (isteğe bağlı)',
          controller: _about,
          maxLines: 3,
          maxLength: FieldLimits.about,
          hint: 'Hangi makinelerde deneyimlisiniz, hangi projelerde çalıştınız?',
          validator: Validators.text(label: 'Hakkımda', isRequired: false, max: FieldLimits.about, multiline: true),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Şu an iş arıyorum (müsait)', style: TextStyle(fontWeight: FontWeight.w600)),
          value: _available,
          onChanged: (v) => setState(() => _available = v),
        ),
      ],
    );
  }
}
