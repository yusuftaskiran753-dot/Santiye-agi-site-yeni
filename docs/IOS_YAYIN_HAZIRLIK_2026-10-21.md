# iOS yayın hazırlığı — 21 Ekim 2026

Bu belge hazırlık kaydıdır; yayın onayı veya tamamlanmış cihaz testi anlamına gelmez.

## Doğrulanan uygulama

- App Store Connect: Şantiye Ağı Pro, Apple ID `6824034438`.
- Bundle ID: `com.yusuftaskiran.santiyeagi.pro`.
- Hedef satış bölgesi: yalnız Türkiye (kullanıcı onayı).
- Mevcut mobil sürüm: 2.1.2+11. App Store iOS taslağı 2.1.2 olarak kaydedildi; TestFlight ekranında No Builds görüldü. İmzalı paket henüz yüklenmedi.
- Firebase: `santiye-agi`, doğru iOS uygulama kaydı ve yerel plist hazır. Üretim APNs anahtarı kullanıcı onayıyla Firebase'e yüklendi; özel anahtar içerikleri bu belgeye veya Git'e eklenmedi. Geliştirme APNs ayarı ve gerçek cihaz teslimi ayrıca kontrol edilecek.
- SMS kullanıcının talebiyle beklemede; sunucuda SMS veya doğrulama ayarı değiştirilmedi.

## Son müşteri onayına göre ürün fiyatları

| ID | Tür | Türkiye fiyatı |
|---|---|---|
| santiye_premium_aylik | 1 ay otomatik yenilenen | 199,00 TL |
| santiye_premium_yillik | 1 yıl otomatik yenilenen, yıllık peşin | 1.599,99 TL |
| santiye_kredi_5 | Tüketilebilir, 5 kredi | 99,99 TL |
| santiye_kredi_15 | Tüketilebilir, 15 kredi | 149,00 TL |
| santiye_kredi_40 | Tüketilebilir, 40 kredi | 419,99 TL |

21 Ekim 2026 son müşteri talebi aylık 199 TL, yıllık 1.600 TL, 15 kredi 149 TL, 40 kredi 420 TL olarak geldi. Apple ek fiyat listesinde 199,00 ve 149,00 aynen seçildi; 1.600/420 yerine birer kuruş düşük 1.599,99/419,99 kullanıcı onayıyla kaydedildi. 5 kredi 99,99 TL korunur. Dört ürünün Türkiye fiyatları kayıt sonrası fiyat ayrıntılarından doğrulandı. Uygulamanın tahmini/demo fiyatları da aynı değerlere eşitlendi. Google Play Console ve backend kataloğundaki olası fiyat alanları bu tur değiştirilmedi; gerçek tahsilat mağaza ürün fiyatından gelir.

Beş ürün de App Store Connect’te oluşturuldu; Türkçe ad/açıklama, tabloda belirtilen Türkiye baz fiyatı ve yalnız Türkiye satış bölgesi kaydedildi. Aylık/yıllık aynı Premium grubundadır. Yalnız ürün oluşturmak satış/doğrulama testinin geçtiği anlamına gelmez.

Aynı hakları veren aylık ve yıllık planlar kullanıcının Safari sürükleme desteğiyle aynı seviye 1’e alındı, kaydedildi ve sayfa yenilenerek kalıcılığı doğrulandı. Plan geçişleri gerçek mağaza testi bekler.

## Önceki backend sohbetine aktarılacak iş

Mevcut Windows/IIS ayarları korunarak Apple satın alma bağlantısı tamamlanmalı. Mobil uygulamanın gerçek Bundle ID'si `com.yusuftaskiran.santiyeagi.pro`, Apple App ID `6824034438`; ürünler yukarıdaki kimliklerdir. `Billing:AppleBundleId` ve `Billing:AppleAppId` bu değerlerle eşleşmeli. Satın alma API anahtarı, Issuer/Key ID, güvenli özel anahtar yolu ve Apple güven kökleri `docs/ODEME_KURULUMU.md` uyarınca bağlanmalı. APNs anahtarı satın alma anahtarı değildir. Apple sandbox ortamının TestFlight satın alma testi için kabul edilmesi, `Enabled`/`AllowSandbox` ve test verisinin canlı haklarla karışmaması önceki sohbet tarafından planlanmalı. `POST /api/v1/billing/verify`, `/sync` ve Apple V2 bildirim uçları gerçek mağaza yanıtlarıyla kontrol edilmeli. Anahtarlar sohbete/Git'e veya mobil pakete eklenmeyecek. SMS beklemede kalacak. Bu sohbet backend veya Windows sunucusunda değişiklik yapmadı.

