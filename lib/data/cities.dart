import 'package:latlong2/latlong.dart';

/// Türkiye'nin 81 il merkezi (yaklaşık koordinatlar).
const Map<String, LatLng> kCities = {
  'Adana': LatLng(37.00, 35.32),
  'Adıyaman': LatLng(37.76, 38.28),
  'Afyonkarahisar': LatLng(38.76, 30.54),
  'Ağrı': LatLng(39.72, 43.05),
  'Aksaray': LatLng(38.37, 34.03),
  'Amasya': LatLng(40.65, 35.83),
  'Ankara': LatLng(39.93, 32.86),
  'Antalya': LatLng(36.90, 30.71),
  'Ardahan': LatLng(41.11, 42.70),
  'Artvin': LatLng(41.18, 41.82),
  'Aydın': LatLng(37.85, 27.84),
  'Balıkesir': LatLng(39.65, 27.88),
  'Bartın': LatLng(41.64, 32.34),
  'Batman': LatLng(37.88, 41.13),
  'Bayburt': LatLng(40.26, 40.23),
  'Bilecik': LatLng(40.14, 29.98),
  'Bingöl': LatLng(38.88, 40.50),
  'Bitlis': LatLng(38.40, 42.11),
  'Bolu': LatLng(40.74, 31.61),
  'Burdur': LatLng(37.72, 30.29),
  'Bursa': LatLng(40.19, 29.06),
  'Çanakkale': LatLng(40.15, 26.41),
  'Çankırı': LatLng(40.60, 33.62),
  'Çorum': LatLng(40.55, 34.96),
  'Denizli': LatLng(37.78, 29.09),
  'Diyarbakır': LatLng(37.91, 40.23),
  'Düzce': LatLng(40.84, 31.16),
  'Edirne': LatLng(41.68, 26.56),
  'Elazığ': LatLng(38.68, 39.22),
  'Erzincan': LatLng(39.75, 39.49),
  'Erzurum': LatLng(39.90, 41.27),
  'Eskişehir': LatLng(39.78, 30.52),
  'Gaziantep': LatLng(37.07, 37.38),
  'Giresun': LatLng(40.91, 38.39),
  'Gümüşhane': LatLng(40.46, 39.48),
  'Hakkari': LatLng(37.58, 43.74),
  'Hatay': LatLng(36.20, 36.16),
  'Iğdır': LatLng(39.92, 44.05),
  'Isparta': LatLng(37.76, 30.55),
  'İstanbul': LatLng(41.01, 28.98),
  'İzmir': LatLng(38.42, 27.14),
  'Kahramanmaraş': LatLng(37.58, 36.94),
  'Karabük': LatLng(41.20, 32.62),
  'Karaman': LatLng(37.18, 33.22),
  'Kars': LatLng(40.60, 43.10),
  'Kastamonu': LatLng(41.38, 33.78),
  'Kayseri': LatLng(38.73, 35.49),
  'Kilis': LatLng(36.72, 37.12),
  'Kırıkkale': LatLng(39.85, 33.51),
  'Kırklareli': LatLng(41.74, 27.23),
  'Kırşehir': LatLng(39.15, 34.17),
  'Kocaeli': LatLng(40.85, 29.88),
  'Konya': LatLng(37.87, 32.49),
  'Kütahya': LatLng(39.42, 29.98),
  'Malatya': LatLng(38.35, 38.31),
  'Manisa': LatLng(38.61, 27.43),
  'Mardin': LatLng(37.31, 40.74),
  'Mersin': LatLng(36.81, 34.64),
  'Muğla': LatLng(37.22, 28.36),
  'Muş': LatLng(38.75, 41.51),
  'Nevşehir': LatLng(38.62, 34.71),
  'Niğde': LatLng(37.97, 34.68),
  'Ordu': LatLng(40.98, 37.88),
  'Osmaniye': LatLng(37.07, 36.25),
  'Rize': LatLng(41.02, 40.52),
  'Sakarya': LatLng(40.76, 30.40),
  'Samsun': LatLng(41.29, 36.33),
  'Siirt': LatLng(37.93, 41.94),
  'Sinop': LatLng(42.03, 35.15),
  'Sivas': LatLng(39.75, 37.02),
  'Şanlıurfa': LatLng(37.16, 38.79),
  'Şırnak': LatLng(37.52, 42.46),
  'Tekirdağ': LatLng(40.98, 27.51),
  'Tokat': LatLng(40.31, 36.55),
  'Trabzon': LatLng(41.00, 39.72),
  'Tunceli': LatLng(39.11, 39.55),
  'Uşak': LatLng(38.68, 29.41),
  'Van': LatLng(38.49, 43.38),
  'Yalova': LatLng(40.65, 29.27),
  'Yozgat': LatLng(39.82, 34.81),
  'Zonguldak': LatLng(41.45, 31.79),
};

/// İl merkezinin koordinatı. Bilinmeyen il adında İstanbul döner (eski
/// davranış; harita merkezi gibi yaklaşık kullanımlar için). Hesaplamalarda
/// yanlış konum kullanmamak için [cityLatLngOrNull] tercih edin.
LatLng cityLatLng(String city) => cityLatLngOrNull(city) ?? kCities['İstanbul']!;

/// İl adını büyük/küçük harf, boşluk ve Türkçe karakter farkını gözetmeden
/// bulur ("  istanbul " → İstanbul). Bilinmiyorsa null.
String? findCity(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (kCities.containsKey(trimmed)) return trimmed;
  final wanted = normalizeTr(trimmed);
  for (final name in kCities.keys) {
    if (normalizeTr(name) == wanted) return name;
  }
  return null;
}

LatLng? cityLatLngOrNull(String city) {
  final name = findCity(city);
  return name == null ? null : kCities[name];
}

final List<String> kCityNames = kCities.keys.toList(growable: false);

/// Türkçe karakterleri sadeleştirerek arama yapar ("istanbul" -> "İstanbul").
String normalizeTr(String s) => s
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');
