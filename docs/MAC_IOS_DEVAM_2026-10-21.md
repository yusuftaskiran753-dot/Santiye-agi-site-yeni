# Mac iOS devam notu — 21 Ekim 2026

## 22 Ekim Mac StoreKit ölçümü — en güncel durum

Main `625b690` alındı. iPhone'da **2.1.2 (11)**, doğru bundle doğrulandı. Gerçek cihaz günlüğünde beş doğru ürün ID'si istendi, **0 ürün döndü ve beşi de notFoundIDs** oldu. StoreKit storefront **TUR**. Kod/Apple ID eşleşmesi, Türkçe ürün bilgileri ve beş güncel Türkiye fiyatı doğrulandı. Paid Apps Agreement/vergiler/banka, Business sayfasındaki veri yükleme hatası yüzünden doğrulanamadı; kullanıcı şu an hesap sahibinden kontrol alamıyor. Pasif olduğu varsayılmaz. Kaynak değişikliği yalnız güvenli katalog tanısı ve yanıltıcı hata mesajı düzeltmesi; build 11'e yüklenmedi. Ürün/fiyat sorunu henüz çözülmedi; satın alma yapılmadı. Ayrıntı: **IOS_STOREKIT_URUN_SORGUSU_2026-10-22.md**. Backend'e dokunulmadı, SMS açılmadı. Aşağıdaki eski TestFlight/cihaz yok kayıtları bu son ölçümlerle güncellenmiştir.

## 22 Ekim kullanıcıdan gelen yeni gerçek cihaz sonucu

Kullanıcı TestFlight uygulamasını iPhone'a kurup `test` hesabıyla giriş yaptığını teyit etti. Windows tek cihaz aracında hesap `6cdadd60-f73f-494b-aa2d-7b59528bc4b2`, son aktif iOS cihazı `4f9eb8a6-21ab-4cf5-843c-0dffb43993ac`, kayıt 2026-10-21T21:59:03.213404Z seçildi. FCM'ye yalnız bir istek, HTTP 200/SENT/FcmAccepted=true; kullanıcı bildirimi telefonda gördüğünü açıkça doğruladı. Ayar hash'i değişmedi; SMS'e dokunulmadı. Bu, aşağıdaki eski “TestFlight yüklenmedi/cihazda uygulama yok” durumunu günceller. Hangi yeni build'in yüklendiği bu Windows sohbetinde ayrıca ölçülmedi; taze App Store Connect/TestFlight ekranından kontrol edilmelidir. Arka plan/kapalı işlem/tıklama matrisinin tamamı yapılmış sayılmaz.

Kalan yeni belirti: satın almada “Bu ürün mağazada henüz tanımlı değil.” Kaynak `lib/services/billing_service.dart` `_buy` içinde ürün `_products` sözlüğünde yokken (mağaza erişilebilir görünüyor) çıkar; Apple'ın doğrudan hata metni değildir. `init` içindeki `queryProductDetails` ürünleri döndürmemiş/ürün sözlüğü dolmamış olabilir. Bu aşama backend makbuz doğrulamasından öncedir; Billing ayarı veya APNs anahtarı değiştirerek çözülmüş sayılmaz.

Mac'te doğru müşteri uygulamasında beş ürün ID'si/bundle eşleşmesi, ürün fiyat/lokalizasyon/ülke uygunluğu ve hesabın storefront'u; Paid Apps Agreement Active durumu, banka/vergi eksikleri kontrol edilmeli. Ürünleri silip yeniden oluşturmadan gerçek iPhone'da istenen/dönen ürün ID'leri, `notFoundIDs` ve sorgu hatası güvenli biçimde raporlanmalı; anahtar/JWT/mağaza makbuzu paylaşılmamalı. Kaynak: https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox . Ürün sorgusunun düzelmesi gerçek satın almanın tamamlandığı anlamına gelmez: backend Sandbox izolasyonu ve PhoneVerified/inceleme hesabı hâlâ ayrı açık maddelerdir.

## Güncel durum

Kullanıcı Mac tarafında mağaza hazırlığı ve gerçek iPhone push kontrolüne devam edilmesini istedi. Backend satın alma/Sandbox/inceleme hesabı Windows sohbetinde yürütülür; bu sohbette backend veya Windows ayarı değiştirilmez. SMS beklemede. Backend hazır haberi gelmeden satın alma/geri yükleme, son derleme ve yayın gönderimine geçilmez. TestFlight yüklemesi yapılmadı.

## Çalışma yeri ve sınırlar

