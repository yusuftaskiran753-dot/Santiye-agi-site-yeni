import 'content_filter.dart';

/// Küfür / hakaret / argo süzgeci (sosyal yorum, gönderi ve mesajlar).
///
/// Mevcut [ContentFilter] (ilan metinleri) olduğu gibi korunur; burada onun
/// üstüne geniş bir Türkçe küfür ve argo sözlüğü ile harf sansürü yakalama
/// eklenir:
///  * noktalı / tireli / boşluklu yazım: `a.m.k`, `s-i-k-t-i-r`, `o r o s p u`
///  * yıldızlı sansür: `s*ktir`, `or*spu`
///  * harf uzatma: `siiiktir`, `ammmk`
///  * rakam / simge ile yazım: `s1kt1r`, `0r0spu`, `@mk`
///  * Türkçe karakter kaçırma: `göt` ↔ `got`, `piç` ↔ `pic`
///
/// Yanlış alarmı azaltmak için "sık sık", "sıkıntı", "götür", "alçak gerilim",
/// "mal sahibi" gibi sık kullanılan masum sözcükler bilerek eşleştirilmez.
class ProfanityFilter {
  const ProfanityFilter._();

  // ───────────────────────── Sözlük ─────────────────────────
  // Tüm girdiler küçük harf, ş/ğ/ü/ö/ç/â sadeleştirilmiş (s/g/u/o/c/a) yazılır.

  /// Yalnızca kelimenin tamamı eşleşirse küfür sayılanlar (kısa / kısaltma).
  static const List<String> _exactWords = [
    'amk', 'amq', 'aq', 'oc', 'pic', 'got', 'bok', 'yarak', 'tasak', 'dassak',
    'tassak', 'pust', 'sk', 'sakso',
  ];

  /// "ı" ile "i" ayrımının önemli olduğu tam kelimeler.
  /// "sık sık", "sıkıntı", "sıkık" gibi masum sözcüklerle karışmasın diye
  /// yalnızca noktalı "i" ile yazıldığında eşleşir.
  static const List<String> _strictExact = ['sik', 'sikik', 'sikim', 'sikis'];

  /// Bu köklerle başlayan her kelime küfürdür.
  static const List<String> _prefixWords = [
    // Anne / aile / cinsel küfürler
    'orospu', 'orosbu', 'orspu', 'oruspu', 'orusbu', 'orospuc',
    'sikeyim', 'sikerim', 'sikecem', 'sikicem', 'sikiyim', 'sikiyom',
    'sikiyorum', 'sikecegim', 'siktirgit', 'siktirol',
    'amcik', 'amcuk', 'amcigi', 'amciga', 'aminakoy', 'aminakod',
    'aminiskey', 'aminoglu',
    'yarrak', 'yarak', 'yarrag', 'yarram', 'dalyarak', 'dalyarrak',
    'kodumun', 'kodugum', 'kodumunun',
    'tasak', 'dassak', 'tassak',
    'gotveren', 'gotlek', 'gotos', 'gotunu', 'gotune', 'gotoglan',
    'avradin', 'avradini', 'avradina',
    'bokluk', 'boktan', 'boklu', 'bokum', 'bokunu', 'bokyiyen', 'bokcu',
    'zikkim', 'zikkimin',
    // Kadın / erkek aşağılama, argo hakaret
    'pezevenk', 'pezo', 'gavat', 'kavat', 'kahpe', 'kaltak', 'kancik',
    'surtuk', 'fahise', 'yavsak', 'yavsac', 'ibne', 'ipne', 'ibina',
    'pust', 'lavuk', 'pickurusu', 'picler', 'piclik',
    'serefsiz', 'haysiyetsiz', 'namussuz', 'onursuz', 'karaktersiz',
    'ahlaksiz', 'pislik', 'itoglu', 'itkopek', 'kopekoglu',
    // Zeka / akıl hakareti
    'salak', 'aptal', 'gerzek', 'gerizekali', 'dangalak', 'andaval', 'ahmak',
    'budala', 'embesil', 'kretin', 'moron',
    // Yabancı kökenli yaygın küfürler
    'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'dickhead', 'cunt',
    'pussy', 'whore', 'slut', 'motherfucker', 'wanker',
  ];

  /// "ı" ayrımına duyarlı kökler ("sıktırmak" masum, "siktir" küfür).
  static const List<String> _strictPrefix = ['siktir'];

