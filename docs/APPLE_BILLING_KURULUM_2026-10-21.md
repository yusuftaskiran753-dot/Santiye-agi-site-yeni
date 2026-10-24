# Apple anahtarıyla güvenli bağlantı — 21 Ekim 2026

## Gerçek durum

Kullanıcının paylaştığı canlı salt okunur rapor: Production, Billing kapalı, Sandbox kapalı; Apple alanları boş. Firebase etkin ve sunucudaki servis hesabı `santiye-agi` ile eşleşiyor. Gemini etkin/anahtar mevcut; gerçek proje ve faturalandırma teyidi ayrı bekliyor.

Yeni aday Key ID `CY8L78UR5Q`, Issuer ID `e0061e2a-caf2-40d0-81f4-21d2ead8c973`. Anahtar Mac İndirilenler'de; Windows'a güvenli aktarım henüz teyit edilmedi. `Access: App Manager` veya dosya adı satın alma API yetkisinin kanıtı değildir. Önceki L3FC8F5LZ7 adayına dayanarak ayar yapılmaz.

Bu tur **gerçek anahtar okunmadı, Apple'a gerçek yetki isteği gönderilmedi, IIS ayarı değiştirilmedi**. Aktarım ve kullanıcı tarafından sunucuda çalıştırılacak komut bekleniyor.

## Kurulum

1. P8'i Uzak Masaüstü dosya aktarımıyla `C:\ProgramData\santiye\keys\AuthKey_CY8L78UR5Q.p8` konumuna kopyalayın. Sohbete/Git'e göndermeyin. Sunucu yöneticisi dışında erişim vermeyin.
2. Bu teslimdeki yeni ZIP ve hash'e bağlı `guncelle.ps1` dosyasını `C:\ProgramData\santiye` içine birlikte kopyalayın. Önce güncelleyin:

   `powershell -ep bypass -File C:\ProgramData\santiye\guncelle.ps1`

3. Ardından anahtar kontrolü ve kurulum:

   `powershell -ep bypass -File C:\inetpub\wwwroot\santiye\deploy\set-apple-billing.ps1`

4. Kurulum başarılıysa bağımsız callback kontrolü:

   `powershell -ep bypass -File C:\inetpub\wwwroot\santiye\deploy\test-apple-notifications.ps1`

Betik önce etkin IIS dış ayar yolunu, Production ortamını, DLL/yetenek hash'ini ve dosya konumunu doğrular. Billing ortam değişkeni varsa sessizce ezmek yerine durur. P8 ve resmî Apple kök sertifikasına SYSTEM/yöneticiler tam erişim, yalnız ilgili IIS havuzuna okuma izni verir. Sertifika SHA-256 ile sabitlenmiştir.

Geçici, yöneticilere özel minimal ayarla resmî Production `POST /inApps/v1/notifications/test` çağrılır. Bu süreç DB'ye bağlanmaz, HTTP sunucusu/arka plan işleri başlatmaz. JWT ve dönüşteki test belirteci yalnız bellekte kalır. Apple başarılı yanıt ve geçerli test belirteci döndürmeden canlı Billing dosyası değişmez. 401/403, hatalı anahtar, eksik dosya, ağ hatası veya eski DLL bağlantıyı etkinleştirmez.

Başarıdan sonra yalnız gerekli Apple alanları, `Enabled=true`, `AllowSandbox=false` birleştirilir. Diğer ayarlar korunur; eşzamanlı değişiklik hash'i kontrol edilir, ACL koruyan atomik dosya değişimi ve korumalı önceki ayar kopyası kullanılır. IIS havuzu yeniden başlatılır. Güncel API yetkisi callback tesliminden ayrıdır: ilk test kurulumdan önce gittiği için eski callback 503 dönebilir; kurulum sonrası ikinci kontrol gerçek teslimi ölçer. İstek kabulü **satın alma/yenileme/iade doğrulaması değildir**.

`Billing.Enabled` ortak anahtardır; Google kimlik bilgileri bu betikle kurulmaz veya değiştirilmez. Google da geçerli doğrulama olmadan hak vermez. Sandbox üretimde açılmaz; ayrı test ortamı hâlâ kurulmadı. TestFlight yüklenmez.

## SMS'siz satın alma değerlendirmesi

`StoreBillingService.Apply` doğru mağaza makbuzu ve `appAccountToken` hesabı eşleşmesine ek olarak `PhoneVerified=true` ister. Girişte SMS zorunluluğunun kapalı olması bu koşulu kaldırmaz. Son incelenen test hesabı doğrulanmamıştır. Bu hesapla hak tanımlama tamamlanamaz; satın alıp hak alamama riski nedeniyle gerçek işlem öncesi çözülmelidir.

Üretimde telefon doğrulamasını atlatmama depo kuralı gereği koşul kaldırılmadı; hesap doğrulanmış gibi işaretlenmedi, özel inceleme hesabı istisnası eklenmedi. Önceden gerçekten telefonunu doğrulamış bir hesap varsa bu engeli yaşamaz; makbuz/hak kontrolü yine gerekir. Böyle bir hesap yoksa SMS/gerçek doğrulama beklenmeli. SMS'siz kalıcı üyelik modeli istenirse doğrulanabilir alternatif hesap kimliği, kurtarma ve işlem yetkileri ayrı ürün/güvenlik çalışması gerektirir; bu kurulum onu uygulamaz.

## Yapılan kontroller

