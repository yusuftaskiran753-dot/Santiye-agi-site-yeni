import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../billing/billing_flows.dart';

/// Teklif / talep gönderme. Önce iletişim hakkı açılır (ücretsiz hak, Premium
/// veya kredi). Gönderilirse true döner.
Future<bool> sendRequestFlow(BuildContext context, Listing listing) async {
  if (!await ensureUnlocked(context, listing)) return false;
  if (!context.mounted) return false;
  final sent = await showAppSheet<bool>(context, (ctx) => RequestSheet(listing: listing));
  return sent ?? false;
}

class RequestSheet extends StatefulWidget {
  const RequestSheet({super.key, required this.listing});

  final Listing listing;

  @override
  State<RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<RequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _qty = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  bool _daily = true;
  String _period = 'Günlük';
  TradeRequest? _existing;

  Listing get l => widget.listing;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _existing = app.myPendingRequestFor(l);
    final e = _existing;
    switch (l) {
      case Load load:
        _amount.text = e != null
            ? formatNumber(e.amount)
            : load.price > 0
                ? formatNumber(load.price)
                : '';
        _date = e?.startDate ?? (load.date.isBefore(DateTime.now()) ? DateTime.now() : load.date);
      case Machine _:
        _daily = e == null || e.unit != 'saat';
        _qty.text = e != null ? formatNumber(e.quantity) : (_daily ? '1' : '8');
      case MaterialListing m:
        _qty.text = e != null ? formatNumber(e.quantity, decimals: 2) : formatNumber(m.minQty > 0 ? m.minQty : 10);
      case WorkerCard _:
        _amount.text = e != null ? formatNumber(e.amount) : '';
        _period = e != null && kWagePeriods.contains(e.unit) ? e.unit : 'Günlük';
      default:
        break;
    }
    if (e != null) {
      _addressCtrl.text = e.address;
      _note.text = e.note;
      if (e.startDate != null && l is! Load) _date = e.startDate!;
    }
    _qty.addListener(_refresh);
    _amount.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in [_amount, _qty, _addressCtrl, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _machineEstimate {
    final m = l as Machine;
    return (_daily ? m.daily : m.hourly) * parseNumber(_qty.text);
  }

  String get _title => switch (l.kind) {
        ListingKind.yuk => 'Nakliye teklifi',
        ListingKind.makine => 'Kiralama talebi',
        ListingKind.malzeme => 'Sipariş talebi',
        ListingKind.personel => 'İşe başvur',
        ListingKind.sicil => 'İş teklif et',
      };

  final FieldValidator _address = Validators.text(label: 'Adres', min: 3, max: FieldLimits.address);
  final FieldValidator _amountCheck =
      Validators.number(label: 'Tutar', positive: true, max: FieldLimits.maxRequestAmount, unit: '₺');

  /// Talebin toplam tutarı sunucu sınırını aşmamalı (miktar × birim fiyat).
  String? _totalCheck(double total) =>
      total > FieldLimits.maxRequestAmount ? 'Toplam tutar en fazla ${formatTL(FieldLimits.maxRequestAmount)} olabilir' : null;

  String? _dateCheck() {
    final today = startOfToday();
    final d = DateTime(_date.year, _date.month, _date.day);
    if (d.isBefore(today)) return 'Tarih geçmiş olamaz';
    if (d.isAfter(today.add(const Duration(days: 366)))) return 'Tarih en fazla bir yıl sonrası olabilir';
    return null;
  }

  RequestDraft _draft() {
    final note = Sanitize.block(_note.text);
    final address = Sanitize.line(_addressCtrl.text);
    return switch (l) {
      Load load => RequestDraft(
          kind: l.kind,
          listingId: l.id,
          amount: parseNumber(_amount.text),
          quantity: load.tons,
          unit: 'ton',
          startDate: _date,
          note: note,
        ),
      Machine _ => RequestDraft(
          kind: l.kind,
          listingId: l.id,
          amount: _machineEstimate,
          quantity: parseNumber(_qty.text),
          unit: _daily ? 'gün' : 'saat',
          startDate: _date,
          address: address,
          note: note,
        ),
      MaterialListing m => RequestDraft(
          kind: l.kind,
          listingId: l.id,
          amount: parseNumber(_qty.text) * m.price,
          quantity: parseNumber(_qty.text),
          unit: m.unit,
          startDate: _date,
          address: address,
          note: note,
        ),
      WorkerCard _ => RequestDraft(
          kind: l.kind,
          listingId: l.id,
          amount: parseNumber(_amount.text),
          quantity: 1,
          unit: _period,
          startDate: _date,
          address: address,
          note: note,
        ),
      _ => RequestDraft(kind: l.kind, listingId: l.id, note: note),
    };
  }

  Future<void> _submit() async {
    if (!validateForm(context, _formKey)) return;
    if (l is! JobPost) {
      final dateError = _dateCheck();
      if (dateError != null) {
        showSnack(context, dateError, kind: NoticeKind.warning);
        return;
      }
    }
    final draft = _draft();
    final totalError = _totalCheck(draft.amount);
    if (totalError != null) {
      showSnack(context, totalError, kind: NoticeKind.warning);
      return;
    }
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      await app.sendRequest(l, draft);
      navigator.pop(true);
      showSaved(
        null,
        '${l.kind.requestLabel} iletildi. Yanıtı "İşlerim" sekmesinden takip edebilirsiniz.',
        queued: app.lastWriteQueued,
      );
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _submit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              '${l.title} · ${l.owner.displayName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted),
            ),
            if (_existing != null) ...[
              const SizedBox(height: 10),
              const InfoBanner(
                text: 'Bu ilana bekleyen bir talebiniz var; gönderirseniz güncellenir.',
                icon: Icons.edit_note_rounded,
              ),
            ],
            const SizedBox(height: 16),
            ..._fields(),
            LabeledField(
              label: 'Not (isteğe bağlı)',
              controller: _note,
              maxLines: 3,
              maxLength: FieldLimits.note,
              hint: _noteHint,
              validator: Validators.text(label: 'Not', isRequired: false, max: FieldLimits.note, multiline: true),
            ),
            const SizedBox(height: 4),
            AsyncButton(
              icon: Icons.send_rounded,
              label: _existing == null ? 'Gönder' : 'Güncelle',
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            const ResponsibilityNote(),
          ],
        ),
      ),
    );
  }

  String get _noteHint => switch (l.kind) {
        ListingKind.yuk => 'Araç plakası, ne zaman yükleyebileceğiniz…',
        ListingKind.makine => 'İşin türü, operatör ihtiyacı, mesai saatleri…',
        ListingKind.malzeme => 'Teslim saati, pompa ihtiyacı, fatura bilgisi…',
        ListingKind.personel => 'Kısaca deneyiminiz ve ne zaman başlayabileceğiniz…',
        ListingKind.sicil => 'İşin türü, süre, konaklama/yemek durumu…',
      };

  List<Widget> _fields() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    switch (l) {
      case Load load:
        return [
          LabeledField(
            label: 'Teklifiniz (navlun)',
            controller: _amount,
            suffix: '₺',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _amountCheck,
            helper: load.price > 0 ? 'İlan navlunu: ${formatTL(load.price)}' : 'İlan sahibi fiyat belirtmemiş; teklifinizi yazın.',
          ),
          DateBox(label: 'Yükleyebileceğim gün', value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 14),
        ];
      case Machine m:
        return [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Günlük')),
                ButtonSegment(value: false, label: Text('Saatlik')),
              ],
              selected: {_daily},
              onSelectionChanged: (s) => setState(() {
                _daily = s.first;
                _qty.text = _daily ? '1' : '8';
              }),
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: _daily ? 'Kaç gün?' : 'Kaç saat?',
            controller: _qty,
            suffix: _daily ? 'gün' : 'saat',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: Validators.number(
              label: _daily ? 'Gün sayısı' : 'Saat',
              positive: true,
              max: _daily ? 365 : 2000,
              unit: _daily ? 'gün' : 'saat',
            ),
          ),
          DateBox(label: 'Başlangıç', value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Şantiye konumu / adres',
            controller: _addressCtrl,
            hint: 'Örn. Kartal, Yakacık şantiyesi',
            validator: _address,
            maxLength: FieldLimits.address,
          ),
          _TotalBox(
            label: 'Tahmini tutar',
            value: _machineEstimate,
            note: '${_daily ? formatTL(m.daily) : formatTL(m.hourly)} × ${_qty.text.isEmpty ? '0' : _qty.text} ${_daily ? 'gün' : 'saat'}'
                '${m.withOperator ? ' · operatör dahil' : ''}',
          ),
          const SizedBox(height: 14),
        ];
      case MaterialListing m:
        final qty = parseNumber(_qty.text);
        return [
          LabeledField(
            label: 'Miktar',
            controller: _qty,
            suffix: m.unit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: Validators.all([
              Validators.number(label: 'Miktar', positive: true, max: FieldLimits.maxQuantity, unit: m.unit),
              (v) {
                final q = parseNumber(v ?? '');
                if (m.minQty > 0 && q < m.minQty) return 'En az sipariş: ${formatNumber(m.minQty, decimals: 2)} ${m.unit}';
                return null;
              },
            ]),
          ),
          DateBox(label: 'Teslim tarihi', value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Teslimat adresi',
            controller: _addressCtrl,
            hint: 'Şantiye adı ve adresi',
            validator: _address,
            maxLength: FieldLimits.address,
          ),
          _TotalBox(
            label: 'Malzeme bedeli (KDV hariç)',
            value: qty * m.price,
            note: m.delivery
                ? 'Nakliye bedelini satıcı teyit eder.'
                : 'Satıcı nakliye sağlamıyor; aracı sizin ayarlamanız gerekir.',
          ),
          const SizedBox(height: 14),
        ];
      case JobPost _:
        final card = context.read<AppState>().myWorkerCard;
        return [
          if (card == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'İpucu: Profil → "Sicil kartım" ile deneyim ve belgelerinizi ekleyin; işveren başvurunuzla birlikte görür.',
                style: TextStyle(fontSize: 12.5, color: muted),
              ),
            ),
        ];
      case WorkerCard _:
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Ücret',
                  controller: _amount,
                  suffix: '₺',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: Validators.number(label: 'Ücret', positive: true, max: FieldLimits.maxWage, unit: '₺'),
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
          DateBox(label: 'Başlangıç', value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 14),
          LabeledField(
            label: 'Çalışma yeri',
            controller: _addressCtrl,
            hint: 'İl / ilçe, şantiye',
            validator: _address,
            maxLength: FieldLimits.address,
          ),
        ];
      default:
        return const [];
    }
  }
}

class _TotalBox extends StatelessWidget {
  const _TotalBox({required this.label, required this.value, this.note});

  final String label;
  final double value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(formatTL(value), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: primary)),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
