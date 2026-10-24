/// Şantiye sektörleri. Çekirdek beşli (Altyapı…Hafriyat) kayıtta zorunlu seçeneklerin
/// başında durur; gerisi aynı iş ağında karşılaşılan komşu meslek gruplarıdır.
enum WorkSector {
  altyapi('Altyapı'),
  ustyapi('Üstyapı'),
  elektrik('Elektrik'),
  mekanik('Mekanik'),
  hafriyat('Hafriyat'),
  yolAsfalt('Yol / Asfalt'),
  betonarme('Betonarme'),
  celikYapi('Çelik yapı'),
  tunel('Tünel / Metro'),
  demiryolu('Demiryolu'),
  liman('Liman / Deniz yapıları'),
  zemin('Zemin iyileştirme / Fore kazık'),
  jeoteknik('Jeoteknik'),
  izolasyon('Yalıtım / İzolasyon'),
  cephe('Cephe / Cam giydirme'),
  cati('Çatı'),
  iskeleKalip('İskele / Kalıp'),
  suTesisat('Sıhhi tesisat'),
  yangin('Yangın tesisatı'),
  iklimlendirme('İklimlendirme / HVAC'),
  asansor('Asansör'),
  zayifAkim('Zayıf akım / Otomasyon'),
  peyzaj('Peyzaj'),
  prefabrik('Prefabrik / Modüler'),
  restorasyon('Restorasyon'),
  betonSantrali('Beton santrali / Agrega'),
  nakliye('Nakliye / Lojistik'),
  isGuvenligi('İş güvenliği'),
  olcme('Harita / Ölçme'),
  kalite('Kalite kontrol / Laboratuvar');

  const WorkSector(this.label);
  final String label;

  /// Birbiriyle iş yapan komşu sektörler (akışta karşılaşırlar).
  List<WorkSector> get related => switch (this) {
    WorkSector.altyapi => const [
      WorkSector.hafriyat,
      WorkSector.yolAsfalt,
      WorkSector.elektrik,
      WorkSector.mekanik,
      WorkSector.suTesisat,
      WorkSector.zemin,
      WorkSector.tunel,
    ],
    WorkSector.ustyapi => const [
      WorkSector.betonarme,
      WorkSector.celikYapi,
      WorkSector.elektrik,
      WorkSector.mekanik,
      WorkSector.cephe,
      WorkSector.cati,
      WorkSector.iskeleKalip,
      WorkSector.asansor,
    ],
    WorkSector.elektrik => const [
      WorkSector.ustyapi,
      WorkSector.altyapi,
      WorkSector.zayifAkim,
      WorkSector.mekanik,
      WorkSector.asansor,
      WorkSector.yangin,
    ],
    WorkSector.mekanik => const [
      WorkSector.ustyapi,
      WorkSector.elektrik,
      WorkSector.iklimlendirme,
      WorkSector.yangin,
      WorkSector.suTesisat,
      WorkSector.asansor,
    ],
    WorkSector.hafriyat => const [
      WorkSector.altyapi,
      WorkSector.yolAsfalt,
      WorkSector.zemin,
      WorkSector.nakliye,
      WorkSector.tunel,
      WorkSector.betonSantrali,
    ],
    WorkSector.yolAsfalt => const [
      WorkSector.hafriyat,
      WorkSector.altyapi,
      WorkSector.betonSantrali,
      WorkSector.nakliye,
    ],
    WorkSector.betonarme => const [
      WorkSector.ustyapi,
      WorkSector.iskeleKalip,
      WorkSector.betonSantrali,
      WorkSector.celikYapi,
    ],
    WorkSector.celikYapi => const [
      WorkSector.ustyapi,
      WorkSector.betonarme,
      WorkSector.cephe,
    ],
    WorkSector.tunel => const [
      WorkSector.altyapi,
      WorkSector.hafriyat,
      WorkSector.zemin,
      WorkSector.elektrik,
    ],
    WorkSector.demiryolu => const [
      WorkSector.altyapi,
      WorkSector.hafriyat,
      WorkSector.elektrik,
    ],
    WorkSector.liman => const [
      WorkSector.altyapi,
      WorkSector.hafriyat,
      WorkSector.celikYapi,
    ],
    WorkSector.zemin => const [
      WorkSector.hafriyat,
      WorkSector.jeoteknik,
      WorkSector.altyapi,
      WorkSector.tunel,
    ],
    WorkSector.jeoteknik => const [
      WorkSector.zemin,
      WorkSector.hafriyat,
      WorkSector.olcme,
    ],
    WorkSector.izolasyon => const [
      WorkSector.ustyapi,
      WorkSector.cati,
      WorkSector.cephe,
    ],
    WorkSector.cephe => const [
      WorkSector.ustyapi,
      WorkSector.celikYapi,
      WorkSector.izolasyon,
    ],
    WorkSector.cati => const [WorkSector.ustyapi, WorkSector.izolasyon],
    WorkSector.iskeleKalip => const [
      WorkSector.betonarme,
      WorkSector.ustyapi,
      WorkSector.isGuvenligi,
    ],
    WorkSector.suTesisat => const [
      WorkSector.mekanik,
      WorkSector.altyapi,
      WorkSector.yangin,
    ],
    WorkSector.yangin => const [
      WorkSector.mekanik,
      WorkSector.elektrik,
      WorkSector.suTesisat,
    ],
    WorkSector.iklimlendirme => const [
      WorkSector.mekanik,
      WorkSector.elektrik,
      WorkSector.ustyapi,
    ],
    WorkSector.asansor => const [
      WorkSector.elektrik,
      WorkSector.mekanik,
      WorkSector.ustyapi,
    ],
    WorkSector.zayifAkim => const [WorkSector.elektrik, WorkSector.ustyapi],
    WorkSector.peyzaj => const [WorkSector.ustyapi, WorkSector.altyapi],
    WorkSector.prefabrik => const [WorkSector.ustyapi, WorkSector.celikYapi],
    WorkSector.restorasyon => const [WorkSector.ustyapi, WorkSector.izolasyon],
    WorkSector.betonSantrali => const [
      WorkSector.betonarme,
      WorkSector.yolAsfalt,
      WorkSector.hafriyat,
      WorkSector.nakliye,
    ],
    WorkSector.nakliye => const [
      WorkSector.hafriyat,
      WorkSector.betonSantrali,
      WorkSector.yolAsfalt,
    ],
    WorkSector.isGuvenligi => WorkSector.values,
    WorkSector.olcme => const [
      WorkSector.altyapi,
      WorkSector.ustyapi,
      WorkSector.jeoteknik,
    ],
    WorkSector.kalite => const [
      WorkSector.betonarme,
      WorkSector.yolAsfalt,
      WorkSector.betonSantrali,
    ],
  };
}

