/// Bütün formlarda ortak, katı alan doğrulamaları.
///
/// Sınırlar sunucudaki tablo kısıtlarıyla (supabase/schema.sql) aynıdır;
/// böylece kullanıcı hatayı göndermeden, alanın hemen altında görür ve
/// sunucudan anlaşılmaz bir "bilgileri kontrol edin" hatası almaz.
///
/// Kullanım:
/// ```dart
/// validator: Validators.text(label: 'Yük cinsi', min: 2, max: FieldLimits.cargo),
/// validator: Validators.number(label: 'Ağırlık', min: 0.1, max: FieldLimits.maxTons),
/// validator: Validators.all([Validators.required, ContentFilter.validate]),
/// ```
library;

import '../data/cities.dart';
import '../config.dart';
import 'content_filter.dart';
import 'format.dart';

/// Flutter'daki `FormFieldValidator<String>` ile aynı imza.
typedef FieldValidator = String? Function(String? value);

/// Sunucudaki sütun sınırları (karakter / değer).
abstract final class FieldLimits {
  static const int personName = 80;
  static const int company = 120;
  static const int cargo = 120;
  static const int note = 500;
  static const int machineModel = 80;
  static const int machineCapacity = 80;
  static const int product = 80;
  static const int plantName = 120;
  static const int jobTitle = 120;
  static const int jobDuration = 60;
  static const int about = 500;
  static const int address = 300;
  static const int dealTitle = 160;
  static const int dealDetails = 1500;
  static const int paymentTerms = 300;
  static const int counterparty = 120;
  static const int ratingComment = 300;
  static const int reportNote = 500;
  static const int haulPointName = 80;
  static const int haulMaterial = 40;

  /// Virgülle ayrılan listeler (belgeler, aranan şartlar).
  static const int listItems = 20;
  static const int listItemLength = 60;

  static const double maxTons = 1000;
  static const double maxLoadPrice = 100000000;
  static const double maxMachinePrice = 10000000;
  static const double maxMaterialPrice = 10000000;
  static const double maxMinQty = 10000000;
  static const double maxWage = 10000000;
  static const double maxRequestAmount = 100000000;
  static const double maxQuantity = 1000000;
  static const double maxDealAmount = 1000000000;
  static const int maxYears = 60;
  static const double maxHaulVolume = 100000000;
  static const double maxHaulFee = 1000000;

  /// Anlaşma kodu alfabesi (sunucudaki new_deal_code ile aynı).
  static const String dealCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int dealCodeLength = 8;
}

/// Kayıttan önce metni temizler.
abstract final class Sanitize {
  static final RegExp _control = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏  ﻿]',
  );
  static final RegExp _spaces = RegExp(r'[ \t ]+');

  /// Tek satırlık alan: kenar boşlukları atılır, araya giren çoklu boşluk tek boşluk olur.
  static String line(String? input) => (input ?? '')
      .replaceAll(_control, '')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll(_spaces, ' ')
      .trim();

  /// Çok satırlı alan (açıklama, not): satır sonları korunur, en fazla bir boş satır bırakılır.
  static String block(String? input) {
    final text = (input ?? '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_control, '')
        .split('\n')
        .map((l) => l.replaceAll(_spaces, ' ').trim())
        .join('\n');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// "MYK belgesi, G sınıfı ehliyet" → ['MYK belgesi', 'G sınıfı ehliyet'] (tekrarlar ve boşlar atılır).
  static List<String> commaList(String? input) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in (input ?? '').split(RegExp(r'[,;\n]'))) {
      final item = line(raw);
      if (item.isEmpty || !seen.add(normalizeTr(item))) continue;
      result.add(item);
    }
    return result;
  }
}

abstract final class Validators {
  /// Verilen doğrulayıcıları sırayla çalıştırır, ilk hatayı döner.
  static FieldValidator all(List<FieldValidator> validators) => (value) {
    for (final v in validators) {
      final error = v(value);
      if (error != null) return error;
    }
    return null;
  };

  static String? required(String? value) =>
      Sanitize.line(value).isEmpty ? 'Zorunlu alan' : null;

