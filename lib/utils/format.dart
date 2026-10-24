import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 12500.5 -> "12.500,5"
String formatNumber(num value, {int decimals = 0}) {
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  var out = buf.toString();
  if (parts.length > 1) {
    final dec = parts[1].replaceAll(RegExp(r'0+$'), '');
    if (dec.isNotEmpty) out += ',$dec';
  }
  return value < 0 && out != '0' ? '-$out' : out;
}

/// 12500 -> "₺12.500"
String formatTL(num value, {int decimals = 0}) {
  final n = formatNumber(value.abs(), decimals: decimals);
  return '${value < 0 && n != '0' ? '-' : ''}₺$n';
}

String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
  'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

String formatDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

String formatDateTime(DateTime d) => '${formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

String formatShortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String friendlyDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Bugün';
  if (diff == 1) return 'Yarın';
  if (diff == -1) return 'Dün';
  return formatShortDate(d);
}

String timeAgo(DateTime d) {
  final minutes = DateTime.now().difference(d).inMinutes;
  if (minutes < 1) return 'Az önce';
  if (minutes < 60) return '$minutes dk önce';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours sa önce';
  final days = hours ~/ 24;
  if (days < 30) return '$days gün önce';
  return formatDate(d);
}

/// Türkçe sayı girişlerini çözer: "12.500" -> 12500, "2,5" -> 2.5, "2.5" -> 2.5.
/// Geçersiz girişte 0 döner; doğrulama için [tryParseNumber] kullanın.
double parseNumber(String input) => tryParseNumber(input) ?? 0;

final RegExp _numberChars = RegExp(r'^[0-9.,]+$');
final RegExp _ignoredInNumber = RegExp(r'[\s  ₺]|tl$', caseSensitive: false);

/// Sayı girişini katı biçimde çözer; anlaşılamayan girişte null döner.
///
/// * "12.500" → 12500 (binlik nokta) · "2,5" / "2.5" → 2.5 · "0.500" → 0.5
/// * "1.250,75" → 1250.75 · "12,500.50" → 12500.5 (son ayraç ondalıktır)
/// * "₺ 3.000", "3.000 TL" → 3000 · "-5" → -5
/// * "12a", "1.2.3,4,5", "1.25.000" → null
double? tryParseNumber(String input) {
  var t = input.trim().replaceAll(_ignoredInNumber, '');
  if (t.isEmpty) return null;
  var negative = false;
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  }
  if (t.isEmpty || !_numberChars.hasMatch(t)) return null;

  bool grouped(String intPart, String sep) =>
      RegExp('^\\d{1,3}(${RegExp.escape(sep)}\\d{3})+\$').hasMatch(intPart);

  String normalized;
  final lastComma = t.lastIndexOf(',');
  final lastDot = t.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // İki ayraç da var: sonda olan ondalık, diğeri binlik ayracıdır.
    final decimalSep = lastComma > lastDot ? ',' : '.';
    final groupSep = decimalSep == ',' ? '.' : ',';
    final cut = t.lastIndexOf(decimalSep);
    final intPart = t.substring(0, cut);
    final fraction = t.substring(cut + 1);
    if (fraction.isEmpty || fraction.contains(groupSep) || !grouped(intPart, groupSep)) return null;
    normalized = '${intPart.replaceAll(groupSep, '')}.$fraction';
  } else if (lastComma >= 0 || lastDot >= 0) {
    final sep = lastComma >= 0 ? ',' : '.';
    final count = sep.allMatches(t).length;
    if (count > 1) {
      // "1.250.000" gibi yalnızca binlik ayraçlı giriş.
      if (!grouped(t, sep)) return null;
      normalized = t.replaceAll(sep, '');
    } else {
      final cut = t.indexOf(sep);
      final intPart = t.substring(0, cut);
      final fraction = t.substring(cut + 1);
      if (fraction.isEmpty && intPart.isEmpty) return null;
      // Türkçede "12.500" binliktir; "0.500" ve "2.5" ise ondalık.
      final isGrouping = sep == '.' && fraction.length == 3 && intPart.isNotEmpty && intPart != '0' && intPart.length <= 3;
      normalized = isGrouping ? '$intPart$fraction' : '${intPart.isEmpty ? '0' : intPart}.${fraction.isEmpty ? '0' : fraction}';
    }
  } else {
    normalized = t;
  }
  final v = double.tryParse(normalized);
  if (v == null || !v.isFinite) return null;
  return negative ? -v : v;
}

// ───────────── Telefon ─────────────

/// Türkiye numarasını +90XXXXXXXXXX biçimine çevirir; geçersizse boş döner.
/// "0555 123 45 67" / "+90 555 123 45 67" / "5551234567" → "+905551234567"
String normalizePhoneTr(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0090')) digits = digits.substring(2);
  if (digits.length == 12 && digits.startsWith('90')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length != 10) return '';
  // Mobil (5xx) veya sabit hat (2xx-4xx) numaraları.
  if (!RegExp(r'^[2-5]\d{9}$').hasMatch(digits)) return '';
  return '+90$digits';
}

bool isValidTrPhone(String input) => normalizePhoneTr(input).isNotEmpty;

/// "+905551234567" → "0555 123 45 67"
String formatPhoneDisplay(String phone) {
  final e164 = normalizePhoneTr(phone);
  if (e164.isEmpty) return phone.trim();
  final d = e164.substring(3);
  return '0${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6, 8)} ${d.substring(8)}';
}

/// WhatsApp (wa.me) için yalnızca rakam: "905551234567".
String phoneToInternational(String phone) {
  final e164 = normalizePhoneTr(phone);
  if (e164.isNotEmpty) return e164.substring(1);
  return phone.replaceAll(RegExp(r'\D'), '');
}

// ───────────── Mesafe ─────────────

double haversineKm(LatLng a, LatLng b) {
  const r = 6371.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// Kuş uçuşu mesafeyi yaklaşık karayolu mesafesine çevirir.
const double kRoadFactor = 1.25;
double roadKm(LatLng a, LatLng b) => haversineKm(a, b) * kRoadFactor;

String formatKm(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${formatNumber(km, decimals: km < 10 ? 1 : 0)} km';
}

// ───────────── Metin ─────────────

/// Türkçe büyük harf: "i" → "İ" (Dart'ın toUpperCase'i "I" yapar).
String trUpper(String s) => s.replaceAll('i', 'İ').toUpperCase();

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String first(String p) => p.substring(0, 1);
  if (parts.length == 1) return trUpper(first(parts.first));
  return trUpper(first(parts.first) + first(parts.last));
}

/// Günaydın / İyi günler / İyi akşamlar
String greeting([DateTime? at]) {
  final h = (at ?? DateTime.now()).hour;
  if (h >= 5 && h < 12) return 'Günaydın';
  if (h >= 12 && h < 18) return 'İyi günler';
  return 'İyi akşamlar';
}
