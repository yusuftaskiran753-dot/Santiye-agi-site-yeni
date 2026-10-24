# Şantiye Ağı .NET backend

.NET 10, PostgreSQL ve IIS için hazırlanan API. Mobil `Backend` arayüzündeki alanlar ve JSON isimleri esas alınmıştır. Mevcut Supabase veritabanına doğrudan kurulum yapılmaz; yeni `santiye` şeması kullanılır.

## Hazır olan geliştirme grubu

- JWT erişim/yenileme oturumu, yenileme token rotasyonu, çıkışta iptal ve hesap silmede oturum iptali.
- Kullanıcı profili, beş ilan türü ve sahiplik/yetki kontrolleri.
- Liste, teklif ve anlaşmalarda sayfalama; eski 300 kayıt sınırına bağlı olmayan mobil okuma.
- İletişim hakkı, ücretsiz hak, kredi cüzdanı ve ilan öne çıkarma kontrolleri.
- Teklif kabul/ret/geri çekme; makine müsaitliği ve engelleme kontrolü.
- Elle anlaşma, katılım kodu, teslim, tamamlama, not ve puanlama.
- Aktif anlaşma iptalinde karşılıklı onay; sorun çözümünün sorunu bildiren tarafça onaylanması.
- Hesap silme ve karşı tarafta kalan puanların anonimleştirilmesi.
- Uygulama içi bildirimler ve süreye bağlı bildirim temizliği.
- PostgreSQL işlemleri/kilitleri ve `Idempotency-Key` ile tekrar gönderim kontrolü.
- Flutter `DotNetBackend`, güvenli token saklama ve yerel test bağlantısı.
- Kullanıcıya özel hafriyat sahası/ocak kayıtları; PostgreSQL'de kalıcılık, sahiplik kontrolü ve hesap silmede temizlik. Optimizasyon hesabı mobilde çalışır.

## Canlı servis ayarları ve teslim

SMS zorunluluğu `Auth:RequirePhoneVerification` ile yönetilir. Kaynak varsayılanı `true`, müşterinin bu teslim için istediği IIS paket varsayılanı `false` değeridir. Kapalıyken normal cihaz oturumuyla profil oluşturulur; telefon doğrulanmış sayılmaz. Sunucu ayarı açıldığında mevcut doğrulanmamış oturumlar da kısıtlanır. Mobil ayarı API'den okur. [SMS aç/kapat rehberi](../docs/SMS_AC_KAPAT.md).

- **Telefon:** VatanSMS.net OTP adaptörü, kalıcı gönderim sınırları ve kısa süreli kod hazır. Müşterinin API ID/key, onaylı başlık ve OTP yetkisi sunucuda tanımlanınca gerçek gönderim kontrol edilir. WhatsApp doğrulaması eklenmedi. Eksik ayarda Production `CONFIG` döner; geliştirme koduyla giriş atlatılmaz.
- **Google/Apple satın alma ve iadeler:** Gerçek mağaza API'sinden makbuz doğrulama, hesap eşleştirme, tekrar kredi vermeme, yenileme/iptal/iade takibi ve webhook uçları hazır. Gerçek mağaza anahtarları/ürünleri girilmeden `CONFIG` döner ve hak vermez. Harcanmış kredinin iadesi gelecekteki alımdan mahsup edilir. Ayrıntılar: [ödeme kurulumu](../docs/ODEME_KURULUMU.md).
- **Push:** Firebase HTTP v1, cihaz/oturum ilişkisi, kalıcı gönderim kuyruğu ve tekrar deneme hazır. 16 Ekim'de gerçek VDS'den Android emülatörüne arka plan ve kapalı işlem bildirimi ile bildirimden açılış doğrulandı. Fiziksel Android cihaz ve iOS/APNs testi kalır. Ayrıntılar: [Android canlı kontrolü](../docs/ANDROID_BILDIRIM_CANLI_KONTROLU_2026-10-16.md), [SMS ve bildirim kurulumu](../docs/BILDIRIM_SMS_KURULUMU.md).
- **Fotoğraf galerisi:** İlk sürüm hazır. Kullanıcı profillerinde yükleme, açıklama, büyütme ve sahip tarafından silme var. JPEG/PNG/WebP kabul edilir; en fazla 8 MB giriş, 12 megapiksel ve hesap başına 20 fotoğraf. Görüntü 1600 piksele küçültülüp JPEG olarak yeniden kodlanır; EXIF/GPS bilgisi saklanmaz. Normalize edilmiş görüntüler PostgreSQL'de bytea olarak tutulur; veritabanı yedeği fotoğrafları da içerir. Hesap silinince fotoğraflar da silinir. Görüntüler yalnız oturum açmış, engelleme kuralına uygun kullanıcılara API üzerinden verilir.
- **Canlı veri taşıma:** Eski canlı kullanıcı/veri varsa ayrıca aktarım planı gerekir.