- Apple erişim çağrısı için başarılı yanıt, 401, 403, hatalı test belirteci ve sır çıkmaması yerel HTTP sahteleriyle kontrol edildi. Bu testler gerçek Apple yetkisini kanıtlamaz.
- Billing birim testlerinin 24'ü geçti; PowerShell sözdizimi kontrol edildi. Telefon/üyelik/işlem kodu değiştirilmedi.
- Canlı anahtar testi, IIS kurulumu, callback teslimi ve gerçek makbuz işlemi bekliyor. SMS ve TestFlight kullanıcının isteğiyle beklemede.

Resmî kaynaklar: [IAP anahtarları](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases), [test bildirimi](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification).

## Güncel sonuç: Sandbox erişimi doğrulandı, yayın öncesi kurulum düzeltildi

Kullanıcının sunucuda yaptığı gerçek test 21 Ekim 2026 19:57:50 UTC: Sandbox bildirim geçmişi HTTP 200 / APPLE_API_ACCESS_CONFIRMED. Dosya SHA-256 birebir eşleşiyor, JWT alanları/imzası doğru, 64 bayt imza/300 saniye süre; Apple saatine yaklaşık fark 0,1 saniye (RTT 678,9 ms). Bu anahtar/Issuer/Bundle birleşiminin Sandbox API yetkisi artık kanıtlandı. Müşteri anahtarının yanlış olduğu söylenmez.

Production testinin 401 dönmesi ilk üretim yayını öncesi erişim kısıtıyla uyumlu; bu açıklama Apple çalışanının https://developer.apple.com/forums/thread/806452 yanıtına dayanıyor. Sandbox başarısı Production erişiminin açıldığını kanıtlamaz. İlk yayın sonrası ayrıca kontrol edilmelidir.

### Bu aşamada kullanılacak komut

Önceki `apple.ps1` / Production'a bağlı kurulum yerine **output/apple-probe/apple-kur.ps1** tek dosya teslimi kullanılır. Yeni ZIP gerekmez. Dosyayı sunucuda `C:\ProgramData\santiye` içine kopyalayıp:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\apple-kur.ps1
```

Bu **ayar yazan** kurulum aracıdır; yalnız tanı betiği değildir. Gömülü açık program dosyalarının hash'i, seçilen P8 özeti ve sabit kimlikler doğrulanır. Yeni, gerçek Sandbox geçmiş okuma isteği yapılır. Çıkış 0, tek/tipleri doğru başarılı kayıt, HTTP 200, tam dosya özeti/başlık/yük/imza/adres eşleşmesi olmadan ayar kaydedilmez. Farklı Key ID/Issuer ile bu ön yayın modu çalışmaz.

Başarılı kontrolden sonra yalnız Apple alanları ve Billing.Enabled=true kaydedilir; Production AllowSandbox=false kalır. Mevcut Google ve diğer ayar alanları korunur; ayar/anahtar hash'i tekrar denetlenir, korumalı önceki ayar kopyası alınır ve atomik dosya değişimi yapılır. IIS yeniden başlatılır; salt okunur etkin ayar kontrolü ve HTTPS ready ölçümü geçmeden başarı yazılmaz. Bir hata olursa ayar kaydedildi/kaydedilmedi durumu ayrı gösterilir. Production TEST isteği otomatik yapılmaz.

Bu komut **henüz sunucuda çalıştırılmış sayılmaz**; kullanıcının çıktısı bekleniyor. Çalışınca bağlantı ayarları hazırlanmış olur; gerçek makbuz/satın alma/yenileme/iade/Production callback teslimi tamamlanmış olmaz. Üretimde Sandbox makbuzları kabul edilmez; ayrı test ortamı bekler. SMS/TestFlight ve PhoneVerified kuralı değiştirilmez. Doğrulanmamış inceleme hesabının satın alma hakkı alma engeli devam eder.

Yeni PowerShell politika kontrolleri Windows PowerShell 5.1 ve PowerShell 7'de geçti: doğru Sandbox yetkisi kabul, 13 bozuk/tip/adres/HTTP/imza alanı reddi, mevcut Google/SMS/Auth/AI/Push/DB alanlarının korunması ve tam Apple birleştirmesi. Üretilen tek dosya ayrıştırma ve salt okunur kontrol fixture'ı başarılı. Gerçek kurulum henüz bekliyor.

### Gerçek kurulum sonucu — 21 Ekim 2026

Kullanıcının yeni sunucu çıktısı apple-kur.ps1'in başarıyla tamamlandığını doğruladı: yeni Sandbox yetki kontrolü çıkış 0, Apple Billing ayarları kaydedildi, AllowSandbox=false, mevcut SMS/Auth/Firebase/Gemini/Google/DB ayarları korundu. Başarı mesajları kayıt sonrası etkin ayar/HTTPS ready kontrollerinden sonra verilir; bu kontroller betik çıktısına göre geçti. Bu bölüm önceki “kurulum kullanıcı çıktısını bekliyor” durumunu günceller.

Bağlantı ayarlarının yayın öncesi kurulumu tamamlandı. Gerçek Production API kabulü, mağaza makbuzu, satın alma/yenileme/iade ve callback teslimi kapanmış değildir. Ayrı Sandbox test ortamı ve doğrulanmamış hesap için PhoneVerified şartı açık maddelerdir; SMS ve TestFlight kullanıcı isteğiyle beklemede kalır.
