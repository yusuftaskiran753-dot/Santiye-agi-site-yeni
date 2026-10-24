import '../models/models.dart';

/// Uygulamayla gelen örnek kayıtlar. Tamamı "Örnek" etiketiyle gösterilir ve
/// Profil → "Örnek ilanlar" anahtarıyla gizlenebilir. Gerçek firmalar değildir.
class DemoData {
  const DemoData._();

  static DateTime _days(int d, [int h = 0]) => DateTime.now().add(Duration(days: d, hours: h));

  static PublicProfile _p(
    String id,
    String name, {
    String company = '',
    UserRole role = UserRole.yukSahibi,
    String city = 'İstanbul',
    double rating = 4.6,
    int count = 20,
    int deals = 30,
    bool verified = true,
    bool companyVerified = false,
    int monthsAgo = 14,
  }) =>
      PublicProfile(
        id: id,
        name: name,
        company: company,
        role: role,
        city: city,
        ratingAvg: rating,
        ratingCount: count,
        dealsCompleted: deals,
        phoneVerified: verified,
        companyVerified: companyVerified,
        createdAt: DateTime.now().subtract(Duration(days: monthsAgo * 30)),
      );

  static final Map<String, PublicProfile> _profiles = {
    for (final p in [
      _p('demo-u1', 'Kemal Arı', company: 'Marmara Demir Ticaret', rating: 4.8, count: 37, companyVerified: true),
      _p('demo-u2', 'Selin Acar', company: 'Anadolu Yapı Market', city: 'Ankara', rating: 4.7, count: 22),
      _p('demo-u3', 'Hakan Uçar', company: 'Körfez Çimento Bayi', city: 'Kocaeli', rating: 4.4, count: 12, verified: false),
      _p('demo-u4', 'Ramazan Öz', company: 'Ova Tarım Kooperatifi', city: 'Konya', rating: 4.9, count: 51, companyVerified: true),
      _p('demo-u5', 'Gizem Tan', company: 'Nilüfer Lojistik', city: 'Bursa', rating: 4.5, count: 18),
      _p('demo-u6', 'Ozan Kılıç', company: 'Akdeniz Meyve', city: 'Mersin', rating: 4.3, count: 9, verified: false),
      _p('demo-u7', 'Murat Şen', company: 'Ege Kazı İnşaat', role: UserRole.muteahhit, city: 'İzmir', rating: 4.8, count: 29),
      _p('demo-u8', 'Ercan Toprak', company: 'Başkent Makine Kiralama', role: UserRole.makineSahibi, city: 'Ankara', rating: 4.9, count: 64, companyVerified: true),
      _p('demo-u9', 'Yusuf Demir', company: 'Örnek Nakliyat', role: UserRole.nakliyeci, city: 'Kocaeli', rating: 4.7, count: 33),
      _p('demo-u10', 'Cengiz Yıldız', company: 'Yıldız Makine', role: UserRole.makineSahibi, rating: 4.8, count: 41),
      _p('demo-u11', 'Levent Er', company: 'Trakya Hafriyat', role: UserRole.makineSahibi, rating: 4.7, count: 26),
      _p('demo-u12', 'Fatih Kurt', company: 'Anadolu Kazı', role: UserRole.makineSahibi, rating: 4.9, count: 58, companyVerified: true),
      _p('demo-u13', 'Nihat Aksoy', company: 'Körfez Asfalt', role: UserRole.tedarikci, city: 'Kocaeli', rating: 4.6, count: 22),
      _p('demo-u14', 'Burcu Çetin', company: 'Boğaziçi Hazır Beton', role: UserRole.tedarikci, rating: 4.7, count: 45, companyVerified: true),
      _p('demo-u15', 'Tuncay Bal', company: 'Kemerburgaz Agrega', role: UserRole.tedarikci, rating: 4.6, count: 31),
      _p('demo-u16', 'Serdar Ay', company: 'Başkent Asfalt', role: UserRole.tedarikci, city: 'Ankara', rating: 4.7, count: 19),
      _p('demo-u17', 'Okan Güler', company: 'Marmara Yol Yapım', role: UserRole.muteahhit, rating: 4.6, count: 15),
      _p('demo-u18', 'Pınar Kaya', company: 'Başkent Altyapı', role: UserRole.muteahhit, city: 'Ankara', rating: 4.8, count: 21),
      _p('demo-w1', 'Mehmet Kaya', role: UserRole.personel, rating: 4.9, count: 38, deals: 46),
      _p('demo-w2', 'Hasan Demir', role: UserRole.personel, city: 'Ankara', rating: 4.8, count: 29, deals: 34),
      _p('demo-w3', 'Ali Yılmaz', role: UserRole.personel, rating: 4.6, count: 22, deals: 27),
      _p('demo-w4', 'Murat Çelik', role: UserRole.personel, city: 'Kocaeli', rating: 4.7, count: 18, deals: 21),
      _p('demo-w5', 'Emre Şahin', role: UserRole.personel, city: 'Bursa', rating: 4.5, count: 31, deals: 52, verified: false),
      _p('demo-w6', 'Osman Arslan', role: UserRole.personel, city: 'Konya', rating: 4.9, count: 14, deals: 19),
    ])
      p.id: p,
  };

