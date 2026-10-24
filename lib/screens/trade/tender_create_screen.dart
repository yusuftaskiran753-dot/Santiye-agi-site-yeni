import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/santiye_constants.dart';
import '../../models/trade.dart';
import '../../state/app_state.dart';
import '../../utils/legal_notices.dart';
import '../../utils/profanity_filter.dart';
import '../../utils/validators.dart';
import '../../widgets/city_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/legal_notice_bar.dart';

/// İhale açma formu (müteahhit / şantiye şefi).
class TenderCreateScreen extends StatefulWidget {
  const TenderCreateScreen({super.key});

  @override
  State<TenderCreateScreen> createState() => _TenderCreateScreenState();
}

class _TenderCreateScreenState extends State<TenderCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _detail = TextEditingController();
  String? _city;
  late Set<WorkSector> _sectors;
  Set<TradeProfession> _allowed = {
    TradeProfession.taseron,
    TradeProfession.formen,
    TradeProfession.ustabasi,
  };
  DateTime _closes = DateTime.now().add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _sectors = {...app.myIdentity.sectors};
    _city = app.city;
  }

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!validateForm(context, _formKey)) return;
    if (_city == null) {
      showSnack(context, 'İl seçin.');
      return;
    }
    if (_sectors.isEmpty || _allowed.isEmpty) {
      showSnack(context, 'En az bir sektör ve bir meslek seçin.');
      return;
    }
    final app = context.read<AppState>();
    // Seçilen gün sonunda (23:59) teklif alma biter.
    final closes = DateTime(_closes.year, _closes.month, _closes.day, 23, 59);
    await app.createTender(
      title: _title.text,
      detail: _detail.text,
      city: _city!,
      sectors: _sectors.toList(),
      allowed: _allowed.toList(),
      closesAt: closes,
    );
    if (!mounted) return;
    Navigator.pop(context);
    showSuccess(context, 'İhale açıldı.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('İhale aç')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const LegalNoticeBar(detail: LegalNotices.tender),
            const SizedBox(height: 18),
            LabeledField(
              label: 'İhale başlığı',
              controller: _title,
              maxLength: FieldLimits.jobTitle,
              validator: Validators.all([
                Validators.text(label: 'Başlık', min: 6, max: FieldLimits.jobTitle),
                ProfanityFilter.validate,
              ]),
            ),
            LabeledField(
              label: 'İş tanımı',
              controller: _detail,
              maxLines: 5,
              maxLength: FieldLimits.note,
              validator: Validators.all([
                Validators.text(
                  label: 'İş tanımı',
                  min: 10,
                  max: FieldLimits.note,
                  multiline: true,
                ),
                ProfanityFilter.validate,
              ]),
            ),
            CityField(
              label: 'İl',
              value: _city,
              onChanged: (c) => setState(() => _city = c ?? _city),
            ),
            const SizedBox(height: 14),
            DateBox(
              label: 'Teklif verme son günü',
              value: _closes,
              onChanged: (d) => setState(() => _closes = d),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Sektör'),
            MultiChoiceWrap<WorkSector>(
              values: [...kSektorler, ...WorkSector.values.where((s) => !kSektorler.contains(s))],
              selected: _sectors,
              labelOf: (s) => s.label,
              onChanged: (s) => setState(() => _sectors = s),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Kimler teklif verebilir?'),
            MultiChoiceWrap<TradeProfession>(
              values: kMeslekler,
              selected: _allowed,
              labelOf: (p) => p.label,
              onChanged: (s) => setState(() => _allowed = s),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 56,
            child: AsyncButton(label: 'İhaleyi aç', icon: Icons.gavel_rounded, onPressed: _submit),
          ),
        ),
      ),
    );
  }
}
