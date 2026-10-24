# Şantiye Ağı - Windows VDS kurulum sırası

14 Ekim 2026. Windows Server 2022 x64 için hazırlanmıştır. Yeni VDS'ye bu çalışma sırasında bağlantı veya kurulum yapılmadı.

## 1. Windows güncellemeleri

Windows Update'i çalıştırın, güncellemeleri yükleyin ve gerekiyorsa sunucuyu yeniden başlatın.

## 2. IIS

Server Manager > Add Roles and Features > Role-based or feature-based installation > Web Server (IIS) yolundan IIS'i ve yönetim araçlarını kurun. Varsayılan web özellikleriyle birlikte HTTP Logging ve Request Monitor açık olabilir.

Alternatif olarak sunucuda yönetici PowerShell:

```powershell
Install-WindowsFeature -Name Web-Server,Web-Mgmt-Console,Web-Http-Logging,Web-Request-Monitor -IncludeManagementTools
```

Yükleme sonucunda yeniden başlatma istenirse uygulayın. IIS Manager'ın açıldığını kontrol edin.

## 3. .NET 10 Hosting Bundle

[Resmî .NET 10 indirme sayfasında](https://dotnet.microsoft.com/en-us/download/dotnet/10.0) ASP.NET Core Runtime bölümünün Windows satırındaki **Hosting Bundle** kurulumunu seçin. 14 Ekim itibarıyla güncel kararlı sürüm 10.0.13'tür.

Hosting Bundle'ı IIS'ten sonra kurun; IIS daha sonra kurulmuşsa Hosting Bundle kurulumunu Repair ile tekrar çalıştırın. Paket runtime ve IIS'in ASP.NET Core modülünü içerir. Hazır yayın paketini çalıştırmak için sunucuda SDK veya Visual Studio kurulması gerekmez. [Microsoft IIS rehberi](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/iis/?view=aspnetcore-10.0)

Kurulumdan sonra sunucuyu yeniden başlatın. Yönetici PowerShell'de kontrol edin:

```powershell
dotnet --list-runtimes
```

Listede Microsoft.NETCore.App 10.0.x ve Microsoft.AspNetCore.App 10.0.x görünmeli.

## 4. PostgreSQL 17 x64

[PostgreSQL Windows indirme sayfasından](https://www.postgresql.org/download/windows/) EDB installer bağlantısına gidin ve PostgreSQL 17'nin güncel Windows x64 sürümünü kurun. Bu projenin yerel veritabanı testleri PostgreSQL 17 ile yapıldı; PostgreSQL'in resmî sayfası Windows Server 2022 için 17 sürümünü listeler.

Kurulum bileşenleri: PostgreSQL Server, Command Line Tools ve yönetim için pgAdmin 4. Stack Builder'dan ek bileşen kurulmasına bu proje için gerek yok.

- Varsayılan port: 5432.
- Yönetici hesabı: postgres; güçlü, ayrı bir parola belirleyin.
- PostgreSQL Windows hizmetinin çalıştığını kontrol edin.
- API aynı sunucuda çalışacağı için bağlantı adresi 127.0.0.1 olacak.
- postgresql.conf içindeki listen_addresses ayarını localhost ile sınırlayın; değiştirdiğinizde PostgreSQL hizmetini yeniden başlatın.
- 5432 portuna internetten erişim açmayın.

## 5. Uygulama veritabanı ve kullanıcıları

pgAdmin'de yalnız uygulama için santiye veritabanını hazırlayın. Şema kurulum/geçişi için ayrı kurulum hesabı, API çalışması için kısıtlı santiye_app hesabı kullanın. API postgres süper kullanıcısı ile çalıştırılmamalı. Migration sonrası santiye_app hesabına ilgili tablolar ve şema için gerekli erişimler verilecek.

Kaynakta PostgreSQL migration dosyaları ve output/backend/postgresql-migrations.sql bulunuyor. Boş veritabanının oluşturulması ile uygulama tablolarının kurulması ayrı adımlardır.

## 6. Alan adı ve HTTPS

Kullanılacak API alt alan adının A kaydını VDS'nin IPv4 adresine yönlendirin. api.sizin-alan-adiniz.tld burada yalnız bir örnektir; müşterinin gerçek alan adı kullanılacak.

TLS sertifikası hazırlayın, IIS'te alan adına uygun HTTPS/443 bağlamasını oluşturun. Windows ve sağlayıcının güvenlik duvarında web trafiği için 80 ve 443 portlarını açın. Uzak masaüstü erişimini yönetim adresleriyle sınırlayın.

## 7. IIS uygulama havuzu ve yayın klasörü

Örnek klasör: C:\Sites\SantiyeAgi.Api. Ayrı bir SantiyeAgiApi uygulama havuzu oluşturun:

- .NET CLR Version: No Managed Code.
- Managed Pipeline Mode: Integrated.
- Enable 32-Bit Applications: False.
- Site yolu: yayın klasörü.
- Site host adı: müşterinin API alan adı.

IIS havuz kimliğine yayın klasörünü okuma/çalıştırma izni verin. Galerinin normalize edilmiş fotoğrafları PostgreSQL'de tutulur; ayrı bir herkese açık yükleme klasörü kullanılmaz.

output/backend/SantiyeAgi-Backend-IIS.zip içeriğini yayın klasörüne açın; web.config, çalıştırılabilir dosya, DLL'ler ve ayarlar aynı düzeyde bulunmalı. Bu ZIP ilk backend grubudur; tamamlanmış canlı teslim paketi değildir.

## 8. Sunucu ayarları ve tablo kurulumu

IIS uygulama havuzunun ortam değişkenlerinde aşağıdaki değerleri tanımlayın; değişiklikten sonra havuzu yeniden başlatın:

| Ayar | Değer |
|---|---|
| ASPNETCORE_ENVIRONMENT | Production |
| ConnectionStrings__Postgres | Host=127.0.0.1;Port=5432;Database=santiye;Username=santiye_app;Password=SUNUCUDA_BELIRLENECEK_PAROLA |
| Auth__SigningKey | En az 32 bayt uzunluğunda, rastgele ve kalıcı gizli anahtar |
| AllowedHosts | Gerçek API alan adı |

Parola ve anahtarlar kaynak koduna/yayın ZIP'ine eklenmez. Migration komutu için ayrı PowerShell oturumunda aynı ayar adlarını, geçici şema kurulum hesabının bağlantısıyla tanımlayın. IIS'teki uygulama havuzu ayarları PowerShell oturumuna kendiliğinden aktarılmaz.

Yayın klasöründe, kurulum hesabının yetkileriyle tablo geçişini uygulayın:

```powershell
dotnet .\SantiyeAgi.Api.dll --migrate
```

API'yi çalıştırırken kısıtlı uygulama hesabını kullanın. Veritabanı ve sonradan eklenecek fotoğraflar için sunucu dışına günlük yedek ve geri yükleme kontrolü planlayın.

## 9. Kontrol ve mobil bağlantı

Gerçek HTTPS adresinden /health/live yanıtı ok, /health/ready yanıtı ready olmalı. Ardından Flutter derlemesine müşterinin API adresi API_BASE_URL olarak verilecek ve uygulama aynı PostgreSQL verilerini kullanacak.

Şu an yerel bağlantı http://10.0.2.2:5080 ile Android emülatörde kullanılıyor. Bu adres müşterinin VDS adresi değildir.

## Güncel giriş ve teslim durumu

Kullanıcı isteğiyle gerçek SMS entegrasyonu sonraya bırakıldı. Şimdilik yerel Development ortamında test koduyla giriş ve doğrulama durumu gösterilecek. Test hesabı, telefon sahibinin gerçek SMS ile doğrulandığı anlamına gelmez. Production ortamında test kodu veya anonim giriş açılmadı.

İş fotoğraf galerisi ilk sürümü eklendi; AddPortfolioPhotos migration'ı ve güncel yayın paketi kullanılmalı. Canlı giriş yöntemi/SMS, push, Google/Apple ödeme-abonelik-iade işlemleri ve mağaza testleri tamamlanmadan tüm proje bitmiş sayılmaz. Kurulum yapılabilir; bu paketin yeni kullanıcı kaydı ve ücretli satış özellikleri henüz canlı kullanıma hazır değildir.