- Depo `/Users/tunacort/Desktop/asfaltik/santiye_app`, `TunaCrt/santiye_app`, `main`. Üstteki asfaltik ayrı uygulama.
- Önce AGENTS.md, MAC_IOS_DEVIR_2026-10-20.md ve bu dosyayı oku. Mevcut tasarım/özellikler korunur.
- Sırlar, P8, profil, IPA, oturum/test parolası Git'e veya sohbet/loga alınmaz. Kullanıcı inceleme giriş bilgilerini kendisi girecek.
- Safari/native UI yalnız CUA ile; özet sonrası cua.rewriteDocumentation(). AX indeksleri taze gözlemden alınır. Hücre tıklaması yalnız odaklarsa screenshot koordinatı kullanılır.

## Main / Windows'tan gelen yeni durum

Temiz main `717a30a` → `1d111ee` fast-forward güncellendi; Windows sohbetinin kodu korundu, bu sohbette backend düzenlenmedi.

`docs/APPLE_BILLING_KURULUM_2026-10-21.md` son bölümü: gerçek Sandbox geçmiş okuma HTTP 200, P8 dosya özeti/JWT/saat kontrolleri doğru ve yayın öncesi Apple Billing kurulumu kullanıcı çıktısıyla başarılı. Production AllowSandbox=false korunuyor. Bu kayıt önceki 401/kurulum kapalı notlarından yenidir; müşterinin yanlış anahtar verdiği iddia edilmez. Production erişimi/teslimi, ayrı Sandbox ve PhoneVerified/inceleme hesabı hâlâ tamamlanmış değil. Kullanıcının tam hazır haberini bekle.

## Mağaza — son Safari kontrolü

- Şantiye Ağı Pro, Apple App ID `6824034438`, Bundle `com.yusuftaskiran.santiyeagi.pro`, Team `D49KUWV4VG`.
- **Beş ürünün tamamının inceleme görseli VE notu taze sayfa açılışında doğrulandı.** Üç kredi ürünündeki eski Processing/boş not belirsizliği çözüldü. SOURCE görseli ve doğru adetli not mevcut, Save pasif; kayıtlar kalıcı. Hiçbirinde Add for Review yapılmadı.
- Aylık `6825081370` / `santiye_premium_aylik`: 199,00 TL/ay; yıllık `6825081982` / `santiye_premium_yillik`: 1.599,99 TL/yıl peşin. Grup `22497968`, ikisi de seviye 1; süreler 1 month / 1 year, Türkçe grup adı hazır.
- 5 kredi `6825082912` / `santiye_kredi_5`: 99,99 TL; 15 kredi `6825083520` / `santiye_kredi_15`: 149,00 TL; 40 kredi `6825207287` / `santiye_kredi_40`: 419,99 TL. Üçü tüketilebilir. Yalnız Türkiye, uygulama ücretsiz; önceki fiyat onayı korunur.
- Sürüm 2.1.2 Prepare for Submission. Açıklama, promo, keywords, copyright, destek/pazarlama URL'leri ve inceleme iletişimi kayıtlı. Asfaltik değiştirilmedi. Sign-in required açık, kullanıcı/parola alanları Windows inceleme hesabını bekler. Build seçili değil/yüklenmedi. Mevcut otomatik sürüm yayımlama tercihi değiştirilmedi; gönderim yapılmadı.
- iPhone medium ve iPad 13 için beşer PNG yeniden doğrulandı (5 of 10). iPhone large için beş görsel önceki Media Manager kontrolünde doğrulanmıştı. Yerel çıktılar `output/mobile/app-store-2026-10-21/{iphone,iphone-large,ipad,review}`, manifest.json. `review/obsolete-premium-before-fix.png` kullanılmaz.
- Gizlilik 13 veri türü, 11'i işlevsellik/kullanıcıyla bağlantılı/izleme yok; **Coarse Location ve Other User Content hâlâ Set Up**, Publish pasif. Gemini'nin etkin olması ücretli veri işleme koşullarını ispatlamaz; gerçek proje/Billing/veri kullanım teyidi beklenir.
- Gizlilik/koşullar/hesap silme sayfası mevcut: https://yusuftaskiran753-dot.github.io/-santiye-agi/#gizlilik . Önceki kontrol geçerli; bu tur web değiştirilmedi.
- Apple Production ve Sandbox Server Notifications şimdilik aynı: `https://45.59.70.198/api/v1/billing/apple/notifications`. Windows ayrı Sandbox tam URL'sini çalışır olarak bildirmeden değiştirme.
- TestFlight açıklama/iletişim/notlar önceden kaydedildi. İnceleme hesabı gelince beta Sign-in required ve giriş alanları tamamlanacak. Sözleşme/vergi/banka tamamlandı sayılmaz.

