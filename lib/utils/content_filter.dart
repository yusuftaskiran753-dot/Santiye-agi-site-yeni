/// İlan ve not metinlerinde uygunsuz içerik denetimi.
///
/// Apple (Kural 1.2) ve Google, kullanıcı içeriği barındıran uygulamalarda
/// uygunsuz içeriğin süzülmesini ister. Bu basit süzgeç yaygın küfür ve
/// hakaretleri kelime bazında yakalar; ayrıca şikâyet + otomatik gizleme
/// sunucuda çalışır.
class ContentFilter {
  const ContentFilter._();

  /// Bu köklerle başlayan kelimeler reddedilir (küçük harf, ş/ğ/ü/ö/ç sadeleştirilmiş, ı korunur).
  static const List<String> _prefixes = [
    'orospu', 'orosbu', 'sikerim', 'siktir', 'yarrak', 'amcık', 'amcik', 'pezevenk', 'serefsiz',
    'gotveren', 'avradını', 'avradini', 'dalyarak', 'yavsak', 'kaltak', 'kahpe', 'gavat', 'ibne',
    'fuck', 'bitch',
  ];

  /// Yalnızca tam kelime olarak eşleşenler.
  static const Set<String> _words = {'amk', 'aq', 'pic', 'got', 'sikik', 'sikim', 'yarak', 'shit'};

  static String _normalize(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'ı')
      .toLowerCase()
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  /// Metin uygunsuz bir ifade içeriyorsa true.
  static bool isOffensive(String text) {
    if (text.trim().isEmpty) return false;
    final words = _normalize(text).split(RegExp(r'[^a-z0-9ı]+')).where((w) => w.isNotEmpty);
    for (final w in words) {
      if (_words.contains(w)) return true;
      for (final p in _prefixes) {
        if (w.startsWith(p)) return true;
      }
    }
    return false;
  }

  /// Form doğrulayıcısı: uygunsuzsa hata mesajı döner.
  static String? validate(String? text) =>
      isOffensive(text ?? '') ? 'Lütfen uygunsuz ifadeleri kaldırın' : null;
}
