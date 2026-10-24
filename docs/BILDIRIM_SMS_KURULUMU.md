# Telefon doğrulama ve uygulama kapalıyken bildirim

Son güncelleme: 16 Ekim 2026.

Bu dosya VatanSMS.net üzerinden SMS doğrulamanın ve Firebase Cloud Messaging üzerinden push bildiriminin canlı kurulumu içindir. 16 Ekim'de Firebase müşteri VDS'sinde etkinleştirildi; Android emülatöründe arka plan/kapalı işlem teslimatı ve bildirimden açılış doğrulandı. Fiziksel Android cihaz, iOS/APNs ve gerçek SMS kontrolleri bekler. Ayrıntılar `ANDROID_BILDIRIM_CANLI_KONTROLU_2026-10-16.md`. Geliştirmede sahte sağlayıcılarla yapılan testler gerçek teslimatın yerine geçmez.

## 1. Şu an hazırlanan davranış

- Kullanıcı `+905xxxxxxxxx` biçimindeki telefonuyla kod ister. API altı basamaklı rastgele kod üretir; veritabanında yalnız kodun anahtarlı özeti saklanır.
- Kod beş dakika geçerlidir. Beş hatalı denemeden sonra kullanılamaz. Başarılı doğrulamada kod silinir; tekrar kullanılamaz.
- Aynı telefona en erken 60 saniye sonra yeniden kod istenebilir. Telefon başına saatte beş, 24 saatlik pencerede on istek sınırı vardır. Sağlayıcıya başarısız gönderim denemesi de sınırı tüketir.
- Gerçek SMS için uygulamanın tamamında varsayılan 24 saatlik 200 gönderim denemesi bütçesi uygulanır. `Sms:DailyBudget` ile 1–10.000 arasında ayarlanır. Bu sınır telefon/IP sınırlarına ek olarak veritabanında tutulur ve IIS yeniden başlatıldığında sıfırlanmaz.
- Sağlayıcı başarısız olursa kullanıcıya gönderildi denmez; yeni kod etkinleştirilmez ve önceki kod iptal edilmiş olur. HTTP 200 cevabı tek başına başarı sayılmaz.
- Geliştirme kodu sadece `Development` ortamında döner. `Production` ortamında `Development` sağlayıcısı seçilse bile test koduyla giriş açılamaz.
- Yeni uygulama içi bildirim ile push kuyruğu aynı veritabanı işlemi içinde kaydedilir. IIS yeniden başlatılsa da tamamlanmamış görevler kuyrukta kalır.
- Bir hesaba en fazla on cihaz kaydedilir. Gönderimden önce cihazın hesap ve oturum ilişkisi tekrar kontrol edilir. Çıkışta o oturumun cihaz kayıtları, hesap silindiğinde hesabın cihaz ve push görevleri silinir.
- Aynı telefon başka hesaba geçtiğinde aynı Firebase tokenı önceki hesaptan ayrılır. Mobil uygulama bildirimdeki alıcı kimliğini de kontrol eder.
- Push üzerinde özel teklif/telefon/ücret bilgisi gösterilmez. Kilit ekranında genel bir bildirim metni bulunur; ayrıntı oturum açılan uygulamadan alınır.
- Geçici sağlayıcı hataları artan beklemeyle yeniden denenir. Bir cihaza en fazla sekiz deneme yapılır, 24 saatten eski bildirim gönderilmez. Firebase `UNREGISTERED` cevabı verdiğinde eski cihaz tokenı kaldırılır. Anahtar/proje hatası cihaz kayıtlarını topluca silmez.

## 2. VatanSMS.net için müşteriden gerekenler

| Bilgi | Nereden alınır? |
| --- | --- |
| API ID | VatanSMS.net panelinde **Hesabım → API Bilgilerimi Görüntüle** |
| API Key | Aynı bölüm; yalnız sunucuya güvenli şekilde girilir |
| Gönderici başlığı | Hesaba tanımlanmış, onaylanmış SMS başlığı |
| SMS/OTP yetkisi ve bakiye | Panel veya VatanSMS desteği |
| IP kısıtlaması | Hesapta varsa VDS'nin dışarıya çıkış IP'si izin listesine eklenir |

