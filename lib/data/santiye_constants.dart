import '../models/models.dart';
import '../models/trade.dart';

/// Şantiye Ağı'nda kullanılan sektör, meslek ve makine sabitleri.
///
/// Değerlerin kendisi `WorkSector`, `TradeProfession` ve `MachineType`
/// sıralamalarında tanımlıdır (ilanlar bu adlarla kaydedilir, adlar değişmez).
/// Burası yalnızca ekranlarda gösterilecek ana listeleri ve gruplamaları verir.

/// Ana sektörler (kayıt ve akış filtresinde ilk gösterilenler).
const List<WorkSector> kSektorler = [
  WorkSector.insaat,
  WorkSector.hafriyat,
  WorkSector.altyapi,
  WorkSector.nakliye,
  WorkSector.mermer,
  WorkSector.maden,
  WorkSector.orman,
];

/// Ana sektörlerin ekranda görünen adları.
List<String> get kSektorAdlari => [for (final s in kSektorler) s.label];

/// Meslekler, gruplarına göre. Tam liste için [kMeslekler] kullanın.
const Map<String, List<TradeProfession>> kMeslekGruplari = {
  'Yönetim ve teknik kadro': [
    TradeProfession.muteahhit,
    TradeProfession.taseron,
    TradeProfession.santiyeSefi,
    TradeProfession.formen,
    TradeProfession.ustabasi,
    TradeProfession.muhendis,
    TradeProfession.insaatMuhendisi,
    TradeProfession.elektrikMuhendisi,
    TradeProfession.makineMuhendisi,
    TradeProfession.haritaMuhendisi,
    TradeProfession.jeolojiMuhendisi,
    TradeProfession.statikMuhendisi,
    TradeProfession.mimar,
    TradeProfession.tekniker,
    TradeProfession.topograf,
    TradeProfession.jeolog,
    TradeProfession.teknikRessam,
    TradeProfession.metraj,
    TradeProfession.isGuvenligiUzmani,
    TradeProfession.kaliteKontrolcu,
    TradeProfession.laboratuvarTeknisyeni,
  ],
  'İş makinesi operatörleri': [
    TradeProfession.operator,
    TradeProfession.kepceOperatoru,
    TradeProfession.loderOperatoru,
    TradeProfession.greyderOperatoru,
    TradeProfession.dozerOperatoru,
    TradeProfession.silindirOperatoru,
    TradeProfession.finiserOperatoru,
    TradeProfession.vincOperatoru,
    TradeProfession.kuleVincOperatoru,
    TradeProfession.forkliftOperatoru,
    TradeProfession.betonPompaOperatoru,
    TradeProfession.kaziciOperatoru,
    TradeProfession.sondorOperatoru,
  ],
  'Şoförler ve nakliye': [
    TradeProfession.sefor,
    TradeProfession.kamyonSoforu,
    TradeProfession.tirSoforu,
    TradeProfession.mikserSoforu,
    TradeProfession.servisSoforu,
    TradeProfession.nakliyeci,
    TradeProfession.yukSahibi,
    TradeProfession.makineSahibi,
    TradeProfession.tedarikci,
  ],
  'Usta ve işçiler': [
    TradeProfession.usta,
    TradeProfession.kalfa,
    TradeProfession.isci,
    TradeProfession.kalipci,
    TradeProfession.demirci,
    TradeProfession.betoncu,
    TradeProfession.siva,
    TradeProfession.boyaci,
    TradeProfession.fayansci,
    TradeProfession.alcipanci,
    TradeProfession.catiUstasi,
    TradeProfession.yalitimci,
    TradeProfession.asfaltci,
    TradeProfession.dogramaci,
    TradeProfession.celikMontajci,
    TradeProfession.iskeleci,
    TradeProfession.parkeci,
    TradeProfession.tesisatci,
    TradeProfession.elektrikci,
    TradeProfession.kaynakci,
    TradeProfession.tamirci,
    TradeProfession.lastikci,
  ],
  'Maden, mermer ve orman': [
    TradeProfession.patlatmaci,
    TradeProfession.ocakUstasi,
    TradeProfession.madenci,
    TradeProfession.mermerUstasi,
    TradeProfession.ormanIsci,
    TradeProfession.motorluTestereci,
    TradeProfession.peyzajci,
  ],
  'Ofis, depo ve güvenlik': [
    TradeProfession.puantor,
    TradeProfession.satinAlma,
    TradeProfession.muhasebeci,
    TradeProfession.ofisPersoneli,
    TradeProfession.depocu,
    TradeProfession.bekci,
    TradeProfession.guvenlikGorevlisi,
    TradeProfession.asci,
    TradeProfession.temizlikGorevlisi,
    TradeProfession.saglikMemuru,
  ],
};

