import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../state/app_state.dart';
import '../../../utils/format.dart';
import '../../../utils/validators.dart';
import '../../../widgets/city_picker.dart';
import '../../../widgets/common.dart';
import 'listing_forms.dart';

/// Personel (operatör, şoför, usta) ilanı.
class JobFormScreen extends StatefulWidget {
  const JobFormScreen({super.key, this.initial});

  final JobPost? initial;

  @override
  State<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends State<JobFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _wage;
  late final TextEditingController _duration;
  late final TextEditingController _requirements;
  late final TextEditingController _note;
  WorkerRole _role = WorkerRole.ekskavatorOp;
  String _period = 'Günlük';
  late String _city;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final j = widget.initial;
    _role = j?.role ?? WorkerRole.ekskavatorOp;
    _period = j != null && kWagePeriods.contains(j.wagePeriod) ? j.wagePeriod : 'Günlük';
    _city = j?.city ?? app.city;
    _title = TextEditingController(text: j?.title ?? '');
    _wage = TextEditingController(text: j == null || j.wage <= 0 ? '' : formatNumber(j.wage, decimals: 2));
    _duration = TextEditingController(text: j?.duration ?? '');
    _requirements = TextEditingController(text: j == null ? 'MYK belgesi, G sınıfı ehliyet' : j.requirements.join(', '));
    _note = TextEditingController(text: j?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_title, _wage, _duration, _requirements, _note]) {
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
    final job = JobPost(
      id: initial?.id ?? '',
      owner: app.me ?? PublicProfile.unknown,
      title: Sanitize.line(_title.text),
      role: _role,
      city: _city,
      wage: parseNumber(_wage.text),
      wagePeriod: _period,
      duration: Sanitize.line(_duration.text),
      requirements: Sanitize.commaList(_requirements.text),
      note: Sanitize.block(_note.text),
      status: initial?.status ?? ListingStatus.active,
      createdAt: initial?.createdAt,
    );
    final navigator = Navigator.of(context);
    final ok = await saveListingFlow(
      context,
      job,
      isNew: !_editing,
      successMessage: _editing ? 'İlan güncellendi' : 'İlanınız yayında',
    );
    if (ok) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: _editing ? 'İlanı düzenle' : 'Personel ilanı ver',
      formKey: _formKey,
      submitLabel: _editing ? 'Değişiklikleri kaydet' : 'İlanı yayınla',
      onSubmit: _save,
      children: [
        const FieldLabel('Aranan pozisyon'),
        ChoiceWrap<WorkerRole>(
          values: WorkerRole.values,
          selected: _role,
          labelOf: (r) => r.label,
          onSelected: (r) => setState(() => _role = r),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'İlan başlığı',
          controller: _title,
          hint: 'Örn. Otoyol projesi için silindir operatörü',
          maxLength: FieldLimits.jobTitle,
          validator: Validators.text(label: 'Başlık', min: 3, max: FieldLimits.jobTitle, needsLetter: true),
        ),
        CityField(label: 'Çalışma ili', value: _city, onChanged: (c) => setState(() => _city = c ?? _city)),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Ücret (isteğe bağlı)',
                controller: _wage,
                suffix: '₺',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: Validators.number(label: 'Ücret', isRequired: false, min: 0, max: FieldLimits.maxWage, unit: '₺'),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: DropdownButton<String>(
                value: _period,
                underline: const SizedBox.shrink(),
                items: [for (final p in kWagePeriods) DropdownMenuItem(value: p, child: Text(p))],
                onChanged: (v) => setState(() => _period = v ?? _period),
              ),
            ),
          ],
        ),
        LabeledField(
          label: 'Çalışma süresi (isteğe bağlı)',
          controller: _duration,
          hint: 'Örn. 3 ay',
          maxLength: FieldLimits.jobDuration,
          validator: Validators.text(label: 'Süre', isRequired: false, max: FieldLimits.jobDuration),
        ),
        LabeledField(
          label: 'Aranan şartlar (virgülle ayırın)',
          controller: _requirements,
          maxLines: 2,
          maxLength: FieldLimits.listItems * (FieldLimits.listItemLength + 2),
          validator: Validators.commaList(label: 'Aranan şartlar'),
        ),
        LabeledField(
          label: 'Açıklama (isteğe bağlı)',
          controller: _note,
          maxLines: 3,
          maxLength: FieldLimits.note,
          hint: 'Konaklama, yemek, mesai, yol…',
          validator: Validators.text(label: 'Açıklama', isRequired: false, max: FieldLimits.note, multiline: true),
        ),
        const ResponsibilityNote(
          text: 'İş ilişkisi (sözleşme, sigorta, ücret ödemesi) işveren ile çalışan arasındadır; '
              'iş mevzuatına uymak işverenin sorumluluğundadır.',
        ),
      ],
    );
  }
}
