# SMS doğrulamasını açma ve kapatma

Bu teslim paketinde SMS zorunluluğu kapalı başlar. Kullanıcı doğrudan profil oluşturur; işlemler normal API oturumuyla PostgreSQL'e kaydedilir. Telefon doğrulanmış sayılmaz ve doğrulama rozeti gösterilmez. SMS gönderilmez.

## Mevcut sunucuya güncelleme

SMS ayarının kendisi yeni veritabanı migration'ı gerektirmez. Güncel paket ayrıca hafriyat tablosunu eklediğinden yükleme için `CANLI_GUNCELLEME.md` adımlarını izleyin. `C:\ProgramData\santiye` içindeki ayarlar ve anahtarlar korunur. Mevcut HTTP/HTTPS bağlantılarını yeniden oluşturmayın.

Uygulamayı yeniden açın. `/api/v1/auth/options` adresi `phone_verification_required: false` döndürmelidir. Sunucuya özel ayarlarda daha önce `true` tanımlandıysa aşağıdaki Off komutunu çalıştırın.

## Tek komutla değişiklik

Sunucuda yönetici PowerShell kullanın. SMS'i kapatmak:

```powershell
& "C:\inetpub\wwwroot\santiye\deploy\set-sms-verification.ps1" -Mode Off
```

Gerçek SMS sağlayıcısı kurulduktan sonra açmak:

```powershell
& "C:\inetpub\wwwroot\santiye\deploy\set-sms-verification.ps1" -Mode On
```

Betik `C:\ProgramData\santiye\settings.json` içindeki `Auth.RequirePhoneVerification` değerini değiştirip `santiye` uygulama havuzunu yeniden başlatır. Diğer ayarlar, anahtarlar ve veriler korunur. Mobil uygulamayı yeniden açın; APK güncellemesi gerekmez.

SMS açıldığında doğrulanmamış mevcut oturumlar da telefon doğrulamasına yönlendirilir. Doğru SMS koduyla aynı telefonun hesabına dönülür; önceki kayıtları korunur. Kapalıyken hesap cihazdaki oturuma bağlıdır: uygulama verileri silinirse veya cihaz değiştirilirse yalnız telefon yazmak eski hesaba erişim sağlamaz. Aynı telefonla ikinci hesap açılmaz.

Production ortamında geliştirme test kodu kullanılmaz. Gerçek SMS gönderimi sağlayıcı kurulumu sonrası ayrıca kontrol edilecek. Mağaza satın almaları ve push bildirimleri bu ayardan bağımsızdır.
