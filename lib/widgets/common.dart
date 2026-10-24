import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/app_notice.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'feedback.dart';

export '../services/app_notice.dart' show NoticeKind;
export 'feedback.dart' show AppFeedback;

// ════════════════════════════ Yardımcı işlevler ════════════════════════════

void showSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  NoticeKind kind = NoticeKind.info,
}) {
  AppFeedback.show(message, kind: kind, context: context, actionLabel: actionLabel, onAction: onAction);
}

/// İşlem başarıyla tamamlandı (yeşil).
void showSuccess(BuildContext context, String message) => AppFeedback.success(message, context: context);

/// Yazma işleminin sonucu: sunucuya ulaştıysa [onlineMessage] (yeşil);
/// internet yokken cihaza kaydedilip gönderim sırasına alındıysa ([queued]) bunu söyler.
void showSaved(BuildContext? context, String onlineMessage, {required bool queued}) {
  final ctx = context != null && context.mounted ? context : null;
  if (queued) {
    AppFeedback.warning(
      'İnternet yok: kaydınız cihaza alındı, bağlantı gelince otomatik gönderilecek.',
      context: ctx,
    );
  } else {
    AppFeedback.success(onlineMessage, context: ctx);
  }
}

/// Hatayı kullanıcının anlayacağı Türkçe mesajla gösterir. Bağlantı hatalarında
/// [onRetry] verilirse "Tekrar dene" düğmesi çıkar.
void showError(BuildContext context, Object error, {VoidCallback? onRetry}) {
  if (!context.mounted) return;
  AppFeedback.error(error, context: context, onRetry: onRetry);
}

/// Formu doğrular. Hatalı alan varsa kullanıcıyı uyarır, ilk hatalı alana
/// kaydırır ve false döner.
bool validateForm(BuildContext context, GlobalKey<FormState> formKey) {
  final form = formKey.currentState;
  if (form == null) return false;
  if (form.validate()) return true;
  AppFeedback.warning('Lütfen kırmızıyla işaretlenen alanları düzeltin.', context: context);
  return false;
}

Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title, {
  String? message,
  String ok = 'Evet',
  String cancel = 'Vazgeç',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.red) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Bağlantıyı tarayıcıda / ilgili uygulamada açar. [url] boşsa bilgi verir.
Future<void> openExternal(BuildContext context, String url, {String? failMessage}) async {
  if (url.trim().isEmpty) {
    showSnack(context, 'Bu bağlantı henüz eklenmedi.');
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) showSnack(context, failMessage ?? 'Bağlantı açılamadı');
}

Future<void> callPhone(BuildContext context, String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) {
    showSnack(context, 'Telefon numarası yok');
    return;
  }
  var ok = false;
  try {
    ok = await launchUrl(Uri(scheme: 'tel', path: digits));
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) showSnack(context, 'Arama başlatılamadı: ${formatPhoneDisplay(phone)}');
}

/// Kişiye hazır mesajla WhatsApp'tan yazar.
Future<void> openWhatsApp(BuildContext context, String phone, String text) {
  final number = phoneToInternational(phone);
  return openExternal(
    context,
    Uri.https('wa.me', '/$number', {'text': text}).toString(),
    failMessage: 'WhatsApp açılamadı',
  );
}

/// Metni WhatsApp'ta paylaşır (kişi seçimi WhatsApp'ta yapılır).
Future<void> shareOnWhatsApp(BuildContext context, String text) => openExternal(
      context,
      Uri.https('wa.me', '/', {'text': text}).toString(),
      failMessage: 'WhatsApp açılamadı',
    );

Future<void> openDirections(BuildContext context, {required String origin, required String destination}) =>
    openExternal(
      context,
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'origin': origin,
        'destination': destination,
        'travelmode': 'driving',
      }).toString(),
      failMessage: 'Harita uygulaması açılamadı',
    );

Future<void> openMapAt(BuildContext context, double lat, double lng) => openExternal(
      context,
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'}).toString(),
      failMessage: 'Harita uygulaması açılamadı',
    );

Future<void> copyText(BuildContext context, String text, {String done = 'Panoya kopyalandı'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, done);
}

// ════════════════════════════ Küçük bileşenler ════════════════════════════

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction, this.padding});

  final String text;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(2, 20, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, letterSpacing: -0.1)),
          ),
          if (action != null && onAction != null)
            TextButton(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36)),
              onPressed: onAction,
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.brand, this.icon, this.filled = false});

  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color = AppColors.brand, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.color, this.onTap});

  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? theme.colorScheme.onSurface),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: muted.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.4)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.icon, this.valueColor});

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: muted),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: TextStyle(color: muted))),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w600, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.count, this.size = 15});

  final double rating;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isNew = rating <= 0 || (count != null && count == 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: size + 2, color: isNew ? muted : const Color(0xFFF5A623)),
        const SizedBox(width: 2),
        Text(
          isNew ? 'Yeni üye' : rating.toStringAsFixed(1).replaceAll('.', ','),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: size - 1, color: isNew ? muted : null),
        ),
        if (!isNew && count != null && count! > 0)
          Text(' ($count)', style: TextStyle(fontSize: size - 2, color: muted)),
      ],
    );
  }
}