  static PublicProfile profile(String id) => _profiles[id] ?? PublicProfile(id: id, name: 'Örnek Firma');

  static bool isDemoId(String id) => id.startsWith('demo-');

  /// Demo modunda iletişim açılınca gösterilen örnek numara.
  static String phoneOf(String userId) {
    final n = userId.hashCode.abs() % 100;
    return '+90555000${n.toString().padLeft(2, '0')}${(n * 7 % 100).toString().padLeft(2, '0')}';
  }

  /// Demo modunda kullanıcının ilanlarına örnek teklif veren taraflar.
  static PublicProfile get sampleCarrier => profile('demo-u9');
  static PublicProfile get sampleCustomer => profile('demo-u7');
  static PublicProfile get sampleWorker => profile('demo-w3');
  static PublicProfile get sampleEmployer => profile('demo-u17');

  static List<Listing> listings(ListingKind kind) => switch (kind) {
        ListingKind.yuk => loads(),
        ListingKind.makine => machines(),
        ListingKind.malzeme => materials(),
        ListingKind.personel => jobs(),
        ListingKind.sicil => workers(),
      };

  static List<Load> loads() {
    Load l(String id, String owner, String from, String to, String cargo, double tons, VehicleType v, double price,
            DateTime date, DateTime created, {String note = ''}) =>
        Load(
          id: id,
          owner: profile(owner),
          fromCity: from,
          toCity: to,
          cargo: cargo,
          tons: tons,
          vehicle: v,
          price: price,
          date: date,
          note: note,
          demo: true,
          createdAt: created,
        );
    return [
      l('demo-L1', 'demo-u1', 'İstanbul', 'Ankara', 'İnşaat demiri', 24, VehicleType.tir, 28500, _days(0, 4), _days(0, -1),
          note: 'Sabah 08.00 yükleme, forklift var.'),
      l('demo-L2', 'demo-u2', 'Ankara', 'İstanbul', 'Paletli seramik', 22, VehicleType.tir, 27000, _days(1), _days(0, -2)),
      l('demo-L3', 'demo-u3', 'Kocaeli', 'İzmir', 'Çimento (torbalı)', 25, VehicleType.tir, 31000, _days(1, 3), _days(0, -3)),
      l('demo-L4', 'demo-u4', 'Konya', 'Ankara', 'Hububat (dökme)', 26, VehicleType.damperli, 17500, _days(0, 6), _days(0, -1)),
      l('demo-L5', 'demo-u5', 'Bursa', 'Eskişehir', 'Otomotiv yan sanayi', 14, VehicleType.tir, 12500, _days(2), _days(0, -5)),
      l('demo-L6', 'demo-u2', 'Eskişehir', 'İstanbul', 'Beyaz eşya', 18, VehicleType.tir, 19800, _days(1, 2), _days(0, -4)),
      l('demo-L7', 'demo-u6', 'Mersin', 'Gaziantep', 'Narenciye', 20, VehicleType.frigo, 21000, _days(0, 8), _days(0, -2)),
      l('demo-L8', 'demo-u1', 'Gaziantep', 'Ankara', 'Tekstil', 16, VehicleType.tir, 26500, _days(2, 1), _days(0, -6)),
      l('demo-L9', 'demo-u7', 'İzmir', 'Manisa', 'Hafriyat toprağı', 30, VehicleType.damperli, 4200, _days(0, 2), _days(0, -1)),
      l('demo-L10', 'demo-u8', 'Ankara', 'Kayseri', 'Ekskavatör (28 ton)', 28, VehicleType.lowbed, 24000, _days(3), _days(0, -8)),
      l('demo-L11', 'demo-u5', 'Kayseri', 'Konya', 'Mobilya', 12, VehicleType.tir, 15500, _days(1, 5), _days(0, -3)),
      l('demo-L12', 'demo-u3', 'Sakarya', 'Bursa', 'Hazır beton katkı', 10, VehicleType.kamyonet, 7800, _days(0, 5), _days(0, -2)),
      l('demo-L13', 'demo-u6', 'Antalya', 'Konya', 'Sera ürünleri', 19, VehicleType.frigo, 18500, _days(1), _days(0, -7)),
      l('demo-L14', 'demo-u15', 'İstanbul', 'Kocaeli', 'Mıcır 15-25', 32, VehicleType.kirkayak, 6200, _days(0, 3), _days(0, -1)),
      l('demo-L15', 'demo-u4', 'Samsun', 'Ankara', 'Fındık (çuval)', 21, VehicleType.tir, 22500, _days(2, 4), _days(0, -9)),
      l('demo-L16', 'demo-u16', 'Ankara', 'Konya', 'Asfalt bitümü', 24, VehicleType.tir, 16800, _days(1, 6), _days(0, -2)),
    ];
  }

