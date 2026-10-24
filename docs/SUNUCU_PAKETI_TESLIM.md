# Şantiye Ağı — sunucu paketini kurma

Bu paket .NET 10 API'nin Windows x64 / IIS yayın dosyalarıdır. Flutter uygulaması bu API ile konuşur; PostgreSQL aynı sunucuda çalışabilir. Sunucuda .NET SDK veya Visual Studio gerekmez, .NET 10 Hosting Bundle gerekir.

**Mevcut 45.59.70.198 sunucusuna güncelleme:** Bu sürüm `HaulPoints` tablosunu ekler. `kurulum-notlari/CANLI_GUNCELLEME.md` adımlarını uygulayın; dosyaları yükledikten sonra `deploy/apply-migrations.ps1` çalıştırılmalıdır. Hesap temizleme betiği tekrar çalıştırılmamalıdır.

## Paketin içindekiler

- `SantiyeAgi.Api.dll`, bağımlılıklar ve IIS için `web.config`.
- `deploy/configure-iis.ps1`: uygulama havuzu, sunucuya özel ayarlar, klasör izinleri ve veritabanı migration kurulumu.
- `deploy/postgresql-migrations.sql`: aynı şema için alternatif, idempotent SQL dosyası. `--migrate` kullanıldıysa ayrıca çalıştırmanız gerekmez.
- `deploy/backup-postgres.ps1`: PostgreSQL custom-format yedeği.
- `kurulum-notlari/`: SMS, push, mağaza ve mobil yayın bağlantısı.
- `kurulum-notlari/BACKEND_KABUL_KONTROLU.md`: kontrol edilen iş akışları, test sonuçları ve canlı hizmetlerde kalan adımlar.
- `PACKAGE-MANIFEST.json`: paketin dosya listesi ve SHA-256 kontrol değerleri.

Parolalar, SMS anahtarları, Firebase servis hesabı ve Apple özel anahtarı pakete dahil değildir. Var olan sunucunun veritabanını veya müşteri verilerini içermez.

## İlk kurulum sırası

1. IIS ve ardından **.NET 10 Hosting Bundle**, ayrıca **PostgreSQL 17** kurulu olmalı. Windows yeniden başlatma gerekiyorsa tamamlayın.
2. PostgreSQL'de `santiye` veritabanını oluşturun. API aynı sunucudaysa PostgreSQL'i `127.0.0.1:5432` üzerinden kullanın.
3. ZIP'i örneğin `C:\Sites\SantiyeAgi` klasörüne açın. Alan adı için A kaydını VDS IP'sine yönlendirin. HTTPS sertifikasını kurun.
4. Yönetici PowerShell'de çalıştırın. Alan adı örneğini kendi API alan adınızla değiştirin:

```powershell
Set-Location C:\Sites\SantiyeAgi
.\deploy\configure-iis.ps1 -SitePath C:\Sites\SantiyeAgi -HostName api.sizin-alan-adiniz.com -DatabaseName santiye -DatabaseUser postgres
```

Betik PostgreSQL parolasını ekranda göstermeden ister. Sunucuya özel ayarları `C:\ProgramData\SantiyeAgi\settings.json` içinde oluşturur. İmzalama anahtarını üretir, şemayı kurar; IIS havuzunu **No Managed Code / 64 bit / AlwaysRunning** olarak ayarlar. Var olan ayar dosyasını üzerine yazmaz.

İlk kurulumda mevcut `postgres` hesabıyla deneme yapılabilir. Canlıya geçmeden uygulamaya özel PostgreSQL hesabı ve uygun izinler yapılandırılmalıdır. SQL ve migration aynı uygulama şemasını kurar; Supabase tablolarının otomatik taşınması yapılmaz.

5. Betiğe `-CertificateThumbprint SERTIFIKA_PARMAK_IZI` vererek mevcut Windows sertifikasını HTTPS bağlamasına takabilirsiniz; IIS üzerinden elle de yapılabilir. Güvenlik duvarında HTTP/HTTPS ve gerekli yönetim erişimini sağlayın.
6. `https://api.sizin-alan-adiniz.com/health/ready` yanıtı `ready` olmalı.
7. Aşağıdaki servis ayarlarını tamamlayıp uygulama havuzunu yeniden başlatın. Mobil uygulamayı bu HTTPS adresiyle derleyin.