/// Etiketli metin alanı.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.maxLength,
    this.suffix,
    this.prefix,
    this.textCapitalization = TextCapitalization.sentences,
    this.readOnly = false,
    this.onChanged,
    this.helper,
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;

  /// Başka bir alan değişince bu alanı yeniden doğrulamak için (çapraz doğrulama).
  final GlobalKey<FormFieldState<String>>? fieldKey;
  final String? hint;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final int? maxLength;
  final String? suffix;
  final String? prefix;
  final TextCapitalization textCapitalization;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          TextFormField(
            key: fieldKey,
            controller: controller,
            keyboardType: keyboardType,
            validator: validator,
            maxLines: maxLines,
            maxLength: maxLength,
            readOnly: readOnly,
            onChanged: onChanged,
            textCapitalization: textCapitalization,
            decoration: InputDecoration(
              hintText: hint,
              suffixText: suffix,
              prefixText: prefix,
              helperText: helper,
              helperMaxLines: 3,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Tıklanınca seçim açan, metin alanı görünümlü kutu.
class PickerBox extends StatelessWidget {
  const PickerBox({super.key, required this.text, required this.onTap, this.icon, this.placeholder = false});

  final String text;
  final VoidCallback onTap;
  final IconData? icon;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerColor)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    color: placeholder ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.expand_more, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarih seçim kutusu.
class DateBox extends StatelessWidget {
  const DateBox({super.key, required this.value, required this.onChanged, required this.label, this.allowPast = false});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;
  final bool allowPast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        PickerBox(
          text: '${formatDate(value)} · ${friendlyDay(value)}',
          icon: Icons.calendar_today_outlined,
          onTap: () async {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final first = allowPast ? today.subtract(const Duration(days: 365)) : today;
            final picked = await showDatePicker(
              context: context,
              initialDate: value.isBefore(first) ? first : value,
              firstDate: first,
              lastDate: today.add(const Duration(days: 365)),
            );
            if (picked != null) onChanged(picked);
          },
        ),
      ],
    );
  }
}

/// Yatay kaydırılabilir seçim çipleri.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.allLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T?> onSelected;

  /// Verilirse başa "Tümü" gibi bir seçenek eklenir (null değer).
  final String? allLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (allLabel != null)
        ChoiceChip(label: Text(allLabel!), selected: selected == null, onSelected: (_) => onSelected(null)),
      for (final v in values)
        ChoiceChip(label: Text(labelOf(v)), selected: selected == v, onSelected: (_) => onSelected(v)),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Center(child: chips[i]),
      ),
    );
  }
}

/// Birden fazla çip seçimi (sektör vb.).
class MultiChoiceWrap<T> extends StatelessWidget {
  const MultiChoiceWrap({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          FilterChip(
            label: Text(labelOf(v)),
            selected: selected.contains(v),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(v);
              } else {
                next.remove(v);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Sarmalı seçim çipleri (formlar için).
class ChoiceWrap<T> extends StatelessWidget {
  const ChoiceWrap({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(label: Text(labelOf(v)), selected: selected == v, onSelected: (_) => onSelected(v)),
      ],
    );
  }
}

/// Temizleme düğmeli arama kutusu.
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.initial = '', this.autofocus = false});

  final String hint;
  final ValueChanged<String> onChanged;
  final String initial;
  final bool autofocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Temizle',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: (v) {
        setState(() {});
        widget.onChanged(v);
      },
    );
  }
}

/// Uygulamayla gelen örnek kayıtları gerçeklerinden ayırmak için etiket.
class DemoTag extends StatelessWidget {
  const DemoTag({super.key});

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'Uygulamayla gelen örnek kayıt; gerçek bir firma değildir. Profil → "Örnek ilanlar" ile gizleyebilirsiniz.',
      child: Pill('Örnek', color: AppColors.grey, icon: Icons.science_outlined),
    );
  }
}

class BoostTag extends StatelessWidget {
  const BoostTag({super.key});

  @override
  Widget build(BuildContext context) => const Pill('Öne çıkan', color: AppColors.brand, icon: Icons.bolt_rounded);
}

/// Çevrimdışıyken yapılan ve henüz sunucuya gönderilmemiş kayıt.
class SyncPendingTag extends StatelessWidget {
  const SyncPendingTag({super.key});

