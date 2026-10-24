# Apple 401 incelemesi — 21 Ekim 2026

## Kesinleşenler

- Windows'ta önceki bağımsız aday dosya testi P-256 anahtarı okuyup ES256 imzası üretti, Production TEST isteğine gerçek Apple HTTP 401 geldi. Bu sonuç **müşteri anahtarının türü/aidiyeti yanlış** sonucunu tek başına kanıtlamaz.
- İncelenen backend ve tanı kodu şu değerleri kullanıyor: Key ID `CY8L78UR5Q`, Issuer `e0061e2a-caf2-40d0-81f4-21d2ead8c973`, Bundle ID `com.yusuftaskiran.santiyeagi.pro`.
- Başlık `alg=ES256`, `typ=JWT`, doğru `kid`; yük `iss`, `iat`/`exp` UNIX saniye, `aud=appstoreconnect-v1`, `bid`; süre 300 saniye. ECDSA imza biçimi JOSE için 64 bayt P1363. Kaynak kod ve yerel imza testlerinde belirgin üretim hatası bulunmadı.
- Doğru Production adresi `POST https://api.storekit.apple.com/inApps/v1/notifications/test`. Tanı aracında HTTP yönlendirmesi kapalı, TLS sertifika doğrulaması açık; Authorization veya yanıt gövdesi loglanmaz.
- Başarısız kurulum Billing dosyasını kaydetmedi. Önceki tanı aracı etkin IIS ayarlarını kullanmıyordu; açıkça seçilen aday dosyayı ve sabit kimlikleri kullanıyordu. Dolayısıyla etkin Billing ayarlarının boş olması aday testinin 401 nedenini açıklamaz; iki kontrol ayrı raporlanmalıdır.

## Sunucuda ölçülmesi gerekenler

Kullanıcının verdiği beklenen dosya SHA-256 özeti:

`0a969ec424de180b72a7dcbf7e7b3f39ff954d47397cbb382a4c0b560820f9c2`

Windows dosyasının gerçek özeti, etkin IIS dosya seçimi ve saat farkı önceki çıktılarda yoktur. Bu bilgisayardan uzak sunucunun dosya/saatine doğrudan erişim bulunmadığından eşleşmiş gibi raporlanamaz.

`backend/deploy/build-apple-probe.ps1 -Audit` tek dosyalık `output/apple-probe/apple-detay.ps1` üretir. Dosya sunucuda `C:\ProgramData\santiye` içine kopyalanıp şu komutla çalıştırılır:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\apple-detay.ps1
```

Kontrol şu sonuçları ayrı verir:

- **Etkin ayar kaynağı:** IIS havuz/web.config/makine ortamı ve dış JSON dosyasının yeniden birleştirilmesi; doğru anahtar yolu, ID/Issuer/Bundle, Billing/Sandbox durumu, etkin dosyanın SHA-256 karşılaştırması. Bu, çalışan worker belleğinin dökümü değildir. İncelenen paket DLL hash'iyle eşleşme ayrıca gösterilir.
- **Aday dosya:** Özet verilen değerle birebir karşılaştırılır. SHA-256 yalnız dosya aktarım eşitliğini gösterir; Apple hesabı veya API yetkisini kanıtlamaz.
- **Saat:** Sunucunun UTC saati ve Apple'ın HTTPS yanıtındaki HTTP Date; ortalama istek anı ile fark, ağ gidiş-dönüş süresiyle birlikte raporlanır. HTTP Date yaklaşık ölçümdür; NTP sertifikası veya tam senkronizasyon kanıtı değildir. Servisin Running olması da senkronizasyon kanıtı sayılmaz. Araç saati değiştirmez.
- **JWT:** Oluşturulan gerçek token bellekte tekrar ayrıştırılır; beklenen başlık/yük, 300 saniyelik süre ve 64 bayt imza kontrol edilir. İmza ayrı ECDSA nesnesine aktarılan yalnız açık anahtarla doğrulanır. Token veya özel anahtar yazdırılmaz. Yerel imza doğruluğu Apple'ın o Key ID'yi o hesap/uygulamayla eşlediğini kanıtlamaz.
- **API:** Yönlendirmesiz gerçek Apple adresi, HTTP kodu ve sabit hata sınıfı. TEST çağrısı hak/para işlemi yapmaz; başarılı olması callback tesliminin veya gerçek satın almanın başarılı olduğu anlamına gelmez.

## Sonuç değerlendirme

Sunucu çıktısı gelmeden kök neden kesinleştirilemez. Özet/saat/alanlar/imza doğru ve 401 devam ederse yerel JWT üretim sorunu bulunduğu iddia edilmez; Apple tarafındaki anahtar aktifliği, API türü, ekip/uygulama erişimi veya servis yetkilendirmesi ayrıca kanıtlanmalıdır. Mevcut anahtarlar iptal edilmez, Billing/SMS/TestFlight ayarları değiştirilmez.

Yerelde 9 tanı testi geçti: doğru ve reddedilen yanıtlar, dosya özeti uyuşması/uyuşmaması, JWT imzası/alanları, ölçülen yapay 900 saniye saat farkı, sır sızmaması. Bu testler gerçek Windows dosyasını veya Apple yetkisini doğrulamaz.

Resmî kaynaklar: [Apple JWT alanları](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests), [TEST bildirimi adresi](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification).

## Sonraki gerçek Windows ölçümü

Kullanıcının `apple-detay.ps1` çıktısıyla şu noktalar doğrulandı:

- Aday dosya özeti verilen `0a969ec424de180b72a7dcbf7e7b3f39ff954d47397cbb382a4c0b560820f9c2` ile birebir aynı.
- İncelenen paket DLL hash'i kurulu DLL ile eşleşiyor.
- IIS dış ayar dosyası doğru çözüldü ve değişmedi. Billing kapalı, Apple alanları kaydedilmemiş; aday dosya testinden ayrı durum.
- Gerçek token başlığı/yükü ve yerel açık anahtarla imza geçerli, 64 bayt ES256-P1363, süre 300 saniye.
- ServerUtc 2026-10-21T19:52:36.6486362Z, AppleDateUtc 19:52:37Z, RTT 627,4 ms, yuvarlanmış saat farkı 0 saniye. Bu hassasiyette anlamlı sapma gözlenmedi.
- Doğru Production TEST adresinden yine HTTP 401 geldi. Apple tarafında token bu uygulama/anahtar birleşimiyle kabul edilmedi; nedeninin müşteri anahtarı olduğu kanıtlanmadı.

### Yeni resmî bilgi ve sonraki ayrım

[Apple App Store Commerce Engineer'ın yanıtı](https://developer.apple.com/forums/thread/806452), ilk üretim yayınına kadar Production API erişiminin kapalı olduğunu açıklıyor. Bu uygulamanın ilk yayını henüz yapılmadığından bu açıklama 401 için güçlü bir olasılıktır; aynı anahtarın Sandbox'ta kabulü henüz ölçülmeden kesin kök neden olarak sunulmaz. Başka forum kullanıcısının 401'de otomatik Sandbox fallback önerisi Apple tarafından onaylanmış bir talimat sayılmadı; üretimde Sandbox açılmadı.

Yalnız Production başarısını zorunlu kılan mevcut kurulum kapısı yayın öncesi aşamada fazla kısıtlayıcı olabilir. Dosya/type hatasına hükmedilmez. Önce bağımsız Sandbox API erişimi kanıtlanacak; sonra kurulum durumu ve Production erişimi ayrı raporlanmalıdır.

Yeni `output/apple-probe/apple-sandbox.ps1`, aynı anahtarla yalnız son 60 saniyenin Sandbox bildirim geçmişini okur: `POST https://api.storekit-sandbox.apple.com/inApps/v1/notifications/history`. Hiçbir TEST callback veya satın alma isteği göndermez; DB/ayar/IIS/SMS/TestFlight değiştirmez, AllowSandbox açmaz. Yanıttaki geçmiş/JWS içerikleri yazdırılmaz. `200` aynı anahtar/Issuer/Bundle'ın Sandbox tarafından kabulünü kanıtlar; Production kabulünü veya gerçek makbuz işlemini kanıtlamaz. Kaynak: [Apple geçmiş API'si](https://developer.apple.com/documentation/appstoreserverapi/get-notification-history).