## Mağaza metni taslağı

Alt başlık: İş, makine ve nakliye ağı

Şantiye Ağı Pro, inşaat ve saha işlerinde yük, nakliye, iş makinesi, malzeme ve iş ilanlarını tek yerde buluşturur.

İlanları il ve kategoriye göre inceleyin; ihtiyaçlarınıza uygun ilan oluşturun, teklif verin ve anlaşmalarınızı takip edin. Firma ve kullanıcı profillerini, yapılan iş fotoğraflarını ve puanları inceleyin.

- Yük ve nakliye ihtiyaçları, iş makineleri, malzemeler ve iş ilanları.
- Teklif, anlaşma, teslim ve ödeme durumunu takip etme.
- Haritada saha ve ilan noktaları; isteğe bağlı süreli canlı konum paylaşımı.
- İhtiyacınızı yazarak arama; ayrı onayla Gemini destekli yorumlama.
- Hafriyat, sefer, yakıt ve dönüş yükü planlama araçları.
- Teklif ve iş hareketleri için uygulama içi bildirimler ve izin verilirse cihaz bildirimleri.

Ücretsiz üyeliğin kullanım sınırları uygulamada gösterilir. Premium, sınırsız ilan ve iletişim/teklif hakları sunar. İsteğe bağlı kredi paketleri iletişim/teklif hakkı ve ilan öne çıkarma için kullanılır. Fiyatlar satın alma ekranında gösterilir; iş bedelleri uygulama üzerinden tahsil edilmez.

Aylık ve yıllık Premium abonelikleri otomatik yenilenir. Ödeme satın alma onayında Apple hesabınıza yansıtılır. Aboneliğinizi Apple hesap ayarlarından yönetebilir veya iptal edebilirsiniz. Kredi paketleri tek seferlik uygulama içi satın alımlardır.

Konum paylaşımı isteğe bağlıdır ve uygulamadan durdurulabilir. Gemini kullanımı ayrıca onay ister; yanıtlar hatalı olabilir. Uygulama 18 yaş ve üzerindeki kullanıcılara yöneliktir.

Gizlilik: https://yusuftaskiran753-dot.github.io/-santiye-agi/#gizlilik
Kullanım koşulları: https://yusuftaskiran753-dot.github.io/-santiye-agi/#kullanim-kosullari
Apple standart kullanım koşulları: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Destek: yusuftaskiran753@gmail.com


## Canlı giriş seçenekleri — salt okunur kontrol

21 Ekim 2026'da HTTPS `GET /api/v1/auth/options` yanıtı `phone_verification_required=false`, `password_login_enabled=true` gösterdi. Böylece mevcut sunucu SMS zorunlu kılmıyor ve parolalı giriş seçeneği açık. Bu kontrol yeni kullanıcı kaydı veya gerçek inceleme hesabıyla giriş testi değildir; üretim doğrulaması atlatılmadı ve sunucu ayarı değiştirilmedi.

## Bu aşamada mağazada doğrulanan işlemler