## Gerçek iPhone push kontrolü: somut engel

- `İbrahim Tuna iPhone’u`, iPhone 13, kullanıcı USB ile bağladı. İlk ağ bağlantısı timeout verdi; USB sonrası devicectl apps sorgusu başarılı.
- **Şantiye Ağı Pro yüklü değil.** Kullanıcı da bunu doğruladı. Mevcut Asfalt Takip AI (`com.asfaltik.ai`) değiştirilmedi.
- Yereldeki doğru müşteri profili App Store dağıtım profili: production push, get-task-allow=false, ProvisionedDevices=0. Development/Ad Hoc müşteri profili yok. Bu profil cihaz UDID'si için USB kurulumu sağlamaz; TestFlight/App Store yoluyla kurulur.
- Kullanıcının backend hazır olana kadar TestFlight bekleme sınırı korunuyor. Dolayısıyla gerçek APNs/FCM teslimi bu tur test edilemedi; başarı iddia edilmez. Developer/ad hoc yetkisi veya yeni anahtar oluşturulmadı.
- Firebase santiye-agi iOS kaydı ve onayla yüklenmiş production APNs anahtarı hazır. Development APNs boş. Sonraki TestFlight uygulamasında izin → APNs/FCM token → oturumlu cihaz kaydı → yalnız test cihazına bildirim → arka plan/kapalı uygulama teslimi/tıklama kontrol edilir. Özel tokenler sohbete yazılmaz. Ön planda alert/sound kapalı, badge/uygulama içi güncelleme tasarımı korunur.

## İmzalı paket ve yerel kalite

- Doğru yeni profil: `~/Downloads/Santiyeagiappstore (1).mobileprovision`, UUID `def78a82-6064-47a6-b2cf-3d75184b2a85`; doğru bundle/ekip/yerel sertifika ve aps-environment=production.
- Arşiv `build/ios/archive/Runner-signed.xcarchive`. IPA `output/mobile/ios-app-store-2026-10-21/signed/santiye_agi.ipa`, 2.1.2+11, 23.659.242 bayt. SHA-256 `16675cc0f25e6c515c09ff8efa57c096e94662a8171e49140c0ba70728a301ee`. Son uygulamada production push, gömülü profil ve codesign strict kontrolü başarılı. Bu son kabul sonrası yapılacak nihai build'in yerine geçmez.
- İlk yanlış export `.invalid-no-push.ipa.disabled` olarak ayrıldı; yüklenmez. Runner Release geçici Manual imzalama ayarları geri alındı; global profil override Pods'u bozduğundan kullanılmaz.
- Xcode otomatik dağıtımı müşteri ekip hesabı bulunamadı hatası verdi; ASC yükleme yetkisinin yokluğu kesinleşmedi. Transporter lisansı kullanıcı onayıyla kabul edildi, giriş bekler. Kullanıcı yeni devam talebi verene kadar yükleme başlatılmaz.
- Son Flutter analizi temiz; 234 test geçti, ayrı yerel API isteyen 2 atlandı. Bu tur mobil kaynak değişmedi, aynı testler gereksiz tekrarlanmadı. Main'e gelen değişiklikler Windows/backend çalışması; bu sohbet bu kodu çalıştırmadı/değiştirmedi.

## Devam sırası

1. Windows'tan ayrı Sandbox API/callback URL'si, inceleme hesabı/PhoneVerified çözümü ve gerçek Gemini proje/veri işleme teyidini al.
2. Apple gizlilikte kalan iki alanı doğru bilgilerle tamamla; inceleme hesabını kullanıcı güvenli şekilde ASC'ye girsin. Beta giriş zorunluluğunu da tamamla.
3. Çalışan test API'siyle uygun yeni build, kullanıcı devam talebine göre TestFlight yüklemesi; hazır IPA production API'ye bakar ve kendiliğinden ayrı Sandbox'a geçmez.
4. Gerçek iPhone push ve StoreKit ürün/fiyat sorgusu, abonelik/geri yükleme/yenileme/iade, kredi tekrar işlememe ve konum kontrolleri. Gerçek satın alma adımları uygun kullanıcı katılımıyla yürütülür.
5. Son üretim build/kimlik/push doğrulaması, beş ürünü ilk iOS sürümüne bağlama, nihai mağaza/hesap kontrolleri ve yayın gönderimi. Kontroller kapanmadan yayına hazır denmez.
