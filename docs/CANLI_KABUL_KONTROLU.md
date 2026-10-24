# Canlı sunucu ve mobil kabul kontrolü — 15 Ekim 2026

## Kullanılan ortam

Android emülatöründeki uygulama `https://45.59.70.198` adresindeki IIS / .NET 10 API'ye bağlıdır. Kayıtlar müşterinin PostgreSQL veritabanında tutulur. Cihaz içi demo backend'i ve örnek ilanlar kullanılmaz. Son Android sürümü profile olarak kurulmuştur; uygulama kapatılıp açılınca cihazda saklanan normal API oturumu geri gelir.

Müşterinin çalıştırdığı temizleme aracının işlem öncesi/sonrası sayımları 0 hesap, 0 ilan ve 0 anlaşmadır. Araç sunucuda yedek aldı; COMMIT çıktısı görüldü. Daha sonra iki canlı kontrol hesabı oluşturuldu. Hesap silme kontrolü için açılan üçüncü geçici hesap normal hesap silme API'siyle kaldırıldı.

İlanlardaki “Kontrol” adları ve açıklamalar, bu kayıtların teknik kontrol için oluşturulduğunu belirtir. Kayıtlar gerçek sunucuda saklanır; ticari iş, gerçek para transferi veya gerçek iş deneyimi iddiası taşımaz.

## Canlıda kontrol edilenler

| Bölüm | Yapılan kontrol ve sonuç |
|---|---|
| API ve PostgreSQL | HTTPS sağlık ve şema kontrolleri başarılı. Oturumsuz profil erişimi 401 döndürür. |
| SMS'siz profil | Tuna Test hesabı emülatörden oluşturuldu. Telefon doğrulanmış gösterilmedi. Uygulama yeniden açıldığında aynı hesaba dönüldü. |
| Beş ilan türü | İkinci hesapla yük, makine, malzeme, personel ve operatör/sicil kaydı gerçek API'de oluşturuldu; ana hesap bunları okuyup ekranda gösterdi. |
| Mobil ilan yayını | Emülatörden Kontrol-Mobil-Makine ilanı 20 ton kapasite ve 6.500 TL günlük bedelle yayınlandı. İkinci hesap aynı kaydı API'den okudu. |
| İletişim ve ücretsiz hak | Numarayı göster işlemiyle sunucudan telefon açıldı; kalan hak 5'ten 4'e indi. Gerçek arama veya WhatsApp mesajı gönderilmedi. |
| Giden talep | Emülatörden adresli, 9.500 TL tutarlı bir günlük kiralama talebi gönderildi. İkinci hesap kabul etti; anlaşma uygulamada göründü. |
| Gelen talep | İkinci hesap 13.000 TL tutarlı iki günlük talep gönderdi. Ana hesap emülatörden kabul etti; ikinci hesap kabul edilmiş durumu ve anlaşmayı okudu. |
| Ödeme takibi | Emülatörden Ödedim bildirildi; karşı hesap tahsilatı işaretledi. İki işaret de sunucuda görüldü. Bunlar yalnız kayıt işlemidir. |
| Teslim ve puan | Hizmet veren teslim bildirdi. Alıcı emülatörden tamamladı ve açıkça test değerlendirmesi olarak açıklanmış puan verdi. Sunucuda rating_count 1 oldu. |
| İş fotoğrafı | Android galerisinden bu çalışma için hazırlanmış kontrol görseli seçildi, açıklamayla yüklendi, profilde ve büyütülerek açıldı. İkinci hesap aynı görseli gördü; silme girişimi 403 ile reddedildi. |
| Uygulama içi bildirim | Teklif kabulü, tahsilat ve teslim bildirimleri listede görüldü. Tümünü okundu say işleminden sonra API kayıtlarında read_at dolu olarak doğrulandı. |
| Hafriyat sahaları | Yeni migration müşteri sunucusunda uygulandı. Emülatörden 2.000 m³ kazı sahası ve 5.000 m³ / 150 TL/m³ döküm sahası eklendi; ana hesabın API kaydında okundu. |
| Saha sahipliği | Başka hesabın özel saha kaydını silme girişimi 403 döndürdü. Kontrol için açılan geçici saha sahibi tarafından silindi. |
| Engel | İki kontrol hesabı arasındaki engel sırasında iletişim erişimi BLOCKED ile reddedildi; ardından engel kaldırıldı. |
| Hesap silme | Ayrı geçici canlı hesap profil/saha kaydıyla oluşturulup normal API'den silindi; eski oturum 401 ile reddedildi. Ana hesaplar korunur. |
| Premium sınırı | Ücretsiz hesapta rota optimizasyonu Premium ekranına yönlendirdi. Makbuz doğrulanmadan kredi veya Premium verilmedi. |

## Yerel otomatik kontroller

- 72 backend testi başarılı. Bu testler yalnız kendi oluşturdukları yerel `santiye_test_*` PostgreSQL veritabanlarında çalıştı.
- 181 standart mobil testi başarılı; yerel API gerektiren 2 kabul testi standart turda atlandı.
- `flutter analyze lib test`: sorun yok. Android x64 profile ve üç mimarili Android profile APK derlemeleri başarılı.
- Yeni saha migration'ı, yedekten geri yüklenmiş ayrı yerel test veritabanına uygulandı. 4 hesap, 5 ilan ve 1 anlaşma korunurken migration sayısı 3'ten 4'e çıktı.
- IIS'in JSON olmayan bakım/503 yanıtının geçici sunucu hatası olarak ele alınması ve oturumun korunması normal istek/fotoğraf gönderimi için test edildi.

Bu belgedeki canlı kontroller elle yürütülen kabul işlemleridir. Otomatik backend entegrasyon takımı müşteri veritabanında çalıştırılmadı. Ekran görüntüleri ve ayrıntılı günlükler yerel `tmp/live-vds` altındadır; oturum anahtarları ve derleme çıktıları Git'e eklenmez.

## Hizmet ayarlarını bekleyen aşamalar

- SMS sağlayıcısı şu an kapalıdır. Gerçek SMS gönderimi ve gerçek telefondan hesap kurtarma denenmedi. Telefon ve şifreyle tekrar giriş özelliği mevcut akışta yoktur; hesabı cihaz oturumu açar.
- Google Play / Apple gerçek ürün, makbuz, abonelik yenileme ve iade kontrolleri müşteri mağaza erişimlerini bekler. Kontrol sırasında gerçek satın alma yapılmadı.
- 16 Ekim ek kontrolünde Firebase, müşteri VDS'sine bağlandı; Android emülatöründe arka planda ve uygulama işlemi kapalıyken gerçek push teslimi ve bildirimden açılış doğrulandı. Ayrıntılar `ANDROID_BILDIRIM_CANLI_KONTROLU_2026-10-16.md`. Fiziksel Android cihaz ve iOS/APNs kontrolleri bekler.
- iOS arşiv/TestFlight ve gerçek iPhone kontrolü macOS/Xcode ve Apple hesabıyla yapılacak. Android profile APK mağaza imzalı yayın paketi değildir.
- İşletici bilgileri, destek adresi ve yayımlanmış yasal bağlantılar müşteriyle yayın aşamasında tamamlanmalı.

Kaynak demo envanteri `MOBIL_ILK_SURUM_OZELLIK_ENVANTERI.md`, önceki yerel kabul turu `BACKEND_KABUL_KONTROLU.md`, kurulum adımları `CANLI_GUNCELLEME.md` dosyalarındadır.