IIS paketi ve kurulum betikleri hazırdır. Müşteri VDS kurulumu ve gerçek dış hizmetlerin kabul testleri sonraki aşamadır. [Sunucu paketi](../docs/SUNUCU_PAKETI_TESLIM.md), [mobil bağlantı](../docs/MOBIL_BAGLANTI_VE_YAYIN.md), [ilk demo envanteri](../docs/MOBIL_ILK_SURUM_OZELLIK_ENVANTERI.md).

## Geliştirme kurulumu

1. .NET 10 SDK ve PostgreSQL 17 veya desteklenen daha yeni bir sürümü hazırlayın.
2. Yalnız uygulama için veritabanı/kullanıcı oluşturun. API çalışma kullanıcısına PostgreSQL süper kullanıcı yetkisi vermeyin.
3. Bağlantı bilgisini ortam değişkeni veya `dotnet user-secrets` ile verin. Parolayı kaynak koduna yazmayın.

```powershell
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:ConnectionStrings__Postgres = 'Host=127.0.0.1;Port=5432;Database=santiye;Username=santiye_app;Password=YEREL_PAROLA'
# En az 32 baytlık rastgele anahtar; yeniden başlatmalarda aynı değer kullanılmalı.
$env:Auth__SigningKey = 'YEREL_GUVENLI_RASTGELE_ANAHTAR'
dotnet run --project backend/SantiyeAgi.Api -- --migrate
dotnet run --project backend/SantiyeAgi.Api --no-launch-profile --urls http://127.0.0.1:5080
```

Development ortamında anahtar verilmezse yalnız o süreç için rastgele anahtar üretilir. Yeniden başlatmada aktif erişim tokenları geçersiz olur; test için kalıcı yerel anahtar önerilir.

Sağlık kontrolü: `/health/live` ve `/health/ready`.

## Android emülatör bağlantısı

```powershell
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:5080
```

`API_BASE_URL` verilirse .NET kullanılır. Verilmezse önceki demo/Supabase seçimi korunur. Yerel HTTP yalnız debug derlemesinde kabul edilir; canlı adres HTTPS olmalıdır.

Geliştirme telefon akışında rastgele test kodu uygulamadaki bilgi kutusunda görünür; gerçek SMS gönderilmez. VatanSMS yapılandırması etkinleştirilince SMS gönderilir; Production yanıtına kod eklenmez.

### Kalıcı yerel test hesabı

```powershell
./backend/deploy/create-local-test-account.ps1
```

Araç yalnız localhost/127.0.0.1 adresini kabul eder; Development kodunu alıp normal doğrulama API'sinden geçer. Test Kullanıcısı / Şantiye Ağı Test profili ve +905000000001 test telefonu kullanılır. Kimlik/telefon sahipliği gerçek SMS ile teyit edilmiş değildir. Terminale erişim tokenı veya yenileme tokenı yazılmaz. Aynı test telefonu tekrar kullanıldığında mevcut test hesabı güncellenir. Kod isteği başına 60 saniye bekleme kuralı korunur.

Emülatörde bu telefonla kod isteyin; ekranda çıkan geçici geliştirme kodunu girin. Profilde Telefon doğrulandı rozeti görünür. Gerçek SMS sağlayıcısı bağlandığında bu geliştirme kodunun yerini SMS gönderimi alacak.