## Canlı servislerin durumu

| Bölüm | Paketteki davranış | Canlıda gereken |
|---|---|---|
| Profil, ilan, teklif, anlaşma, puan, fotoğraf | API ve PostgreSQL üzerinden çalışır | Veritabanı, HTTPS, mobil API adresi |
| Telefon doğrulama | VatanSMS OTP adaptörü; 5 dakika geçerli, sınırlı deneme ve gönderim | API ID, API key, onaylı başlık, OTP yetkisi ve bakiye |
| Google Play / App Store | Sunucu doğrulaması, hak kaydı, abonelik yenileme ve iade takibi | Mağaza ürünleri, servis erişimleri, webhook ve gerçek sandbox kontrolleri |
| Anlık bildirim | FCM cihaz kaydı, kalıcı gönderim kuyruğu ve tekrar deneme | Firebase projesi; mobil platform dosyaları; sunucu servis hesabı; iOS APNs bağlantısı |

Servisler kurulmadığında canlı SMS gönderilmez ve doğrulanmamış satın almaya kredi/Premium verilmez. Development kodu Production ortamında geçerli değildir. Hesaplarda gerçek mağaza/SMS/Firebase bilgileri olmadığı için bu bağlantıların canlı uçtan uca testi teslim sırasında yapılmış sayılmaz.

Bu teslimde kullanıcı talebiyle SMS zorunluluğu kapalıdır. Yeni kullanıcılar SMS kodu beklemeden profil oluşturabilir; telefon doğrulanmış gösterilmez. `deploy/set-sms-verification.ps1 -Mode On` ile gerçek SMS hazır olduğunda zorunluluk açılır; `-Mode Off` ile kapanır. Ayrıntılar: `kurulum-notlari/SMS_AC_KAPAT.md`. Mevcut sunucuya yeni ZIP yüklenmeden bu davranış değişmez. Yerel test hesapları pakette yoktur.

## Çalışma ve bakım

- Kurulum betiği IIS Application Initialization rol hizmetini ve site ön yüklemesini etkinleştirir. Havuz AlwaysRunning ve boşta kapanma kapalı olarak ayarlanır. Sunucu yeniden başladıktan sonra sağlık adresiyle çalışmayı kontrol edin.
- Sitede işletim sistemi güncellemesi/yeniden başlatma, veritabanı yedeği ve disk kullanımı izlenir. 4 GB RAM kapasitesi gerçek trafik ve fotoğraf büyüklükleriyle ölçülür.
- `C:\ProgramData\SantiyeAgi\keys` ve ayar dosyasını güvenli şekilde yedekleyin. Windows DPAPI ile korunan anahtarların başka sunucuya taşınması ayrı anahtar aktarım planı gerektirir; yalnız klasörü kopyalamak yeterli olmayabilir.
- Fotoğraflar PostgreSQL yedeğine dahildir. Yedeklemeyi Görev Zamanlayıcı ile günlük çalıştırın, sunucu dışında bir kopya tutun ve geri yüklemeyi ayrı test veritabanında deneyin.
- Paket güncellemeden önce yedek alın. IIS'i durdurup yeni dosyaları açın; sunucuya özel ayarları ve anahtar klasörünü koruyun. Migration'ı uygulayın, havuzu başlatıp sağlık ve mobil temel akışları kontrol edin.

15 Ekim 2026 itibarıyla müşterinin `https://45.59.70.198` adresindeki IIS ve PostgreSQL sağlık kontrolleri başarılıdır. IP sertifikası IIS'te WebHosting deposundan, boş ana bilgisayar adı ve SNI kapalı olacak şekilde 443 bağlantısına takıldı. Simple-acme yenileme görevinin çalışması izlenmelidir. Yukarıdaki alan adlı ilk kurulum örneği alternatif yeni kurulumlar içindir; mevcut sunucuyu yeniden kurmak gerekmez.

Gerçek mağaza/SMS/push teslimat kontrolleri müşteri hizmet hesapları yapılandırıldıktan sonra yapılacaktır. SMS kurulmadan kalan özelliklerin ayrı Development API ile kontrol sonuçları kabul belgesinde bulunur.
