# Google Play ve App Store ödeme kurulumu

Güncelleme: 15 Ekim 2026. Bu belge geliştirici ve sunucu yöneticisi içindir.

## Teslim edilen kod ne yapıyor?

- Mobil uygulama, satın alma bilgisini oturum açmış kullanıcının kimliğiyle `.NET` API'ye gönderir. API ürünü ve işlemi doğrudan ilgili mağazaya sorar.
- Mağaza doğrulaması başarılı olmadan kredi veya Premium hakkı verilmez. Mobilin gönderdiği fiyat, gün sayısı ve kredi miktarı yetkili veri kabul edilmez.
- Aynı işlemin aynı anda veya tekrar gönderilmesi ikinci kez kredi vermez. Mağaza işlemi başka uygulama hesabına aktarılamaz; doğrulanmış hesap eşleştirmesi zorunludur.
- Google Play kredileri sunucuda kalıcı kayda alındıktan sonra tüketilir; yeni abonelikler aynı aşamadan sonra onaylanır. Mağaza onayı geçici olarak başarısız olursa tekrar deneme kredi eklemez.
- Aboneliğin yenilenmesini iptal etmek, ödenmiş dönemi hemen kaldırmaz. Erişim mağazanın güncel bitiş tarihine kadar sürer. Süre sonu, bekletme ve iptal/geri alma durumları yeniden sorgulanır.
- Apple'da ilk satın alma makbuzunun eski bitiş tarihine güvenilmez: aynı abonelik zincirinin güncel yenilemesi ve varsa mağazanın tanıdığı ek ödeme süresi sorgulanır.
- İade edilen krediler geri alınır. Kullanılmış kredilerin iadesinde kalan bakiye sıfıra kadar düşer; eksik tutar borç kaydı olur ve sonraki kredi alımından mahsup edilir. Bakiyenin sıfıra düşmesi iadeyi unutmaya yol açmaz.
- Google'ın miktar bazlı kısmi iadeleri de izlenir. Mağaza sorgusu ve iade bildirimi aynı iadeyi bildirirse iki kez kesinti yapılmaz.
- Apple yanıtlarında `ES256` imzası ve sertifika zinciri, kurulum sırasında verilen Apple güven kökleriyle doğrulanır. İmzasız istemci verisi veya bildirimin kendi sunduğu kök sertifika kabul edilmez.
- Satın alma referansları veritabanında ASP.NET Data Protection ile şifrelenir. Hesap silinince mağaza sorgulama referansları temizlenir; aynı işlemin tekrar harcanmasını önleyen özet kayıt kalır.

**Doğrulama durumu:** mağaza yanıt örnekleriyle otomatik testler ve yerel PostgreSQL üzerinde gerçek işlem/idempotency/iade testleri vardır. Müşterinin gerçek Google/Apple erişim anahtarları, ürünleri ve cihazlarıyla canlı veya mağaza sandbox satın alımı henüz yapılmadı. Bu kontrollerin başarılı olduğu iddia edilmez. Yapılandırılmamış ödeme bağlantısı `CONFIG` hatası verir; test adı altında canlı hak tanımlamaz.

## 1. Ürünleri mağazalarda hazırlama

Flutter `lib/config.dart` ve sunucu `Billing/StoreCatalog` aynı kimlikleri kullanır:

| Ürün kimliği | Tür | Hak |
|---|---|---|
| `santiye_premium_aylik` | Otomatik yenilenen abonelik | Mağazanın bildirdiği bitiş tarihine kadar Premium |
| `santiye_premium_yillik` | Otomatik yenilenen abonelik | Mağazanın bildirdiği bitiş tarihine kadar Premium |
| `santiye_kredi_5` | Tüketilebilir uygulama içi ürün | Birim başına 5 kredi |
| `santiye_kredi_15` | Tüketilebilir uygulama içi ürün | Birim başına 15 kredi |
| `santiye_kredi_40` | Tüketilebilir uygulama içi ürün | Birim başına 40 kredi |

Gerçek paket/bundle kimlikleri mağaza kaydı ve imzalı uygulamayla birebir aynı olmalıdır. Test uygulamasının farklı paket adı kullanılması gerçek mağaza ürünlerini doğrulamaz. Fiyatları mağaza yönetir; uygulama mağazanın yerel fiyatını gösterir.

