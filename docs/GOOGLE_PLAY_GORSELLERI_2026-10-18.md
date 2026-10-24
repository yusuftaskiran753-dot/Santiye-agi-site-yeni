# Google Play görselleri — 18 Ekim 2026

Teslim arşivi: `output/SantiyeAgi-GooglePlay-Gorseller.zip`. Açılmış dosyalar: `output/google-play/`. Bu çıktılar Git'e eklenmez.

| Mağaza alanı | Dosya | Ölçü |
|---|---|---|
| Uygulama simgesi | `01-uygulama-simgesi-512.png` | 512 × 512 |
| Özellik grafiği | `02-ozellik-grafigi-1024x500.png` | 1024 × 500 |
| Telefon ekran görüntüleri | `screenshots/` içindeki 6 PNG | 1080 × 1920, 9:16 |

Ekran sırası: ana sayfa, yük ilanları, makine ilanları, anlaşma takibi, ilan oluşturma seçenekleri, personel ilanları. Her biri 8 MB altında RGB PNG'dir. Özellik grafiği RGB PNG ve 15 MB altında; simge 1 MB altındadır. Video hazırlanmadı; bu isteğe bağlı alan boş bırakılabilir.

## Gerçek ekranların kaynağı

- Mağazaya hazırlanan `2.1.2 (7)` AAB'sinden Google bundletool ile universal APK üretildi; aynı upload anahtarıyla imzalanıp emülatöre kuruldu. Paket `com.santiyeagi.app`, sürüm kodu 7 olarak cihazdan kontrol edildi.
- Açılış ekranından koşullar kabul edilip “Hesabım var — kullanıcı adıyla giriş” üzerinden `test` hesabıyla giriş yapıldı. Canlı Tuna profili, ilanlar ve anlaşmalar yüklendi. Bu tur yeni release girişini emülatör üzerinde doğrular; fiziksel Android veya iOS testi değildir.
- Android'in gerçek bildirim izni ekranından izin verildi. Cihazda `POST_NOTIFICATIONS` izninin açık olduğu kontrol edildi; bu tur ayrıca yeni FCM teslim testi yapılmadı.
- Mevcut teknik kontrol verileri kullanıldı. “Kontrol” adlı ilanlar, örnek tutarlar ve test hesabı gerçek ticari faaliyet veya para transferi iddiası değildir. Yeni ilan/anlaşma, ödeme veya ücretli hak oluşturulmadı.
- Ekranlar Android'in kendi ekran yakalamasıyla alındı; içerikler yeniden çizilmedi. Yalnız PNG dosyaları kayıpsız RGB biçimine dönüştürüldü. Çekimde emülatör 1080 × 1920 / 360 dpi kullanıldı; saat ve durum simgeleri düzenlendi. Çekimden sonra çözünürlük/dpi geri alındı, durum çubuğu görünürlüğü açıldı. Yeni uygulama oturumu açık bırakıldı; eski paket silinmedi.

## Görsel üretimi ve kontrol

`tools/generate_play_assets_test.dart` uygulamanın mevcut Material şantiye simgesini aynı turuncu/ beyaz renklerle 512 piksel olarak çizer. Özellik grafiği aynı simge, uygulamadaki ifade ve temel ilan türleriyle vektör çizim olarak oluşturuldu; yapay uygulama ekranı veya henüz çalışmayan özellik iddiası eklenmedi.

```powershell
flutter test --no-pub tools/generate_play_assets_test.dart
python tools/package_play_assets.py
```

Üretici Windows Segoe UI fontlarını kullanır; `PLAY_ASSET_FONT_DIR` ile font klasörü belirtilebilir. Paketleme aracı Pillow gerektirir. Gerçek ekranların `output/google-play/screenshots` altında önceden yakalanmış olması gerekir; paketleme bunları uydurmaz veya sunucudan veri oluşturmaz.

Üretici çalıştırması ve dosya analizi başarılıdır. Tüm görseller açılıp ölçü, renk biçimi ve dosya sınırları kontrol edildi. Özellik grafiği ve altılı ekran önizlemesi görsel olarak incelendi; ZIP bütünlüğü kontrol edildi. Önizleme `output/google-play-onizleme.jpg` dosyasındadır; mağazaya bu kolaj yerine altı ayrı ekran yüklenmelidir.

Görseller Play Console'a yüklenmedi; mağaza onayı veya kapalı testin başladığı anlamına gelmez.

Ölçü kaynağı: [Google Play görsel varlık rehberi](https://support.google.com/googleplay/android-developer/answer/9866151?hl=tr).