Bu entegrasyon **VatanSMS.net REST OTP SMS** içindir. VatanSMS.com hesabı veya WhatsApp hizmetiyle aynı kabul edilmez. WhatsApp Business üzerinden doğrulama ayrı bir sağlayıcı, şablon ve kurulum gerektirir; SMS anahtarını WhatsApp anahtarı olarak kullanmayın.

Sunucu ortam değişkenleri / IIS uygulama ayarları:

```text
Sms__Provider=VatanSms
Sms__Enabled=true
Sms__DailyBudget=200
Sms__VatanSms__ApiId=<paneldeki API ID>
Sms__VatanSms__ApiKey=<gizli API anahtarı>
Sms__VatanSms__Sender=<onaylı gönderici başlığı>
```

Kodun kullandığı uç nokta `POST https://api.vatansms.net/api/v1/otp` olur. Türkiye numarası sağlayıcıya başındaki `+90` çıkarılarak `5xxxxxxxxx` biçiminde iletilir. TLS sertifika doğrulaması açıktır, yönlendirmeler izlenmez ve gönderim otomatik olarak tekrarlanmaz; böylece zaman aşımında ücretli SMS iki kez gönderilmeye çalışılmaz.

VatanSMS'in herkese açık OTP sayfası istek alanlarını açıklıyor; yanıt gövdesinin ayrıntılı şemasını vermiyor. Kod açık bir başarı yanıtı (`status: "success"` / `"SUCCESS"`, sayısal `status: 200` veya `success: true`) arar; bilinmeyen yanıtı hata kabul eder. **Canlıya geçerken sağlayıcının bu hesaba verdiği gerçek yanıtın uyumu tek bir kontrollü gönderimle doğrulanmalıdır.** Farklı bir yanıt varsa uyumlu ayrıştırıcı eklenmeden etkin kabul edilmez. Güncel entegrasyon testi gerçek SMS göndermez.

Eksik ayar veya kapalı sağlayıcı durumunda giriş isteği `CONFIG` hatası verir; doğrulama atlanmaz. Geliştirme ortamındaki yerel hesapla yapılan test, canlı kullanıcı girişi olarak değerlendirilmez.

## 3. Firebase push kurulumu

1. Müşteriye ait Firebase projesini oluşturun. Projedeki Android ve iOS uygulama kimlikleri, yayımlanacak Flutter uygulamasının kimlikleriyle aynı olmalıdır.
2. Android uygulamasına projeye ait `google-services.json`, iOS uygulamasına `GoogleService-Info.plist` dosyasını ekleyin. Bunlar başka projeden kopyalanmaz. Mobil derlemede push yapılandırmasını etkinleştirin.
3. Firebase Cloud Messaging API'yi etkinleştirin. iOS için Apple Developer üzerinden APNs doğrulama anahtarını Firebase projesine tanımlayın; imzalama ve Push Notifications yetkisini açın.
4. Firebase konsolu **Proje ayarları → Hizmet hesapları → Yeni özel anahtar oluştur** yolundan sunucunun hizmet hesabı JSON dosyasını alın. Hesabın ilgili projede Cloud Messaging gönderim izni bulunmalıdır.
5. Bu özel JSON dosyasını yayın klasörünün **dışında**, örneğin `C:\SantiyeSecrets\firebase-service-account.json` konumunda saklayın. Yalnız ilgili IIS uygulama havuzu kimliğine okuma izni verin. Mobil uygulamaya, Git'e, ZIP'e veya herkese açık web klasörüne koymayın.
6. Sunucuyu aşağıdaki ayarlarla yapılandırıp uygulama havuzunu yeniden başlatın:

```text
Push__Enabled=true
Push__Firebase__ProjectId=<Firebase proje ID>
Push__Firebase__ServiceAccountPath=C:\SantiyeSecrets\firebase-service-account.json
```

