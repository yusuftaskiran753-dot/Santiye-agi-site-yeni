# iOS backend yayın kontrol raporu — 21 Ekim 2026

**Sonuç: Apple satın alma bağlantısı henüz canlıya hazır değil.** Mac'in hazırladığı üretim push yetkili 2.1.2+11 IPA ve TestFlight yüklemesinin bekletilmesi korunur. SMS açılmadı. Canlı sunucu ayarları değiştirilmedi; doğrulanmamış makbuzla Premium/kredi verilmedi.

## 1. Hazır ve bu turda doğrulananlar

- `main`, temiz yerel çalışma ağacı korunarak `605b05f` → `e3013f2` fast-forward ile güncellendi; Mac'in iOS/provisioning/tasarım/fiyat değişiklikleri korundu.
- Canlı `GET https://45.59.70.198/health/ready`: **200 / ready**.
- Canlı `/api/v1/auth/options`: **200**, `phone_verification_required=false`, `password_login_enabled=true`.
- Korumalı yerel test hesabı bilgisi yalnız bellekte kullanılarak parolalı giriş **200**, oturumlu profil okuma **200** ve `/ai/options` **200 / enabled=true** doğrulandı. Kullanıcı adı/parola/oturum anahtarı rapora veya loga yazılmadı. Giriş bir oturum oluşturur; test hesabı yeniden oluşturulmadı veya hakları değiştirilmedi.
- Canlı `POST /billing/verify` ve `/billing/sync` oturumsuz istekleri **401 / AUTH_REQUIRED** ile reddediyor. Bu kontrol satın alma başarısı anlamına gelmez.
- Firebase konsolunda **santiye-agi**, iOS uygulaması **com.yusuftaskiran.santiyeagi.pro**, **FCM v1 Enabled**, üretim APNs anahtarı ve **D49KUWV4VG** ekibi görüldü. Development APNs anahtarı yok; bu, Mac'in production yetkili IPA'sının teslim testinin geçtiği anlamına gelmez.
- Yerel korumalı FCM servis hesabının `project_id=santiye-agi` ve OAuth alan adı, Android Firebase yapılandırmasının proje ID/numarası (`615764719930`) ile tutarlı. **Canlı Windows ayarındaki seçili dosya doğrudan okunamadı; yerel dosya canlı dosya sayılmadı.**
- Push API'si oturumlu iOS cihaz kaydını kabul eden kod yoluna sahip; FCM gönderimi yapılandırılmış projenin HTTP v1 adresine gider. Anahtar/proje uyuşmazlığına karşı kontrol mevcut. Gerçek iPhone kurulum tokeni gönderilmedi ve bildirim teslimi iddia edilmedi.
- Apple JWS ES256/zincir/sertifika iptal denetimi korunuyor. Resmî Apple PKI'dan Root CA G3 indirildi: SHA-256 `63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179`, subject/issuer Apple Root CA - G3, bitiş 2039-04-30. Bu açık sertifika yerel teslim klasöründe; sunucuya kurulmuş sayılmaz.

## 2. Apple bağlantısındaki somut eksikler

Canlı `POST /api/v1/billing/apple/notifications` (geçersiz, sır içermeyen kontrol gövdesi) **503 / CONFIG** döndü. Bu cevap, satın alma/bildirim yapılandırmasının hazır olmadığını gösterir; hangi alanın eksik olduğunu tek başına söylemez. Etkin `Billing` ayarları görülmeden Enabled, App ID veya özel anahtar yolu hakkında tahmin yapılmadı.

Beklenen gerçek değerler:

- `AppleBundleId=com.yusuftaskiran.santiyeagi.pro`
- `AppleAppId=6824034438`
- Ürünler: `santiye_premium_aylik`, `santiye_premium_yillik`, `santiye_kredi_5`, `santiye_kredi_15`, `santiye_kredi_40`; haklar ve kimlikler değiştirilmedi. Mağaza fiyatları hak doğrulamasının kaynağı değildir.

Eksik/teyit bekleyenler:

1. Mac'teki `AuthKey_L3FC8F5LZ7.p8` dosyasının **App Store Connect → Integrations → In-App Purchase** bölümünden üretildiğinin teyidi. Dosya adı ve P-256 özel anahtar yapısı kullanım amacını kanıtlamaz. APNs anahtarı kullanılamaz.
2. Doğru **Issuer ID** ve bu anahtarla eşleşen **Key ID**. Issuer ID Apple Team ID değildir. Bu Windows çalışma alanında görevdeki yeni dosya yok; bulunan farklı `.p8` kullanılmadı.
3. Anahtarın güvenli Windows dizinine aktarılması, uygulama havuzunun gerekli okuma izni ve `ApplePrivateKeyFile` yolu. Özel anahtar mobil pakete veya web köküne konmaz.
4. Güven kökleri ve `AppleRootCertificateFiles`, dış dosya yolu ve olası ortam değişkeni önceliği. Google Billing, SMS, Firebase, Gemini ve Data Protection ayarları korunmalı. Bilinmeyen alanları sahte değerle doldurup Enabled açılmadı.