  static List<Machine> machines() {
    Machine m(String id, String owner, MachineType t, String model, String cap, String city, double lat, double lng,
            double hourly, double daily, {bool available = true, bool withOp = true}) =>
        Machine(
          id: id,
          owner: profile(owner),
          type: t,
          model: model,
          capacity: cap,
          city: city,
          lat: lat,
          lng: lng,
          hourly: hourly,
          daily: daily,
          available: available,
          withOperator: withOp,
          demo: true,
          createdAt: _days(-3),
        );
    return [
      m('demo-M1', 'demo-u10', MachineType.silindir, 'Hamm 3411', '11 ton', 'İstanbul', 41.06, 28.80, 1400, 10500),
      m('demo-M2', 'demo-u10', MachineType.silindir, 'Bomag BW 213', '13 ton', 'Kocaeli', 40.80, 29.92, 1500, 11000, available: false),
      m('demo-M3', 'demo-u11', MachineType.greyder, 'CAT 140K', '3,7 m bıçak', 'İstanbul', 41.12, 28.65, 2200, 16500),
      m('demo-M4', 'demo-u12', MachineType.ekskavator, 'Komatsu PC300', '30 ton · 1,6 m³', 'İstanbul', 40.98, 29.20, 2600, 19500),
      m('demo-M5', 'demo-u12', MachineType.ekskavator, 'Hidromek HMK 220', '22 ton · 1,2 m³', 'Sakarya', 40.78, 30.38, 2100, 15500),
      m('demo-M6', 'demo-u13', MachineType.finiser, 'Vögele Super 1800', '9 m serme', 'Kocaeli', 40.77, 29.55, 3200, 24000),
      m('demo-M7', 'demo-u10', MachineType.loder, 'Volvo L120H', '3,5 m³ kova', 'Bursa', 40.22, 28.98, 1900, 14000),
      m('demo-M8', 'demo-u11', MachineType.bekoloder, 'JCB 3CX', '1,1 m³ kova', 'İstanbul', 41.03, 28.70, 1100, 8500),
      m('demo-M9', 'demo-u8', MachineType.dozer, 'CAT D6', '20 ton', 'Ankara', 39.98, 32.70, 2700, 20000),
      m('demo-M10', 'demo-u8', MachineType.silindir, 'Dynapac CA2500', '12 ton', 'Ankara', 39.88, 32.95, 1350, 10000),
      m('demo-M11', 'demo-u16', MachineType.finiser, 'Ammann AFT 500', '8 m serme', 'Ankara', 39.95, 32.80, 3000, 22500, available: false),
      m('demo-M12', 'demo-u8', MachineType.greyder, 'Mitsuber MG 330', '3,7 m bıçak', 'Konya', 37.90, 32.55, 1900, 14500),
      m('demo-M13', 'demo-u7', MachineType.ekskavator, 'Volvo EC480', '48 ton · 2,8 m³', 'İzmir', 38.47, 27.20, 3400, 25500),
      m('demo-M14', 'demo-u7', MachineType.silindir, 'Hamm HD 12 (Tandem)', '10 ton', 'İzmir', 38.38, 27.10, 1250, 9500),
      m('demo-M15', 'demo-u12', MachineType.vinc, 'Liebherr LTM 1090', '90 ton', 'İstanbul', 40.92, 29.30, 4500, 34000),
      m('demo-M16', 'demo-u11', MachineType.dozer, 'Komatsu D65', '21 ton', 'Antalya', 36.95, 30.65, 2600, 19000),
    ];
  }