API, resmî `Google.Apis.Auth` kütüphanesiyle kısa süreli OAuth tokenı alır ve FCM HTTP v1 kullanır. Kabul edilen dosya türü `service_account` olmalı; proje kimliği ayarla eşleşmeli ve token adresi `https://oauth2.googleapis.com/token` olmalıdır.

Cihaz kayıt uç noktaları JWT oturumu ister:

```text
PUT /api/v1/push/devices/<kurulum UUID>
{"token":"<Firebase cihaz tokenı>","platform":"android"}

DELETE /api/v1/push/devices/<kurulum UUID>
```

Başkasının cihaz kaydı DELETE isteğiyle silinemez. Token yenilendiğinde mobil uygulama kaydı yeniler. Gönderilecek mesaj `notification_id`, `user_id`, `ref_type`, `ref_id` alanlarını taşır; Android kanal adı `santiye_updates` olur.

## 4. IIS ve işletim

### Android bağlantısının mevcut durumu — 16 Ekim 2026

Müşterinin indirdiği Android ayar dosyası kontrol edildi: Firebase proje kimliği `santiye-agi`, Android paket adı `com.santiyeagi.santiye_agi`. Yerel dosya `android/app/google-services.json` konumuna yerleştirildi; Git'e ve backend ZIP'ine eklenmez. Bu dosya mobil uygulama ayarıdır; sunucunun özel hizmet hesabı anahtarının yerine geçmez.

Android push denemeleri için `config/live-android-push.json` kullanılır:

```powershell
flutter build apk --profile --target-platform android-x64 --dart-define-from-file=config/live-android-push.json
```

Bu ayar müşteri VDS'sine bağlanır ve mobil push kaydını etkinleştirir. iOS Firebase dosyası henüz sağlanmadığı için bu yapılandırma yalnız Android içindir. Genel `config/live.json` bu aşamada push kapalı kalır. Başka bilgisayarda derleme yapılacaksa aynı Firebase projesinin Android ayar dosyası ayrıca sağlanmalıdır.

Sunucunun hizmet hesabı dosyası, `Push:Enabled` ayarı ve gerçek FCM teslim testi tamamlanmadan bu adım "bildirimler canlıda çalışıyor" anlamına gelmez.

### Mevcut VDS'de Firebase'i açma

16 Ekim'de sunucu hizmet hesabı sağlandı. Proje/tür alanları kontrol edildi ve Google OAuth sunucusu anahtarla kimlik doğrulamaya HTTP 200 verdi. Bu kontrol bildirim göndermez. Özel dosya yerel deponun dışına, kullanıcıya özel izinlerle alındı; kaynak koda, APK'ye veya ZIP'e eklenmez.

Mevcut API yeniden yüklenmeden aşağıdaki kurulum yapılabilir:

1. Özel JSON dosyasını VDS'de `C:\ProgramData\santiye\firebase-service-account.json` konumuna kopyalayın. Web sitesinin `wwwroot` klasörüne koymayın.
2. `deploy/set-firebase-push.ps1` aracını VDS'de `C:\ProgramData\santiye\set-firebase-push.ps1` konumuna kopyalayın.
3. Yönetici Windows PowerShell'de çalıştırın:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\santiye\set-firebase-push.ps1"
```

Araç varsayılan olarak `santiye` uygulama havuzunu ve `C:\ProgramData\santiye\settings.json` dosyasını kullanır. Anahtarın proje kimliğini kontrol eder, web klasöründe tutulan anahtarı reddeder, anahtara yalnız yönetici/SYSTEM ve ilgili havuzun erişmesini sağlar. Diğer JSON ayarlarını ve settings dosyasının izinlerini koruyarak Firebase proje/yol bilgisini ve push açık ayarını yazar. Havuzu sürekli çalışacak şekilde ayarlayıp yeniden başlatır; kısa bağlantı kesintisi olabilir. Gizli anahtarın içeriğini ayarlara veya çıktıya yazmaz. Geri kapatmak için aynı komuta `-Mode Off` eklenebilir.

Yerel kurulum kontrolleri `powershell.exe -NoProfile -ExecutionPolicy Bypass -File backend/deploy/tests/set-firebase-push.Tests.ps1` ile çalıştırılır. Testteki `SkipIisSetup` seçeneği yalnız dosya ayarlarını denemek içindir; gerçek VDS kurulumunda kullanılmaz. Yerel test IIS izin/havuz değişikliğinin canlı sunucuda yapıldığı anlamına gelmez. Servis ayarları tamamlandıktan sonra bildirim açık APK'den cihaz kaydı ve yeni bir teklifin arka plan teslimatı ayrıca kontrol edilmelidir.

- Migration dosyası uygulanmış olmalıdır: `PhoneOtpQuotas`, `PushDevices`, `PushOutbox` ve `PushDeliveries` tabloları gereklidir.
- Uygulama havuzunu **AlwaysRunning** yapın; boşta kalma zaman aşımını `0` olarak ayarlayın. IIS Application Initialization / preload kurulumunu kullanın. Uygulama havuzu tamamen kapatılırsa kuyruk gönderimi de durur; uygulama çalışmaya başladığında devam eder.
- Sunucunun dışarıya HTTPS erişimi VatanSMS API, Google OAuth ve FCM adreslerine açık olmalıdır. PostgreSQL portunun internete açılması bu entegrasyonlar için gerekmez.
- Bildirim teslimi ağ ve cihaz koşullarına bağlıdır. Sunucu FCM'ye gönderdikten hemen sonra veritabanı kaydı sırasında çökerse nadiren tekrar gönderim olabilir; sabit bildirim kimliği Android etiketi ve APNs collapse kimliği olarak da kullanılır. “FCM kabul etti” ile “kullanıcı gördü” aynı şey değildir.
- Tamamlanan push görevleri yedi gün, etkin olmayan cihaz kayıtları en fazla 60 gün tutulur. Süresi biten telefon challenge kayıtları yaklaşık bir gün, gönderim kotaları iki gün sonra saatlik temizlikte kaldırılır. İş verileri uygulama içi bildirim saklama kurallarına tabidir.
- SMS anahtarı veya Firebase özel anahtarı değiştiğinde sunucu ayarını/dosyasını güncelleyip uygulama havuzunu yeniden başlatın. Uygulama loglarına kod, telefon, cihaz tokenı veya sağlayıcının özel yanıt gövdesi yazılmaz.

## 5. Yayına geçerken gerçek cihaz kontrolü

Bu adımlar sağlayıcı hesapları hazır olduğunda yapılacak canlı kontrollerdir; yerel testlerin geçtiği belirtilerek yapılmış sayılmaz.

1. Müşterinin belirlediği test numarasına tek kod gönderin; panelde gönderim ve bakiye kaydını görün. Yanlış/süresi geçmiş kodun giriş açmadığını doğrulayın.
2. Gerçek Android cihazda bildirim iznini açın. İkinci hesapla teklif oluşturup uygulama arka plandayken ve kapalıyken bildirimin gelişini kontrol edin.
3. iPhone/APNs kurulumu tamamlandıktan sonra aynı testi gerçek iPhone'da yapın.
4. Çıkış ve hesap değiştirmeden sonra önceki hesabın bildiriminin açılmadığını; bildirim izni reddedildiğinde uygulama içi bildirim listesinin çalıştığını kontrol edin.
5. IIS uygulama havuzunu kontrollü yeniden başlatıp bekleyen bir bildirimin kuyruktan devam ettiğini kontrol edin.

## Resmî kaynaklar

- [VatanSMS.net OTP REST isteği](https://docs.vatansms.net/rest-sms-api/otp-sms)
- [VatanSMS.net API hesabı ve gönderici bilgileri](https://www.vatansms.net/sms-api)
- [FCM HTTP v1 ve sunucu yetkilendirmesi](https://firebase.google.com/docs/cloud-messaging/send/v1-api)
- [FCM hata kodları](https://firebase.google.com/docs/cloud-messaging/error-codes)
- [FCM cihaz tokenı yönetimi](https://firebase.google.com/docs/cloud-messaging/manage-tokens)