### Telefon doğrulamasıyla ilgili ayrı yayın engeli

İnceleme hesabının profilinde `phone_verified=false` görüldü. Mevcut `StoreBillingService.Apply`, satın alma haklarını tanımlarken **PhoneVerified** istiyor; genel SMS zorunluluğunun kapalı olması bu kontrolü kaldırmıyor. Dolayısıyla girişin çalışması satın alım hakkı verilebildiğini kanıtlamaz. Bu kural bu turda gevşetilmedi ve hesap doğrulanmış işaretlenmedi. Mevcut doğrulanmış bir hesap/gerçek doğrulama olmadan satın alma kabulü kapanmış sayılamaz. SMS müşteri talebiyle kapalı kalır; Production doğrulama atlatması eklenmedi.

## 3. TestFlight / Sandbox izolasyon planı

`AllowSandbox=true` mevcut kodda sandbox işlemini aynı kullanıcı kredi/Premium tablosuna uygulamaya izin verir; kendiliğinden ikinci bakiye veya ayrı test alanı oluşturmaz. Bu yüzden canlı ayarda açılmadı.

Plan: ayrı IIS uygulaması/havuzu, **ayrı veritabanı**, ayrı dış ayar ve Data Protection dizini, farklı JWT issuer/audience/signing key, yalnız test profilleri. Canlı hesaplar/bakiyeler/oturumlar kopyalanmaz; test bildirimleri gerçek kullanıcılara gitmez. Üretim API'sinde `AllowSandbox=false` kalır; yalnız izole API'de `true` olur. Test profilleri ve doğrulama fixture'ları gerçek kullanıcı verisi içermez; Production'a sabit doğrulama kodu eklenmez.

Aynı HTTPS site altında `/sandbox` IIS alt uygulaması kullanılabilir. **Henüz oluşturulmamış öneri adresleri:**

- Mobil test API: `https://45.59.70.198/sandbox`
- Apple Sandbox Notifications: `https://45.59.70.198/sandbox/api/v1/billing/apple/notifications`
- Production adresi mevcut `https://45.59.70.198/api/v1/billing/apple/notifications` olarak kalır.

Bu URL'ler henüz çalışır teslim adresi değildir. Ayrı ortam kurulup doğrulanmadan Mac'teki alan değiştirilmemeli. Şu an aynı production API'ye bakan IPA izole Sandbox'a kendiliğinden geçmez; TestFlight satın alma denemesi için izole API tanımıyla yeni build hazırlanması gerekir. Bu turda ne ayrı IIS/DB kuruldu ne de Mac IPA yeniden üretildi.

## 4. Eklenen güvenli araçlar

### Mevcut sunucuyu salt okunur inceleme

`backend/deploy/inspect-ios-readiness.ps1`; yerel kopyası `output/ios-backend-audit-20261021/kontrol.ps1`.