- Premium grup ID `22497968`; Türkçe grup adı Şantiye Ağı Premium kaydedildi.
- Aylık Apple ürün ID `6825081370`, yıllık `6825081982`. Süreler 1 ay ve yıllık peşin 1 yıl; aylık taksitli taahhüt açılmadı.
- 5 kredi Apple ürün ID `6825082912`, 15 kredi `6825083520`, 40 kredi `6825207287`. Üçü de tüketilebilir; Türkçe ad/açıklama, fiyat ve Türkiye satışı kaydedildi.
- Ürünler Apple incelemesine gönderilmedi. Aylık/yıllık inceleme görselleri ve notları kaydedildi; kredi ürünlerinin görsel/not işlemleri kısmen tamamlandı ve kalıcılık kontrolü bekler. Ayrıntılı son durum MAC_IOS_DEVAM_2026-10-21.md dosyasında. Satın alma sandbox/gerçek cihaz testi yapılmadı.
- App Store sürüm metni, tanıtım, anahtar kelimeler, destek/pazarlama URL’leri, copyright ve kullanıcının istediği Asfaltik inceleme iletişimi kaydedildi. Asfaltik kaydı değiştirilmedi. İnceleme hesabının giriş bilgilerini kullanıcı sonra kendisi girecek.
- Uygulama ücretsiz: Türkiye baz fiyatı 0 TL. Uygulamanın satış bölgesi yalnız Türkiye; Türkiye durumu Available on App Release olarak görüldü.
- Yaş derecelendirmesi mevcut 18+ hedef kitleye uygun şekilde 18+ kaydedildi (eski işletim sistemleri 17+). Kullanıcı içeriği, sosyal keşif, iletişim ve ücretli ilan öne çıkarma özellikleri soru formunda dikkate alındı. İçerik hakları mevcut kullanım koşullarıyla eşleştirildi.
- Apple Production ve Sandbox Server Notifications adresleri `https://45.59.70.198/api/v1/billing/apple/notifications` olarak kaydedildi. Ekranda V1/V2 seçimi sunulmadı; gerçek V2 bildirim teslimi ve sunucu doğrulaması henüz test edilmedi.
- TestFlight beta açıklaması, geri bildirim adresi, iletişim, web/gizlilik adresleri ve inceleme notları kaydedildi. No Builds: yükleme veya test dağıtımı yok. Beta inceleme hesabı boş olduğundan Sign-in required seçimi kaydedilemedi; dış test incelemesinden önce kullanıcı hesabı girip bu seçimi etkinleştirmeli. App Store sürümündeki giriş zorunlu seçimi korunur; kullanıcı/parola bekler.
- Apple sözleşme/vergi/banka durumu bu çalışmada tamamlandı veya onaylandı sayılmaz.

## Yayın sayfası için hazır alanlar

- Sürüm: 2.1.2 (yüklenen paketle aynı olacak).
- Tanıtım metni: Şantiye işleriniz için yük, nakliye, iş makinesi, malzeme ve iş ilanlarını bulun; tekliflerinizi ve anlaşmalarınızı tek yerden takip edin.
- Anahtar kelimeler: şantiye,inşaat,nakliye,hafriyat,iş makinesi,kamyon,malzeme,yük,teklif,ilan,tedarik
- Destek URL: https://yusuftaskiran753-dot.github.io/-santiye-agi/
- Pazarlama URL: https://yusuftaskiran753-dot.github.io/-santiye-agi/
- Copyright: 2026 Yusuf Taşkıran
- Gizlilik URL: https://yusuftaskiran753-dot.github.io/-santiye-agi/#gizlilik
- Kategori: Business.
- Alt başlık: İş, makine ve nakliye ağı.
- İnceleme iletişimi: kullanıcının isteğiyle Asfaltik kaydından alınıp Şantiye Ağı’na kaydedildi; kişisel telefon bu belgeye yazılmadı.
- İnceleme giriş bilgileri: kullanıcı App Store Connect'e kendisi girecek. Sabit SMS kodu veya doğrulama atlatma eklenmeyecek.

## Gizlilik formu hazırlığı

Kaynaklar: `legal/gizlilik_politikasi.md`, `docs/KONUM_ASISTAN_GIZLILIK_MAGAZA_2026-10-20.md`, https://developer.apple.com/app-store/app-privacy-details/.

Gizlilik politikası URL’si kaydedildi. 13 veri türü seçildi: ad, telefon, fiziksel adres, diğer finansal bilgiler, tam/yaklaşık konum, özel iletişim metinleri, fotoğraf/video, diğer kullanıcı içeriği, kullanıcı/cihaz kimliği, satın alma geçmişi ve ürün etkileşimi.

Bunların 11’i için uygulama işlevselliği, kullanıcıyla bağlantılı ve izleme yok yanıtları kaydedildi. Gemini’ye gidebilen **yaklaşık konum** ve **diğer kullanıcı içeriği** amaçları bekliyor. Kullanıcı faturalandırmaya bağlı olduğunu düşünüyor; bu kesin doğrulama değildir. Önceki backend sohbeti, sunucudaki Gemini anahtarının ait olduğu Google projesinde aktif Cloud Billing/ücretli hizmet koşullarını ve veri kullanımını anahtarı açıklamadan doğrulamalı. Bu doğrulamaya göre kalan iki beyan tamamlanacak. **Gizlilik beyanı yayımlanmadı; Publish pasif.** Kart bilgileri uygulama tarafından toplanmaz; reklam/izleme SDK’sı yoktur.

## Görsel ve cihaz doğrulaması

