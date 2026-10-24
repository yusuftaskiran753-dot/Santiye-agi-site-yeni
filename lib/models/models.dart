import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// ════════════════════════════ JSON yardımcıları ════════════════════════════
// Aynı modeller hem sunucu satırlarını (Supabase) hem de cihazda saklanan
// kayıtları okur; alan adları veritabanı sütun adlarıyla aynıdır.

int _localIdCounter = 0;

/// Cihazda (Demo modu) oluşturulan kayıtlar için benzersiz kimlik.
String newLocalId() =>
    'loc-${DateTime.now().microsecondsSinceEpoch}-${_localIdCounter++}';

final math.Random _secureRandom = math.Random.secure();

/// Rastgele UUID (v4). Canlı modda yeni kayıtların kimliği cihazda üretilir;
/// böylece bağlantı koptuğu için tekrar gönderilen kayıt sunucuda ikinci kez
/// oluşmaz (aynı kimlik = aynı kayıt).
String newUuid() {
  final b = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isUuid(String value) => _uuidPattern.hasMatch(value);

/// Bugünün 00:00 anı (yerel saat).
DateTime startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

double asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int asInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

String asString(Object? v, [String fallback = '']) =>
    v == null ? fallback : '$v';

bool asBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

DateTime? asDateOrNull(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final parsed = DateTime.tryParse(v);
  return parsed?.toLocal();
}

DateTime asDate(Object? v) => asDateOrNull(v) ?? DateTime.now();

List<String> asStringList(Object? v) =>
    v is List ? [for (final e in v) '$e'] : <String>[];

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asMapList(Object? v) =>
    v is List ? [for (final e in v) asMap(e)] : <Map<String, dynamic>>[];

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Yalnızca tarih (saat yok): 2026-10-09
String dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String? isoOrNull(DateTime? d) => d?.toUtc().toIso8601String();

// ════════════════════════════ Profil ════════════════════════════

enum UserRole {
  nakliyeci('Nakliyeci / Tırcı'),
  yukSahibi('Yük Sahibi'),
  makineSahibi('Makine Sahibi'),
  muteahhit('Müteahhit / Şantiye'),
  tedarikci('Malzeme Tedarikçisi'),
  personel('Operatör / Personel');

  const UserRole(this.label);
  final String label;
}

/// Herkese açık profil bilgisi (telefon hariç).
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.name,
    this.company = '',
    this.role = UserRole.nakliyeci,
    this.city = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.dealsCompleted = 0,
    this.phoneVerified = false,
    this.companyVerified = false,
    this.premiumUntil,
    this.createdAt,
  });

  final String id;
  final String name;
  final String company;
  final UserRole role;
  final String city;
  final double ratingAvg;
  final int ratingCount;
  final int dealsCompleted;
  final bool phoneVerified;
  final bool companyVerified;
  final DateTime? premiumUntil;
  final DateTime? createdAt;

  static const PublicProfile unknown = PublicProfile(id: '', name: 'Kullanıcı');

  /// Firma adı varsa firma, yoksa kişi adı.
  String get displayName =>
      company.trim().isNotEmpty ? company.trim() : name.trim();

  bool get isPremium =>
      premiumUntil != null && premiumUntil!.isAfter(DateTime.now());

  /// Profil kaç aydır üye (güven göstergesi).
  int get memberMonths {
    final c = createdAt;
    if (c == null) return 0;
    return DateTime.now().difference(c).inDays ~/ 30;
  }

  factory PublicProfile.fromJson(Map<String, dynamic> j) => PublicProfile(
    id: asString(j['id']),
    name: asString(j['name'], 'Kullanıcı'),
    company: asString(j['company']),
    role: enumByName(UserRole.values, j['role'], UserRole.nakliyeci),
    city: asString(j['city']),
    ratingAvg: asDouble(j['rating_avg']),
    ratingCount: asInt(j['rating_count']),
    dealsCompleted: asInt(j['deals_completed']),
    phoneVerified: asBool(j['phone_verified']),
    companyVerified: asBool(j['company_verified']),
    premiumUntil: asDateOrNull(j['premium_until']),
    createdAt: asDateOrNull(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'company': company,
    'role': role.name,
    'city': city,
    'rating_avg': ratingAvg,
    'rating_count': ratingCount,
    'deals_completed': dealsCompleted,
    'phone_verified': phoneVerified,
    'company_verified': companyVerified,
    'premium_until': isoOrNull(premiumUntil),
    'created_at': isoOrNull(createdAt),
  };

  PublicProfile copyWith({
    String? name,
    String? company,
    UserRole? role,
    String? city,
    double? ratingAvg,
    int? ratingCount,
    int? dealsCompleted,
    bool? phoneVerified,
    DateTime? premiumUntil,
  }) => PublicProfile(
    id: id,
    name: name ?? this.name,
    company: company ?? this.company,
    role: role ?? this.role,
    city: city ?? this.city,
    ratingAvg: ratingAvg ?? this.ratingAvg,
    ratingCount: ratingCount ?? this.ratingCount,
    dealsCompleted: dealsCompleted ?? this.dealsCompleted,
    phoneVerified: phoneVerified ?? this.phoneVerified,
    companyVerified: companyVerified,
    premiumUntil: premiumUntil ?? this.premiumUntil,
    createdAt: createdAt,
  );
}

/// Sunucudan profil çekerken kullanılan sütunlar.
const String kProfileColumns =
    'id,name,company,role,city,phone_verified,company_verified,rating_avg,rating_count,deals_completed,premium_until,created_at';

// ════════════════════════════ İlan türleri ════════════════════════════

/// İlan türü. Adlar veritabanındaki değerlerle aynıdır.
enum ListingKind {
  yuk('Yük', 'Yük ilanı', 'Nakliye teklifi'),
  makine('Makine', 'Makine ilanı', 'Kiralama talebi'),
  malzeme('Malzeme', 'Malzeme ilanı', 'Sipariş talebi'),
  personel('İş ilanı', 'Personel ilanı', 'İş başvurusu'),
  sicil('Operatör', 'Sicil kartı', 'İş teklifi');