  /// Bir kelimenin herhangi bir yerinde geçse küfür sayılan uzun kökler
  /// ("hassiktir", "oruspucocugu", "motherfucker"). Yanlış alarm riski
  /// olmayacak kadar uzun / ayırt edici olanlar seçilir.
  static const List<String> _containsRoots = [
    'orospu', 'sikeyim', 'sikerim', 'yarrak', 'dalyarak', 'pezevenk',
    'gerizekali', 'aminakoy', 'aminakod', 'kodumun', 'kodugum', 'gotveren',
    'fuck', 'motherfucker',
  ];
  static const List<String> _strictContains = ['siktir'];

  /// Sözlükteki benzersiz küfür / argo girdisi sayısı.
  static int get wordCount => {
    ..._exactWords,
    ..._strictExact,
    ..._prefixWords,
    ..._strictPrefix,
    ..._containsRoots,
    ..._strictContains,
  }.length;

  // ───────────────────────── Genel API ─────────────────────────

  /// Metin küfür / hakaret / argo içeriyorsa true.
  ///
  /// Önce mevcut [ContentFilter] (eski davranış) çalışır; sonra geniş sözlük.
  static bool isOffensive(String text) =>
      ContentFilter.isOffensive(text) || firstMatch(text) != null;

  /// Form doğrulayıcısı: uygunsuzsa Türkçe hata mesajı döner.
  static String? validate(String? text) =>
      isOffensive(text ?? '') ? 'Lütfen küfür ve hakaret içeren ifadeleri kaldırın' : null;

  /// İlk eşleşen sözlük girdisini (hata ayıklama / test için) döner; yoksa null.
  static String? firstMatch(String text) {
    if (text.trim().isEmpty) return null;
    for (final c in _candidates(text)) {
      final hit = _check(c);
      if (hit != null) return hit;
    }
    return null;
  }

  // ───────────────────────── Normalleştirme ─────────────────────────

  static const Map<String, String> _foldMap = {
    'ş': 's', 'ğ': 'g', 'ü': 'u', 'ö': 'o', 'ç': 'c', 'â': 'a', 'î': 'i', 'û': 'u',
  };

  static const Map<String, String> _leetMap = {
    '@': 'a', r'$': 's', '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's',
    '7': 't', '!': 'i', '€': 'e', '£': 'e',
  };

  static String _fold(String s) {
    final lower = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    final b = StringBuffer();
    for (final r in lower.runes) {
      final ch = String.fromCharCode(r);
      b.write(_foldMap[ch] ?? ch);
    }
    return b.toString();
  }

  static final RegExp _hasLetter = RegExp('[a-zı]');
  static final RegExp _nonToken = RegExp('[^a-zı0-9*]+');
  static final RegExp _spaces = RegExp(r'\s+');

  static String _leet(String chunk) {
    if (!_hasLetter.hasMatch(chunk)) return chunk;
    final b = StringBuffer();
    for (final r in chunk.runes) {
      final ch = String.fromCharCode(r);
      b.write(_leetMap[ch] ?? ch);
    }
    return b.toString();
  }

  static String _trimMask(String t) =>
      t.replaceAll(RegExp(r'^\*+|\*+$'), '');