iPhone orta boy (1206×2622), iPhone büyük boy (1320×2868) ve iPad 13 inç (2064×2752) için beşer gerçek uygulama ekran görüntüsü alındı, görsel olarak kontrol edilip Media Manager’a yüklendi; her grupta 5/10 görüntülendi. Yerel örnek hesap/Örnek etiketli uygulama verileri kullanıldı; canlı sunucuda işlem yapılmadı. Aylık/yıllık referans satın alma görselleri yüklendi ve notları kaydedildi. Kredi inceleme alanları kısmen tamamlandı; son durumu ve kalıcılığı ayrıca kontrol edilecek. Cihaz ve gerçek mağaza satın alma testleri tamamlanmadı. Varsayılan boş açılış görseli ilk arşivde uyarı verdi; mevcut marka ikonu ile değiştirilip 160 punto ölçülü açılış ekranı hazırlandı. Uygulamanın iç tasarımında/özelliklerinde değişiklik yok.


## Son yerel arşiv kontrolü

Yeni fiyat değişikliklerinden sonra imzasız arşiv yeniden başarıyla üretildi (2.1.2+11, 195,2 MB); imzalı IPA oluşturulmadı. Önceki açılış ekranı düzeltmesinden sonra canlı API/push dart-define dosyasıyla `flutter build ipa --release --no-codesign --dart-define-from-file=config/live-android-push.json` başarılı. App Settings Validation geçti; varsayılan açılış görseli uyarısı giderildi. `build/ios/archive/Runner.xcarchive` 2.1.2+11, iOS 15, doğru Bundle ID ve `santiye-agi` plist eşleşmesiyle kontrol edildi. İmzalama kapalı olduğundan IPA oluşturulmadı; TestFlight/App Store yüklemesi yapılmadı. TestFlight’ta No Builds görüldü; yükleme anında sürüm/build eşleşmesi yeniden kontrol edilecek.

İlk kontrolde Mac’te ilgili dağıtım profili yoktu. Sonradan gelen `Santiyeagiappstore.mobileprovision` doğru uygulama/ekip ve mevcut yerel sertifikayla eşleşti; fakat `aps-environment` alanı yok. Bu profil push içeren dağıtım için yeterli değil. Müşteriden Push Notifications etkinleştirilip yeniden üretilmiş profil bekleniyor. Yeni `.p8` dosyası da geldi; içeriği açılmadı ve satın alma anahtarı olduğu henüz teyit edilmedi. [Müşteri profil ve satın alma anahtarı talimatı](MUSTERI_IOS_PROFIL_TALIMATI_2026-10-21.md). Profil gelince imzalı paketin `aps-environment=production` ve kimlik/ekip/sertifika eşleşmesi kontrol edilmeli.

Yayın öncesi ayrıca: Apple satın alma sunucu bağlantısı; inceleme hesabı; kredi ürünlerinin inceleme görsel/not kayıtları ve son mağaza görsel kontrolü; gizlilik beyanı; gerçek iPhone bildirim, satın alma, geri yükleme ve konum kontrolleri tamamlanmalı. Uygulama henüz yayına hazır değildir.


## Yayındaki web sayfası kontrolü

21 Ekim 2026 Safari kontrolünde `https://yusuftaskiran753-dot.github.io/-santiye-agi/#gizlilik` açıldı. 20.10.2026 güncellemeli gizlilik metni, ayrı Gemini onayı, sağlayıcı planına göre veri kullanımı, isteğe bağlı GPS, FCM, Apple/Google satın alma doğrulaması, 14 günlük yerel yedek ve hesap silme açıklamaları görüntülendi. Kullanım koşulları ve hesap silme bağlantıları mevcut. App Store alanları bu adresleri kullanıyor. Sitede fiyat tutarı yerine mağazanın güncel fiyatına yönlendirme olduğundan eski sabit fiyat düzeltmesi gerekmedi. Gemini projesinin gerçek planı hâlâ backend teyidi bekler; web sayfasının varlığı bu teyidin yerine geçmez.

Önceki backend sohbetine iletilecek ayrıntılı görev: [BACKEND_IOS_YAYIN_GOREVI_2026-10-21.md](BACKEND_IOS_YAYIN_GOREVI_2026-10-21.md).


## Güncel durum — yeni profil ve imzalı IPA