  @override
  Widget build(BuildContext context) => const Tooltip(
        message: 'Bu değişiklik cihazınıza kaydedildi; internet bağlantısı gelince otomatik gönderilecek.',
        child: Pill('Gönderilmeyi bekliyor', color: AppColors.amber, icon: Icons.cloud_upload_outlined),
      );
}

/// Kullanıcının baş harfleriyle yuvarlak avatar.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.radius = 20, this.color = AppColors.brand});

  final String name;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.13),
      child: Text(
        initials(name),
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: radius * 0.72),
      ),
    );
  }
}

/// Güven rozetleri: telefon doğrulandı, onaylı firma, Premium.
class TrustBadges extends StatelessWidget {
  const TrustBadges(this.profile, {super.key, this.compact = false});

  final PublicProfile profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (profile.companyVerified) const Pill('Onaylı firma', color: AppColors.green, icon: Icons.verified_rounded),
        if (profile.phoneVerified)
          const Pill('Telefon doğrulandı', color: AppColors.blue, icon: Icons.phone_iphone_rounded)
        else if (!compact)
          const Pill('Telefon doğrulanmadı', color: AppColors.grey, icon: Icons.phone_disabled_outlined),
        if (profile.isPremium) const Pill('Premium', color: AppColors.amber, icon: Icons.workspace_premium_rounded),
        if (!compact && profile.dealsCompleted > 0) Pill('${profile.dealsCompleted} tamamlanan iş', color: AppColors.teal),
      ],
    );
  }
}

/// İlan sahibinin kısa özeti: avatar, ad, puan, rozetler.
class OwnerLine extends StatelessWidget {
  const OwnerLine(this.profile, {super.key, this.onTap, this.trailing});

  final PublicProfile profile;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final since = profile.memberMonths;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Avatar(profile.displayName, radius: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (profile.companyVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 16, color: AppColors.green),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      RatingStars(profile.ratingAvg, count: profile.ratingCount, size: 13),
                      if (since > 0) ...[
                        Text('  ·  ', style: TextStyle(color: muted, fontSize: 12)),
                        Flexible(
                          child: Text(
                            since >= 12 ? '${since ~/ 12} yıldır üye' : '$since aydır üye',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            ?trailing,
            if (trailing == null && onTap != null) Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    );
  }
}

/// Renkli bilgi kutusu.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color = AppColors.blue,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? title;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                ],
                Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                if (actionLabel != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: color,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Basılınca işlem bitene kadar kendini kilitleyen düğme (çift dokunuşla
/// mükerrer kayıt oluşmasını engeller).
///
/// İşlem içinde yakalanmamış bir hata olursa düğme kilitli kalmaz ve hata
/// kullanıcıya anlaşılır bir mesajla gösterilir (bağlantı hatasında
/// "Tekrar dene" düğmesiyle).
class AsyncButton extends StatefulWidget {
  const AsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.color,
    this.expand = true,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool outlined;
  final Color? color;
  final bool expand;

  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) {
        showError(context, e, onRetry: _run);
      } else {
        AppFeedback.error(e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !_busy;
    final Widget child = _busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: widget.outlined ? null : Theme.of(context).colorScheme.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final Widget button = widget.outlined
        ? OutlinedButton(
            style: widget.color == null
                ? null
                : OutlinedButton.styleFrom(foregroundColor: widget.color, side: BorderSide(color: widget.color!)),
            onPressed: enabled ? _run : null,
            child: child,
          )
        : FilledButton(
            style: widget.color == null ? null : FilledButton.styleFrom(backgroundColor: widget.color),
            onPressed: enabled ? _run : null,
            child: child,
          );
    return widget.expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Kullanım koşulları · Gizlilik · KVKK bağlantıları.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 36),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton(
          style: style,
          onPressed: () => openExternal(context, AppConfig.termsUrl),
          child: const Text('Kullanım Koşulları'),
        ),
        TextButton(
          style: style,
          onPressed: () => openExternal(context, AppConfig.privacyUrl),
          child: const Text('Gizlilik Politikası'),
        ),
        TextButton(
          style: style,
          onPressed: () => openExternal(context, AppConfig.kvkkUrl),
          child: const Text('KVKK'),
        ),
      ],
    );
  }
}

/// Uygulamanın taraf olmadığını belirten kısa not.
class ResponsibilityNote extends StatelessWidget {
  const ResponsibilityNote({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.handshake_outlined, size: 16, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text ??
                '${AppConfig.appName} bir ilan ve buluşma platformudur. İş, ödeme ve teslimat sorumluluğu '
                    'taraflar arasındadır; ödemeler doğrudan taraflar arasında yapılır.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}