  static List<MaterialListing> materials() {
    MaterialListing x(String id, String owner, MaterialKind k, String product, double price, StockLevel stock,
            String plant, String city, double lat, double lng, int minutesAgo) =>
        MaterialListing(
          id: id,
          owner: profile(owner),
          materialKind: k,
          product: product,
          unit: k.defaultUnit,
          price: price,
          stock: stock,
          plantName: plant,
          city: city,
          lat: lat,
          lng: lng,
          minQty: k == MaterialKind.beton ? 6 : 20,
          demo: true,
          createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
        );
    const b = MaterialKind.beton, a = MaterialKind.agrega, s = MaterialKind.stabilize, f = MaterialKind.asfalt;
    const bol = StockLevel.bol, az = StockLevel.az, yok = StockLevel.yok;
    return [
      x('demo-P1', 'demo-u14', b, 'C25/30', 2950, bol, 'Boğaziçi Hazır Beton', 'İstanbul', 41.08, 28.75, 25),
      x('demo-P2', 'demo-u14', b, 'C30/37', 3150, bol, 'Boğaziçi Hazır Beton', 'İstanbul', 41.08, 28.75, 25),
      x('demo-P3', 'demo-u14', b, 'C35/45', 3400, az, 'Boğaziçi Hazır Beton', 'İstanbul', 41.08, 28.75, 25),
      x('demo-P4', 'demo-u13', b, 'C25/30', 2790, bol, 'Körfez Beton', 'Kocaeli', 40.78, 29.80, 140),
      x('demo-P5', 'demo-u13', b, 'C30/37', 2990, bol, 'Körfez Beton', 'Kocaeli', 40.78, 29.80, 140),
      x('demo-P6', 'demo-u13', b, 'C35/45', 3290, yok, 'Körfez Beton', 'Kocaeli', 40.78, 29.80, 140),
      x('demo-P7', 'demo-u16', b, 'C25/30', 2750, bol, 'Başkent Beton', 'Ankara', 39.97, 32.75, 40),
      x('demo-P8', 'demo-u16', b, 'C30/37', 2960, bol, 'Başkent Beton', 'Ankara', 39.97, 32.75, 40),
      x('demo-P9', 'demo-u15', a, '0-5 Kum', 390, bol, 'Kemerburgaz Agrega', 'İstanbul', 41.17, 28.88, 15),
      x('demo-P10', 'demo-u15', a, '5-12 Mıcır', 420, bol, 'Kemerburgaz Agrega', 'İstanbul', 41.17, 28.88, 15),
      x('demo-P11', 'demo-u15', a, '12-22 Mıcır', 410, az, 'Kemerburgaz Agrega', 'İstanbul', 41.17, 28.88, 15),
      x('demo-P12', 'demo-u13', a, '0-5 Kum', 350, bol, 'Dilovası Kırma Taş', 'Kocaeli', 40.78, 29.53, 200),
      x('demo-P13', 'demo-u13', a, '5-12 Mıcır', 385, bol, 'Dilovası Kırma Taş', 'Kocaeli', 40.78, 29.53, 200),
      x('demo-P14', 'demo-u15', s, 'Plent-miks Temel (PMT)', 360, bol, 'Kemerburgaz Agrega', 'İstanbul', 41.17, 28.88, 15),
      x('demo-P15', 'demo-u15', s, 'Ocak Stabilize', 290, bol, 'Kemerburgaz Agrega', 'İstanbul', 41.17, 28.88, 15),
      x('demo-P16', 'demo-u16', s, 'Ocak Stabilize', 250, bol, 'Gölbaşı Stabilize', 'Ankara', 39.80, 32.80, 95),
      x('demo-P17', 'demo-u13', f, 'Binder', 2580, bol, 'Körfez Asfalt', 'Kocaeli', 40.77, 29.55, 120),
      x('demo-P18', 'demo-u13', f, 'Aşınma', 2790, az, 'Körfez Asfalt', 'Kocaeli', 40.77, 29.55, 120),
      x('demo-P19', 'demo-u16', f, 'Binder', 2520, bol, 'Başkent Asfalt', 'Ankara', 39.95, 32.80, 45),
      x('demo-P20', 'demo-u16', f, 'Aşınma', 2740, bol, 'Başkent Asfalt', 'Ankara', 39.95, 32.80, 45),
    ];
  }