Kullanıcının devam talebiyle yeni `Santiyeagiappstore (1).mobileprovision` kontrol edildi. UUID `def78a82-6064-47a6-b2cf-3d75184b2a85`, ekip/uygulama/yerel dağıtım sertifikası eşleşiyor; `aps-environment=production`, `get-task-allow=false`. Önceki push içermeyen profil hakkındaki üst kayıt tarihsel durumdur; yeni profil sorunu çözdü.

`build/ios/archive/Runner-signed.xcarchive` başarıyla üretildi. Doğru IPA: `output/mobile/ios-app-store-2026-10-21/signed/santiye_agi.ipa`, 2.1.2+11, 23.659.242 bayt. SHA-256 `16675cc0f25e6c515c09ff8efa57c096e94662a8171e49140c0ba70728a301ee`. Son uygulama imzasında **aps-environment=production**, doğru ekip/bundle ve dağıtım profili doğrulandı; `codesign --verify --deep --strict` başarılı. Kaynak proje geçici Runner Release imzalama ayarları derleme sonrasında geri alındı; anahtar/profil/IPA Git'e eklenmedi. İlk imzasız arşivden dışa aktarılan push eksik IPA, yanlışlıkla kullanılmaması için `.invalid-no-push.ipa.disabled` olarak yeniden adlandırıldı.

Xcode Organizer App Store Connect dağıtımı `No Account for Team "yusuf taskiran"` ve `No profiles ... were found` hatalarıyla durdu. Bu, yerel profil/imzanın hatalı olduğu veya App Store Connect yükleme rolünün bulunmadığı anlamına gelmez; otomatik dağıtım müşteri Developer ekibi hesabını aradı. Alternatif Transporter açıldı, lisansı kullanıcının ayrıca verdiği onayla kabul edildi; Apple hesabıyla giriş gerekiyor. **Kullanıcı yüklemeyi şimdilik bekletmemizi istedi. IPA Apple'a yüklenmedi.**

40 kredi inceleme görseli de denendi; Apple ekranında Processing kaldı, Save sonrasında not boşaldı ve kayıt kalıcılığı doğrulanamadı. 5/15 krediyle birlikte bu alanlar tamamlandı sayılmaz. Safari yenilemesi sonunda Apple `authResult=FAILED` giriş ekranı açıldı; yeniden oturum açılmalı. Hiçbir ürün veya sürüm Apple incelemesine gönderilmedi.

Güncel devam adımları [MAC_IOS_DEVAM_2026-10-21.md](MAC_IOS_DEVAM_2026-10-21.md), backend'e iletilecek görev [BACKEND_IOS_YAYIN_GOREVI_2026-10-21.md](BACKEND_IOS_YAYIN_GOREVI_2026-10-21.md). Backend/Windows değiştirilmedi. SMS beklemede. Yayın henüz hazır değildir.


## Son mağaza ve fiziksel cihaz kontrolü

Kullanıcının devam talebiyle main `1d111ee`'ye mevcut çalışmalar korunarak güncellendi. Windows'un yeni raporunda Sandbox API erişimi ve yayın öncesi Billing ayarları başarılı; ayrı Sandbox/inceleme hesabı/PhoneVerified işi Windows sohbetinde devam eder. Bu sohbet backend veya Windows ayarı değiştirmedi.

Beş ürünün **tamamının** inceleme görseli ve notu Safari'de taze ürün sayfalarından doğrulandı; Save pasif, doğru görsel ve notlar mevcut. Önceki kredi Processing/kayıt belirsizliği çözüldü. Aylık/yıllık seviye 1, süre ve Türkçe grup bilgileri doğrulandı. iOS 2.1.2 metin/iletişim alanları, iPhone medium/iPad beşer görseli mevcut. Ürün/sürüm incelemeye gönderilmedi.

USB ile bağlanan iPhone 13'e erişim başarılı; Şantiye Ağı yüklü değil. Mevcut profil App Store dağıtımı içindir, cihaz listesi yok; USB'den doğrudan kurulum profili bulunmuyor. Backend hazır olmadan TestFlight başlatılmadı. Bu nedenle gerçek push teslimi henüz test edilmedi. Ayrıntılı güncel devam sırası MAC_IOS_DEVAM_2026-10-21.md içindedir.

Gizlilikte Coarse Location ve Other User Content alanları Gemini gerçek proje/veri kullanım teyidini bekliyor; Publish pasif. İnceleme giriş bilgileri Windows hesabını bekler. Tasarım ve özellikler korunur; bu tur mobil kod değişmedi. SMS beklemede.
