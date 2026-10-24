# StoreKit ürün sorgusu — 22 Ekim 2026

## Gerçek cihaz kanıtı

Main `e506bf7` → `625b690` fast-forward güncellendi; 22 Ekim Windows push notu okundu. Gerçek iPhone push teslimi kullanıcı tarafından doğrulandı; bu satın alma katalog sorgusundan bağımsızdır. Backend/Windows bu sohbette değiştirilmedi.

USB ile bağlı iPhone 13'te devicectl uygulama metadatası: Şantiye Ağı, `com.yusuftaskiran.santiyeagi.pro`, **2.1.2 (11)**. Kullanıcı uygulamayı tamamen kapatıp yeniden açtı, Premium ve Kredi al ekranlarına girdi; satın alma başlatmadı. macOS Konsol üzerinden gerçek cihaz günlükleri incelendi; genel hesap/kimlik/oturum günlükleri dışa aktarılmadı.

StoreKit daemonunun Media API ürün isteğinde görülen ID'ler:

```text
santiye_kredi_15,santiye_kredi_40,santiye_kredi_5,santiye_premium_aylik,santiye_premium_yillik
```

Cevap kaydı `Ignoring empty product response: (<private>)`; dönen ürün sayısı **0**. Özel alanların gizliliği aşılmadı. Flutter'ın iki yeni açılış kaydındaki `notFoundIDs` karşılığı:

```text
santiye_premium_aylik, santiye_premium_yillik, santiye_kredi_5, santiye_kredi_15, santiye_kredi_40
```

StoreKit `Storefront updated` kaydı **countryCode=TUR**, locale tr/currency try gösteriyor. Bu ölçüm yalnız telefonun diline bakılarak yapılmış bir varsayım değildir.

**Hata sınırı:** build 11 `ProductDetailsResponse.error` alanını kaydetmiyor. Kaynak hata alanını kullanmadan `notFoundIDs` yazdırıyor. Bu nedenle bu ölçümde `error=null` olduğu veya belirli bir Apple hata kodu kanıtlanmış değildir. StoreKit 2 eklentisi boş dönen ürünü de sorgu PlatformException'ını da bulunamayan ID listesine çevirebilir. Boş cevap günlüğü ve beş notFound doğrudan gözlemdir; sözleşme eksikliği ise henüz doğrulanmamıştır.

## Apple katalog eşleşmesi

Safari'de doğru müşteri Şantiye Ağı Pro / App ID `6824034438` kayıtları kontrol edildi. Kodun beş ID'siyle mağaza kayıtları aynı. Bundle proje ayarlarında ve gerçek cihazda aynı; kaynakta yerel `.storekit` yapılandırması/StoreKit config override yok. StoreKit 2 eklentinin varsayılan yoludur; StoreKit sürümü rastgele değiştirilmedi.

| Ürün | Apple ID | Güncel Türkiye fiyatı |
| --- | --- | --- |
| santiye_premium_aylik | 6825081370 | 199,00 TL / ay |
| santiye_premium_yillik | 6825081982 | 1.599,99 TL / yıl, peşin |
| santiye_kredi_5 | 6825082912 | 99,99 TL |
| santiye_kredi_15 | 6825083520 | 149,00 TL |
| santiye_kredi_40 | 6825207287 | 419,99 TL |

Üç kredi fiyatı Current Price → Türkiye satırından; abonelikler Current Pricing for New Subscribers → Countries or Regions Selected for Availability → Türkiye satırından taze doğrulandı. Türkçe ad/açıklamalar mevcut; iki abonelik aynı Premium grubunda/seviye 1, 1 ay ve 1 yıl. Ürünler Prepare for Submission; ilk sürümle Apple incelemesine henüz gönderilmedi. Apple'ın sandbox belgesi ürünlerin sorgulanması için önceden inceleme onayını şart koşmuyor; bu durum tek başına hata nedeni sayılmaz.

Üç kredi ürününün de ülke penceresinde yalnız Türkiye seçili olduğu taze doğrulandı. Aboneliklerin satışa açık ülkeler filtresi yalnız Türkiye satırını gösterdi. Uygulamanın Pricing and Availability ekranında da 1 Available → Türkiye doğrulandı. Ürün veya fiyat/satış seçimi değiştirilmedi, hiçbir ürün silinip yeniden oluşturulmadı.

## Paid Apps Agreement — doğrulanamayan zorunlu koşul

Safari müşteri oturumunda üst menüde Apps / Xcode Cloud / Users and Access var, Business yok. Doğrudan `https://appstoreconnect.apple.com/business` denendi; sayfa **We were unable to load your data at this time. Please try again later.** hatası verdi. Bu hata tek başına sözleşmenin pasif olduğu veya belirli bir yetkinin eksik olduğu anlamına gelmez. **Active durumu, vergi ve banka tamamlığı doğrulanamadı.** Kullanıcı hesap sahibinden şu an kontrol alamadığını belirtti.

Apple'ın resmî koşuluna göre Paid Apps Agreement, sandbox IAP testleri için de Active olmalıdır. Hesap sahibi Business → Agreements → Paid Apps satırının durumunu ve eksik banka/vergi uyarılarını kontrol etmeli. Sözleşme kabulü/finansal bilgi girişi bu sohbet tarafından yapılmadı. Yeni anahtar gerekçesi veya müşterinin hatalı işlem yaptığı iddiası yoktur.

## Mobilde hazırlanan dar tanı değişikliği

`billing_service.dart` katalog sorgusunun requested / returned / notFoundIDs ve error source/code alanlarını güvenli günlükler. Hata details/ham sağlayıcı cevabı/hesap/anahtar/oturum/makbuz kaydedilmez. Boş ürün için “mağazada tanımlı değil” kesin hükmü yerine mağaza bilgilerinin alınamadığı açıklaması kullanılır. Satın alma, hak tanımlama, fiyat hesaplama ve tasarım korunur.

Bu kaynak değişikliği **mevcut build 11'de yoktur**, yeni IPA/TestFlight üretilmedi/yüklenmedi. Tanı eklenmesi ürünlerin görünmesi sorununu çözmüş sayılmaz. `flutter analyze lib test` temiz. Yalnız tanı ve mesaj değiştiği için yeni yapay test yazılmadı; önceki test sonucu bu tur yeniden çalıştırılmış gibi sunulmaz.

## Devam

1. Hesap sahibinden Paid Apps Agreement **Active** ve banka/vergi durumunun kesin sonucunu al. Aktif değilse sahibi Apple ekranında tamamlasın; mevcut ürünleri koru.
2. Durum doğru olduktan sonra aynı build 11'i tamamen kapat/aç ve ürün sorgusunu yeniden ölç. Beş gerçek StoreKit fiyatı görünmeden katalog hazır denmez.
3. Active teyidine rağmen sorgu boşsa, güvenli tanı içeren yeni build ile response.error alanını ölç; Apple katalog/sandbox için TN3186 kanıtlarıyla ilerle. Gerekirse Apple desteğine bundle, ürün ID'leri ve sır içermeyen sorgu bulguları iletilir; bu sohbet kullanıcı adına destek mesajı göndermedi.
4. Backend Sandbox ve PhoneVerified/inceleme hesabı Windows sohbetinin işi. Ürünlerin gelmesi gerçek satın alma/geri yükleme başarısı sayılmaz; bu adımlar burada denenmedi. SMS kapalı kalır.

Kaynaklar: [Apple IAP yapılandırma koşulları](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/), [Apple inceleme/sandbox hazırlığı](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases), [TN3186](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox).
