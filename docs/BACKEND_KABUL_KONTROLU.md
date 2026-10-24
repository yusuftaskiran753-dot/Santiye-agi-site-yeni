# Backend ve mobil kabul kontrolü — 15 Ekim 2026

**Bu belge önceki yerel kabul turunun kaydıdır.** Sonraki gerçek VDS ve emülatör kontrolleri için `CANLI_KABUL_KONTROLU.md` belgesine bakın. SMS zorunluluğu artık sunucu ayarından kapanabilir; hafriyat kayıtları için de yeni sunucu tablosu eklenmiştir.

## Yapılan kontrol

SMS sağlayıcısını beklemeden iş akışlarının kontrol edilebilmesi için ayrı bir **yerel Development API** ve bu çalışma için oluşturulan `santiye_test_*` PostgreSQL veritabanı kullanıldı. Emülatörde Test Kullanıcısı hesabıyla giriş yapıldı. Bu hesap gerçek SMS ile doğrulanmış bir müşteri hesabı değildir; canlı sunucunun telefon doğrulaması kapatılmadı.

Bu ortam önceki cihaz içi demodan farklıdır: veriler gerçek .NET API'ye gönderilip PostgreSQL'e yazılır. İki ayrı hesap aynı ilanları, talepleri ve anlaşmaları sunucudan okur. Test ilanları ve test fotoğrafı müşteri sunucusuna yüklenmedi.

## Kontrol edilen işlemler

| İşlem | Sonuç ve kapsam |
|---|---|
| Profil oluşturma ve oturumu yeniden açma | Gerçek API üzerinden profil kaydı/okuma ve saklanan oturumun geri yüklenmesi geçti. |
| Yük, makine, malzeme, personel ve sicil ilanı | Beş türün mobil modellerle kaydı, düzenlenmesi ve başka hesaptan okunması geçti. |
| Müsaitlik ve iletişim hakkı | Müsait olmayan makineye hak açma reddedildi. Beş ücretsiz hak kullanımı sunucuda sayıldı. |
| Teklif/talep güncelleme | Aynı bekleyen teklif yeni bir kayıt oluşturulmadan güncellendi. |
| Kabul ve anlaşma | Beş türde teklif kabul edilince bedel, miktar, tarih, adres ve not anlaşmaya taşındı. |
| Ödeme takibi | Alıcı ödeme bildirdi, hizmet veren tahsilatı işaretledi; bu yalnız taraflar arasındaki ödemenin kaydıdır. |
| Sorun, teslim ve puanlama | Sorunu yalnız bildiren taraf çözebildi. Hizmet veren teslimi, alıcı tamamlanmayı bildirdi; puan kaydedildi. |
| İptal ve kodla katılım | İki tarafın iptal onayı, sekiz karakterli kod ve önceki on karakterli kodla katılım testleri geçti. |
| Engelleme ve şikâyet | Engel sonrası ilan/iletişim erişimi reddedildi; engel kaldırılınca erişim döndü. Şikâyet gönderimi geçti. |
| İş fotoğrafları | Yükleme, JPEG okuma, başka hesaptan görüntüleme ve sahibi tarafından silme geçti. Başkası silmeye çalışınca reddedildi. |
| Hesap değiştirilirken fotoğraf | Bekleyen eski yüklemenin yeni hesapla yeniden gönderilmesi engellendi. Geç gelen başarılı yanıt da yeni hesaba taşınmıyor. |
| Uygulama içi bildirim | Bildirimler sunucudan okundu, okundu durumu kaydedildi. Bu kontrol Firebase push teslimatı değildir. |
| Hesap silme ve yetkiler | Oturum iptali, kişisel alanların temizlenmesi ve anonim puanların korunması .NET testlerinde geçti. |
| Tekrar gönderim ve kotalar | Aynı işlemin ikinci kez ücret/hak tüketmemesi ve ilan sınırı kontrolleri geçti. |

## Emülatörde elle yapılan kontroller