Sunucuda `C:\ProgramData\santiye\kontrol.ps1` olarak kopyalayıp yönetici PowerShell'de:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\kontrol.ps1
```

IIS havuzu/web.config/makine ortamından seçilen `SANTIYE_CONFIG_FILE`, JSON katmanları ve ilgili ortam değişkenleri okunur. Güvenli durum alanları üretilir; dosya/ACL yazımı, IIS restart veya DB/hak işlemi yoktur. Yalnız `IisConfigPathResolved=true` olan gerçek sunucu kontrolü canlı ayarın kanıtıdır; `-Offline` yerel fixture içindir. Anahtarın amacı ve Gemini projesi/ücretlendirmesi bu araçla doğrulanamaz; bunların teyit bayrakları false kalır.

### Resmî Apple TEST bildirimi

Yeni backend'in `--apple-notification-test` işletim komutu ve `backend/deploy/test-apple-notifications.ps1` eklendi. Bunlar herkese açık yeni bir HTTP ucu oluşturmaz. Apple'ın seçilen Production/Sandbox hostunda `POST /inApps/v1/notifications/test` ve `GET /inApps/v1/notifications/test/{token}` kullanılır; kısa süreli sonuç sorgusu yapılır. Çıktıda yalnız ortam, istek kabulü, teslim bayrağı ve sınırlı `sendAttemptResult` kodları vardır. JWT, test tokeni, JWS, özel anahtar veya sağlayıcı ham cevabı yazdırılmaz. Ücretli hak uygulanmaz; SMS/DB ayarı değiştirilmez.

Wrapper, paketin destek dosyasını ve DLL hash'ini doğrulamadan komutu çalıştırmaz; eski DLL'in tanımadığı argümanla yanlışlıkla ikinci web sunucusu başlatılması önlenir. Doğru yeni paket kurulup Apple ayarları tamamlandıktan sonra yönetici PowerShell:

```powershell
powershell -ep bypass -File C:\inetpub\wwwroot\santiye\deploy\test-apple-notifications.ps1
```

Sandbox komutu yalnız gerçekten izole ortamda `-StoreEnvironment Sandbox -IsolatedSandbox` ile kullanılabilir. Komut mevcut bir canlı ortamı izole etmez. `delivered=false` başarı sayılmaz; 2 çıkış kodu teslim bekleyen/başarısız denemeyi ayırır. **Anahtar/Issuer ID ve sunucu yapılandırması eksik olduğundan bu turda gerçek Apple TEST isteği gönderilmedi.**

## 5. Gemini projesi ve veri kullanımı

- Canlı AI options etkin; önceki gerçek Gemini araması kaydı korunuyor. Ancak Windows'taki etkin özel anahtar dosyası/ayarı okunamadığı için anahtarın ait olduğu gerçek Google projesi bu turda kesinleştirilemedi.
- Açık Google hesabının AI Studio Projects ekranında `gen-lang-client-0366229056` adlı Default Gemini Project **Free tier** görünüyor. Firebase `santiye-agi` projesi **Spark** görünüyor. **Bunların hiçbiri canlı Gemini anahtarının bu projelerden birine ait olduğunu kanıtlamaz.** Hesaptaki Pro üyeliği, başka projedeki kart veya Firebase planı üzerinden Gemini anahtarının ücretli olduğuna karar verilmedi.
- Gereken kanıt: canlı sunucuda kullanılan anahtarla eşleşen AI Studio/Cloud proje kimliği; **o proje** için bağlı etkin Cloud Billing hesabı/`billingEnabled=true`, kullanılan API ve veri işleme ayarları. Anahtarın kendisi ekrana/sohbete/loga verilmemeli. Hesap sahibi AI Studio → API Keys üzerinden anahtarın projesini, aynı proje için Cloud Console → Billing ve AI Studio Billing ekranını kontrol etmeli. Başka Google hesabında ise o hesaba erişim gerekir.
- 21 Ekim 2026'da resmî Gemini koşulları yeniden okundu: API'nin aktif Cloud Billing'e bağlı projeden kullanılması ücretli hizmet koşuludur. Ücretli hizmette prompt/cevap ürün/model geliştirme için kullanılmaz; güvenlik/ihlali önleme için sınırlı saklama olabilir. Ücretsiz hizmette içerik ürün/model geliştirme ve insan incelemesine konu olabilir. Gerçek proje eşleşmesi olmadan “ücretli, eğitimde kullanılmaz” beyanı verilmez.
- Kaynak kodunda kullanıcı onayıyla en fazla 400 karakter metin ve seçili il gönderiliyor. `GeminiClient` HTTP gövdesini yalnız isteği karşılamak için bellekte işler, sağlayıcı hata içeriğini atar; `AiQuota` yalnız hesap/zaman/kota metadatasını yazar. Prompt/model cevabı için DB sütunu/kalıcı yazma yolu bulunmadı. `x-goog-api-key` başlığı günlükte maskeleniyor; HTTP URL anahtar içermez. IIS/proxy/Google tarafındaki haricî kayıt ayarları bu kod incelemesinden doğrulanamaz.
- Mevcut web politikası ücretsiz/ücretli ayrımını koşullu anlatıyor; doğrulanmamış “ücretli plan” iddiasıyla değiştirilmedi. Mac'in yaklaşık konum/diğer kullanıcı içeriği için bekleyen iki Apple beyanı kesin ücretli-plan teyidi almış sayılmaz. İzleme/reklam amacı eklendiğine dair kanıt yoktur; sağlayıcı veri kullanım planı belirsizliği açık kalır.

## 6. Otomatik kontroller ve gerçek işlem bekleyenler

Başlangıçtaki 131 API testi gerçek yerel PostgreSQL `santiye_test_*` veritabanlarıyla geçti. Yeni HTTP kontrolleri verify/sync oturum koruması, imzasız Apple isteğinin reddi, doğru/yanlış bundle/App ID, Production/Sandbox kabulü ve TEST bildiriminin hak vermemesini kapsıyor. Apple test isteğinin iki ayrı doğru hosta gittiği ve ham JWS/test tokeninin çıktıya sızmadığı sahte HTTP ile kontrol edildi. Son tam tur **140 başarılı / 0 başarısız / 0 atlanan**; kısa polling düzenlemesinden sonra Apple sınıfının **23 testi** tekrar başarılı. Derleme hatasız. Salt okunur PowerShell fixture'ı kaynak dosyanın değişmediğini, sırların çıkmadığını ve doğrulanamayan noktaların false kaldığını denetledi; iki scriptin sözdizimi geçti.

Bu testlerde Apple HTTP/JWS seam'leri sahte, veritabanları yerel ve kendi oluşturdukları test veritabanlarıdır. Gerçek Apple imzası/TEST teslimi/satın alma başarılı denmedi. Mac IPA ve fiziksel iPhone bu bilgisayarda doğrulanmadı.

Bekleyen gerçek kontroller: In-App Purchase anahtarının Apple API yetkisi, Production ve izole Sandbox TEST teslimi, TestFlight satın alma/yenileme/iptal/geri yükleme, kredi idempotency ve iade akışı, telefon doğrulamasıyla yetki verme, gerçek iPhone FCM/APNs teslimi ve konum. Mevcut otomatik testler bu kabul adımlarının yerine geçmez.

## 7. Mac tarafına kısa cevap

> Backend ana dalı güncellendi; canlı API ve inceleme girişi çalışıyor. Firebase'de doğru iOS kaydı/üretim APNs bağlantısı var. Apple callback şu anda CONFIG/503; yeni In-App Purchase anahtarının türü, Issuer ID ve güvenli Windows kurulumu henüz teyit edilmedi. Canlıda Sandbox açılmadı; ayrı API/DB gerekiyor ve mevcut IPA'nın test API'si buna göre yeniden ayarlanacak. İnceleme hesabı phone_verified=false; satın alma kodunun doğrulanmış telefon şartı korunuyor. Gemini'nin gerçek anahtar projesi ve o projedeki aktif Billing teyit edilemedi; kalan iki gizlilik alanını “ücretli plan teyit edildi” diyerek kapatmayın. Ayrıntı docs/BACKEND_IOS_YAYIN_SONUC_2026-10-21.md içinde. SMS açılmadı, TestFlight'a yükleme yapılmadı.

## Kaynaklar

- [Apple API anahtarı oluşturma](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-use-with-the-app-store-server-api)
- [Apple TEST bildirimi](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification), [TEST sonucu](https://developer.apple.com/documentation/appstoreserverapi/get-test-notification-status)
- [Apple PKI](https://www.apple.com/certificateauthority/)
- [Gemini API veri kullanım koşulları](https://ai.google.dev/gemini-api/terms)

Bu rapor canlı Windows ayarları okunamadığı için gerçek anahtar/Issuer ID/Gemini planının tamamlandığı iddiasını içermez. Kullanıcıdan beklenen güvenli bilgiler ve sunucu salt okunur durum çıktısı yukarıda açıkça ayrılmıştır.

## 8. Doğrulanan yerel sunucu teslimi

- Kaynak commit: `9328621` (Mac geçmişinin üzerine normal commit/push).
- ZIP: `output/ios-backend-audit-20261021/SantiyeAgi-Backend-IIS.zip`, 30.404.432 bayt.
- SHA-256: `AE379CF01C99204ABC8573421D3FC3EA9DFFD0BEC0D528D9615212F32D1E33C3`.
- Aynı klasörde ZIP hash'ini içeren `guncelle.ps1`, salt okunur `kontrol.ps1`, Apple G3 açık sertifikası ve güvenli HTTP durum JSON'ları mevcut. Paket yetenek dosyası DLL hash'iyle eşleştirildi; özel anahtar/üretim ayarı dosyası bulunmadığı manifestten kontrol edildi. Paketlenmiş CLI, sahte yerel ve Billing kapalı ayarla CONFIG/503 ve 1 çıkış kodu vererek HTTP sunucusu başlatmadan kapandı.
- **Paket canlı IIS'e kurulmadı.** Önce salt okunur kontrol çıktısı ve Apple anahtarı/Issuer bilgisi tamamlanmalı. Bu güncellemenin yeni satın alma migration'ı yok; mevcut hash kontrollü kurucu yedek/geri yükleme denetimi ve dış ayarları koruma akışını kullanır. Yükleme Gemini veya Apple ayarlarını kendi kendine tamamlamaz; Sandbox da açılmaz.
