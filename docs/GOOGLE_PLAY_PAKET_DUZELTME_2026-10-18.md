# Google Play paket kimliği düzeltmesi — 18 Ekim 2026

Google Play Console'daki mevcut uygulama kaydı `com.santiyeagi.app` paket kimliğini istiyor. İlk AAB `com.santiyeagi.santiye_agi` kimliği taşıdığı için Console tarafından reddedildi. Mağaza kaydını değiştirmek yerine Android uygulaması bu mevcut kimliğe eşleştirildi.

## Güncel paket

- Paket kimliği ve Android namespace: `com.santiyeagi.app`.
- Kotlin ana etkinlik paketi ve dosya yolu yeni namespace ile eşleştirildi.
- Mobildeki mağaza abonelik yönetimi bağlantısı ve harita istemci kimliği de `com.santiyeagi.app` kullanır.
- Sürüm: `2.1.2 (6)`. Yerel AAB: `output/mobile/SantiyeAgi-2.1.2-6-Kapali-Test.aab`.
- Aynı upload anahtarı kullanılır; anahtar ve parola Git dışında kalır.
- Canlı API `https://45.59.70.198`, Android push açık, örnek ilanlar kapalı.

## Firebase eşleştirmesi

Mevcut `santiye-agi` Firebase projesine `com.santiyeagi.app` paketli yeni Android uygulama kaydı Firebase Management API üzerinden oluşturuldu. Google'ın bu kayıt için döndürdüğü gerçek `google-services.json` indirildi ve paket kimliği kontrol edilerek yerel `android/app/google-services.json` değiştirildi. Eski dosyadaki paket alanı elle değiştirilmedi. Dosya Git'e eklenmez.

Firebase proje kimliği aynı kaldığı için VDS'deki FCM hizmet hesabını değiştirmek gerekmez. Önceki emülatör push teslim kontrolleri eski Android paketine aittir; bu yeni paketle gerçek cihaz teslim testi yeniden yapılmalıdır. Eski Android paketi farklı bir uygulama kimliği olduğundan yeni pakete cihaz oturumu otomatik taşınmaz.

Google Play satın alma entegrasyonu kurulurken sunucunun dış ayarındaki `Billing.GooglePackageName` de `com.santiyeagi.app` olmalıdır. Bu işlemde canlı sunucu satın alma ayarları değiştirilmedi.

## Doğrulama

- `flutter analyze lib test`: temiz; `flutter test`: 181 başarılı, 2 yerel API testi standart turda atlandı.
- Release AAB derlemesi başarılı. Bundletool 1.18.3 paket yapısını doğruladı; manifestte `com.santiyeagi.app`, sürüm kodu `6` ve `com.santiyeagi.app.MainActivity` kontrol edildi.
- `jarsigner -verify`: imza geçerli; mevcut upload anahtarı korundu.
- ZIP bütünlüğü ve 12 yerel kütüphane kontrol edildi; 64 bit ELF segmentleri 16 KB hizalamayı geçti. Cihazda çalışma testi değildir.
- Dosya boyutu: 47.805.029 bayt. SHA-256: `43C91C2A93BB7CA2E1DEF3858E9A04D617C3253024A9565C6C06B4BDEB381227`.
- Bu turda bağlı Android cihaz/emülatör bulunmadığından kurulum ve gerçek push teslimi denenmedi.

## Yayın kapsamı

Bu düzeltme paket adı hatasını giderir. Console'a yükleme/onay veya kapalı test süresinin başlaması henüz doğrulanmadı. SMS, gerçek mağaza ürünleri/satın alma testleri, nihai yasal adresler ve fiziksel Android kontrolleri önceki yayın listesinde beklemeye devam eder.