/// Tüm meslekler (gruplar sırasıyla, tekrarsız).
List<TradeProfession> get kMeslekler => [
  for (final g in kMeslekGruplari.values) ...g,
];

/// Meslek adlarının düz listesi (ekranda gösterilen ad).
List<String> get kMeslekAdlari => [for (final p in kMeslekler) p.label];

/// Makineler, kullanım alanına göre. Tam liste için [kMakineler] kullanın.
const Map<String, List<MachineType>> kMakineGruplari = {
  'Kazı ve yükleme': [
    MachineType.ekskavator,
    MachineType.miniEkskavator,
    MachineType.lastikliEkskavator,
    MachineType.uzunKolEkskavator,
    MachineType.hidrolikKirici,
    MachineType.bekoloder,
    MachineType.loder,
    MachineType.lastikliLoder,
    MachineType.paletliLoder,
    MachineType.miniYukleyici,
    MachineType.teleskopik,
    MachineType.trencher,
  ],
  'Yol ve toprak': [
    MachineType.greyder,
    MachineType.dozer,
    MachineType.skrayper,
    MachineType.silindir,
    MachineType.tandemSilindir,
    MachineType.lastikliSilindir,
    MachineType.vibrasyonluSilindir,
    MachineType.toprakSilindiri,
    MachineType.koyunAyagiSilindir,
    MachineType.vibroPlaka,
    MachineType.finiser,
    MachineType.asfaltFreze,
    MachineType.asfaltKesici,
    MachineType.asfaltPlenti,
    MachineType.yolCizgi,
    MachineType.karKureme,
  ],
  'Nakliye': [
    MachineType.kamyon,
    MachineType.onTekerKamyon,
    MachineType.kamyonet,
    MachineType.tir,
    MachineType.cekici,
    MachineType.damperliDorse,
    MachineType.kayarTabla,
    MachineType.romork,
    MachineType.eklemliDamper,
    MachineType.rijitDamper,
    MachineType.miniDamper,
    MachineType.silobas,
    MachineType.suTankeri,
    MachineType.yakitTankeri,
    MachineType.bitumTankeri,
    MachineType.arozoz,
    MachineType.vidanjor,
    MachineType.copKamyonu,
    MachineType.tomrukTasiyici,
  ],
  'Vinç ve kaldırma': [
    MachineType.vinc,
    MachineType.paletliVinc,
    MachineType.kuleVinc,
    MachineType.gezerVinc,
    MachineType.hiyap,
    MachineType.orumcekVinc,
    MachineType.forklift,
    MachineType.platform,
    MachineType.sepetliPlatform,
    MachineType.santiyeAsansoru,
  ],
  'Beton': [
    MachineType.betonPompa,
    MachineType.betonMikser,
    MachineType.betonSantrali,
    MachineType.helikopterMala,
    MachineType.karot,
  ],
  'Sondaj, kazık ve tünel': [
    MachineType.kazik,
    MachineType.kazikCakma,
    MachineType.delici,
    MachineType.kuyuSondaj,
    MachineType.paletliDelici,
    MachineType.jumbo,
    MachineType.tbm,
  ],
  'Kırma, eleme ve maden': [
    MachineType.kirmaEleme,
    MachineType.mobilKirici,
    MachineType.elek,
    MachineType.konveyor,
    MachineType.telTestere,
    MachineType.zincirliKesici,
  ],
  'Orman': [
    MachineType.tomrukYukleyici,
    MachineType.harvester,
    MachineType.forwarder,
    MachineType.skidder,
    MachineType.cipper,
    MachineType.traktor,
  ],
  'Yardımcı ekipman': [
    MachineType.kompresor,
    MachineType.jenerator,
    MachineType.suPompasi,
    MachineType.kaynakMakinesi,
    MachineType.isikKulesi,
    MachineType.mobilKonteyner,
    MachineType.diger,
  ],
};

/// Tüm makineler (gruplar sırasıyla, tekrarsız).
List<MachineType> get kMakineler => [
  for (final g in kMakineGruplari.values) ...g,
];

/// Makine adlarının düz listesi (ekranda gösterilen ad).
List<String> get kMakineAdlari => [for (final m in kMakineler) m.label];
