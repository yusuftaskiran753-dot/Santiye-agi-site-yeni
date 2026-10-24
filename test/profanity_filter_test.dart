import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/utils/profanity_filter.dart';

void main() {
  group('Sözlük', () {
    test('en az 100 benzersiz küfür / argo girdisi var', () {
      expect(ProfanityFilter.wordCount, greaterThanOrEqualTo(100));
    });
  });

  group('Küfür yakalama', () {
    const bad = [
      'amk',
      'AMK',
      'a.m.k',
      'a m k',
      'a-m-k',
      'a_m_k',
      'sen bir s.k',
      's k',
      'S.İ.K.T.İ.R',
      'siktir git',
      'siiiiktir',
      'ammmk',
      'orospu çocuğu',
      'o r o s p u',
      '0r0spu',
      's1kt1r',
      '@mk',
      's*ktir',
      'or*spu',
      'a*k',
      'ya**ak',
      'hassiktir',
      'göt',
      'götveren',
      'göt veren',
      'piç',
      'yarrak',
      'yaaarrak',
      'aptal herif',
      'gerizekalı',
      'geri zekalı',
      'amına koyayım',
      'amına koyim',
      'ananı sikeyim',
      'dalyarak',
      'pezevenk',
      'serefsiz',
      'şerefsiz',
      'kahpe',
      'ibne',
      'fuck you',
      'f.u.c.k',
      'bitch',
      'Bu iş yapılmaz, sen salak mısın?',
      'a.m.k.',
      'A M K',
      'a  m  k',
      's.k.',
      'S.K',
      'amkkkk',
      'a-m-k',
      'a_m_k',
      'o ç',
      's i k t i r',
      'p.i.ç',
      'g.ö.t',
    ];
    for (final t in bad) {
      test('engellenir: $t', () => expect(ProfanityFilter.isOffensive(t), isTrue));
    }
  });

  group('Masum cümleler geçer', () {
    const good = [
      '',
      '   ',
      'Merhaba, ekskavatör hâlâ boş mu?',
      'sık sık çalışırız',
      'Sıkıntı yok, sıkı çalışıyoruz',
      'sıkıştırma silindiri lazım',
      'Mal sahibi ile görüşün',
      'Mal teslimi yarın',
      'alçak gerilim panosu',
      'götür yarın getir',
      'Saat 15:30 da şantiyede olun, 25 ton hafriyat',
      'Kirli temel kazısı 3.500 TL, 2 kamyon',
      'Ali Kerim ile görüştüm',
      'Bu hafta 5 gün 8 saat çalışıldı',
      'Saksofon kursu gibi saksı değil',
      'Şantiye pislik temizliği yapılacak',
      'A.Ş. firması ile sözleşme imzalandı',
      'M.K. Mühendislik ile çalıştık',
      'Amcamın oğlu operatör, güvenilir',
      'Fiyat 12.500 TL + KDV, saat 08.00',
    ];
    for (final t in good) {
      test('geçer: "$t"', () => expect(ProfanityFilter.isOffensive(t), isFalse));
    }
  });

  test('validate Türkçe hata mesajı döner', () {
    expect(ProfanityFilter.validate('s.k'), contains('küfür'));
    expect(ProfanityFilter.validate('Merhaba'), isNull);
    expect(ProfanityFilter.validate(null), isNull);
  });
}
