import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../utils/format.dart';
import '../../utils/validators.dart';
import '../../widgets/city_picker.dart';
import '../../widgets/common.dart';

/// Profil formunun çıktısı.
class ProfileInput {
  const ProfileInput({
    required this.name,
    required this.company,
    required this.phone,
    required this.role,
    required this.city,
  });

  final String name;
  final String company;

  /// +90XXXXXXXXXX biçiminde.
  final String phone;
  final UserRole role;
  final String city;
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.onSubmit,
    required this.submitLabel,
    this.initial,
    this.initialPhone = '',
    this.phoneLocked = false,
  });

  final PublicProfile? initial;
  final String initialPhone;

  /// Telefon SMS ile doğrulandıysa değiştirilemez.
  final bool phoneLocked;
  final Future<void> Function(ProfileInput input) onSubmit;
  final String submitLabel;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _company;
  late final TextEditingController _phone;
  late UserRole _role;
  late String _city;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p?.name ?? '');
    _company = TextEditingController(text: p?.company ?? '');
    _phone = TextEditingController(text: widget.initialPhone.isEmpty ? '' : formatPhoneDisplay(widget.initialPhone));
    _role = p?.role ?? UserRole.nakliyeci;
    _city = (p?.city.isNotEmpty ?? false) ? p!.city : 'İstanbul';
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!validateForm(context, _formKey)) return;
    await widget.onSubmit(ProfileInput(
      name: Sanitize.line(_name.text),
      company: Sanitize.line(_company.text),
      phone: normalizePhoneTr(_phone.text),
      role: _role,
      city: _city,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledField(
            label: 'Ad Soyad',
            controller: _name,
            hint: 'Örn. Ahmet Yılmaz',
            maxLength: FieldLimits.personName,
            textCapitalization: TextCapitalization.words,
            validator: Validators.personName,
          ),
          LabeledField(
            label: 'Firma (isteğe bağlı)',
            controller: _company,
            hint: 'Örn. Yılmaz Nakliyat',
            maxLength: FieldLimits.company,
            textCapitalization: TextCapitalization.words,
            validator: Validators.text(label: 'Firma adı', isRequired: false, min: 2, max: FieldLimits.company),
          ),
          LabeledField(
            label: 'Cep telefonu',
            controller: _phone,
            hint: '05xx xxx xx xx',
            keyboardType: TextInputType.phone,
            readOnly: widget.phoneLocked,
            helper: widget.phoneLocked
                ? 'SMS ile doğrulandı.'
                : 'Herkese açık değildir; iletişim hakkı açan kullanıcılar, teklif/talebin tarafları ve anlaşmanın tarafları görebilir.',
            maxLength: 20,
            validator: Validators.phone,
          ),
          const FieldLabel('Ne iş yapıyorsunuz?'),
          ChoiceWrap<UserRole>(
            values: UserRole.values,
            selected: _role,
            labelOf: (r) => r.label,
            onSelected: (r) => setState(() => _role = r),
          ),
          const SizedBox(height: 16),
          CityField(label: 'Çalıştığınız il', value: _city, onChanged: (c) => setState(() => _city = c ?? _city)),
          const SizedBox(height: 22),
          AsyncButton(label: widget.submitLabel, onPressed: _submit),
        ],
      ),
    );
  }
}