## IIS / Windows Server 2022

Adım adım sıralı hazırlık: [VDS kurulum rehberi](../docs/VDS_KURULUM_REHBERI.md). Önce IIS, sonra .NET 10 Hosting Bundle kurulmalıdır; PostgreSQL ayrı bileşendir.

1. PostgreSQL'i kurun, uygulama veritabanını ve kısıtlı çalışma kullanıcısını oluşturun. PostgreSQL portunu internete açmayın; aynı sunucuda loopback kullanın.
2. IIS ve .NET 10 Hosting Bundle kurun; Hosting Bundle IIS'ten sonra kurulmalıdır.
3. Yayın paketini hazırlayın:

```powershell
./backend/deploy/publish-iis.ps1
```

4. Paket dosyalarını IIS sitesi klasörüne açın. Ayrı uygulama havuzu kullanın: **No Managed Code**, 64 bit. TLS sertifikası ve HTTPS bağlamasını ekleyin.
5. Paketteki `deploy/configure-iis.ps1` betiği bağlantı ve imzalama anahtarını site dışında `C:\ProgramData\SantiyeAgi\settings.json` içinde oluşturur. API `SANTIYE_CONFIG_FILE` ile okur. `DataProtection:KeysPath` kalıcı anahtar klasörü olmalıdır. Sırları ZIP veya Git'e koymayın.
6. Veritabanı geçişini tek seferlik ayrı kurulum yetkisiyle uygulayın. API kullanıcısına sürekli şema değiştirme yetkisi vermeyin. Yayınlanan klasörde:

```powershell
dotnet SantiyeAgi.Api.dll --migrate
```

7. `/health/ready` ve mobil HTTPS bağlantısını kontrol edin. Her yükseltmeden önce veritabanı yedeği alın. IIS kimliğine yalnız gerekli klasör izinlerini verin.

**Not:** Müşteri sunucusuna kurulum henüz yapılmadı. Yerel PostgreSQL, sahte sağlayıcı HTTP yanıtları ve mobil testler gerçek SMS/mağaza/FCM teslimat kontrolü yerine geçmez. Gerekli servis ayarları girildikten sonra canlı kabul kontrolü yapılmalıdır.

## Testler

Saf iş kuralı testleri ve gerçek PostgreSQL üzerinde HTTP entegrasyon testleri bulunur. Entegrasyon testleri yalnız localhost üzerinde, kendilerinin oluşturduğu rastgele `santiye_test_*` veritabanını kullanıp temizler.

Fotoğraf tabloları için AddPortfolioPhotos migration'ı uygulanmalıdır. `GET /api/v1/profiles/{userId}/portfolio` metadata listesini, `GET /api/v1/portfolio/{photoId}/image` JPEG görüntüyü verir. Yükleme `POST /api/v1/portfolio` multipart alanları `id`, `caption`, `file`; silme `DELETE /api/v1/portfolio/{photoId}`. Tekrar denemede aynı id ve içerik kullanılmalıdır. Aynı anda en fazla iki yükleme işlenir. Orijinal dosya adı, dosya yolu ve MIME bilgisi erişim/yetki kararı için kullanılmaz.

```powershell
$env:SANTIYE_TEST_POSTGRES = 'Host=127.0.0.1;Port=5432;Database=postgres;Username=YEREL_TEST_ADMIN;Password=YEREL_TEST_PAROLA'
dotnet test backend/SantiyeAgi.slnx
```

Bu bağlantı yalnız test içindir; canlı veritabanı bağlantısı verilmemelidir. Test kullanıcısının veritabanı oluşturabilmesi gerekir. Yalnız iş kuralı testleri için `--filter FullyQualifiedName~DomainTests` kullanabilirsiniz.

## Teknik referanslar

- [Microsoft IIS yayın rehberi](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/iis/?view=aspnetcore-10.0)
- [Npgsql EF Core 10](https://www.npgsql.org/efcore/release-notes/10.0.html)
