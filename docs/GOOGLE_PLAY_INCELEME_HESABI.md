# Google Play inceleme hesabı — 18 Ekim 2026

**Son canlı doğrulama:** Müşteri `duzelt.ps1` dosyasını VDS'de başarıyla çalıştırdı. HTTPS API'ye `test` kullanıcısı ve özel parola ile giriş HTTP 200 döndürdü; hesap kimliği ve profil adı mevcut Tuna Test hesabıyla eşleşti. Kontrol için açılan ayrı oturum `/auth/logout` ile kapatıldı (204); emülatör/diğer cihaz oturumlarına dokunulmadı. Bu doğrulama API girişidir; yeni release AAB üzerinde fiziksel cihaz veya iOS giriş testi yapılmış sayılmaz. Güncel kullanıcı adı `test`; aşağıdaki önceki kurulum engelleri tarihçedir.

> Güncel tercih: Müşteri mevcut **Tuna Test** hesabını Android ve iOS için ortak kullanmak istedi. Yeni kurulum dosyası `output/backend/Test-Hesabi-Kur.ps1`, giriş adı **`test`**; hedef hesap canlı API'den adı kontrol edilen mevcut Tuna Test hesabıdır. Aşağıdaki ilk `play.inceleme` hesabı ve `Play-Inceleme-Hesabi-Kur.ps1` adları tarihçedir; yeni kurulumda kullanılmamalıdır. Yeni dosyayı sunucuya `C:\ProgramData\santiye\Test-Hesabi-Kur.ps1` olarak kopyaladıktan sonra `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\santiye\Test-Hesabi-Kur.ps1"` çalıştırın. Güncel özel parola notu `%USERPROFILE%\.santiye-secrets\test-account-login.txt` dosyasındadır. Kurulum dosyasını hazırlamak sunucuya kopyalamaz veya canlı girişi açmaz.

## Kısa kurulum seçeneği

Windows PowerShell 5.1 / Türkçe ortamında ilk parola özeti kontrolünün yanlış reddedildiği yeniden üretildi. Base64 doğrulaması büyük/küçük harfe duyarlı `-cnotmatch` kullanacak şekilde düzeltildi; Windows PowerShell 5.1 ve PowerShell 7 altında `tr-TR` regresyon kontrolleri başarılıdır. Kurulum bu hatada yarım kalmışsa `output/backend/duzelt.ps1` dosyasını `C:\ProgramData\santiye\duzelt.ps1` olarak kopyalayıp `powershell -ep bypass -File C:\ProgramData\santiye\duzelt.ps1` çalıştırın. Bu araç yalnız iki doğrulama karşılaştırmasını düzeltir, mevcut test kurulumunu yeniden çalıştırır ve başarılı olunca bakım sayfasını kaldırır; ZIP'i tekrar yüklemeyi gerektirmez.

Uzun komutları elle yazmak yerine `output/backend/kur.ps1` dosyasını sunucuya `C:\ProgramData\santiye\kur.ps1` olarak kopyalayın. Güncel `SantiyeAgi-Backend-IIS.zip`, `Test-Hesabi-Kur.ps1` ve mevcut `settings.json` aynı sunucu klasöründe bulunmalı. Yönetici PowerShell'de `powershell -ep bypass -File C:\ProgramData\santiye\kur.ps1` yeterlidir.

Bu dosya `backend/deploy/update-test-server.ps1` kaynağından, beklenen ZIP SHA-256 değeri sabitlenerek üretildi. Dosyaları ve IIS havuzunu kontrol eder; ZIP'i ayrı klasörde açar, gerekli API/yardımcı dosyaları doğrular. Bakım sırasında eski site dosyalarını ve dış ayarları erişimi sınırlı yedek klasörüne kopyalar, yayın dosyalarını günceller, mevcut test hesabı kurulumunu çalıştırır ve siteyi açar. Hata olursa bakım sayfasını koruyup hatayı gösterir; otomatik geri alma veya veritabanı temizleme yapmaz. Yerelde söz dizimi ve ZIP eşleşmesi kontrol edildi; gerçek IIS güncellemesi henüz denenmedi.

## Durum

Gerçek VDS API'si üzerinden `Google Play İnceleme` adlı, İstanbul / Müteahhit rolünde teknik kontrol profili oluşturuldu. Profil gerçek PostgreSQL'de saklanır; örnek/demo backend kullanılmaz. Kullanıcı adı `play.inceleme` olarak tanımlanacak. Parola ve hesap kimliği özel yerel dosyalarda tutulur; kaynak koduna veya AAB'ye konulmaz.

Eski uygulamada profil oluşturma vardı, fakat SMS kapalıyken aynı hesaba başka cihazdan kullanıcı adı/parola ile giriş yoktu. Bu erişim yeni API ve `2.1.2 (7)` mobil sürümüyle eklendi. **Sunucuya yeni API ve hesaba ait yapılandırma yüklenmeden parola ile canlı giriş çalışmaz.** Önceki `2.1.2 (6)` AAB giriş ekranını içermez.

## Erişim tasarımı

