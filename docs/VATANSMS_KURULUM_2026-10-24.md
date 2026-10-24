# VatanSMS doğrulama kurulumu — 24 Ekim 2026

Bu hazırlık müşterinin VatanSMS.NET API ID/anahtar ve onaylı gönderici başlığı içindir. Anahtar, gerçek alıcı numarası ve doğrulama kodu Git'e, mobil uygulamaya veya bu belgeye eklenmez. Gönderici başlığı **SANTIYEAGI**.

## Entegrasyon ve geçiş

Mevcut backend adaptörü resmî `POST https://api.vatansms.net/api/v1/otp` ucunu kullanır. `api_id`, `api_key`, `sender`, `message_type`, `message`, tek elemanlı `phones` dizisi gönderilir; uygulamadaki +90 kaldırılır. Kod backend'de üretilir, beş dakika geçerlidir, beş hatalı denemeden sonra kullanılamaz. Üretimde geliştirme kodu dönmez. Gönderim tekrarları ve günlük bütçe korunur. [Resmî OTP belgesi](https://docs.vatansms.net/rest-sms-api/otp-sms), [API bilgileri](https://www.vatansms.net/sms-api)

Yeni `/auth/options` alanı `phone_verification_available`, SMS gönderme yapılandırmasının kullanılabilirliğini gösterir; sağlayıcıya istek veya teslim kanıtı değildir. `phone_verification_required` ayrı kalır. VatanSMS açıkken normal `/phone/request` ve `/phone/verify` akışı zorunluluk açılmadan kullanılabilir; mevcut parola/inceleme hesabı erişimi bu hazırlıkta korunur. Hiçbir telefon doğrudan doğrulanmış olarak işaretlenmez.

Gelen gerçek kod, aynı numaraya bağlı hesabı doğrular; kayıtlı olmayan numara için normal uygulama davranışı yeni hesap oluşturmaktır. Başka numarayı doğrulamak `test` hesabının telefonunu değiştirmez veya o hesaba giriş hakkı vermez. İnceleme hesabının eşleşmesi yalnız ID karşılaştırmasıyla raporlanır; hesabın bağlantıları değiştirilmez.

## Sunucuda kısa kurulum