Google Play'de aylık ve yıllık abonelik planlarını, aktif temel planları ve test kullanıcılarını hazırlayın. App Store Connect'te abonelik grubunu, süreleri ve tüketilebilir kredi ürünlerini hazırlayın. Ücretli uygulama sözleşmeleri ve gerekli ödeme/vergi hesap bilgileri mağazada tamamlanmış olmalıdır. Mağazanın ekranları değişebildiği için adımlar [Google Play entegrasyon rehberi](https://developer.android.com/google/play/billing/integrate) ve [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) üzerinden kontrol edilir.

## 2. Google Play servis hesabı

1. Google Cloud projesinde Google Play Android Developer API'yi etkinleştirin.
2. Ödeme doğrulaması için bir servis hesabı oluşturun. Servis hesabını Play Console'da ilgili uygulamaya davet edip sipariş/abonelik görüntüleme ve işlemleri onaylama/tüketme için gereken izinleri verin. Bu hesap SMS veya Firebase anahtarı değildir.
3. Servis hesabının JSON anahtar dosyasını sunucuda web sitesinin dışındaki, yalnız uygulama havuzu ve yöneticinin okuyabildiği bir klasöre koyun. Örnek: `C:\SantiyeSecrets\google-play.json`.
4. Dış yapılandırmada `Billing.GooglePackageName` ve `Billing.GoogleServiceAccountFile` değerlerini doldurun. JSON içeriğini Git'e veya mobil uygulamaya koymayın.

Sunucu servis hesabının özel anahtarıyla OAuth erişim jetonu üretir; yalnız resmî Google alan adlarına HTTPS ile bağlanır. Satın alma jetonunu içeren HTTP adresleri uygulamanın HTTP istemcisi günlüklerine yazdırılmaz.

## 3. App Store sunucu anahtarı ve Apple güven kökleri

1. App Store Connect'te uygulama içi satın almalar için sunucu API anahtarı oluşturun; Issuer ID, Key ID ve indirilen `.p8` dosyasını alın.
2. `.p8` dosyasını web sitesinin dışına koyun. Örnek: `C:\SantiyeSecrets\apple-iap.p8`.
3. [Apple PKI sayfasından](https://www.apple.com/certificateauthority/) resmî Apple kök sertifikalarını indirin. App Store imza zincirini doğrulayan Apple Root CA G3 sertifikası güncel zincir için gereklidir; Apple'ın yayımladığı diğer geçerli kökler ihtiyaç halinde diziye eklenebilir. Bir bildirimin içinden gelen sertifikayı kök olarak eklemeyin.
4. Örnek public sertifika yolu: `C:\SantiyeSecrets\AppleRootCA-G3.cer`. Bunlar açık kök sertifikalardır; `.p8` dosyası ise gizlidir.
5. Bundle ID, uygulamanın sayısal App Store ID'si, Issuer ID, Key ID, özel anahtar dosyası ve kök sertifika yollarını yapılandırın.

Sertifika iptal durumu çevrim içi kontrol edilir. Sunucunun Apple API'lerine ve sertifika iptal adreslerine çıkışına izin verilmelidir. Geçici sertifika kontrol kesintisi satın alımı sahte kabul edip silmez; sunucu geçici hata döndürür ve tekrar denenir.

## 4. Yapılandırma örneği

Bu örnek gizli anahtar içermez. Gerçek değerler sunucudaki dış yapılandırma dosyasında veya IIS ortam değişkenlerinde bulunur. Programın kullandığı dış dosya `SANTIYE_CONFIG_FILE` ile seçilir; yayın klasörüne veya kaynak depoya özel anahtar eklemeyin.

```json
{
  "Billing": {
    "Enabled": false,
    "AllowSandbox": false,
    "GooglePackageName": "MAGAZADAKI_ANDROID_PAKET_KIMLIGI",
    "GoogleServiceAccountFile": "C:\\SantiyeSecrets\\google-play.json",
    "AppleBundleId": "MAGAZADAKI_IOS_BUNDLE_KIMLIGI",
    "AppleAppId": 0,
    "AppleIssuerId": "APP_STORE_CONNECT_ISSUER_ID",
    "AppleKeyId": "APP_STORE_CONNECT_KEY_ID",
    "ApplePrivateKeyFile": "C:\\SantiyeSecrets\\apple-iap.p8",
    "AppleRootCertificateFiles": ["C:\\SantiyeSecrets\\AppleRootCA-G3.cer"],
    "GooglePushAudience": "https://api.ornek.com/api/v1/billing/google/notifications",
    "GooglePushServiceAccountEmail": "PLAY_PUBSUB_PUSH_SERVIS_HESABI"
  }
}
```

Hazırlık tamamlanınca `Enabled=true` yapılır. Ayrı test ortamında `AllowSandbox=true` kullanılır; canlı sistemde varsayılanı `false`tur. Sandbox satın alımlarını canlı kullanıcı haklarıyla karıştırmamak için ayrı test veritabanı önerilir. Apple ve Google yapılandırmaları kendi platformları çağrıldığında denetlenir; yalnız Android ile başlamak iOS anahtarını sahte değerlerle doldurmayı gerektirmez.

**Data Protection:** Dış JSON dosyasındaki `DataProtection.KeysPath` (ortam değişkeni kullanılırsa `DataProtection__KeysPath`) sunucuda kalıcı, web dışı bir klasöre verilmelidir. IIS kurulum betiği bunu `C:\ProgramData\SantiyeAgi\keys` olarak hazırlar. Bu anahtar halkasını ve erişim izinlerini yedekleyin. Windows'ta anahtarlar makine korumasıyla şifrelenir; başka makineye taşıma ayrıca planlanır. Anahtarları silmek veya yeni yayın sırasında klasörü değiştirmek, kayıtlı satın alma referanslarının okunamamasına ve eşitlemenin durmasına yol açar. Aynı dosyaları tekrar yayınlamak bu anahtarları yenilememelidir.

## 5. Sunucu bildirimleri

### Google Play RTDN

1. Google Cloud Pub/Sub konusu oluşturun ve Play Console'da uygulamanın gerçek zamanlı geliştirici bildirimleri için seçin.
2. Google Play'in konuya yayın yapabilmesi için resmî [RTDN kurulum rehberindeki](https://developer.android.com/google/play/billing/getting-ready#configure-rtdn) izinleri verin.
3. Push aboneliğinin adresini `https://API_ADRESI/api/v1/billing/google/notifications` yapın.
4. Push isteği için kimlik doğrulamasını etkinleştirin. Ayrı bir Google servis hesabı seçin ve hedef kitleyi (`audience`) sunucu ayarındaki `GooglePushAudience` ile aynı yapın. Hesabın e-posta adresini `GooglePushServiceAccountEmail` alanına yazın. Bu kimlik, Play API'ye erişen servis hesabıyla aynı olmak zorunda değildir.
5. Sunucu Google'ın imzasını, süresini, hedef kitleyi, doğrulanmış e-posta adresini ve uygulama paket adını denetler. Gelen bildirim tek başına kredi veya abonelik tanımlamaz; işlem Google API'den yeniden sorgulanır.

### App Store Server Notifications V2

1. App Store Connect'te Server Notifications adresini `https://API_ADRESI/api/v1/billing/apple/notifications` olarak ayarlayın ve V2 kullanın.
2. Sandbox test adresini ayrı test sunucusuna verin. Test bildirimi gönderin ve mağazadan sonucunu kontrol edin.
3. Sunucu bildirimin Apple imzasını, uygulama kimliğini, sayısal App Store ID'sini ve ortamını kontrol eder; kayıtlı işlem için güncel mağaza durumunu yeniden sorgular.

API'de henüz bu uygulama hesabına bağlanmamış bir satın alma için gelen bildirim kullanıcıya otomatik sahiplik vermez. İlk bağlama mobilde oturum açmış kullanıcının satın alma/geri yükleme işlemiyle yapılır. Kullanıcı mağazadan uygulama dışında abonelik başlatır veya yepyeni Google satın alma jetonuna geçerse uygulamada **Satın alımları geri yükle** işlemi gerekir. Bilinen aboneliğin normal yenilemeleri sunucudan izlenir.

## 6. Eşitleme, iadeler ve IIS

- Bildirimlere ek olarak sunucu, zamanı gelen kayıtlı abonelikleri yaklaşık 15 dakikada bir, kredi işlemlerini yaklaşık 12 saatte bir mağazadan kontrol eder. Bir döngüde 40 kayıt işlenir; toplam kayıt sayısı ve mağaza gecikmesi daha uzun kuyruk oluşturabilir. Bu aralıklar anlık iade garantisi değildir.
- Google iade listesi saatlik olarak son 30 günlük mağaza penceresinden tekrar okunur. Kalıcı olay özetleri tekrarları ayıklar. Son 30 günden uzun bir sunucu kesintisi için ayrıca mağaza raporlarıyla mutabakat gerekir.
- Apple kredi iadeleri bildirim ve kayıtlı işlemin yeniden sorgulanmasıyla yansır. Sunucunun çalışmadığı dönemde kaçırılan Apple bildirimleri için App Store'un [bildirim geçmişi API'si](https://developer.apple.com/documentation/appstoreserverapi/get-notification-history) ve operatör incelemesi kullanılmalıdır; tüm geçmişi otomatik içe alan bir görev bu teslimde yoktur.
- `POST /api/v1/billing/sync`, oturum açmış kullanıcının en son 20 abonelik zincirini isteğe bağlı yeniden sorgular ve güncel bakiye/abonelik tarihini döndürür. Mağaza cevabındaki süre kısalması mevcut veritabanına uygulanabilir.
- IIS uygulama havuzu düzenli olarak durursa arka plan eşitleme çalışmaz. Havuzun boşta kapanma süresini kapatın (`Idle Time-out=0`), uygun olduğunda `AlwaysRunning`/site ön yükleme ve IIS Application Initialization kullanın. Süreci izlemek ve sağlık kontrolü yapmak sunucu işletiminin parçasıdır.
- HTTPS zorunludur. PostgreSQL'i internete açmak ödeme API'sinin çalışması için gerekli değildir. IIS erişim günlüklerinde ve proxy'lerde istek gövdesi veya `Authorization` başlığı kaydedilmemelidir.

## 7. Gerçek mağaza testi sırasında kabul kontrolü

1. Mağazadan kredi satın alın; bakiye doğru miktarda artsın. Aynı işlemi tekrar gönderince bakiye ikinci kez artmasın.
2. Satın alma sonrası ağ kesilsin ve uygulama kapansın; yeniden açıldığında aynı hesapta işlem tamamlanabilsin.
3. Aylık ve yıllık planları, yenilemeyi ve geri yüklemeyi test edin. Yenilemeyi kapatınca kalan dönem devam etsin, süresi dolunca Premium kapansın.
4. Tam ve mümkünse kısmi iade yapın. Harcanmamış kredi geri alınsın; kullanılmış kısım için borç oluşsun ve sonraki satın almada mahsup edilsin.
5. Başka uygulama hesabında aynı makbuzla hak alınamasın. Hesap silinip yeniden açıldığında aynı satın alma ikinci kez harcanamasın.
6. Mağaza bildirimlerinin kimlik doğrulaması doğru çalışsın; sahte imzalı Google/Apple istekleri reddedilsin.
7. Sunucuyu ve IIS havuzunu yeniden başlatın; kalıcı Data Protection anahtarlarıyla kayıtlı işlemler sorgulanabilsin.

Resmî referanslar: [Google abonelik yaşam döngüsü](https://developer.android.com/google/play/billing/lifecycle/subscriptions), [Google products kaynağı](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products), [Google voided purchases](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.voidedpurchases/list), [Apple işlem sorgusu](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info), [Apple abonelik durumları](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses), [Apple imza doğrulama referansı](https://github.com/apple/app-store-server-library-python/blob/main/appstoreserverlibrary/signed_data_verifier.py).

## 21 Ekim 2026 backend kontrolü

Güncel uygulama: `com.yusuftaskiran.santiyeagi.pro`, Apple ID `6824034438`. Ürün kimlikleri aynıdır. Ayrıntılı canlı durum, eksikler ve Sandbox ayrımı: [BACKEND_IOS_YAYIN_SONUC_2026-10-21.md](BACKEND_IOS_YAYIN_SONUC_2026-10-21.md).

Apple ayarları tamamlandığında yeni paketin `deploy/test-apple-notifications.ps1` aracı, resmî TEST bildiriminin teslim sonucunu sır içermeyen JSON ile kontrol eder. Bu bir satın alma testi değildir. Canlı Apple callback şu an CONFIG/503; hazır sayılmaz. Mevcut inceleme hesabı doğrulanmış telefon taşımıyor ve satın alma kodu PhoneVerified ister; SMS kapalıyken bu şart kendiliğinden kalkmaz. Canlıda Sandbox açılmadı, ayrı ortam henüz kurulmadı. Bu turda gerçek Apple anahtarı veya dış ayarlar değiştirilmedi.
