# .NET backend - ilk geliştirme grubu

Tarih: 14 Ekim 2026.

## Kullanılan yapı

- .NET 10 / ASP.NET Core API.
- PostgreSQL, EF Core 10 ve Npgsql.
- Windows Server 2022 / IIS yayın biçimi.
- Mobil uygulamanın mevcut `Backend` arayüzü ve JSON modelleri.

## Bu aşamada yazılanlar

1. Kullanıcı oturumu: kısa süreli erişim tokenı, güvenli yenileme tokenı, token yenileme ve çıkışta oturum iptali.
2. Yerel geliştirmede telefon test kodu akışı. Gerçek SMS henüz yok; canlı giriş yöntemi müşteri kararıyla netleşecek.
3. Profil kaydetme, kendi telefonu okuma ve telefon göstermeyen açık profil bilgileri.
4. Beş ilan türünün kayıt/listeleme/düzenleme/silme ve müsaitlik işlemleri.
5. Sunucuda sahiplik kontrolü: başka kullanıcının ilanına yazma/silme engeli.
6. Sayfalı okuma; mobil bağlantının eski 300 kayıt sınırı olmadan sayfaları toplaması.
7. Ücretsiz iletişim hakkı, kredi harcama, Premium yetkisi ve ilan öne çıkarma temeli.
8. Teklif gönderme, kabul/ret, geri çekme ve anlaşma oluşturma.
9. Müsaitlik ve engelleme kontrollerinin sunucuda uygulanması.
10. Elle anlaşma, davet koduyla katılma, teslim, tamamlama, not ve puanlama.
11. Aktif anlaşma iptalinde karşılıklı onay; sorunu yalnız bildiren tarafın çözümü onaylaması. Mobil model ve açıklamalar buna uyarlandı.
12. Hesap silme, kayıt temizliği, kalan anlaşmanın anonimleştirilmesi ve karşı tarafa verilen puanın korunması.
13. Uygulama içi bildirim kayıtları ve eski bildirimleri temizleyen görev.
14. Aynı çevrimdışı işlem yeniden gönderildiğinde tekrar oluşmasını önleyen işlem kimliği ve PostgreSQL kilitleri.
15. Flutter `DotNetBackend`: HTTP bağlantısı, güvenli token saklama, token yenileme ve sayfalı veri okuma.
16. Veritabanı migration dosyaları, PostgreSQL SQL kurulum çıktısı ve IIS yayın dosyaları.

## Yapılan kontroller

- .NET derleme: 0 hata, 0 uyarı.
- 12 .NET testi geçti; HTTP entegrasyon testleri gerçek yerel PostgreSQL üzerinde çalıştırıldı.
- Flutter bağlantı katmanının 4 yeni testi geçti; mevcut 156 testle toplam 160 test geçti.
- Gerçek API'yi kullanan mobil durum katmanı testi: iki kullanıcıyla profil, ilan, iletişim hakkı, teklif kabulü ve karşılıklı iptal geçti.
- Yerel API'nin `/health/live` ve `/health/ready` kontrolleri başarılı.
- Android emülatör için API bağlantılı debug APK derlendi ve yüklendi.
- IIS yayın dosyaları ve sunucu kurulum rehberi hazırlandı; gerçek IIS sunucusunda test henüz yapılmadı.

## Henüz tamamlanmayanlar

- Müşterinin VDS ve PostgreSQL kurulumuna bağlantı.
- Canlı SMS sağlayıcısı / nihai giriş yöntemi.
- Profil iş fotoğraf galerisi ve dosya saklama.
- Uygulama kapalıyken push bildirimi.
- Google Play / App Store satın alma doğrulaması, abonelik ve iade/iptal eşitlemesi.
- Mağaza sandbox ve gerçek cihaz kontrolleri.
- Üretim için kapsamlı hata/sınır/yük testleri ve canlı veri taşıma gerekiyorsa aktarım.

**Ödeme güvenliği:** Bu ilk API sürümünde ödeme doğrulama uç noktası yapılandırma hatası döner; doğrulanmamış makbuza kredi veya Premium verilmez. Bu paket gerçek satışa açılmaz.

**Test veritabanı:** Resmî Windows PostgreSQL binary paketiyle, yalnız 127.0.0.1:55432 üzerinde yerel test örneği kullanıldı. Müşteri sunucusuna kurulum veya veri değişikliği yapılmadı. Yerel test parolaları ve anahtarlar kaynak koduna/publish ZIP'ine yazılmadı.

## 14 Ekim - SMS ertelenmesi ve emülatör test hesabı

- Kullanıcı SMS entegrasyonunu sonraya bıraktı; e-posta doğrulaması talep edilmedi veya eklenmedi.
- Kalıcı Test Kullanıcısı / Şantiye Ağı Test profili yerel PostgreSQL'de oluşturuldu. Test telefonu: +905000000001.
- Mevcut Development telefon kodu akışı ile giriş yapıldı; API phone_verified=true döndürdü. Bu, gerçek SMS doğrulaması değil test verisidir.
- API bağlantılı güncel Android debug APK emülatöre yüklendi. Test telefonuna uygulamadan yeni kod istendi, ekrandaki geliştirme kodu girildi ve kayıtlı profil açıldı.
- Profilde Telefon doğrulandı rozeti emülatör ekranında ve UI ağacında kontrol edildi. Görsel: output/screenshots/Santiye_Agi_Test_Profil.png.
- Tekrar oluşturma aracı backend/deploy/create-local-test-account.ps1; yalnız yerel API adresinde çalışır, oturum anahtarlarını yazdırmaz.
- Yerel /health/ready kontrolü yeniden başarılı oldu. Yeni VDS'ye hâlâ bağlanılmadı.
- Windows Server için sıralı rehber docs/VDS_KURULUM_REHBERI.md dosyasına eklendi.

## Dosyalar ve kullanım

14 Ekim sonraki geliştirme: profil iş galerisi eklendi. Bu belgedeki ilk grubun "fotoğraf galerisi tamamlanmadı" kaydı o aşamanın tarihsel durumudur. Güncel API/mobil kaynakları JPEG/PNG/WebP fotoğraf yükleme, açıklama, görüntüleme ve sahip tarafından silme işlemlerini içerir; AddPortfolioPhotos migration'ı kullanılmalıdır. Güncel geliştirme kayıtları MUSTERI_CALISMA_NOTLARI.md dosyasındadır.

- API projesi: `backend/SantiyeAgi.Api/`.
- .NET testleri: `backend/SantiyeAgi.Api.Tests/`.
- Mobil bağlantı: `lib/services/dotnet_backend.dart`.
- Kurulum/yayın rehberi: `backend/README.md`.
- IIS paketi: `output/backend/SantiyeAgi-Backend-IIS.zip`.
- Veritabanı geçiş SQL'i: `output/backend/postgresql-migrations.sql`.

Mobil bağlantı için `API_BASE_URL` verilir. Adres yoksa önceki demo/Supabase modu korunur. Yerel test örneği:

```powershell
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:5080
```

Gerçek mobil/API kontrolü:

```powershell
flutter test test/integration/net_api_smoke_test.dart --dart-define=API_BASE_URL=http://localhost:5080
```
