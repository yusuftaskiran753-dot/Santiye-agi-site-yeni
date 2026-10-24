/// Yayından önce doldurulacak bütün ayarlar bu dosyada.
///
/// Adım adım kurulum için YAYIN_REHBERI.md dosyasına bakın.
library;

/// Giriş yöntemi.
///
/// * [anonymous]: Kullanıcı hiçbir şey doğrulamadan, profilini doldurup
///   hemen başlar. SMS altyapısı gerekmez, ücretsizdir.
/// * [phone]: Telefon numarasına SMS kodu gelir. Profilde "Telefon
///   doğrulandı" rozeti çıkar, güven artar. Supabase panelinde bir SMS
///   sağlayıcısı (Twilio, Vonage, MessageBird) bağlamanız gerekir.
enum AuthMode { anonymous, phone }

class AppConfig {
  const AppConfig._();

  static const String appName = 'Şantiye Ağı';
  static const String version = '2.1.2';

  // ───────────── Sunucu (Supabase) ─────────────
  // Boş bırakılırsa uygulama "Demo modu"nda çalışır: her şey yalnızca bu
  // cihazda saklanır, örnek firmalar teklif ve taleplerinizi otomatik yanıtlar.
  // Gerçek yayın için Supabase projenizin adresini ve "publishable" (anon)
  // anahtarını yazın (Supabase → Project Settings → API).

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: '',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static bool get usesDotNet => apiBaseUrl.isNotEmpty;
  static const bool pushEnabled = bool.fromEnvironment(
    'PUSH_ENABLED',
    defaultValue: false,
  );
  static bool get isLive =>
      usesDotNet || (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty);

  // .NET telefon akışı geliştirme ortamında test koduyla çalışır.
  // Canlı SMS sağlayıcısı müşteri kararı ve sunucu yapılandırması gerektirir.
  static const AuthMode authMode = apiBaseUrl != ''
      ? AuthMode.phone
      : AuthMode.anonymous;

  // ───────────── Yasal bilgiler ─────────────
  // legal/ klasöründeki şablonları kendi bilgilerinizle doldurup ücretsiz
  // bir sayfaya (ör. GitHub Pages, Google Sites) koyun ve adreslerini yazın.
  // Apple ve Google bu bağlantıları zorunlu tutar.

  /// Hizmeti sunan kişinin adı (Kullanım Koşulları'nda "işletici").
  static const String operatorName = String.fromEnvironment(
    'OPERATOR_NAME',
    defaultValue: '',
  );
  static const String termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: '',
  );
  static const String privacyUrl = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: '',
  );
  static const String kvkkUrl = String.fromEnvironment(
    'KVKK_URL',
    defaultValue: '',
  );

  /// Google Play, uygulama dışından da hesap silme talebi için bir web adresi ister.
  static const String accountDeletionUrl = String.fromEnvironment(
    'ACCOUNT_DELETION_URL',
    defaultValue: '',
  );
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: '',
  );

  // ───────────── Mağaza ürünleri ─────────────
  // Google Play Console ve App Store Connect'te BİREBİR bu kimliklerle tanımlayın.
  // Sunucudaki doğrulama fonksiyonundaki (supabase/functions/verify-purchase)
  // ürün listesiyle de aynı olmalıdır.

  static const String premiumMonthlyId = 'santiye_premium_aylik';
  static const String premiumYearlyId = 'santiye_premium_yillik';

  /// Kredi paketleri: ürün kimliği → kredi adedi.
  static const Map<String, int> creditPacks = {
    'santiye_kredi_5': 5,
    'santiye_kredi_15': 15,
    'santiye_kredi_40': 40,
  };

  /// Mağazaya ulaşılamadığında gösterilecek tahmini fiyatlar.
  static const String fallbackMonthlyPrice = '₺199,00';
  static const String fallbackYearlyPrice = '₺1.599,99';
  static const Map<String, String> fallbackCreditPrices = {
    'santiye_kredi_5': '₺99,99',
    'santiye_kredi_15': '₺149,00',
    'santiye_kredi_40': '₺419,99',
  };

  // ───────────── Kotalar (Demo modu için) ─────────────
  // Canlı modda bu değerler sunucudaki app_settings tablosundan okunur;
  // uygulamayı güncellemeden panelden değiştirebilirsiniz.

  static const int freeMonthlyUnlocks = 5;
  static const int freeActiveListings = 5;
  static const int boostDayCost = 1;
  static const int boostWeekCost = 5;

  /// Örnek ilanlar başlangıçta gösterilsin mi? Gerçek ilanlar çoğalınca
  /// false yapabilirsiniz (kullanıcı Profil'den yine açıp kapatabilir).
  // Demo açılışında örnek ilanlar görünür; canlı bağlantıda varsayılan kapalıdır.
  // Kullanıcının Profil'deki tercihi korunur. Dart define ile geçersiz kılınabilir.
  static const bool showSamplesByDefault = bool.fromEnvironment(
    'SHOW_SAMPLE_LISTINGS',
    defaultValue: apiBaseUrl == '' && (supabaseUrl == '' || supabaseKey == ''),
  );

  // ───────────── Diğer ─────────────

  /// Uygulama kimliği; harita sunucusuna User-Agent olarak gönderilir.
  static const String packageName = 'com.santiyeagi.app';

  /// Harita karo adresi. OpenStreetMap'in ücretsiz sunucusu yoğun ticari
  /// kullanıma izin vermez; yayında MapTiler, Stadia vb. adresini yazın.
  static const String tileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Haritanın köşesinde gösterilen kaynak notu (sağlayıcı lisansı gereği zorunlu).
  /// MapTiler kullanırsanız: '© MapTiler © OpenStreetMap katkıda bulunanlar'.
  static const String mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap katkıda bulunanlar',
  );

  /// Malzeme "teslim dahil" tahmini için birim başına km nakliye bedeli (₺).
  static const double transportPerUnitKm = 4.0;
}
