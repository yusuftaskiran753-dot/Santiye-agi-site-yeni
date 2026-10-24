import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/data/cities.dart';
import 'package:santiye_agi/logic/deal_rules.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/utils/format.dart';
import 'package:santiye_agi/utils/validators.dart';

/// Form doğrulamaları, sayı çözümleme, hata eşleme ve anlaşma kuralları.

void main() {
  group('Katı sayı çözümleme (tryParseNumber)', () {
    test('Türkçe ve İngilizce biçimler', () {
      expect(tryParseNumber('12.500'), 12500);
      expect(tryParseNumber('2,5'), 2.5);
      expect(tryParseNumber('2.5'), 2.5);
      expect(tryParseNumber('0.500'), 0.5, reason: '"0." ile başlayan binlik olamaz');
      expect(tryParseNumber('1.250,75'), 1250.75);
      expect(tryParseNumber('12,500.50'), 12500.5);
      expect(tryParseNumber('1.250.000'), 1250000);
      expect(tryParseNumber('1,234,567'), 1234567);
      expect(tryParseNumber('₺ 3.000'), 3000);
      expect(tryParseNumber('3.000 TL'), 3000);
      expect(tryParseNumber(' 7 '), 7);
      expect(tryParseNumber(',5'), 0.5);
      expect(tryParseNumber('-5'), -5);
    });

    test('Anlaşılamayan girişler null', () {
      for (final bad in ['', '   ', 'abc', '12a', '1.2.3,4,5', '1.25.000', '1e5', '--5', '-', ',', '.', '1,2,3,4.5,6']) {
        expect(tryParseNumber(bad), isNull, reason: '"$bad"');
      }
    });

    test('parseNumber eski davranışı korur (geçersizde 0)', () {
      expect(parseNumber('abc'), 0);
      expect(parseNumber(''), 0);
      expect(parseNumber('12.500'), 12500);
    });

    test('Ekranda gösterilen sayı yeniden okununca aynı değer çıkar', () {
      for (final v in [0.5, 2.5, 12.5, 1000.0, 12500.5, 1234567.25, 18.0, 999.999]) {
        expect(tryParseNumber(formatNumber(v, decimals: 3)), closeTo(v, 1e-9), reason: formatNumber(v, decimals: 3));
      }
    });
  });

  group('Metin doğrulama', () {
    final cargo = Validators.text(label: 'Yük cinsi', min: 2, max: 120, needsLetter: true);

    test('Zorunluluk, uzunluk ve harf', () {
      expect(cargo(null), 'Yük cinsi zorunlu');
      expect(cargo('   '), 'Yük cinsi zorunlu');
      expect(cargo('a'), contains('en az 2'));
      expect(cargo('x' * 121), contains('en fazla 120'));
      expect(cargo('12345'), contains('harf içermeli'));
      expect(cargo('Paletli seramik'), isNull);
    });

    test('Uygunsuz ifade reddedilir', () {
      expect(cargo('siktir git'), isNotNull);
    });

    test('İsteğe bağlı alan boş geçilebilir', () {
      final note = Validators.text(label: 'Not', isRequired: false, max: 10, multiline: true);
      expect(note(''), isNull);
      expect(note(null), isNull);
      expect(note('a\nb'), isNull);
      expect(note('çok uzun bir not'), contains('en fazla 10'));
    });

    test('Görünmez karakterler ve fazla boşluk uzunluğa sayılmaz', () {
      final short = Validators.text(label: 'Ad', min: 3, max: 5);
      expect(short('  a​b  '), contains('en az 3'), reason: 'Sıfır genişlikli boşluk sayılmaz');
      expect(short('ab   c'), isNull, reason: 'Çoklu boşluk tek boşluk olur: "ab c"');
    });

    test('Ad soyad', () {
      expect(Validators.personName('Ahmet Yılmaz'), isNull);
      expect(Validators.personName("Şerafettin O'Neil-Çağlayan"), isNull);
      expect(Validators.personName('José Álvarez'), isNull);
      expect(Validators.personName('Al'), isNotNull);
      expect(Validators.personName('Ahmet 123'), isNotNull);
      expect(Validators.personName('...'), isNotNull);
    });
  });

  group('Sayı doğrulama', () {
    final tons = Validators.number(label: 'Ağırlık', positive: true, max: 1000, unit: 'ton');

    test('Zorunlu, pozitif ve üst sınır', () {
      expect(tons(''), 'Ağırlık zorunlu');
      expect(tons('abc'), contains('Geçerli bir sayı'));
      expect(tons('0'), contains('sıfırdan büyük'));
      expect(tons('-3'), contains('sıfırdan büyük'));
      expect(tons('1.001'), contains('en fazla'), reason: '"1.001" = 1001 ton');
      expect(tons('22,5'), isNull);
    });

    test('Tam sayı ve alt sınır', () {
      final years = Validators.number(label: 'Deneyim', min: 0, max: 60, integer: true);
      expect(years('5'), isNull);
      expect(years('5,5'), contains('tam sayı'));
      expect(years('61'), contains('en fazla'));
      final optional = Validators.number(label: 'Ücret', isRequired: false, min: 0);
      expect(optional(''), isNull);
      expect(optional('-1'), contains('en az'));
    });

    test('Çapraz doğrulama: alanlardan en az biri', () {
      var daily = '';
      var hourly = '';
      final check = Validators.anyPositive([() => daily, () => hourly], 'Saatlik veya günlük ücret yazın');
      expect(check(null), isNotNull);
      hourly = '750';
      expect(check(null), isNull);
      hourly = '0';
      daily = 'abc';
      expect(check(null), isNotNull);
    });

    test('Birleştirme ilk hatayı döner', () {
      final v = Validators.all([Validators.required, Validators.number(label: 'Miktar', max: 10)]);
      expect(v(''), 'Zorunlu alan');
      expect(v('11'), contains('en fazla'));
      expect(v('3'), isNull);
    });
  });

  group('Diğer alanlar', () {
    test('Telefon, il ve anlaşma kodu', () {
      expect(Validators.phone('0555 123 45 67'), isNull);
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.city('İstanbul'), isNull);
      expect(Validators.city(' istanbul '), isNull);
      expect(Validators.city('Gotham'), isNotNull);
      expect(Validators.dealCode('abcd2345'), isNull);
      expect(Validators.dealCode('ABCD-2345'), isNull);
      expect(Validators.dealCode('ABC2345'), contains('8 haneli'));
      expect(Validators.dealCode('ABCD0345'), contains('0, O, 1 ve I'));
      expect(Validators.dealCode('ABCD#345'), contains('geçersiz'));
    });

    test('Virgüllü liste: tekrar ve boşlar atılır, sınırlar uygulanır', () {
      expect(Sanitize.commaList('MYK belgesi,  G sınıfı ehliyet , myk belgesi,, '), ['MYK belgesi', 'G sınıfı ehliyet']);
      final v = Validators.commaList(label: 'Belgeler', maxItems: 2, maxItemLength: 10);
      expect(v('a, b'), isNull);
      expect(v('a, b, c'), contains('en fazla 2'));
      expect(v('çok uzun madde adı'), contains('10 karakter'));
    });

    test('Temizleme: tek satır ve çok satır', () {
      expect(Sanitize.line('  Ankara \n  İstanbul\t '), 'Ankara İstanbul');
      expect(Sanitize.block('satır 1  \r\n\r\n\r\n\r\n  satır 2'), 'satır 1\n\nsatır 2');
      expect(Sanitize.line('a\u0000b​c'), 'abc');
    });

    test('İl adı toleranslı bulunur', () {
      expect(findCity('istanbul'), 'İstanbul');
      expect(findCity('  IZMIR '), 'İzmir');
      expect(findCity('Kırıkkale'), 'Kırıkkale');
      expect(findCity(''), isNull);
      expect(findCity('Narnia'), isNull);
      expect(cityLatLngOrNull('Narnia'), isNull);
      expect(cityLatLng('Narnia'), cityLatLng('İstanbul'), reason: 'Eski davranış: harita için varsayılan');
    });
  });

  group('Sunucu hatalarının eşlenmesi', () {
    test('Sunucu fonksiyonunun fırlattığı kod mesajdan okunur', () {
      expect(BackendException.fromServer('P0001', 'LISTING_LIMIT').code, 'LISTING_LIMIT');
      expect(BackendException.fromServer('P0001', 'RATE_LIMIT').code, 'RATE_LIMIT');
    });

    test('PostgreSQL / PostgREST durum kodları', () {
      expect(BackendException.fromServer('23505', 'duplicate key value').code, 'DUPLICATE');
      expect(BackendException.fromServer('23514', 'violates check constraint').code, 'BAD_INPUT');
      expect(BackendException.fromServer('22P02', 'invalid input syntax for type uuid').code, 'BAD_INPUT');
      expect(BackendException.fromServer('42501', 'new row violates row-level security policy').code, 'FORBIDDEN');
      expect(BackendException.fromServer('PGRST301', 'JWT expired').code, 'AUTH_REQUIRED');
      expect(BackendException.fromServer('PGRST116', 'no rows').code, 'NOT_FOUND');
      expect(BackendException.fromServer('57014', 'statement timeout').code, 'SERVER');
      expect(BackendException.fromServer('503', 'Service Unavailable').code, 'SERVER');
      expect(BackendException.fromServer('XX999', 'tuhaf').code, 'UNKNOWN');
    });

    test('Bağlantı hataları ve geçicilik', () {
      expect(BackendException.from(Exception('SocketException: Failed host lookup')).code, 'NETWORK');
      expect(BackendException.from(Exception('Connection reset by peer')).code, 'NETWORK');
      expect(BackendException.from(StateError('x')).code, 'UNKNOWN');
      expect(const BackendException('NETWORK').isTransient, isTrue);
      expect(const BackendException('SERVER').isTransient, isTrue);
      expect(const BackendException('BAD_STATE').isTransient, isFalse);
    });

    test('Bilinmeyen hatanın teknik ayrıntısı kullanıcıya gösterilmez', () {
      final e = BackendException.fromServer('XX999', 'relation "secret_table" does not exist');
      expect(e.message, isNot(contains('secret_table')));
      expect(const BackendException('BAD_INPUT', 'Kod hatalı').message, 'Kod hatalı');
    });
  });

  group('Anlaşma kuralları (DealRules)', () {
    final now = DateTime.utc(2026, 10, 10, 9);
    Map<String, dynamic> row({String? customer = 'a', String? provider = 'b', String createdBy = 'a', String status = 'active'}) =>
        Deal(
          id: 'd1',
          code: 'ABCD2345',
          kind: DealKind.diger,
          title: 'İş',
          customerId: customer,
          providerId: provider,
          createdBy: createdBy,
          status: enumByName(DealStatus.values, status, DealStatus.active),
          milestones: const [DealMilestone(title: 'Avans', amount: 1000)],
        ).toJson();

    Map<String, dynamic> apply(Map<String, dynamic> r, String actor, DealAction action, {int? index, String? note}) =>
        DealRules.apply(r, actor: actor, actorName: actor, action: action, now: now, index: index, note: note);

    void expectCode(void Function() body, String code) {
      try {
        body();
        fail('$code bekleniyordu');
      } on BackendException catch (e) {
        expect(e.code, code);
      }
    }

    test('Taraf olmayan işlem yapamaz', () {
      expectCode(() => apply(row(), 'yabanci', DealAction.note, note: 'x'), 'FORBIDDEN');
    });

    test('Teslimi hizmet veren, tamamlamayı işi veren yapar', () {
      expectCode(() => apply(row(), 'a', DealAction.deliver), 'BAD_STATE');
      final delivered = apply(row(), 'b', DealAction.deliver);
      expect(delivered['status'], 'delivered');
      expectCode(() => apply(delivered, 'b', DealAction.complete), 'BAD_STATE');
      expect(apply(delivered, 'a', DealAction.complete)['status'], 'completed');
    });

    test('Onay: oluşturan karşı tarafı beklerken onaylayamaz; tek kişilik kayıtta onaylar', () {
      expectCode(() => apply(row(status: 'pending'), 'a', DealAction.confirm), 'WAITING_OTHER');
      expect(apply(row(status: 'pending'), 'b', DealAction.confirm)['status'], 'active');
      expect(apply(row(provider: null, status: 'pending'), 'a', DealAction.confirm)['status'], 'active');
    });

    test('Ödeme satırı sınırları ve zaman damgası', () {
      expectCode(() => apply(row(), 'a', DealAction.markPaid, index: 5), 'BAD_INPUT');
      expectCode(() => apply(row(), 'a', DealAction.markPaid), 'BAD_INPUT');
      expectCode(() => apply(row(), 'b', DealAction.markPaid, index: 0), 'BAD_INPUT');
      final paid = apply(row(), 'a', DealAction.markPaid, index: 0);
      final m = asMapList(paid['milestones']).single;
      expect(m['paid_at'], now.toIso8601String());
      final received = apply(paid, 'b', DealAction.markReceived, index: 0);
      expect(asMapList(received['milestones']).single['received_at'], now.toIso8601String());
    });

    test('Sorun bildirimi önceki duruma döner', () {
      final disputed = apply(row(status: 'delivered'), 'a', DealAction.dispute, note: 'Eksik');
      expect(disputed['status'], 'disputed');
      expect(apply(disputed, 'b', DealAction.resolve)['status'], 'delivered');
    });

    test('Boş not reddedilir, uzun not 300 karakterde kesilir', () {
      expectCode(() => apply(row(), 'a', DealAction.note, note: '   '), 'BAD_INPUT');
      final long = apply(row(), 'a', DealAction.note, note: 'x' * 400);
      final last = asMapList(long['log']).last;
      expect((last['text'] as String).length, 'Not: '.length + 300);
    });

    test('İptal yalnızca açık anlaşmada', () {
      expect(apply(row(status: 'pending'), 'a', DealAction.cancel)['status'], 'cancelled');
      expectCode(() => apply(row(status: 'completed'), 'a', DealAction.cancel), 'BAD_STATE');
    });

    test('Sayı biçimi', () {
      expect(DealRules.trimNumber(28000), '28000');
      expect(DealRules.trimNumber(2.5), '2,5');
    });
  });
}