  static List<JobPost> jobs() {
    JobPost j(String id, String owner, String title, WorkerRole role, String city, double wage, String period,
            String duration, List<String> req, DateTime created) =>
        JobPost(
          id: id,
          owner: profile(owner),
          title: title,
          role: role,
          city: city,
          wage: wage,
          wagePeriod: period,
          duration: duration,
          requirements: req,
          demo: true,
          createdAt: created,
        );
    return [
      j('demo-J1', 'demo-u17', 'Asfalt ekibi için silindir operatörü', WorkerRole.silindirOp, 'İstanbul', 2800, 'Günlük',
          '3 ay', ['MYK belgesi', 'G sınıfı ehliyet', 'En az 3 yıl'], _days(0, -3)),
      j('demo-J2', 'demo-u18', 'Otoyol projesi greyder operatörü', WorkerRole.greyderOp, 'Ankara', 65000, 'Aylık', '8 ay',
          ['MYK belgesi', 'G sınıfı ehliyet', 'Konaklama sağlanır'], _days(0, -6)),
      j('demo-J3', 'demo-u12', 'Metro şantiyesi ekskavatör operatörü', WorkerRole.ekskavatorOp, 'İstanbul', 3000,
          'Günlük', '6 ay', ['MYK belgesi', '30 ton üstü deneyim'], _days(-1)),
      j('demo-J4', 'demo-u13', 'Finişer operatörü (gece vardiyası)', WorkerRole.finiserOp, 'Kocaeli', 3200, 'Günlük',
          '2 ay', ['MYK belgesi', 'Vögele deneyimi'], _days(-1, -4)),
      j('demo-J5', 'demo-u11', 'Hafriyat kamyonu şoförü', WorkerRole.tirSoforu, 'İstanbul', 55000, 'Aylık', 'Süresiz',
          ['CE ehliyet', 'SRC-4', 'Psikoteknik'], _days(-2)),
    ];
  }