  static String _squash(String s) {
    final b = StringBuffer();
    String? prev;
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (ch != prev) b.write(ch);
      prev = ch;
    }
    return b.toString();
  }

  /// Metinden denetlenecek aday kelimeleri üretir.
  static List<_Candidate> _candidates(String text) {
    final out = <_Candidate>[];
    final tokens = <String>[];
    for (final chunk in _fold(text).split(_spaces)) {
      if (chunk.isEmpty) continue;
      final leet = _leet(chunk);
      // Boşluksuz bütün parça: "hassiktir", "s.i.k.t.i.r" (sözcük içi arama)
      final solid = leet.replaceAll(_nonToken, '');
      if (solid.length >= 3) out.add(_Candidate(solid, wholeChunk: true));
      for (final p in leet.split(_nonToken)) {
        final t = _trimMask(p);
        if (t.isNotEmpty) tokens.add(t);
      }
    }
    // Ardışık tek harfler birleştirilir: "a m k", "a.m.k" → "amk"
    final merged = <String>[];
    final run = StringBuffer();
    int runLen = 0;
    void flush() {
      if (runLen >= 2) merged.add(run.toString());
      run.clear();
      runLen = 0;
    }
    for (final t in tokens) {
      if (t.length == 1 && _hasLetter.hasMatch(t)) {
        run.write(t);
        runLen++;
      } else {
        flush();
      }
    }
    flush();

    for (final t in tokens) {
      out.add(_Candidate(t));
    }
    for (final m in merged) {
      out.add(_Candidate(m, wholeChunk: true));
    }
    // Bitişik iki kelime: "geri zekalı", "amına koyayım", "göt veren"
    for (var i = 0; i + 1 < tokens.length; i++) {
      out.add(_Candidate(tokens[i] + tokens[i + 1], pair: true));
    }
    return out;
  }

  // ───────────────────────── Eşleştirme ─────────────────────────

  static final _Rules _rawRules = _Rules((s) => s);
  static final _Rules _squashedRules = _Rules(_squash);

  static String? _check(_Candidate c) {
    final strict = c.text;
    if (strict.contains('*')) return _maskHit(strict);
    for (final rules in [_rawRules, _squashedRules]) {
      final s = identical(rules, _rawRules) ? strict : _squash(strict);
      final hit = rules.match(s, c);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Yıldızlı sansür ("s*ktir", "or*spu"): yıldız herhangi bir tek harf yerine geçer.
  static String? _maskHit(String token) {
    final loose = token.replaceAll('ı', 'i');
    final revealed = loose.replaceAll('*', '').length;
    if (revealed < 2) return null;
    for (final w in _maskWords) {
      if (loose.length < w.length) continue;
      // tam kelime ya da kök (önek) olarak karşılaştır
      final head = loose.substring(0, w.length);
      final exactLen = loose.length == w.length;
      if (!exactLen && !_prefixSet.contains(w)) continue;
      var ok = true;
      var shown = 0;
      for (var i = 0; i < w.length; i++) {
        if (head[i] == '*') continue;
        shown++;
        if (head[i] != w[i]) {
          ok = false;
          break;
        }
      }
      if (ok && shown >= 2) return w;
    }
    return null;
  }

  static final Set<String> _prefixSet = {..._prefixWords, ..._strictPrefix};

  static final List<String> _maskWords = {
    ..._exactWords,
    ..._strictExact,
    ..._prefixWords,
    ..._strictPrefix,
  }.where((w) => w.length >= 3).toList();
}

class _Candidate {
  const _Candidate(this.text, {this.wholeChunk = false, this.pair = false});

  final String text;

  /// Tek parça (boşluksuz) metin: "içerir" kontrolü yapılabilir.
  final bool wholeChunk;

  /// İki bitişik kelimenin birleşimi: yalnızca uzun köklerle karşılaştırılır.
  final bool pair;
}

/// Sözlüğün (isteğe bağlı olarak harf yinelemesi sadeleştirilmiş) kural kümesi.
class _Rules {
  _Rules(String Function(String) t)
    : exact = {
        for (final w in ProfanityFilter._exactWords) t(w),
      },
      exactStrict = {for (final w in ProfanityFilter._strictExact) t(w)},
      prefix = [for (final w in ProfanityFilter._prefixWords) t(w)],
      prefixStrict = [for (final w in ProfanityFilter._strictPrefix) t(w)],
      contains = [for (final w in ProfanityFilter._containsRoots) t(w)],
      containsStrict = [for (final w in ProfanityFilter._strictContains) t(w)];

  final Set<String> exact;
  final Set<String> exactStrict;
  final List<String> prefix;
  final List<String> prefixStrict;
  final List<String> contains;
  final List<String> containsStrict;

  String? match(String strict, _Candidate c) {
    final loose = strict.replaceAll('ı', 'i');
    if (!c.pair) {
      if (exact.contains(loose)) return loose;
      if (exactStrict.contains(strict)) return strict;
      for (final p in prefix) {
        if (loose.startsWith(p)) return p;
      }
      for (final p in prefixStrict) {
        if (strict.startsWith(p)) return p;
      }
    } else {
      // Bitişik kelime birleşimi: yanlış alarmı önlemek için yalnız uzun kökler.
      for (final p in prefix) {
        if (p.length >= 6 && loose.startsWith(p)) return p;
      }
      for (final p in prefixStrict) {
        if (p.length >= 6 && strict.startsWith(p)) return p;
      }
    }
    if (c.wholeChunk || c.pair) {
      for (final p in contains) {
        if (loose.contains(p)) return p;
      }
      for (final p in containsStrict) {
        if (strict.contains(p)) return p;
      }
    }
    return null;
  }
}
