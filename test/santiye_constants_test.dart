import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/data/santiye_constants.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/models/trade.dart';

void main() {
  test('ana sektörler istenen yedi sektördür', () {
    expect(kSektorAdlari, [
      'İnşaat',
      'Hafriyat',
      'Altyapı',
      'Nakliye / Lojistik',
      'Mermer',
      'Maden',
      'Orman',
    ]);
  });

  test('her sektörün komşu listesi vardır ve kendini içermez', () {
    for (final s in WorkSector.values) {
      expect(s.related, isNotEmpty, reason: s.name);
      if (s != WorkSector.isGuvenligi) {
        expect(s.related, isNot(contains(s)), reason: s.name);
      }
    }
  });

  test('meslek listesi tam ve tekrarsızdır', () {
    final all = kMeslekler;
    expect(all.toSet().length, all.length, reason: 'tekrar eden meslek var');
    expect(all.toSet(), TradeProfession.values.toSet());
    for (final ad in [
      'Operatör',
      'Şoför',
      'Ustabaşı',
      'Formen',
      'Mühendis',
      'Bekçi',
    ]) {
      expect(kMeslekAdlari, contains(ad));
    }
  });

  test('makine listesi tam ve tekrarsızdır', () {
    final all = kMakineler;
    expect(all.toSet().length, all.length, reason: 'tekrar eden makine var');
    expect(all.toSet(), MachineType.values.toSet());
    for (final ad in ['Ekskavatör', 'Loder', 'Greyder', 'Dozer', 'Kamyon / Damper']) {
      expect(kMakineAdlari, contains(ad));
    }
    expect(kMakineAdlari.any((a) => a.startsWith('Tır')), isTrue);
    expect(kMakineAdlari.any((a) => a.contains('Vinç')), isTrue);
  });

  test('mevcut makine ve meslek adları (kayıtlı ilanlar) değişmedi', () {
    const eskiMakineler = [
      'ekskavator', 'miniEkskavator', 'silindir', 'tandemSilindir',
      'lastikliSilindir', 'greyder', 'finiser', 'loder', 'paletliLoder',
      'miniYukleyici', 'teleskopik', 'bekoloder', 'dozer', 'skrayper', 'vinc',
      'kuleVinc', 'paletliVinc', 'platform', 'forklift', 'betonPompa',
      'betonMikser', 'kazik', 'delici', 'kirmaEleme', 'asfaltKesici',
      'kompresor', 'jenerator', 'suTankeri', 'silobas', 'kamyon', 'cekici',
      'diger',
    ];
    final names = MachineType.values.map((e) => e.name).toList();
    expect(names.sublist(0, eskiMakineler.length), eskiMakineler);

    const eskiRoller = [
      'ekskavatorOp', 'silindirOp', 'greyderOp', 'finiserOp', 'vincOp',
      'tirSoforu', 'ustabasi', 'isci',
    ];
    final roles = WorkerRole.values.map((e) => e.name).toList();
    expect(roles.sublist(0, eskiRoller.length), eskiRoller);
  });

  test('sunucu ilan doğrulaması uygulamadaki makine ve rol adlarını kabul eder', () {
    final src = File('backend/SantiyeAgi.Api/Domain/ListingRules.cs').readAsStringSync();
    for (final m in MachineType.values) {
      expect(src, contains('"${m.name}"'), reason: 'sunucuda makine tipi yok: ${m.name}');
    }
    for (final r in WorkerRole.values) {
      expect(src, contains('"${r.name}"'), reason: 'sunucuda rol yok: ${r.name}');
    }
  });
}