  static List<WorkerCard> workers() {
    WorkerCard w(String id, String owner, WorkerRole role, String city, int years, List<String> certs,
            {bool available = true, String about = ''}) =>
        WorkerCard(
          id: id,
          owner: profile(owner),
          role: role,
          city: city,
          years: years,
          certificates: certs,
          available: available,
          about: about,
          demo: true,
          createdAt: _days(-10),
        );
    return [
      w('demo-K1', 'demo-w1', WorkerRole.silindirOp, 'İstanbul', 12, ['MYK Seviye 3', 'G sınıfı'],
          about: 'Asfalt ve stabilize sıkıştırmada deneyimli. Gece vardiyasına uygun.'),
      w('demo-K2', 'demo-w2', WorkerRole.greyderOp, 'Ankara', 15, ['MYK Seviye 4', 'G sınıfı'],
          about: 'Şev ve kot işlerinde uzman.'),
      w('demo-K3', 'demo-w3', WorkerRole.ekskavatorOp, 'İstanbul', 8, ['MYK Seviye 3', 'G sınıfı'], available: false),
      w('demo-K4', 'demo-w4', WorkerRole.finiserOp, 'Kocaeli', 10, ['MYK Seviye 3']),
      w('demo-K5', 'demo-w5', WorkerRole.tirSoforu, 'Bursa', 6, ['CE ehliyet', 'SRC-4', 'Psikoteknik']),
      w('demo-K6', 'demo-w6', WorkerRole.ustabasi, 'Konya', 20, ['İSG Eğitimi', 'Ustalık belgesi']),
    ];
  }

  static List<Rating> ratingsFor(String userId) {
    if (!isDemoId(userId)) return const [];
    const comments = [
      ('Marmara Yol Yapım', 5, 'Zamanında geldi, işini titiz yaptı.'),
      ('Anadolu Kazı', 5, 'Ödeme ve iletişim sorunsuz.'),
      ('Körfez Asfalt', 4, 'Genel olarak memnun kaldık.'),
    ];
    return [
      for (var i = 0; i < comments.length; i++)
        Rating(
          id: '$userId-r$i',
          dealId: 'demo-deal-$i',
          fromId: 'demo-x$i',
          toId: userId,
          fromName: comments[i].$1,
          stars: comments[i].$2,
          comment: comments[i].$3,
          createdAt: _days(-(i + 1) * 9),
        ),
    ];
  }

  static List<HaulPoint> haulPoints() => [
        HaulPoint(demo: true, id: 'H1', name: 'Kartal Konut Projesi', kind: HaulPointKind.excavation, lat: 40.895, lng: 29.190, volume: 18000, needM3: 2500),
        HaulPoint(demo: true, id: 'H2', name: 'Başakşehir Metro İstasyonu', kind: HaulPointKind.excavation, lat: 41.093, lng: 28.802, volume: 26000),
        HaulPoint(demo: true, id: 'H3', name: 'Ümraniye AVM Temeli', kind: HaulPointKind.excavation, lat: 41.025, lng: 29.120, volume: 12000, needM3: 1500),
        HaulPoint(demo: true, id: 'H4', name: 'Kemerburgaz Döküm Sahası', kind: HaulPointKind.dump, lat: 41.160, lng: 28.920, volume: 40000, feePerM3: 85),
        HaulPoint(demo: true, id: 'H5', name: 'Ömerli Döküm Sahası', kind: HaulPointKind.dump, lat: 41.060, lng: 29.370, volume: 15000, feePerM3: 95),
        HaulPoint(demo: true, id: 'H6', name: 'Tuzla Maden Rehabilitasyon', kind: HaulPointKind.dump, lat: 40.860, lng: 29.330, volume: 12000, feePerM3: 70),
        HaulPoint(demo: true, id: 'H7', name: 'Ömerli Taş Ocağı', kind: HaulPointKind.source, lat: 41.075, lng: 29.350, volume: 50000, feePerM3: 210, material: 'Stabilize'),
        HaulPoint(demo: true, id: 'H8', name: 'Kemerburgaz Agrega', kind: HaulPointKind.source, lat: 41.170, lng: 28.880, volume: 80000, feePerM3: 190, material: 'Stabilize'),
      ];
}