Teslim `output/vatansms-20261024/` klasöründeki **SantiyeAgi-Backend-IIS.zip** ve **sms-kur.ps1** dosyalarıdır. İkisini sunucuda `C:\ProgramData\santiye` içine kopyalayın:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\sms-kur.ps1
```

Betik gerektiğinde mevcut yedekli/hash doğrulamalı backend güncellemesini çalıştırır. Veritabanı hesapları, mevcut Apple/Google satın alma, Firebase, Gemini, IIS web siteleri ve yasal bağlantılar bu SMS kurulumu için değiştirilmez. Genel sunucu güncelleyicisinin mevcut yedek/migration ve bakımda durma davranışı korunur; başarısız güncellemeden sonra bakım dosyası otomatik kaldırılmaz.

1. API anahtarı sunucudaki maskeli isteme yapıştırılır. Komut parametresi veya script içine yazılmaz.
2. Sağlayıcının `/senders` ucuyla yalnız yetki/gönderici sorgusu yapılır. Açık başarı ve beklenen gönderici eşleşmesi yoksa SMS gönderilmeden ve ayarlar değişmeden durur. Resmî dokümanda yanıt gövdesi şeması belirtilmediği için bilinmeyen cevap kabul edilmez; yalnız güvenli tip/boole özetleri alınır.
3. `Stage` mevcut telefon zorunluluğu ve parola girişini koruyarak SMS ayarını dış `settings.json` içinde kaydeder. Yönetici korumalı yedek/atomik yazma, yalnız `santiye` havuzunu yeniden başlatma ve sağlık/etkin ayar kontrolü vardır. Hata halinde eski ayar geri yüklenir.
4. Kullanıcının belirttiği numaraya normal API üzerinden **bir** OTP isteği yapılır. Telefona gelen kod sunucudaki maskeli isteme yazılır; otomatik yeniden SMS gönderilmez. Token, kod veya ham hata çıktıya alınmaz.
5. `--sms-review-readiness` API'yi/sunucuyu başlatmadan, mevcut parola hesaplarının kayıtlı kullanıcılarında profil ve gerçek telefon doğrulama bayraklarını salt okunur PostgreSQL işlemiyle denetler. Yalnız sayılar/boole sonuçlar döner. Tüm kullanılabilir inceleme hesapları hazırsa `Enable` kayıtlı anahtarla zorunluluğu açar; hazır değillerse önceki politika korunur. İnceleme hesabı için üretim atlatması eklenmez.

Yalnız gönderen/anahtar kontrolü: `sms-kur.ps1 -Mode Check`. Yapılandırmadan sonra tek yeni SMS testi: `sms-kur.ps1 -Mode Test` (bu yeniden çalıştırma yeni bir SMS isteği yapar). Önceki normal doğrulamalardan sonra yalnız zorunluluk kontrolü/açılışı: `sms-kur.ps1 -Mode Enable`; SMS göndermeden kayıtlı anahtarı kullanır. Yeni alıcı numarası gerekirse `-Phone` belirtilir; anahtar komut satırından verilmez.

## Sonucun yorumu

- `SenderAudit.ApiAccessVerified/SenderVerified=true`: yetki/gönderici sorgusu kabul edildi; SMS teslimi anlamına gelmez.
- `SMS_CONFIGURED`, `PhoneVerificationAvailable=true`, `PhoneVerificationRequired=false`: sağlayıcı hazır, genel zorunluluk henüz kapalı.
- `OtpRequested=true`: backend sağlayıcı kabulünü aldı; telefonda görülmesi ayrıca teyit edilir.
- `PhoneVerified=true`: kullanıcının konsola girdiği gerçek kod normal doğrulama ucunda kabul edildi.
- `ReviewAccountMatched=false`: doğrulanan numara mevcut inceleme hesabından farklıdır; hesap otomatik taşınmaz.
- `Phase=REVIEW_ACCOUNT_READ_ONLY_CHECK`: hesabın gerçek doğrulaması/bilgisi kontrol edilmeden zorunluluk açılmaz. Doğrulanmamış inceleme hesabının mevcut gerçek numarası veya müşterinin hesap düzenleme kararı ayrıca gerekir.
- `PhoneVerificationRequired=true`: hazırlık sonrasında etkin zorunluluk doğrulanmıştır; yeniden açılan mevcut mobil uygulama runtime ayarını alır. Bu sunucu ayarı için Flutter kaynak değişikliği yapılmadı.

Gerçek hesap yetkisi, gönderici onayı, telefon teslimi ve sunucuya kurulum henüz yapılmış sayılmaz; kullanıcı sunucu çıktısı ve telefonda görülen kodla tamamlanacaktır. Anahtarın yazılı olduğu ham provider yanıtları, ayar dosyaları veya ekran görüntüleri gönderilmemelidir.

## Teslim doğrulaması

- Paket kaynak commit'i `c592cf15eb82e598a2c60d489e2297d03f699787`.
- ZIP: 30.433.012 bayt, SHA-256 `a0ad6bbdaa121f741ec46363e9581d999033ed98b81517a2cc69d330b67fddd9`.
- ZIP içindeki 65 manifest dosyasının özeti ve operasyon yeteneği DLL özeti doğrulandı. Paket uygulama anahtarı, özel anahtar, servis hesabı veya gerçek sunucu `settings.json` içermez.
- Backend 167 test; PowerShell ayar kurulumunun 130, normal tek alıcı OTP betiğinin 35 yerel kontrolü geçti. Gerçek sağlayıcı/ağ/IIS çağrıları bu PowerShell fixture'larında taklit edildi.
- Yayınlanmış DLL, yalnız yerel fixture ayarlarıyla `--sms-review-readiness` çalıştırıldığında tek güvenli JSON ve çıkış 0 döndürdü; HTTP dinleyicisi veya SMS başlatılmadı. Mevcut gerçek inceleme hesabının durumu bu yerel sonuçtan çıkarılamaz.
