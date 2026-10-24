# Android bildirimlerinin canlı kontrolü — 16 Ekim 2026

## Ortam

- Müşterinin IIS / .NET API'si: `https://45.59.70.198`; HTTPS canlılık ve hazır olma kontrolleri HTTP 200.
- Müşteri `set-firebase-push.ps1` aracını VDS'de çalıştırdı; `Firebase push: On. Proje: santiye-agi` çıktısı alındı.
- Firebase Android projesi `santiye-agi`; paket `com.santiyeagi.santiye_agi`.
- Android API 36.1 emülatörüne push açık x64 profile APK mevcut uygulamanın üzerine kuruldu. Uygulama verileri silinmedi; Tuna Test hesabı, ilanları ve anlaşmaları korundu.
- Fiziksel cihaz denemesi için armv7/arm64/x64 içeren profile APK ayrıca başarıyla derlendi: `output/mobile/SantiyeAgi-Android-Push-Test.apk`. Emülatör testi x64 sürümde yapıldı; ARM cihazda çalıştırıldığı iddia edilmez.
- Emülatörde bildirim izni Android debug aracıyla verildi. Fiziksel telefondaki izin penceresinin kullanıcı tarafından kabul edilmesi bu kontrolde denenmedi.

## Canlı sonuçlar

| Kontrol | Sonuç |
|---|---|
| Firebase başlangıcı | Uygulama gerçek Android Firebase ayarıyla açıldı. |
| Cihazın canlı API'ye bağlanması | Ana hesabın cihaz kaydı tamamlandı; mobil servis durumu “Anlık bildirimler açık”, kayıtlı token mevcut. Token çıktıya veya belgeye yazılmadı. |
| Arka planda teslimat | Diğer kontrol hesabı ana hesaba ait makineye teknik kiralama talebi gönderdi. Canlı API'nin oluşturduğu bildirim kimliği Android sistem bildirimindeki etiketle eşleşti. |
| İşlem kapalıyken teslimat | Ana uygulama arka plana alındı ve işlemi kapatıldı; yeni olaydan önce PID olmadığı doğrulandı. Teknik talep güncellendi; yeni bildirim Android sistem paneline ulaştı. Bu, Android ayarlarındaki “Zorla durdur” işlemi değildir. |
| Bildirimden açılış | Arka plandan ve işlem kapalı durumdan bildirime dokunulduğunda doğru hesabın Bildirimler sayfası açıldı. Yeni teklif / güncelleme gerçek API kayıtlarıyla görüldü. |
| Kimlik eşleştirme | İşlem kapalıyken görülen sistem bildiriminin kimliği, uygulama açıldıktan sonra canlı API'deki aynı teknik talebin bildirim kimliğiyle tekrar eşleştirildi. |
| İçerik gizliliği | Sistem panelinde genel “Yeni bir bildiriminiz var. Ayrıntıları uygulamada görüntüleyin.” metni görüldü; telefon, adres veya teklif tutarı gösterilmedi. |
| Test kaydı | Deneme talebi 0 TL ve açık teknik kontrol notuyla oluşturuldu; kontroller bitince gönderen hesap tarafından geri çekildi. Yeni ticari anlaşma veya ödeme oluşturulmadı. |

Bu işlemler müşterinin gerçek VDS API'si ve Firebase üzerinden elle yürütülen kabul kontrolleridir. Müşteri veritabanında otomatik entegrasyon takımı çalıştırılmadı; doğrudan FCM'ye yerelden deneme mesajı gönderilerek backend akışı atlanmadı.

Yerel kanıtlar `tmp/live-vds/push-background-report.json` ve `push-process-closed-report.json` dosyalarında; Android bildirim paneli görseli `output/mobile/Android-Canli-Bildirim.png` konumundadır. Oturum/cihaz anahtarları ve derleme çıktıları Git'e eklenmez.

## Sınırlar ve sonraki aşama

- Gerçek Android telefonda, farklı üreticilerin pil kısıtlamalarında ve fiziksel cihazdaki izin akışında kabul testi kalır. Android profile APK mağaza imzalı yayın paketi değildir.
- iOS Firebase uygulama ayarı, APNs anahtarı, Apple yetkileri ve gerçek iPhone testi henüz tamamlanmadı.
- Android push derlemeleri `config/live-android-push.json` ile yapılır. Genel `config/live.json` henüz yapılandırılmamış iOS nedeniyle push kapalı kalır.
- SMS ve mağaza satın alma aşamaları bu bildirim kontrolüyle tamamlanmış sayılmaz.