  const ListingKind(this.label, this.listingLabel, this.requestLabel);

  final String label;
  final String listingLabel;

  /// Bu ilana gönderilen teklif/talebin adı.
  final String requestLabel;

  /// Türkçe isim tamlamalarının doğru çoğul biçimi.
  String get requestsLabel => switch (this) {
    ListingKind.yuk => 'Nakliye teklifleri',
    ListingKind.makine => 'Kiralama talepleri',
    ListingKind.malzeme => 'Sipariş talepleri',
    ListingKind.personel => 'İş başvuruları',
    ListingKind.sicil => 'İş teklifleri',
  };

  /// Talebi gönderen taraf anlaşmada "hizmet veren" mi? (yük → nakliyeci, iş ilanı → operatör)
  bool get requesterIsProvider =>
      this == ListingKind.yuk || this == ListingKind.personel;
}

enum ListingStatus {
  active('Yayında'),
  closed('Kapalı');

  const ListingStatus(this.label);
  final String label;
}

enum BoostOption {
  day('24 saat'),
  week('7 gün');

  const BoostOption(this.label);
  final String label;
}

/// Bütün ilanların ortak alanları.
abstract class Listing {
  Listing({
    required this.id,
    required this.owner,
    this.status = ListingStatus.active,
    this.boostedUntil,
    this.hidden = false,
    this.demo = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final PublicProfile owner;
  final ListingStatus status;
  final DateTime? boostedUntil;

  /// Şikâyetler nedeniyle yayından kaldırıldı (yalnızca sahibi görür).
  final bool hidden;

  /// Uygulamayla gelen örnek kayıt (gerçek bir firma değildir).
  final bool demo;
  final DateTime createdAt;

  ListingKind get kind;
  String get title;
  String get subtitle;
  String get city;

  /// Arama için düz metin.
  String get searchText;

  String get ownerId => owner.id;

  bool get isBoosted =>
      boostedUntil != null && boostedUntil!.isAfter(DateTime.now());

  /// Pazarda görünür ve teklif alabilir mi?
  bool get isOpen => status == ListingStatus.active && !hidden;

  /// Sunucuya yazılacak alanlar (kimlik, sahip ve sunucu alanları hariç).
  Map<String, dynamic> toRow();

  /// Cihazda saklama için tam kayıt.
  Map<String, dynamic> toJson() => {
    ...toRow(),
    'id': id,
    'owner_id': owner.id,
    'owner': owner.toJson(),
    'boosted_until': isoOrNull(boostedUntil),
    'hidden': hidden,
    'demo': demo,
    'created_at': isoOrNull(createdAt),
  };

  static Listing fromJson(ListingKind kind, Map<String, dynamic> j) =>
      switch (kind) {
        ListingKind.yuk => Load.fromJson(j),
        ListingKind.makine => Machine.fromJson(j),
        ListingKind.malzeme => MaterialListing.fromJson(j),
        ListingKind.personel => JobPost.fromJson(j),
        ListingKind.sicil => WorkerCard.fromJson(j),
      };
}

PublicProfile _ownerOf(Map<String, dynamic> j) {
  final o = asMap(j['owner']);
  if (o.isEmpty) {
    return PublicProfile(id: asString(j['owner_id']), name: 'Kullanıcı');
  }
  return PublicProfile.fromJson(o);
}

ListingStatus _status(Map<String, dynamic> j) =>
    enumByName(ListingStatus.values, j['status'], ListingStatus.active);

// ───────────────────────── Yük ─────────────────────────

enum VehicleType {
  tir('Tır (Tenteli)'),
  frigo('Frigorifik'),
  damperli('Damperli'),
  kirkayak('Kırkayak'),
  lowbed('Lowbed'),
  kamyon('Kamyon'),
  kamyonet('Kamyonet');

  const VehicleType(this.label);
  final String label;
}

class Load extends Listing {
  Load({
    required super.id,
    required super.owner,
    required this.fromCity,
    required this.toCity,
    required this.cargo,
    required this.tons,
    required this.vehicle,
    required this.price,
    required this.date,
    this.note = '',
    super.status,
    super.boostedUntil,
    super.hidden,
    super.demo,
    super.createdAt,
  });

  final String fromCity;
  final String toCity;
  final String cargo;
  final double tons;
  final VehicleType vehicle;

  /// Navlun (₺). 0 ise "Teklif bekleniyor".
  final double price;

  /// Yükleme günü.
  final DateTime date;
  final String note;

  @override
  ListingKind get kind => ListingKind.yuk;

  @override
  String get title => '$fromCity → $toCity';

  @override
  String get subtitle => cargo;

  @override
  String get city => fromCity;

  /// Yükleme günü geçmiş ilan.
  bool get isExpired => date.isBefore(startOfToday());

  @override
  bool get isOpen => super.isOpen && !isExpired;

  @override
  String get searchText =>
      '$cargo $fromCity $toCity ${owner.displayName} $note ${vehicle.label}';

  @override
  Map<String, dynamic> toRow() => {
    'from_city': fromCity,
    'to_city': toCity,
    'cargo': cargo,
    'tons': tons,
    'vehicle': vehicle.name,
    'price': price,
    'load_date': dateOnly(date),
    'note': note,
    'status': status.name,
  };

  factory Load.fromJson(Map<String, dynamic> j) => Load(
    id: asString(j['id']),
    owner: _ownerOf(j),
    fromCity: asString(j['from_city']),
    toCity: asString(j['to_city']),
    cargo: asString(j['cargo']),
    tons: asDouble(j['tons']),
    vehicle: enumByName(VehicleType.values, j['vehicle'], VehicleType.tir),
    price: asDouble(j['price']),
    date: asDate(j['load_date']),
    note: asString(j['note']),
    status: _status(j),
    boostedUntil: asDateOrNull(j['boosted_until']),
    hidden: asBool(j['hidden']),
    demo: asBool(j['demo']),
    createdAt: asDateOrNull(j['created_at']),
  );
}

// ───────────────────────── Makine ─────────────────────────

enum MachineType {
  ekskavator('Ekskavatör'),
  miniEkskavator('Mini ekskavatör'),
  silindir('Silindir'),
  tandemSilindir('Tandem silindir'),
  lastikliSilindir('Lastikli silindir'),
  greyder('Greyder'),
  finiser('Finişer'),
  loder('Loder'),
  paletliLoder('Paletli loder'),
  miniYukleyici('Mini yükleyici / Bobcat'),
  teleskopik('Teleskopik yükleyici'),
  bekoloder('Beko Loder'),
  dozer('Dozer'),
  skrayper('Skrayper'),
  vinc('Mobil Vinç'),
  kuleVinc('Kule vinç'),
  paletliVinc('Paletli vinç'),
  platform('Personel yükseltme / Manlift'),
  forklift('Forklift'),
  betonPompa('Beton pompası'),
  betonMikser('Transmikser'),
  kazik('Fore kazık makinesi'),
  delici('Sondaj / Delici'),
  kirmaEleme('Kırma eleme'),
  asfaltKesici('Asfalt kesici'),
  kompresor('Kompresör'),
  jenerator('Jeneratör'),
  suTankeri('Su tankeri'),
  silobas('Silobas'),
  kamyon('Kamyon / Damper'),
  cekici('Çekici / Lowbed'),
  diger('Diğer'),
  // ── Sonradan eklenenler (mevcut adlar ve sıra korunur) ──
  lastikliEkskavator('Lastikli ekskavatör'),
  uzunKolEkskavator('Uzun kol ekskavatör'),
  hidrolikKirici('Hidrolik kırıcı (Kırıcı çekiç)'),
  lastikliLoder('Lastikli loder'),
  tir('Tır (Çekici + Dorse)'),
  damperliDorse('Damperli dorse'),
  kayarTabla('Kayar tabla / Düz dorse'),
  kamyonet('Kamyonet / Panelvan'),
  onTekerKamyon('Kırkayak / 10 tekerli kamyon'),
  eklemliDamper('Eklemli (belden kırma) damper'),
  rijitDamper('Rijit maden damperi'),
  miniDamper('Şantiye damperi / Dumper'),
  yakitTankeri('Yakıt tankeri'),
  vidanjor('Vidanjör / Kanal temizleme'),
  copKamyonu('Çöp kamyonu / Kompaktör'),
  tomrukTasiyici('Tomruk / Kereste taşıyıcı'),
  romork('Römork / Treyler'),
  hiyap('Hiyap / Kamyon üstü vinç'),
  orumcekVinc('Örümcek vinç'),
  gezerVinc('Gezer köprülü / Portal vinç'),
  sepetliPlatform('Sepetli araç / Hidrolik merdiven'),
  santiyeAsansoru('Şantiye asansörü'),
  vibrasyonluSilindir('Vibrasyonlu silindir'),
  toprakSilindiri('Tek tamburlu toprak silindiri'),
  koyunAyagiSilindir('Koyun ayağı silindir'),
  vibroPlaka('Vibrasyonlu plaka / Tokmak'),
  asfaltFreze('Asfalt kazıma (Freze)'),
  asfaltPlenti('Asfalt plenti'),
  betonSantrali('Beton santrali'),
  helikopterMala('Helikopter mala / Beton vibratörü'),
  karot('Karot / Beton delme'),
  trencher('Hendek açma (Trencher)'),
  kazikCakma('Kazık çakma / Palplanş makinesi'),
  kuyuSondaj('Kuyu / Zemin etüt sondajı'),
  paletliDelici('Paletli kaya delici'),
  jumbo('Jumbo (Tünel delici)'),
  tbm('Tünel açma makinesi (TBM)'),
  mobilKirici('Mobil kırıcı'),
  elek('Mobil elek / Eleme'),
  konveyor('Konveyör bant'),
  telTestere('Mermer tel testere / Katener'),
  zincirliKesici('Blok kesme / Zincirli kesici'),
  tomrukYukleyici('Tomruk yükleyici / Kıskaç'),
  harvester('Orman harvester'),
  forwarder('Orman forwarder'),
  skidder('Skidder (Ağaç çekme)'),
  cipper('Ağaç parçalama (Çipper)'),
  traktor('Traktör'),
  suPompasi('Su pompası / Dalgıç pompa'),
  kaynakMakinesi('Kaynak makinesi / Kaynak jeneratörü'),
  isikKulesi('Aydınlatma kulesi'),
  arozoz('Arazöz / Su tankı'),
  bitumTankeri('Bitüm / Zift tankeri'),
  yolCizgi('Yol çizgi makinesi'),
  karKureme('Kar küreme / Tuz serici'),
  mobilKonteyner('Konteyner / Şantiye kabini');

  const MachineType(this.label);
  final String label;
}

class Machine extends Listing {
  Machine({
    required super.id,
    required super.owner,
    required this.type,
    required this.model,
    required this.capacity,
    required this.city,
    required this.lat,
    required this.lng,
    required this.hourly,
    required this.daily,
    this.withOperator = true,
    this.available = true,
    this.note = '',
    super.status,
    super.boostedUntil,
    super.hidden,
    super.demo,
    super.createdAt,
  });

  final MachineType type;
  final String model;
  final String capacity;
  @override
  final String city;
  final double lat;
  final double lng;
  final double hourly;
  final double daily;
  final bool withOperator;
  final bool available;
  final String note;

  LatLng get position => LatLng(lat, lng);

  @override
  ListingKind get kind => ListingKind.makine;

  @override
  String get title => '${type.label} · $model';

  @override
  String get subtitle => capacity.isEmpty ? city : '$capacity · $city';

  @override
  String get searchText =>
      '${type.label} $model $capacity $city ${owner.displayName} $note';

  @override
  Map<String, dynamic> toRow() => {
    'type': type.name,
    'model': model,
    'capacity': capacity,
    'city': city,
    'lat': lat,
    'lng': lng,
    'hourly': hourly,
    'daily': daily,
    'with_operator': withOperator,
    'available': available,
    'note': note,
    'status': status.name,
  };

  factory Machine.fromJson(Map<String, dynamic> j) => Machine(
    id: asString(j['id']),
    owner: _ownerOf(j),
    type: enumByName(MachineType.values, j['type'], MachineType.diger),
    model: asString(j['model']),
    capacity: asString(j['capacity']),
    city: asString(j['city']),
    lat: asDouble(j['lat']),
    lng: asDouble(j['lng']),
    hourly: asDouble(j['hourly']),
    daily: asDouble(j['daily']),
    withOperator: asBool(j['with_operator'], true),
    available: asBool(j['available'], true),
    note: asString(j['note']),
    status: _status(j),
    boostedUntil: asDateOrNull(j['boosted_until']),
    hidden: asBool(j['hidden']),
    demo: asBool(j['demo']),
    createdAt: asDateOrNull(j['created_at']),
  );
}

// ───────────────────────── Malzeme ─────────────────────────

enum MaterialKind {
  beton('Hazır Beton', 'm³'),
  agrega('Agrega', 'ton'),
  stabilize('Stabilize', 'ton'),
  asfalt('Asfalt', 'ton'),
  cimento('Çimento', 'ton'),
  celik('İnşaat demiri / Çelik', 'ton'),
  tugla('Tuğla / Briket', 'adet'),
  yalitim('Yalıtım malzemesi', 'm²'),
  elektrikMalzeme('Elektrik malzeme', 'adet'),
  mekanikMalzeme('Mekanik malzeme', 'adet'),
  diger('Diğer', 'adet');

  const MaterialKind(this.label, this.defaultUnit);
  final String label;
  final String defaultUnit;
}

enum StockLevel {
  bol('Stok var'),
  az('Stok az'),
  yok('Stok yok');

  const StockLevel(this.label);
  final String label;
}

class MaterialListing extends Listing {
  MaterialListing({
    required super.id,
    required super.owner,
    required this.materialKind,
    required this.product,
    required this.unit,
    required this.price,
    required this.stock,
    required this.plantName,
    required this.city,
    required this.lat,
    required this.lng,
    this.delivery = true,
    this.minQty = 0,
    this.note = '',
    super.status,
    super.boostedUntil,
    super.hidden,
    super.demo,
    super.createdAt,
  });

  final MaterialKind materialKind;
  final String product;
  final String unit;

  /// Birim fiyat (KDV hariç, ₺).
  final double price;
  final StockLevel stock;
  final String plantName;
  @override
  final String city;
  final double lat;
  final double lng;

  /// Satıcı nakliye sağlıyor mu?
  final bool delivery;
  final double minQty;
  final String note;

  LatLng get position => LatLng(lat, lng);

  @override
  ListingKind get kind => ListingKind.malzeme;

  @override
  String get title => product;

  @override
  String get subtitle => '$plantName · $city';

  @override
  bool get isOpen => super.isOpen && stock != StockLevel.yok;

  @override
  String get searchText =>
      '${materialKind.label} $product $plantName $city ${owner.displayName} $note';

  @override
  Map<String, dynamic> toRow() => {
    'kind': materialKind.name,
    'product': product,
    'unit': unit,
    'price': price,
    'stock': stock.name,
    'plant_name': plantName,
    'city': city,
    'lat': lat,
    'lng': lng,
    'delivery': delivery,
    'min_qty': minQty,
    'note': note,
    'status': status.name,
  };

  factory MaterialListing.fromJson(Map<String, dynamic> j) => MaterialListing(
    id: asString(j['id']),
    owner: _ownerOf(j),
    materialKind: enumByName(
      MaterialKind.values,
      j['kind'],
      MaterialKind.diger,
    ),
    product: asString(j['product']),
    unit: asString(j['unit'], 'ton'),
    price: asDouble(j['price']),
    stock: enumByName(StockLevel.values, j['stock'], StockLevel.bol),
    plantName: asString(j['plant_name']),
    city: asString(j['city']),
    lat: asDouble(j['lat']),
    lng: asDouble(j['lng']),
    delivery: asBool(j['delivery'], true),
    minQty: asDouble(j['min_qty']),
    note: asString(j['note']),
    status: _status(j),
    boostedUntil: asDateOrNull(j['boosted_until']),
    hidden: asBool(j['hidden']),
    demo: asBool(j['demo']),
    createdAt: asDateOrNull(j['created_at']),
  );
}

// ───────────────────────── Personel ─────────────────────────

enum WorkerRole {
  ekskavatorOp('Ekskavatör Operatörü'),
  silindirOp('Silindir Operatörü'),
  greyderOp('Greyder Operatörü'),
  finiserOp('Finişer Operatörü'),
  vincOp('Vinç Operatörü'),
  tirSoforu('Tır / Kamyon Şoförü'),
  ustabasi('Ustabaşı / Formen'),
  isci('Saha İşçisi'),
  // ── Sonradan eklenenler (mevcut adlar ve sıra korunur) ──
  dozerOp('Dozer Operatörü'),
  loderOp('Loder Operatörü'),
  bekoloderOp('Beko Loder Operatörü'),
  miniYukleyiciOp('Mini Yükleyici / Bobcat Operatörü'),
  forkliftOp('Forklift Operatörü'),
  kuleVincOp('Kule Vinç Operatörü'),
  betonPompaOp('Beton Pompası Operatörü'),
  kiriciOp('Hidrolik Kırıcı Operatörü'),
  sondorOp('Sondaj / Fore Kazık Operatörü'),
  kamyonSoforu('Kamyon Şoförü'),
  mikserSoforu('Mikser Şoförü'),
  servisSoforu('Servis / Araç Şoförü'),
  forman('Forman'),
  muhendis('Mühendis'),
  tekniker('Tekniker / Teknisyen'),
  santiyeSefi('Şantiye Şefi'),
  bekci('Bekçi'),
  guvenlik('Güvenlik Görevlisi'),
  kaynakci('Kaynakçı'),
  elektrikci('Elektrikçi'),
  tesisatci('Tesisatçı'),
  kalipci('Kalıpçı'),
  demirci('Demirci'),
  betoncu('Betoncu'),
  sivaBoya('Sıvacı / Boyacı'),
  tamirci('Makine Bakım / Tamirci'),
  depocu('Depocu'),
  puantor('Puantör'),
  patlatmaci('Patlatmacı'),
  madenci('Madenci / Ocak Ustası'),
  mermerUstasi('Mermer Ustası'),
  ormanIsci('Orman İşçisi');

  const WorkerRole(this.label);
  final String label;
}

const List<String> kWagePeriods = ['Günlük', 'Aylık', 'Saatlik', 'Götürü'];

class JobPost extends Listing {
  JobPost({
    required super.id,
    required super.owner,
    required this.title,
    required this.role,
    required this.city,
    required this.wage,
    required this.wagePeriod,
    this.duration = '',
    this.requirements = const [],
    this.note = '',
    super.status,
    super.boostedUntil,
    super.hidden,
    super.demo,
    super.createdAt,
  });

  @override
  final String title;
  final WorkerRole role;
  @override
  final String city;
  final double wage;
  final String wagePeriod;
  final String duration;
  final List<String> requirements;
  final String note;

  @override
  ListingKind get kind => ListingKind.personel;

  @override
  String get subtitle => '${role.label} · $city';

  @override
  String get searchText =>
      '$title ${role.label} $city ${owner.displayName} ${requirements.join(' ')} $note';

  @override
  Map<String, dynamic> toRow() => {
    'title': title,
    'role': role.name,
    'city': city,
    'wage': wage,
    'wage_period': wagePeriod,
    'duration': duration,
    'requirements': requirements,
    'note': note,
    'status': status.name,
  };

  factory JobPost.fromJson(Map<String, dynamic> j) => JobPost(
    id: asString(j['id']),
    owner: _ownerOf(j),
    title: asString(j['title']),
    role: enumByName(WorkerRole.values, j['role'], WorkerRole.isci),
    city: asString(j['city']),
    wage: asDouble(j['wage']),
    wagePeriod: asString(j['wage_period'], 'Günlük'),
    duration: asString(j['duration']),
    requirements: asStringList(j['requirements']),
    note: asString(j['note']),
    status: _status(j),
    boostedUntil: asDateOrNull(j['boosted_until']),
    hidden: asBool(j['hidden']),
    demo: asBool(j['demo']),
    createdAt: asDateOrNull(j['created_at']),
  );
}

/// Operatör / personel sicil kartı (kişi başı bir kart).
class WorkerCard extends Listing {
  WorkerCard({
    required super.id,
    required super.owner,
    required this.role,
    required this.city,
    required this.years,
    this.certificates = const [],
    this.available = true,
    this.about = '',
    super.status,
    super.boostedUntil,
    super.hidden,
    super.demo,
    super.createdAt,
  });

  final WorkerRole role;
  @override
  final String city;
  final int years;
  final List<String> certificates;
  final bool available;
  final String about;

  @override
  ListingKind get kind => ListingKind.sicil;

  @override
  String get title => owner.name;

  @override
  String get subtitle => '${role.label} · $city · $years yıl';

  @override
  String get searchText =>
      '${owner.name} ${role.label} $city ${certificates.join(' ')} $about';

  @override
  Map<String, dynamic> toRow() => {
    'role': role.name,
    'city': city,
    'years': years,
    'certificates': certificates,
    'available': available,
    'about': about,
    'status': status.name,
  };

  factory WorkerCard.fromJson(Map<String, dynamic> j) => WorkerCard(
    id: asString(j['id']),
    owner: _ownerOf(j),
    role: enumByName(WorkerRole.values, j['role'], WorkerRole.isci),
    city: asString(j['city']),
    years: asInt(j['years']),
    certificates: asStringList(j['certificates']),
    available: asBool(j['available'], true),
    about: asString(j['about']),
    status: _status(j),
    boostedUntil: asDateOrNull(j['boosted_until']),
    hidden: asBool(j['hidden']),
    demo: asBool(j['demo']),
    createdAt: asDateOrNull(j['created_at']),
  );
}

// ════════════════════════════ Teklif / talep ════════════════════════════

enum RequestStatus {
  pending('Yanıt bekleniyor'),
  accepted('Kabul edildi'),
  rejected('Kabul edilmedi'),
  withdrawn('Geri çekildi');

  const RequestStatus(this.label);
  final String label;
}

/// Bir ilana gönderilen teklif (yük), kiralama talebi (makine), sipariş
/// (malzeme), iş başvurusu (personel) veya iş teklifi (operatör).
class TradeRequest {
  TradeRequest({
    required this.id,
    required this.kind,
    required this.listingId,
    required this.listingTitle,
    required this.ownerId,
    required this.requesterId,
    this.owner,
    this.requester,
    this.amount = 0,
    this.quantity = 0,
    this.unit = '',
    this.startDate,
    this.address = '',
    this.note = '',
    this.status = RequestStatus.pending,
    this.dealId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;
  final ListingKind kind;
  final String listingId;
  final String listingTitle;
  final String ownerId;
  final String requesterId;
  final PublicProfile? owner;
  final PublicProfile? requester;
  final double amount;
  final double quantity;
  final String unit;
  final DateTime? startDate;
  final String address;
  final String note;
  final RequestStatus status;
  final String? dealId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPending => status == RequestStatus.pending;

  factory TradeRequest.fromJson(Map<String, dynamic> j) {
    final owner = asMap(j['owner']);
    final requester = asMap(j['requester']);
    return TradeRequest(
      id: asString(j['id']),
      kind: enumByName(ListingKind.values, j['kind'], ListingKind.yuk),
      listingId: asString(j['listing_id']),
      listingTitle: asString(j['listing_title']),
      ownerId: asString(j['owner_id']),
      requesterId: asString(j['requester_id']),
      owner: owner.isEmpty ? null : PublicProfile.fromJson(owner),
      requester: requester.isEmpty ? null : PublicProfile.fromJson(requester),
      amount: asDouble(j['amount']),
      quantity: asDouble(j['quantity']),
      unit: asString(j['unit']),
      startDate: asDateOrNull(j['start_date']),
      address: asString(j['address']),
      note: asString(j['note']),
      status: enumByName(
        RequestStatus.values,
        j['status'],
        RequestStatus.pending,
      ),
      dealId: j['deal_id'] == null ? null : asString(j['deal_id']),
      createdAt: asDateOrNull(j['created_at']),
      updatedAt: asDateOrNull(j['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'listing_id': listingId,
    'listing_title': listingTitle,
    'owner_id': ownerId,
    'requester_id': requesterId,
    if (owner != null) 'owner': owner!.toJson(),
    if (requester != null) 'requester': requester!.toJson(),
    'amount': amount,
    'quantity': quantity,
    'unit': unit,
    'start_date': startDate == null ? null : dateOnly(startDate!),
    'address': address,
    'note': note,
    'status': status.name,
    'deal_id': dealId,
    'created_at': isoOrNull(createdAt),
    'updated_at': isoOrNull(updatedAt),
  };
}

/// Yeni teklif/talep formu.
class RequestDraft {
  const RequestDraft({
    required this.kind,
    required this.listingId,
    this.amount = 0,
    this.quantity = 0,
    this.unit = '',
    this.startDate,
    this.address = '',
    this.note = '',
  });

  final ListingKind kind;
  final String listingId;
  final double amount;
  final double quantity;
  final String unit;
  final DateTime? startDate;
  final String address;
  final String note;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'listing_id': listingId,
    'amount': amount,
    'quantity': quantity,
    'unit': unit,
    'start_date': startDate == null ? null : dateOnly(startDate!),
    'address': address,
    'note': note,
  };

  factory RequestDraft.fromJson(Map<String, dynamic> j) => RequestDraft(
    kind: enumByName(ListingKind.values, j['kind'], ListingKind.yuk),
    listingId: asString(j['listing_id']),
    amount: asDouble(j['amount']),
    quantity: asDouble(j['quantity']),
    unit: asString(j['unit']),
    startDate: asDateOrNull(j['start_date']),
    address: asString(j['address']),
    note: asString(j['note']),
  );
}

// ════════════════════════════ Anlaşma kaydı ════════════════════════════

enum DealKind {
  yuk('Nakliye'),
  makine('Makine kiralama'),
  malzeme('Malzeme alımı'),
  personel('Personel'),
  sicil('Operatör'),
  diger('Diğer iş');

  const DealKind(this.label);
  final String label;
}

enum DealStatus {
  pending('Onay bekliyor'),
  active('Devam ediyor'),
  delivered('Teslim bildirildi'),
  completed('Tamamlandı'),
  cancelled('İptal edildi'),
  disputed('Sorun bildirildi');

  const DealStatus(this.label);
  final String label;

  bool get isOpen =>
      this != DealStatus.completed && this != DealStatus.cancelled;
}

enum PaymentMethod {
  havale('Havale / EFT'),
  nakit('Nakit'),
  cek('Çek / Senet'),
  kart('Kredi kartı (POS)'),
  diger('Diğer');

  const PaymentMethod(this.label);
  final String label;
}

/// Anlaşmadaki işlemler (veritabanındaki deal_action değerleriyle aynı).
enum DealAction {
  confirm('confirm'),
  reject('reject'),
  cancel('cancel'),
  deliver('deliver'),
  complete('complete'),
  dispute('dispute'),
  resolve('resolve'),
  markPaid('mark_paid'),
  markReceived('mark_received'),
  note('note');

  const DealAction(this.wire);
  final String wire;
}

/// Ödeme takibi satırı. Para uygulama üzerinden geçmez; taraflar
/// ödemeyi birbirine doğrudan yapar ve burada işaretler.
class DealMilestone {
  const DealMilestone({
    required this.title,
    required this.amount,
    this.paidAt,
    this.receivedAt,
  });

  final String title;
  final double amount;

  /// Ödeyen tarafın "ödedim" dediği an.
  final DateTime? paidAt;

  /// Alan tarafın "tahsil ettim" dediği an.
  final DateTime? receivedAt;

  bool get paid => paidAt != null;
  bool get received => receivedAt != null;

  factory DealMilestone.fromJson(Map<String, dynamic> j) => DealMilestone(
    title: asString(j['title'], 'Ödeme'),
    amount: asDouble(j['amount']),
    paidAt: asDateOrNull(j['paid_at']),
    receivedAt: asDateOrNull(j['received_at']),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'amount': amount,
    'paid_at': isoOrNull(paidAt),
    'received_at': isoOrNull(receivedAt),
  };
}

class DealLogEntry {
  const DealLogEntry({required this.at, required this.by, required this.text});

  final DateTime at;
  final String by;
  final String text;

  factory DealLogEntry.fromJson(Map<String, dynamic> j) => DealLogEntry(
    at: asDate(j['at']),
    by: asString(j['by']),
    text: asString(j['text']),
  );

  Map<String, dynamic> toJson() => {
    'at': isoOrNull(at),
    'by': by,
    'text': text,
  };
}

class Deal {
  Deal({
    required this.id,
    required this.code,
    required this.kind,
    required this.title,
    this.requestId,
    this.details = '',
    this.customerId,
    this.providerId,
    this.customerName = '',
    this.providerName = '',
    this.createdBy,
    this.amount = 0,
    this.paymentMethod = PaymentMethod.havale,
    this.paymentTerms = '',
    this.startDate,
    this.status = DealStatus.pending,
    this.prevStatus,
    this.cancelRequestedBy,
    this.disputedBy,
    this.milestones = const [],
    this.log = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  final String id;

  /// Karşı tarafın anlaşmaya katılması ve kaydın doğrulanması için kısa kod.
  final String code;
  final DealKind kind;
  final String title;
  final String? requestId;
  final String details;

  /// İşi veren / alıcı / kiracı.
  final String? customerId;

  /// Hizmeti veren / satıcı / makine sahibi / nakliyeci.
  final String? providerId;
  final String customerName;
  final String providerName;
  final String? createdBy;
  final double amount;
  final PaymentMethod paymentMethod;
  final String paymentTerms;
  final DateTime? startDate;
  final DealStatus status;
  final DealStatus? prevStatus;
  final String? cancelRequestedBy;
  final String? disputedBy;
  final List<DealMilestone> milestones;
  final List<DealLogEntry> log;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isCustomer(String? me) => me != null && customerId == me;
  bool isProvider(String? me) => me != null && providerId == me;

  /// Karşı taraf uygulamada değil; kaydı oluşturan iki tarafın işlemlerini de yapar.
  bool isSolo(String? me) =>
      me != null &&
      createdBy == me &&
      (customerId == null || providerId == null);

  bool canActAsCustomer(String? me) =>
      isCustomer(me) || (isSolo(me) && customerId == null);
  bool canActAsProvider(String? me) =>
      isProvider(me) || (isSolo(me) && providerId == null);

  /// Davet bekleyen (karşı tarafı henüz katılmamış) anlaşma.
  bool get awaitingCounterparty =>
      status == DealStatus.pending &&
      (customerId == null || providerId == null);

  String? counterpartyId(String? me) =>
      isCustomer(me) ? providerId : customerId;

  String counterpartyName(String? me) {
    final name = isCustomer(me) ? providerName : customerName;
    return name.trim().isEmpty ? 'Karşı taraf' : name;
  }

  /// Benim bu anlaşmadaki rolüm: "İşi veren" / "Hizmet veren".
  String myRoleLabel(String? me) => isCustomer(me)
      ? 'İşi veren / alıcı'
      : isProvider(me)
      ? 'Hizmet veren / satıcı'
      : 'Kaydı oluşturan';

  double get paidTotal =>
      milestones.where((m) => m.paid).fold(0.0, (a, m) => a + m.amount);
  double get receivedTotal =>
      milestones.where((m) => m.received).fold(0.0, (a, m) => a + m.amount);
  double get plannedTotal => milestones.fold(0.0, (a, m) => a + m.amount);

  factory Deal.fromJson(Map<String, dynamic> j) {
    final prev = j['prev_status'];
    return Deal(
      id: asString(j['id']),
      code: asString(j['code']),
      kind: enumByName(DealKind.values, j['kind'], DealKind.diger),
      title: asString(j['title']),
      requestId: j['request_id'] == null ? null : asString(j['request_id']),
      details: asString(j['details']),
      customerId: j['customer_id'] == null ? null : asString(j['customer_id']),
      providerId: j['provider_id'] == null ? null : asString(j['provider_id']),
      customerName: asString(j['customer_name']),
      providerName: asString(j['provider_name']),
      createdBy: j['created_by'] == null ? null : asString(j['created_by']),
      amount: asDouble(j['amount']),
      paymentMethod: enumByName(
        PaymentMethod.values,
        j['payment_method'],
        PaymentMethod.havale,
      ),
      paymentTerms: asString(j['payment_terms']),
      startDate: asDateOrNull(j['start_date']),
      status: enumByName(DealStatus.values, j['status'], DealStatus.pending),
      prevStatus: prev == null
          ? null
          : enumByName(DealStatus.values, prev, DealStatus.active),
      cancelRequestedBy: j['cancel_requested_by'] as String?,
      disputedBy: j['disputed_by'] as String?,
      milestones: [
        for (final m in asMapList(j['milestones'])) DealMilestone.fromJson(m),
      ],
      log: [for (final l in asMapList(j['log'])) DealLogEntry.fromJson(l)],
      createdAt: asDateOrNull(j['created_at']),
      updatedAt: asDateOrNull(j['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'kind': kind.name,
    'title': title,
    'request_id': requestId,
    'details': details,
    'customer_id': customerId,
    'provider_id': providerId,
    'customer_name': customerName,
    'provider_name': providerName,
    'created_by': createdBy,
    'amount': amount,
    'payment_method': paymentMethod.name,
    'payment_terms': paymentTerms,
    'start_date': startDate == null ? null : dateOnly(startDate!),
    'status': status.name,
    'prev_status': prevStatus?.name,
    'cancel_requested_by': cancelRequestedBy,
    'disputed_by': disputedBy,
    'milestones': [for (final m in milestones) m.toJson()],
    'log': [for (final l in log) l.toJson()],
    'created_at': isoOrNull(createdAt),
    'updated_at': isoOrNull(updatedAt),
  };
}

/// Elle anlaşma kaydı formu.
class DealDraft {
  const DealDraft({
    required this.title,
    required this.iAmCustomer,
    required this.counterpartyName,
    required this.amount,
    required this.paymentMethod,
    this.details = '',
    this.paymentTerms = '',
    this.startDate,
    this.milestones = const [],
  });

  final String title;

  /// true: işi veren / alıcı benim. false: hizmeti veren / satıcı benim.
  final bool iAmCustomer;
  final String counterpartyName;
  final double amount;
  final PaymentMethod paymentMethod;
  final String details;
  final String paymentTerms;
  final DateTime? startDate;
  final List<DealMilestone> milestones;
}

// ════════════════════════════ Puan, bildirim, kullanım ════════════════════════════

class Rating {
  const Rating({
    required this.id,
    required this.dealId,
    required this.fromId,
    required this.toId,
    required this.fromName,
    required this.stars,
    this.comment = '',
    required this.createdAt,
  });

  final String id;
  final String dealId;
  final String fromId;
  final String toId;
  final String fromName;
  final int stars;
  final String comment;
  final DateTime createdAt;

  factory Rating.fromJson(Map<String, dynamic> j) => Rating(
    id: asString(j['id']),
    dealId: asString(j['deal_id']),
    fromId: asString(j['from_id']),
    toId: asString(j['to_id']),
    fromName: asString(j['from_name'], 'Kullanıcı'),
    stars: asInt(j['stars']).clamp(1, 5).toInt(),
    comment: asString(j['comment']),
    createdAt: asDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'deal_id': dealId,
    'from_id': fromId,
    'to_id': toId,
    'from_name': fromName,
    'stars': stars,
    'comment': comment,
    'created_at': isoOrNull(createdAt),
  };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    this.refType = '',
    this.refId,
    this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;

  /// request · deal · yuk/makine/... (ilan)
  final String refType;
  final String? refId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get unread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: asString(j['id']),
    type: asString(j['type'], 'info'),
    title: asString(j['title']),
    body: asString(j['body']),
    refType: asString(j['ref_type']),
    refId: j['ref_id'] == null ? null : asString(j['ref_id']),
    readAt: asDateOrNull(j['read_at']),
    createdAt: asDate(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'ref_type': refType,
    'ref_id': refId,
    'read_at': isoOrNull(readAt),
    'created_at': isoOrNull(createdAt),
  };
}

/// Ücretsiz hak, kredi ve Premium durumu.
class UsageInfo {
  const UsageInfo({
    this.freeUsed = 0,
    this.freeLimit = 5,
    this.credits = 0,
    this.premiumUntil,
    this.freeListingLimit = 5,
    this.activeListings = 0,
    this.boostDayCost = 1,
    this.boostWeekCost = 5,
    this.announcement = '',
  });

  final int freeUsed;
  final int freeLimit;
  final int credits;
  final DateTime? premiumUntil;
  final int freeListingLimit;
  final int activeListings;
  final int boostDayCost;
  final int boostWeekCost;

  /// Yöneticinin herkese gösterdiği duyuru (boşsa gösterilmez).
  final String announcement;

  bool get isPremium =>
      premiumUntil != null && premiumUntil!.isAfter(DateTime.now());
  int get freeLeft {
    final left = freeLimit - freeUsed;
    return left < 0 ? 0 : left;
  }

  int boostCost(BoostOption o) =>
      o == BoostOption.day ? boostDayCost : boostWeekCost;

  Map<String, dynamic> toJson() => {
    'free_used': freeUsed,
    'free_limit': freeLimit,
    'credits': credits,
    'premium_until': isoOrNull(premiumUntil),
    'free_listing_limit': freeListingLimit,
    'active_listings': activeListings,
    'boost_day_cost': boostDayCost,
    'boost_week_cost': boostWeekCost,
    'announcement': announcement,
  };

  factory UsageInfo.fromJson(Map<String, dynamic> j) => UsageInfo(
    freeUsed: asInt(j['free_used']),
    freeLimit: asInt(j['free_limit']),
    credits: asInt(j['credits']),
    premiumUntil: asDateOrNull(j['premium_until']),
    freeListingLimit: asInt(j['free_listing_limit']),
    activeListings: asInt(j['active_listings']),
    boostDayCost: asInt(j['boost_day_cost']),
    boostWeekCost: asInt(j['boost_week_cost']),
    announcement: asString(j['announcement']),
  );
}

/// İletişim hakkı açma sonucu.
class UnlockResult {
  const UnlockResult({
    required this.ok,
    this.method = '',
    this.reason = '',
    this.credits = 0,
  });

  final bool ok;

  /// free · premium · credit · already · own
  final String method;

  /// QUOTA: ücretsiz hak bitti.
  final String reason;
  final int credits;

  factory UnlockResult.fromJson(Map<String, dynamic> j) => UnlockResult(
    ok: asBool(j['ok']),
    method: asString(j['method']),
    reason: asString(j['reason']),
    credits: asInt(j['credits']),
  );
}

class ContactInfo {
  const ContactInfo({
    required this.userId,
    required this.name,
    required this.phone,
    this.phoneVerified = false,
  });

  final String userId;
  final String name;
  final String phone;
  final bool phoneVerified;

  bool get hasPhone => phone.trim().isNotEmpty;

  /// Onaylanmamış numara asla gösterilmez.
  String get visiblePhone => phoneVerified ? phone.trim() : '';

  bool get hasVisiblePhone => visiblePhone.isNotEmpty;

  factory ContactInfo.fromJson(Map<String, dynamic> j) => ContactInfo(
    userId: asString(j['user_id']),
    name: asString(j['name']),
    phone: asString(j['phone']),
    phoneVerified: asBool(j['phone_verified']),
  );
}

/// Şikâyet nedenleri.
const List<String> kReportReasons = [
  'Sahte veya yanıltıcı ilan',
  'Dolandırıcılık şüphesi',
  'Ödeme yapılmadı / iş yapılmadı',
  'Hakaret veya uygunsuz içerik',
  'Spam / tekrar eden ilan',
  'Diğer',
];

// ════════════════════════════ Hafriyat planlama (cihazda) ════════════════════════════

enum HaulPointKind {
  excavation('Kazı sahası'),
  dump('Döküm sahası'),
  source('Malzeme ocağı');

  const HaulPointKind(this.label);
  final String label;
}

class HaulPoint {
  HaulPoint({
    required this.id,
    required this.name,
    required this.kind,
    required this.lat,
    required this.lng,
    this.volume = 0,
    this.feePerM3 = 0,
    this.needM3 = 0,
    this.material = '',
    this.demo = false,
  });

  final String id;
  final String name;
  final HaulPointKind kind;
  final double lat;
  final double lng;

  /// Kazı: çıkacak hafriyat (m³) · Döküm: kalan kapasite (m³) · Ocak: stok (m³)
  final double volume;

  /// Döküm: m³ başına döküm ücreti · Ocak: m³ başına malzeme fiyatı
  final double feePerM3;

  /// Kazı sahası için geri dolgu malzemesi ihtiyacı (m³) — dönüş yükü fırsatı.
  final double needM3;

  /// Ocak: sağlanan malzeme adı
  final String material;

  /// "Örnek sahaları yükle" ile gelen nokta.
  final bool demo;

  LatLng get position => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'lat': lat,
    'lng': lng,
    'volume': volume,
    'feePerM3': feePerM3,
    'needM3': needM3,
    'material': material,
    'demo': demo,
  };

  factory HaulPoint.fromJson(Map<String, dynamic> j) => HaulPoint(
    id: asString(j['id']),
    name: asString(j['name']),
    kind: enumByName(HaulPointKind.values, j['kind'], HaulPointKind.excavation),
    lat: asDouble(j['lat']),
    lng: asDouble(j['lng']),
    volume: asDouble(j['volume']),
    feePerM3: asDouble(j['feePerM3']),
    needM3: asDouble(j['needM3']),
    material: asString(j['material']),
    demo: asBool(j['demo']),
  );
}
