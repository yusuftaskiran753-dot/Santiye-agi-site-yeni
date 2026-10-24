import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/ai_service.dart';

void main() {
  AiResult p(String s) => LocalUnderstanding.parse(s, myCity: 'İstanbul');

  test('güzergâh, araç ve gün', () {
    final r = p("Yarın İstanbul'dan Ankara'ya tır lazım");
    expect(r.category, ListingKind.yuk);
    expect(r.fromCity, 'İstanbul');
    expect(r.toCity, 'Ankara');
    expect(r.vehicle, VehicleType.tir);
    expect(r.dayOffset, 1);
    expect(r.intent, AiIntent.ara);
  });

  test('ilan verme niyeti, ton ve fiyat', () {
    final r = p(
      "Kocaeli'den İzmir'e 25 ton torbalı çimento taşıtacağım, 31 bin",
    );
    expect(r.intent, AiIntent.ilanVer);
    expect(r.fromCity, 'Kocaeli');
    expect(r.toCity, 'İzmir');
    expect(r.tons, 25);
    expect(r.price, 31000);
    expect(r.canDraftLoad, isTrue);
  });

  test('makine ve il', () {
    final r = p('İstanbul da günlük ekskavatör');
    expect(r.category, ListingKind.makine);
    expect(r.machine, MachineType.ekskavator);
    expect(r.city, 'İstanbul');
  });

  test('malzeme', () {
    final r = p('Kocaeli C30 beton fiyatı');
    expect(r.category, ListingKind.malzeme);
    expect(r.material, 'C30/37');
    expect(r.city, 'Kocaeli');
  });

  test('personel', () {
    final r = p('Silindir operatörü arıyorum');
    expect(r.category, ListingKind.personel);
    expect(r.workerRole, WorkerRole.silindirOp);
  });

  test('"müsait" kelimesi Muş ili sanılmaz', () {
    final r = p('müsait kamyon var mı');
    expect(r.city, isNull);
    expect(r.fromCity, isNull);
  });

  test('Gemini JSON bilinmeyen değerleri yok sayar, il adını düzeltir', () {
    final r = AiResult.fromJson({
      'intent': 'ara',
      'kategori': 'yuk',
      'nereden': 'istanbul',
      'nereye': 'Atlantis',
      'arac': 'uzay_gemisi',
      'ton': -5,
      'ozet': 'Test',
    });
    expect(r.fromCity, 'İstanbul');
    expect(r.toCity, isNull);
    expect(r.vehicle, isNull);
    expect(r.tons, isNull);
  });
}
