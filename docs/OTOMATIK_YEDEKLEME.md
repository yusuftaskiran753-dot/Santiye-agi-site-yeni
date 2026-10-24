# Şantiye Ağı otomatik yerel yedekleme

19 Ekim 2026. Müşteri tercihiyle **sunucu dışına kopya gönderilmez**. GitHub kaynak kodunu saklar; müşteri hesapları, ilanlar, anlaşmalar ve fotoğraflar GitHub'da tutulmaz.

## Tek dosyayla mevcut VDS'ye kurulum

Geliştirici `tools/package_backup_setup.ps1` ile yerel `output/backend/yedek.ps1` dosyasını üretir. Bu dosya araç kodlarını içerir, parola veya müşteri yedeği içermez. Yeni backend ZIP'i yüklemek gerekmez.

1. `yedek.ps1` dosyasını sunucuya `C:\ProgramData\santiye\yedek.ps1` olarak kopyalayın.
2. Yönetici PowerShell'de çalıştırın:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\yedek.ps1
```

Mevcut `C:\ProgramData\santiye\settings.json` içindeki PostgreSQL bağlantısı okunur. Mobil/API kullanıcı ayarları, SMS, bildirim ve mağaza ayarları değiştirilmez. Siteyi bakıma almaz; mevcut kayıtlar silinmez.

Kurucu ilk yedeği ve geri yüklemeyi yapar, `SantiyeAgi-DailyBackup` görevini **SYSTEM** kimliğiyle kaydeder ve görevi bir kez gerçek kimliğiyle başlatıp sonucunu denetler. Sonunda “SYSTEM gorevi de calisti; gercek geri yukleme kontrolu gecti” görülmeden canlı zamanlanmış görev doğrulandı denmez. Üç dakikada tamamlanmazsa kontrol zaman aşımıyla durur; görev ve durum dosyaları incelenir.

## Ne saklanır?

- Veritabanı `pg_dump --format=custom` ile alınır. Profil iş fotoğrafları PostgreSQL'deki ikili alanlarda olduğundan aynı yedeğe dahildir.
- Dış `settings.json`, Data Protection anahtar halkası, yapılandırılmış Firebase/Google Play/Apple özel anahtar dosyaları eklenir. Eksik anahtar veya boş anahtar halkası başarı sayılmaz.
- Dosya özetleriyle bir manifest hazırlanır. Paket AES-256-CBC ve ayrı HMAC-SHA256 anahtarıyla şifrelenip bütünlük doğrulaması yapılır. Kurtarma anahtarı hiçbir arşivin içine konmaz.
- Yedek şifresi `C:\ProgramData\santiye\backup\recovery.key` dosyasındadır. Bu dosyayı silmek eski yedekleri okunamaz yapar; yeniden kurulum mevcut anahtarı korur. Windows izinleri yedek ve araç klasörlerini yöneticiler ile SYSTEM erişimine sınırlar. Görevin veritabanı parolası komut satırında veya durum kaydında bulunmaz; geçici pgpass yalnız kapalı çalışma klasöründe oluşturulur ve sonunda kaldırılır.

## Zamanlama ve saklama

- Her gece **sunucunun yerel saatine göre 03:00**. Sunucunun saat dilimi değiştirilmez.
- Yerel klasör `C:\ProgramData\santiye\backups`.
- Son **14 günlük** şifreli yedek tutulur. Yeni yedek ve geri yükleme başarılı olduktan sonra yalnız aracın kendi ad düzenine uyan eski `.enc` dosyaları kaldırılır. Başka dosya/klasörler temizlenmez.
- Görev sırasında bilgisayar kapalıysa uygun ilk zamanda çalışır. Çakışan çalışma kilitle önlenir.
- `last-success.json` en son tamamlanan yedeği, SHA-256 özetini ve geri yükleme sonucunu içerir. `last-failure.json` varsa tarihini son başarıyla karşılaştırın. Görev başarısızlığı Windows Görev Zamanlayıcı sonucuna da yansır; dış bildirim/izleme hizmeti kurulmaz.
- Boş disk alanı, çalışma süresi ve yedek miktarı kullanım arttıkça izlenmelidir. Windows ZIP aracının dosya boyutu sınırları nedeniyle çok büyük veritabanlarında paketleme yönteminin ayrıca büyütülmesi gerekir; hatalı/eksik paket başarılı raporlanmaz.

## Geri yükleme kontrolü

Her yedekte, şifreli teslim dosyası yeniden açılır ve tüm dosya özetleri kontrol edilir. Yalnız **localhost** üzerinde, aracın o anda oluşturduğu rastgele `santiye_test_<32 hex>` veritabanına `pg_restore --exit-on-error` uygulanır. Sistem dışındaki tüm şemaların tablo sayısı raporlanır. Ayrıca `santiye.Users`, `santiye.Listings`, `santiye.Deals` ve `santiye.PortfolioPhotos` tablolarının varlığı ve okunabildiği doğrulanır; yalnız public şemasının varlığı yetmez. Test veritabanı sonra kaldırılır. Mevcut veritabanı adı hedef olarak kabul edilmez.

İlk VDS kurulumunda kullanıcı SYSTEM görevi ve geri yüklemenin başarı çıktısını iletti. Eski sayacın `Tablo: 1` yazması yalnız public şemasını saymasındandı; dump komutunda şema filtresi yoktur ve tam veritabanı geri yüklenir. Sonraki düzeltme hem toplam sayıyı hem kritik uygulama tablolarının kontrolünü kapsar. Güncellenen tek dosya kurucu tekrar çalıştırılınca aynı görev/anahtar korunarak yeni kontrol uygulanır.

Önceki bir yedeği tekrar sınamak için:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\backup\verify-backup.ps1 -ArchivePath "C:\ProgramData\santiye\backups\YEDEGIN_ADI.enc"
```

Bu araç **canlı veritabanının üzerine geri yükleme yapmaz**. Gerçek kurtarma için duruma göre API kapatma, doğru veritabanı, sunucu dosyaları ve anahtar izinleriyle ayrı bir uygulama planı gerekir. Windows DPAPI ile korunan Data Protection anahtarlarının başka makineye taşınabilirliği, yalnız dosya kopyalamayla garanti edilmez. Günlük sınama PostgreSQL ve paket bütünlüğünü doğrular; farklı bir sunucuya tam felaket kurtarma testi değildir.

Sunucunun diski tamamen kaybolursa aynı diskteki yedek ve kurtarma anahtarı da kaybolabilir. Müşteri bu aşamada dış kopya istemediğini belirtti; otomatik harici kopya kurulmadı.

## Yerel doğrulama

`backend/deploy/tests/backup.Tests.ps1` Windows PowerShell 5.1 ve PowerShell 7.6.5'te gerçek yerel PostgreSQL 17 ile geçti. İki satır ve ikili fotoğraf verisi yedekten birebir döndü; bozuk arşiv/yanlış anahtar reddedildi, tekrar çalıştırma, 14 günlük saklama, başka dosyayı koruma ve çalışma dosyası temizliği kontrol edildi. Kaynak test veritabanının satırları korunur. Testler yalnız kendilerinin oluşturduğu yerel `santiye_test_*` veritabanlarına yazdı. Yerel süreç yönetici olmadığı için ACL komutu fixture içinde taklit edildi; canlı ACL ve Görev Zamanlayıcı kurulumu henüz çalıştırılmış sayılmaz.