/// Kayıtta zorunlu meslek + şantiyede görülen diğer meslek grupları.
enum TradeProfession {
  muteahhit('Müteahhit'),
  taseron('Taşeron'),
  formen('Formen'),
  operator('Operatör'),
  muhendis('Mühendis'),
  mimar('Mimar'),
  santiyeSefi('Şantiye şefi'),
  tekniker('Tekniker'),
  usta('Usta'),
  kalfa('Kalfa'),
  isci('İşçi / Usta yardımcısı'),
  nakliyeci('Nakliyeci / Tırcı'),
  makineSahibi('Makine sahibi'),
  tedarikci('Tedarikçi'),
  yukSahibi('Yük sahibi'),
  insaatMuhendisi('İnşaat mühendisi'),
  elektrikMuhendisi('Elektrik mühendisi'),
  makineMuhendisi('Makine mühendisi'),
  haritaMuhendisi('Harita mühendisi'),
  jeolojiMuhendisi('Jeoloji mühendisi'),
  isGuvenligiUzmani('İş güvenliği uzmanı'),
  metraj('Metraj / Keşif'),
  satinAlma('Satın alma'),
  puantor('Puantör'),
  sefor('Şoför'),
  kalipci('Kalıpçı'),
  demirci('Demirci'),
  betoncu('Betoncu'),
  siva('Sıvacı'),
  boyaci('Boyacı'),
  tesisatci('Tesisatçı'),
  elektrikci('Elektrikçi'),
  kaynakci('Kaynakçı'),
  vincOperatoru('Vinç operatörü');

  const TradeProfession(this.label);
  final String label;

  /// İhaleye teklif verebilen meslekler (varsayılan).
  bool get canBidTender =>
      this == TradeProfession.taseron || this == TradeProfession.formen;

  /// İhale açabilen meslek.
  bool get canOpenTender =>
      this == TradeProfession.muteahhit || this == TradeProfession.santiyeSefi;
}

/// Kayıt formunda önce gösterilen çekirdek seçenekler.
const List<WorkSector> kCoreSectors = [
  WorkSector.altyapi,
  WorkSector.ustyapi,
  WorkSector.elektrik,
  WorkSector.mekanik,
  WorkSector.hafriyat,
];

const List<TradeProfession> kCoreProfessions = [
  TradeProfession.muteahhit,
  TradeProfession.taseron,
  TradeProfession.formen,
  TradeProfession.operator,
  TradeProfession.muhendis,
];

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class TradeCatalog {
  const TradeCatalog._();

  /// A ile B aynı veya komşu sektördeyse karşılaşırlar.
  static bool sectorsMeet(Iterable<WorkSector> a, Iterable<WorkSector> b) {
    if (a.isEmpty || b.isEmpty) return false;
    final reach = <WorkSector>{
      for (final s in a) s,
      for (final s in a) ...s.related,
    };
    return b.any(reach.contains);
  }

  static WorkSector sectorByName(
    Object? name, [
    WorkSector fallback = WorkSector.ustyapi,
  ]) => _byName(WorkSector.values, name, fallback);

  static TradeProfession professionByName(
    Object? name, [
    TradeProfession fallback = TradeProfession.muteahhit,
  ]) => _byName(TradeProfession.values, name, fallback);
}