Sunucuda yalnız bu dosyayı `C:\ProgramData\santiye` içine kopyalayıp `powershell -ep bypass -File C:\ProgramData\santiye\apple-sandbox.ps1` çalıştırmak gerekir. Yeni ZIP kurulmaz. Yerelde toplam 10 tanı testi geçti; yeni test tam Sandbox geçmiş adresini, 60 saniyelik gövdeyi, tek okuma isteğini ve JWS çıktısı olmamasını doğruladı. Gerçek Sandbox yanıtı bekleniyor.

## Sandbox sonucu ve kurulum hazırlığı

Kullanıcının gerçek sonraki çıktısı: 2026-10-21T19:57:50.7498120Z, Sandbox geçmiş API HTTP 200, ApiAccessVerified=true; doğru dosya özeti/kimlikler/yerel imza, saat farkı yaklaşık 0,1 sn. Bu anahtarın bu uygulama için Sandbox API yetkisi kanıtlandı. Production 401'in ilk yayın kısıtıyla uyumlu olduğu çıkarımı güçlendi; Production erişimi doğrudan doğrulanmadı. Anahtar iptal edilmez veya yanlış ilan edilmez.

Yayın öncesi kurulumu Sandbox API yetkisiyle güvenli doğrulayabilen `apple-kur.ps1` hazırlandı; ayrıntı `APPLE_BILLING_KURULUM_2026-10-21.md` belgesinin son bölümünde. Mevcut kullanıcı çıktısında Billing hâlâ kapalı/Apple alanları boş; hazırlanan kurulum çalıştırılıp sonucu gelene kadar bu durum değişmiş sayılmaz. Üretimde AllowSandbox açılmaz, SMS/TestFlight bekler.

## Son durum: yayın öncesi ayarlar sunucuda kaydedildi

Kullanıcı apple-kur.ps1'in başarılı sonucunu paylaştı: çıkış 0 ile yeni Sandbox API yetkisi doğrulandı, Apple Billing ayarları kaydedildi, AllowSandbox=false kaldı ve kayıt sonrası hazır kontrolleri geçti. Diğer ayarlar korundu; SMS/TestFlight değişmedi. Önceki etkin Apple alanları boş gözlemi bu başarılı kurulum öncesine aittir. Production 401 için ilk yayın erişim kısıtı açıklamasıyla uyumlu kanıt vardır; Production kabulü ilk yayın sonrasında ayrıca kontrol edilecektir. Gerçek satın alma/callback/yenileme/iade testleri ve Sandbox izolasyonu tamamlanmış sayılmaz.