1. Development test koduyla mevcut test hesabına giriş yapıldı, ana ekranda sunucudaki ilan sayıları görüldü.
2. Makine listesi ve ilan detayı açıldı; sunucudan gelen fiyat, müsaitlik ve firma bilgileri görüldü.
3. Kiralama talebine adres yazılıp uygulamadan gönderildi. Sunucuya kaydoldu ve uygulamada “Yanıt bekleniyor” göründü.
4. İkinci test hesabı API üzerinden kabul etti. Uygulama anlaşmayı yenileyip İşlerim → Anlaşmalar altında gösterdi.
5. Anlaşma detayında tutar, başlangıç tarihi, adres ve ödeme satırı görüldü. “Ödedim” işlemi onaylanıp sunucuya kaydedildi.
6. Profilde “İş fotoğrafı ekle” ile Android galeri seçicisi açıldı. Bu çalışma için hazırlanan test görseli seçilip açıklama yazıldı, Paylaş ile sunucuya gönderildi ve profil galerisinde göründü. Fotoğraf büyütülerek açıldı. Silme ve başka hesaptan okuma/yetki kontrolleri ayrıca mobil kabul testinde geçti.

## Otomatik kontroller

- .NET Release derlemesi: başarılı.
- .NET test takımı: **68 başarılı, 0 başarısız**; her entegrasyon testi kendisinin oluşturduğu ayrı yerel test veritabanını kullandı.
- Flutter standart test takımı: **174 başarılı, 0 başarısız**. Gerçek yerel API gerektiren iki test bu standart turda atlanır.
- Gerçek yerel API ile mobil kabul turu: **11 başarılı, 0 başarısız**; 9 veri katmanı testi ve ayrıca çalıştırılan 2 gerçek API testi.
- `flutter analyze lib test`: sorun yok.

Test günlükleri ve emülatör ekran kayıtları yerel `tmp/` altındadır. Anahtar, oturum belirteci ve test veritabanı Git'e eklenmez.

## Ortamı ayırt etme

- `config/live.json`: müşterinin `https://45.59.70.198` adresindeki IIS API'si. SMS sağlayıcısı etkinleştirilmeden giriş tamamlanmaz.
- `config/local-emulator.json`: Android emülatöründen geliştirme bilgisayarındaki gerçek API'ye bağlanır. API ayrıca çalışır durumda olmalıdır. Uygulamanın bu sürümü müşteri sunucusuna veri yazmaz.

```powershell
flutter run -d emulator-5554 --dart-define-from-file=config/local-emulator.json
```

Yerel kabul testleri, yalnız bu çalışma için oluşturulmuş `santiye_test_*` veritabanına bağlı Development API'ye karşı çalıştırılır. Kullanılan test veritabanı adı ayrıca verilmelidir:

```powershell
flutter test test/integration --concurrency=1 --dart-define=API_BASE_URL=http://localhost:5080 --dart-define=LOCAL_TEST_DATABASE_NAME=santiye_test_bu_calismaya_ait_veritabani
```

Son parametre bir örnektir; gerçekten oluşturulup yerel API'ye bağlanan test veritabanının adı yazılır. Testler uzaktaki veya müşteri sunucusundaki API adresini kabul etmez.

## Canlı kabul için kalan dış hizmetler

VatanSMS hesabının etkinleştirilmesi, mağaza ürünleri/servis hesapları ve Firebase/APNs ayarları hâlâ gereklidir. Bu sağlayıcılara ait kod hazır olsa da gerçek SMS, gerçek mağaza ödemesi/yenileme/iade ve kapalı uygulamaya push teslimatı müşteri hesaplarıyla henüz doğrulanmadı. iOS arşivi/TestFlight kontrolü macOS/Xcode üzerinde yapılacak.

Müşterinin IIS sunucusunda HTTPS ve PostgreSQL hazırlık kontrolleri başarılıdır. Bu belgedeki oturum gerektiren uçtan uca kontroller yerel test ortamına aittir.