- Giriş: `POST /api/v1/auth/password/login`. Sunucuda dış yapılandırmayla tanımlanmış hesaplara uygulanır; anonim isteklerden hesap sahipliği alınmaz.
- Açık parola yerine rastgele 16 bayt salt ve 600.000 iterasyonlu PBKDF2-SHA256 hash saklanır. Parola 12–128 karakter olmalıdır; karşılaştırma sabit zamanda yapılır.
- Mevcut IP tabanlı `auth` istek sınırı bu endpoint için de geçerlidir. Gizli bilgiler ve kullanıcı listesi `/auth/options` yanıtına eklenmez; yalnız özelliğin açık olup olmadığı döner.
- Her başarılı giriş mevcut JWT/refresh/session altyapısıyla ayrı oturum oluşturur; kullanıcının kredi, Premium veya diğer yetkilerini değiştirmez. Profil/hesap silinirse giriş yeniden kullanılamaz.
- Telefon doğrulama rozeti verilmez. SMS zorunluluğu açıldığında doğrulanmamış kullanıcı parola ile bu kuralı geçemez. Geliştirme OTP'si veya tüm hesapları açan ortak kod eklenmedi.
- Mobil açılışında sunucu bu girişi açmışsa “Hesabım var — kullanıcı adıyla giriş” görünür. Koşulları kabul edip bu bağlantıya dokunarak mevcut hesaba girilir.

## Sunucuda kurulum

1. `output/backend/SantiyeAgi-Backend-IIS.zip` dosyasındaki yeni API'yi mevcut `C:\inetpub\wwwroot\santiye` klasörüne normal bakım yöntemiyle yükleyin. Önce `app_offline.htm` oluşturun, uygulama havuzunu durdurun, yeni yayın dosyalarını kopyalayın. Dış `C:\ProgramData\santiye\settings.json` ve Firebase anahtarını koruyun. Bu değişiklik yeni veritabanı migration'ı gerektirmez; hesap temizleme çalıştırmayın.
2. Hesaba özel `output/backend/Play-Inceleme-Hesabi-Kur.ps1` dosyasını `C:\ProgramData\santiye\Play-Inceleme-Hesabi-Kur.ps1` konumuna kopyalayın. Bu dosya web klasöründe tutulmamalı; hesaba ait parola hash'i içerdiğinden Git'e eklenmez.
3. Yönetici PowerShell'de çalıştırın:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\santiye\Play-Inceleme-Hesabi-Kur.ps1"
Remove-Item -LiteralPath 'C:\inetpub\wwwroot\santiye\app_offline.htm' -ErrorAction SilentlyContinue
Import-Module WebAdministration
Start-WebAppPool -Name 'santiye'
```

4. `/api/v1/auth/options` yanıtında `password_login_enabled: true` görülmeli. Yeni AAB'yi yükleyin; iki ayrı oturumda aynı profile erişimi canlıda doğrulayın. Sonra Play erişim bilgilerini kaydedin.

Genel kurulum aracı `deploy/set-account-login.ps1` diğer dış sunucu ayarlarını korur. Aynı kullanıcı için tekrar çalıştırmak ikinci kayıt oluşturmaz. Parolayı değiştirmek için yeni salt/hash hazırlayıp hesaba ait yapılandırmayı yeniden yükleyin. Özelliği kapatmak için `Auth.AccountLogin.Enabled=false` kullanılır; mevcut oturumları iptal etmek ayrı işlemdir.

## Forma yazılacak bilgiler

- Ad: `Google Play review account`
- Kullanıcı adı: `play.inceleme`
- Parola: özel `%USERPROFILE%\.santiye-secrets\play-review-login.txt` dosyasında.
- Giriş talimatı (kurulum ve canlı doğrulama sonrası):

> On the welcome screen, accept the terms checkbox. Tap “Hesabım var — kullanıcı adıyla giriş”. Enter the username and password provided above, then tap “Giriş yap”. The account uses the live backend. Notification permission is optional for browsing the app.

## Yapılan kontroller ve kalan sınır

- .NET derlemesi başarılı; 77 backend testi geçti. Testler yalnız yerelde kendileri tarafından oluşturulan `santiye_test_*` veritabanlarında çalıştı. Aynı hesaba iki bağımsız giriş, yanlış parola, doğrulanmamış telefon için SMS kuralı ve silinen hesabın reddi kontrol edildi.
- 182 Flutter testi geçti; 2 yerel API testi standart turda atlandı. Parola girişinin yanlış parolada önceki oturumu koruması ve başarılı girişte parolayı saklamadan oturumu kaydetmesi kontrol edildi. Flutter analizi temiz.
- `SantiyeAgi-2.1.2-7-Kapali-Test.aab` release derlemesi başarılı. İmza, bundletool yapısal doğrulama, `com.santiyeagi.app`/sürüm kodu 7 manifesti ve 64 bit 16 KB segment hizalaması doğrulandı. Boyut 47.828.189 bayt; SHA-256: `A837FCB447B9AB47A6EA2B4C91E625A9993BA4083426F7C7103FC0415C4E6B9B`.
- PowerShell kurulum aracı yerelde SMS, push, bağlantı ayarlarını korudu ve tekrar kurulumda kullanıcıyı çoğaltmadı.
- **Canlıda yalnız profil oluşturuldu. Yeni parola endpoint'inin VDS'ye kurulumu ve mobil cihazda uçtan uca giriş henüz doğrulanmadı.**
- Hesap ücretsiz hesap yetkilerindedir. Doğrulanmış mağaza makbuzu olmadan Premium/kredi verilmedi. Ücretli bölümlerin incelemeciye tam erişimi hâlâ yayın öncesi çözülmelidir; yalnız giriş bilgilerini vermek bunu tamamlamaz.
