import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../config.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import 'deal_detail_screen.dart';

/// Ödeme planı şablonları: ad → yüzdeler.
const Map<String, List<int>> kPaymentPlans = {
  'Tek ödeme': [100],
  '%30 avans + %70 teslimde': [30, 70],
  '%30 / %40 / %30': [30, 40, 30],
  'Aylık 4 hakediş': [25, 25, 25, 25],
};

/// Elle anlaşma kaydı: ilan dışında yapılan bir işi kayda almak ve
/// ödemeleri takip etmek için.
class DealFormScreen extends StatefulWidget {
  const DealFormScreen({super.key});

  @override
  State<DealFormScreen> createState() => _DealFormScreenState();
}

class _DealFormScreenState extends State<DealFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _counterparty = TextEditingController();
  final _amount = TextEditingController();
  final _details = TextEditingController();
  final _terms = TextEditingController();
  bool _iAmCustomer = true;
  PaymentMethod _method = PaymentMethod.havale;
  String _plan = kPaymentPlans.keys.elementAt(1);
  DateTime _start = DateTime.now();

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_title, _counterparty, _amount, _details, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  List<DealMilestone> _milestones(double total) {
    if (total <= 0) return const [];
    final percents = kPaymentPlans[_plan]!;
    final result = <DealMilestone>[];
    var allocated = 0.0;
    for (var i = 0; i < percents.length; i++) {
      final isLast = i == percents.length - 1;
      final amount = isLast
          ? total - allocated
          : (total * percents[i] / 100).roundToDouble();
      allocated += amount;
      final String title;
      if (percents.length == 1) {
        title = 'Tam ödeme';
      } else if (_plan.startsWith('Aylık')) {
        title = '${i + 1}. ay hakedişi';
      } else if (i == 0) {
        title = 'Avans (%${percents[i]})';
      } else if (isLast) {
        title = 'Kesin hakediş (%${percents[i]})';
      } else {
        title = '$i. hakediş (%${percents[i]})';
      }
      result.add(DealMilestone(title: title, amount: amount));
    }
    return result;
  }

  Future<void> _save() async {
    if (!validateForm(context, _formKey)) return;
    final total = parseNumber(_amount.text);
    final milestones = _milestones(total);
    // Ödeme planı toplamı bedelle birebir aynı olmalı (yuvarlama farkı son satıra yazılır).
    final planned = milestones.fold<double>(0, (a, m) => a + m.amount);
    if (total > 0 && (planned - total).abs() > 0.009) {
      showSnack(
        context,
        'Ödeme planı toplamı bedelle uyuşmuyor',
        kind: NoticeKind.error,
      );
      return;
    }
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      final deal = await app.createDeal(
        DealDraft(
          title: Sanitize.line(_title.text),
          iAmCustomer: _iAmCustomer,
          counterpartyName: Sanitize.line(_counterparty.text),
          amount: total,
          paymentMethod: _method,
          details: Sanitize.block(_details.text),
          paymentTerms: Sanitize.line(_terms.text),
          startDate: _start,
          milestones: milestones,
        ),
      );
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DealDetailScreen(dealId: deal.id),
        ),
      );
    } catch (e) {
      // Anlaşma kodunu sunucu üretir; bu nedenle kayıt çevrimdışı açılamaz.
      if (mounted) showError(context, e, onRetry: _save);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = parseNumber(_amount.text);
    final preview = _milestones(total);
    return Scaffold(
      appBar: AppBar(title: const Text('Anlaşma kaydı oluştur')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const InfoBanner(
              text:
                  'İlan dışında anlaştığınız bir işi (nakliye, kiralama, taşeron, malzeme) kayda alın. '
                  'Karşı taraf uygulamadaysa kodla katılıp onaylar; ödemeleri birlikte takip edersiniz.',
              icon: Icons.handshake_outlined,
            ),
            const SizedBox(height: 16),
            const FieldLabel('Bu işte ben'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('İşi veren / alıcı')),
                  ButtonSegment(
                    value: false,
                    label: Text('Hizmet veren / satıcı'),
                  ),
                ],
                selected: {_iAmCustomer},
                onSelectionChanged: (s) =>
                    setState(() => _iAmCustomer = s.first),
              ),
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: 'İş tanımı',
              controller: _title,
              hint: 'Örn. Pendik şantiyesi hafriyat nakliyesi',
              maxLength: FieldLimits.dealTitle,
              validator: Validators.text(
                label: 'İş tanımı',
                min: 2,
                max: FieldLimits.dealTitle,
                needsLetter: true,
              ),
            ),
            LabeledField(
              label: 'Karşı taraf (firma / kişi)',
              controller: _counterparty,
              textCapitalization: TextCapitalization.words,
              maxLength: FieldLimits.counterparty,
              validator: Validators.text(
                label: 'Karşı taraf',
                min: 2,
                max: FieldLimits.counterparty,
                needsLetter: true,
              ),
            ),
            LabeledField(
              label: 'Toplam bedel (isteğe bağlı)',
              controller: _amount,
              suffix: '₺',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: Validators.number(
                label: 'Bedel',
                isRequired: false,
                min: 0,
                max: FieldLimits.maxDealAmount,
                unit: '₺',
              ),
            ),
            const FieldLabel('Ödeme şekli'),
            ChoiceWrap<PaymentMethod>(
              values: PaymentMethod.values,
              selected: _method,
              labelOf: (m) => m.label,
              onSelected: (m) => setState(() => _method = m),
            ),
            const SizedBox(height: 16),
            if (total > 0) ...[
              const FieldLabel('Ödeme planı'),
              ChoiceWrap<String>(
                values: kPaymentPlans.keys.toList(),
                selected: _plan,
                labelOf: (s) => s,
                onSelected: (s) => setState(() => _plan = s),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      for (final m in preview)
                        InfoRow(m.title, formatTL(m.amount)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            DateBox(
              label: 'Başlangıç tarihi',
              value: _start,
              allowPast: true,
              onChanged: (d) => setState(() => _start = d),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Ödeme koşulu (isteğe bağlı)',
              controller: _terms,
              hint: 'Örn. Her hakediş fatura tarihinden itibaren 15 gün içinde',
              maxLength: FieldLimits.paymentTerms,
              validator: Validators.text(
                label: 'Ödeme koşulu',
                isRequired: false,
                max: FieldLimits.paymentTerms,
              ),
            ),
            LabeledField(
              label: 'Detaylar (isteğe bağlı)',
              controller: _details,
              maxLines: 4,
              maxLength: FieldLimits.dealDetails,
              hint: 'Miktar, sefer sayısı, adres, teslim şartları…',
              validator: Validators.text(
                label: 'Detaylar',
                isRequired: false,
                max: FieldLimits.dealDetails,
                multiline: true,
              ),
            ),
            const ResponsibilityNote(
              text:
                  'Bu kayıt taraflar arasındaki anlaşmanın özetidir. Para uygulama üzerinden geçmez; '
                  'ödemeler doğrudan taraflar arasında yapılır.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: AsyncButton(label: 'Kaydı oluştur', onPressed: _save),
        ),
      ),
    );
  }
}

/// Karşı tarafın paylaştığı kodla anlaşmaya katılma.
Future<void> showJoinDealSheet(BuildContext context) =>
    showAppSheet<void>(context, (ctx) => const _JoinSheet());

class _JoinSheet extends StatefulWidget {
  const _JoinSheet();

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final error = Validators.dealCode(_code.text);
    if (error != null) {
      showSnack(context, error, kind: NoticeKind.warning);
      return;
    }
    final code = _code.text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      final deal = await app.joinDeal(code);
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => DealDetailScreen(dealId: deal.id),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _join);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kodla anlaşmaya katıl',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Karşı tarafın size gönderdiği 8 haneli kayıt kodunu yazın.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: AppConfig.usesDotNet ? 10 : 8,
            style: const TextStyle(
              fontSize: 22,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              hintText: 'ABCD2345',
              counterText: '',
            ),
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: 14),
          AsyncButton(label: 'Katıl', onPressed: _join),
        ],
      ),
    );
  }
}