  /// Metin alanı: zorunluluk, en az / en çok karakter, uygunsuz içerik ve
  /// görünmez karakter denetimi.
  static FieldValidator text({
    String? label,
    bool isRequired = true,
    int min = 0,
    required int max,
    bool multiline = false,
    bool filter = true,
    bool needsLetter = false,
  }) => (value) {
    final clean = multiline ? Sanitize.block(value) : Sanitize.line(value);
    final name = label ?? 'Bu alan';
    if (clean.isEmpty) return isRequired ? '$name zorunlu' : null;
    final length = clean.runes.length;
    if (min > 0 && length < min) return '$name en az $min karakter olmalı';
    if (length > max) {
      return '$name en fazla $max karakter olabilir (şu an $length)';
    }
    if (needsLetter && !_letter.hasMatch(clean)) return '$name harf içermeli';
    if (filter) return ContentFilter.validate(clean);
    return null;
  };

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _personName = RegExp(
    r"^[\p{L}\p{M} .'\-]+$",
    unicode: true,
  );

  /// Ad soyad: yalnızca harf, boşluk, nokta, kesme ve tire; en az iki harf.
  static String? personName(String? value) {
    final clean = Sanitize.line(value);
    if (clean.runes.length < 3) return 'Adınızı ve soyadınızı yazın';
    if (clean.runes.length > FieldLimits.personName) {
      return 'Ad en fazla ${FieldLimits.personName} karakter olabilir';
    }
    if (!_personName.hasMatch(clean)) return 'Adda yalnızca harf kullanın';
    if (_letter.allMatches(clean).length < 2) {
      return 'Adınızı ve soyadınızı yazın';
    }
    return ContentFilter.validate(clean);
  }

  /// Sayı alanı (Türkçe biçim: "12.500", "2,5"). Geçersiz karakterde,
  /// aralık dışında veya tam sayı beklenirken ondalık yazılırsa hata verir.
  static FieldValidator number({
    String? label,
    bool isRequired = true,
    double? min,
    double? max,
    bool integer = false,
    bool positive = false,
    String unit = '',
  }) => (value) {
    final name = label ?? 'Değer';
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return isRequired ? '$name zorunlu' : null;
    final n = tryParseNumber(raw);
    if (n == null) return 'Geçerli bir sayı yazın (ör. 12.500 veya 2,5)';
    if (integer && n != n.roundToDouble()) return '$name tam sayı olmalı';
    final suffix = unit.isEmpty ? '' : ' $unit';
    if (positive && n <= 0) return '$name sıfırdan büyük olmalı';
    if (min != null && n < min) {
      return '$name en az ${formatNumber(min, decimals: 2)}$suffix olmalı';
    }
    if (max != null && n > max) {
      return '$name en fazla ${formatNumber(max, decimals: 2)}$suffix olabilir';
    }
    return null;
  };

  static String? phone(String? value) =>
      isValidTrPhone(value ?? '') ? null : 'Geçerli bir telefon numarası yazın';

  /// Uygulamadaki il listesinde olmalı (yanlış il, eşleştirme ve haritada yanlış konum demektir).
  static String? city(String? value) =>
      findCity(value ?? '') == null ? 'Listeden bir il seçin' : null;

  /// Virgülle ayrılan liste: madde sayısı ve madde uzunluğu sınırı.
  static FieldValidator commaList({
    String label = 'Liste',
    int maxItems = FieldLimits.listItems,
    int maxItemLength = FieldLimits.listItemLength,
  }) => (value) {
    final items = Sanitize.commaList(value);
    if (items.length > maxItems) {
      return '$label en fazla $maxItems madde olabilir';
    }
    for (final item in items) {
      if (item.runes.length > maxItemLength) {
        return 'Her madde en fazla $maxItemLength karakter olabilir';
      }
    }
    return ContentFilter.validate(items.join(' '));
  };

  /// 8 haneli anlaşma kodu (karışan 0/O, 1/I harfleri kullanılmaz).
  static String? dealCode(String? value) {
    final code = (value ?? '').replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (code.length != FieldLimits.dealCodeLength &&
        !(AppConfig.usesDotNet && code.length == 10)) {
      return 'Kod ${FieldLimits.dealCodeLength} haneli olmalı';
    }
    for (final ch in code.split('')) {
      if (!FieldLimits.dealCodeChars.contains(ch)) {
        return ch == '0' || ch == 'O' || ch == '1' || ch == 'I'
            ? 'Kodda 0, O, 1 ve I kullanılmaz; harfleri kontrol edin'
            : 'Kodda geçersiz karakter var';
      }
    }
    return null;
  }

  /// Birden fazla alandan en az birinin dolu (ve sıfırdan büyük) olmasını ister.
  /// Ör. makinede saatlik VEYA günlük ücret.
  static FieldValidator anyPositive(
    List<String Function()> readers,
    String message,
  ) => (_) {
    for (final read in readers) {
      final n = tryParseNumber(read());
      if (n != null && n > 0) return null;
    }
    return message;
  };
}
