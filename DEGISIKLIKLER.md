# Değişiklikler: v2.1.1 → v2.1.2 (2026-10-12)

Bu bakım sürümünde satın alma kredi tanımlamasının atomik olması, yayın derlemesinin demo ayarlarıyla yanlışlıkla üretilmemesi ve platform hazırlama betiklerinin geri alma güvenliği güçlendirildi. Flutter/Dart/Android SDK/Xcode bu çalışma ortamında bulunmadığından gerçek analiz, test ve native derleme sonucu iddia edilmez.

## Düzeltilen / güçlendirilen noktalar

- `supabase/schema.sql` + `supabase/functions/verify-purchase/index.ts`: Kredi satın alma kaydı, kredi cüzdanı ve defter kaydı artık `record_and_grant_credit_purchase` adlı tek veritabanı transaction'ında yapılır. Aynı makbuz tekrar geldiğinde ikinci kez kredi verilmez. Eski şemadan kalan kredi satın alımları çift ödeme riskine karşı tamamlanmış işaretlenir; eski sürümde kredi teslimatı kaybolmuş olabilecek kayıtlar ayrıca mağaza kaydıyla mutabakat gerektirir.
- `tools/verify_project.sh`: Android/iOS yayın derlemesinden önce canlı Supabase bilgileri, hizmet sağlayıcısı, destek e-postası, HTTPS yasal bağlantılar, harita URL/atıf ve Android imza anahtarı doğrulanır. Yayın betiği gereken `--dart-define` değerlerini otomatik geçirir ve demo ilanlarını kapatır.
- `lib/config.dart`: Operatör, destek, yasal URL'ler ve harita sağlayıcısı artık `--dart-define` ile ayarlanabilir. Örnek ilanlar varsayılan olarak kapalıdır; demo derlemesinde açıkça açılabilir.
- `tools/prepare_platforms.sh`: Platform iskeleti aynı dosya sisteminde geçici hazırlanır, imza dosyaları korunur ve hazırlık/ayar adımı başarısız olursa eski platform klasörleri geri alınır.
- `tools/prepare_platforms.bat`: Kısmi platform iskeletini yanlışlıkla tam kurulum saymak yerine açık hata verir; yeniden üretim için `--force` ister.
- Sürüm `2.1.2+5` olarak artırıldı.

## Bu paketle hâlâ kullanıcı/mağaza tarafında tamamlanması gerekenler

- Supabase projesi, gerçek API URL/anahtarı ve `verify-purchase` fonksiyon sırları kullanıcı tarafından kurulmalıdır.
- Google Play ve App Store ürünleri, abonelik olay bildirimleri (RTDN / App Store Server Notifications), satın alma sandbox testleri ve gerçek mağaza hesapları bu ZIP'ten tek başına üretilemez.
- Gerçek ticari harita sağlayıcısı ve anahtarı seçilmeli; harita atıf koşulları doğrulanmalıdır.
- Gerçek kişi/işletme adı, destek e-postası ve yayınlanmış yasal sayfalar sağlanmalıdır.
- iOS/Android platform klasörleri Flutter SDK ile üretilmeli; iOS IPA için macOS/Xcode, Android AAB için Android SDK ve geçerli imza anahtarı gerekir.
- Flutter analizi/testi ve gerçek cihaz derlemesi bu ortamda çalıştırılamadı. Bkz. `QA_RAPORU.md`.

---

# Değişiklikler: v2.1 → v2.1.1 (2026-10-10)

Kontrol ve düzeltme sürümü. Sunucu şemasında değişiklik yoktur; `schema.sql` yeniden çalıştırılmak zorunda değildir. Edge Function'da küçük bir düzeltme var (aşağıda), yeniden deploy önerilir.

## Düzeltilen hatalar

| Dosya | Sorun | Etki | Düzeltme |
|---|---|---|---|
| `lib/services/sync_queue.dart` | Kullanılmayan `dart:async` importu | `flutter analyze` bunu uyarı sayar ve hata koduyla çıkar; `tools/verify_project.sh` testlere geçmeden dururdu | Import kaldırıldı |
| `tools/prepare_platforms.bat` | `flutter create` komutu `call` olmadan çağrılıyordu | `flutter` bir .bat dosyası olduğundan Windows betiği bu satırdan sonra **hiç devam etmiyordu**: android/ ve ios/ klasörleri hiçbir zaman oluşmuyordu | `call flutter …` / `call dart …` |
| `tools/prepare_platforms.bat` | Yeni klasörler `%TEMP%` altında hazırlanıp projeye `move` ediliyordu | Proje TEMP'ten farklı sürücüdeyse (ör. `D:\`) klasör taşıma başarısız olurdu | Hazırlık proje içindeki `.platform_staging` klasöründe |
| `tools/prepare_platforms.bat` | Dosya LF satır sonuyla kaydedilmişti; geri alma adımı "dokunulmadı" mesajına düşüyordu | cmd.exe `goto`/etiket satırlarını yanlış okuyabilir; yanıltıcı hata mesajı | CRLF + `.gitattributes`; geri alma akışı ayrıldı, yarım kalan geri yüklemede eski klasörler silinmez |
| `tools/prepare_platforms.sh` / `.bat` | Betik yeniden çalıştırılınca `android/` klasörü tamamen silinip yeniden üretiliyordu | `android/key.properties` ve `.jks` yükleme anahtarı da silinirdi (anahtar kaybolursa Google Play'e güncelleme yüklenemez) | İmza dosyaları korunup yeni iskelete taşınır; iskelet zaten varsa `--force` olmadan dokunulmaz |
| `tools/prepare_platforms.sh` | Boş dizi `set -u` ile | macOS'taki bash 3.2'de "unbound variable" hatası | Güvenli dizi açılımı |
| `lib/screens/listings/contact_sheet.dart` | Her hata "İnternet bağlantınızı kontrol edin" olarak gösteriliyordu | Engelleme, hak açılmamış, ilan silinmiş gibi durumlarda yanlış yönlendirme | Gerçek neden gösterilir; "Tekrar dene" yalnızca bağlantı/sunucu hatalarında |
| `lib/screens/deals/deal_form_screen.dart` | Kod örneği `ABCD1234` | Kod alfabesinde 1 yok; örneği yazan kullanıcı hata alırdı | `ABCD2345` |
| `supabase/functions/verify-purchase/index.ts` + `lib/services/backend.dart` | Bozuk istek gövdesi 500 `SERVER` dönüyordu; `BAD_INPUT` kalıcı sayılmıyordu | Uygulama aynı geçersiz doğrulamayı her açılışta sonsuza kadar yeniden denerdi | 400 `BAD_INPUT`; istemci bunu kalıcı ret sayar (test eklendi) |

## Eklenen eksikler

- **Android release imzası otomatik:** `tools/patch_platforms.dart` (hazırlama betikleri çalıştırır) `android/app/build.gradle.kts` dosyasına Flutter belgesindeki imza ayarını ekler. `android/key.properties` varsa release derlemesi yükleme anahtarıyla imzalanır; yoksa debug anahtarı kullanılır ve derlemede uyarı çıkar. Şablon: `android/key.properties.example`.
- **iOS uygulama adı:** Ana ekranda "Santiye Agi" yerine **Şantiye Ağı** görünür; `ITSAppUsesNonExemptEncryption = false` eklendi (uygulama yalnızca standart HTTPS kullanır, App Store'un her yüklemede sorduğu ihracat sorusu çıkmaz).
- **`.gitignore`:** imza anahtarları (`key.properties`, `*.jks`, `*.p8`), servis hesabı JSON'ları, `.env` ve derleme klasörleri depoya girmez.
- **`.gitattributes`:** `.bat` CRLF, `.sh` LF olarak korunur.
- Sürüm `2.1.1+4` (mağazaya yükleme için derleme numarası artırıldı).

# Değişiklikler: v2 → v2.1

Bu sürüm beş başlıkta sağlamlaştırma ve incelemede bulunan hataların düzeltmesidir. **Önce `supabase/schema.sql` dosyasını yeniden (tamamen) çalıştırın, sonra uygulamayı güncelleyin.** Eski uygulama sürümleri yeni şemayla çalışmaya devam eder (tek fark: yanlış anlaşma kodu girilince eski sürüm hata yerine boş bir anlaşma sayfası açar).

## 1. Çevrimdışı çalışma (offline-first)

Şantiyede çekim kesildiğinde yapılan işlemler artık kaybolmaz.

- **Gönderim sırası** (`lib/services/sync_queue.dart`): İnternet yokken yapılan yazma işlemleri cihazda kalıcı bir sıraya yazılır, uygulama kapansa da silinmez ve bağlantı gelince sırayla gönderilir. Kapsam: ilan kaydı/düzenleme/kapatma/silme, makine müsaitliği, teklif gönderme/yanıtlama/geri çekme, anlaşma adımları (onay, teslim, tamamlama, ödeme işaretleri, not, sorun bildirme, iptal), puan, şikâyet, engelleme, profil ve "okundu" bilgisi.
- **İyimser görünüm:** Sıraya alınan işlem ekranda hemen görünür; ilgili kayıtta "Gönderilmeyi bekliyor" etiketi çıkar. Ana sayfadaki bant bekleyen işlem sayısını ve "Şimdi gönder" düğmesini gösterir.
- **Çift kayıt yok:** Her işlemin bir kimliği (UUID) vardır. Yeni ilanın kimliği cihazda üretilir. Yanıtı kaybolan istek (zaman aşımı) aynı kimlikle yeniden gönderilir ve sunucu onu ikinci kez uygulamaz (`client_ops` tablosu, `p_op_id` parametresi).
- **Kurallar cihazda da denetlenir:** Anlaşma durum makinesi `lib/logic/deal_rules.dart` dosyasına taşındı; demo modu ve çevrimdışı denetim aynı kodu kullanır. Kurala uymayan adım (ör. tamamlanmış anlaşmayı yeniden onaylama) sıraya alınmaz, hata hemen gösterilir.
- **Sunucu reddederse:** İşlem sıradan çıkarılır, kullanıcıya hangi işlemin neden uygulanamadığı bildirilir ve sunucudaki doğru hâl gösterilir.
- **Sıra korunur:** Sırada işlem varken yeni işlem araya girmez. Aynı kaydın ardışık değişiklikleri birleştirilir (yalnızca son hâl gider); anlaşma adımları birleştirilmez.
- **Otomatik yeniden deneme:** 5 sn, 10 sn, 20 sn … en çok 5 dk aralıkla; ayrıca uygulama öne gelince ve "Şimdi gönder" ile. Bağlantı geri gelince bekleyen mağaza doğrulamaları da tamamlanır.
- **Önbellek** artık kullanım haklarını (Premium, kredi) ve puanlanmış anlaşmaları da saklar; internetsiz açılışta bekleyen işlemler son sunucu verisinin üstüne uygulanır.
- Kredi harcayan veya kodu sunucuda üretilen işlemler (iletişim hakkı, öne çıkarma, anlaşma kaydı oluşturma/katılma, satın alma) bilerek yalnızca çevrimiçidir.
- Çıkış yaparken gönderilmemiş işlem varsa kullanıcı uyarılır.

## 2. Form doğrulamaları

- Ortak, katı doğrulayıcılar: `lib/utils/validators.dart` (`Validators`, `FieldLimits`, `Sanitize`). Sınırlar sunucudaki tablo kısıtlarıyla aynıdır; kullanıcı hatayı göndermeden alanın altında görür.
- Kapsam: yük, makine, malzeme, iş ilanı, sicil kartı, profil, teklif/talep, elle anlaşma kaydı, anlaşmaya katılma kodu, puan yorumu, anlaşma notu, şikâyet açıklaması, hafriyat noktası.
- Dinamik doğrulama: alanlar yazdıkça denetlenir; çapraz kurallar (makinede saatlik **veya** günlük ücret, malzemede en az sipariş, teklif toplamının üst sınırı, ödeme planı toplamı = bedel, tarih aralığı); hatalı alan varsa "işaretli alanları düzeltin" uyarısı.
- Sayı girişi katılaştı (`tryParseNumber`): "12a" gibi girişler artık sessizce 0 sayılmaz; "12,500.50" doğru okunur; negatif ücret/miktar reddedilir; adet/torba/palet birimlerinde tam sayı istenir.
- Metinler kaydedilmeden önce temizlenir (görünmez karakterler, fazla boşluk/boş satır, tekrar eden liste maddeleri).

## 3. Güvenlik (RLS ve yetkiler)

Tüm kurallar `supabase/tests/10_rls_test.sql` ile gerçek PostgreSQL 16 üzerinde (sıfırdan kurulum ve v2'den yükseltme) test edildi.

| Bulgu | Risk | Düzeltme |
|---|---|---|
| Oturumsuz (yalnızca yayınlanabilir anahtarla) istek profilleri, ilanları ve puanları okuyabiliyordu | Toplu veri çekme | Bütün kurallar yalnızca `authenticated` rolüne; `anon` için tablo yetkileri kaldırıldı |
| `is_blocked_between`, `listing_info`, `display_name`, `notify` herkes tarafından çağrılabiliyordu (oturumsuz bile; denendi) | "A, B'yi engellemiş mi?" sorgusu, gizlenmiş ilan bilgisi | Uygulamadan çağrılamaz; yalnızca sunucu fonksiyonlarının içinden çalışır |
| `is_premium`, `active_listing_count` başka kullanıcı için sorgulanabiliyordu | Bilgi sızıntısı | Yalnızca kendi bilgisini döndürür |
| Kredi ile hak açmada bakiye düşülemese bile hak açılıyordu; eşzamanlı isteklerle ücretsiz hak aşılabiliyordu | Gelir kaybı | Kullanıcı başına işlem kilidi ve bakiye kontrolü |
| Anlaşma kodu 16 karakterli alfabeden (0-9, A-F) ve sınırsız denemeyle | Kod tahmin ederek başkasının anlaşmasına katılma | 32 karakterli alfabe (~1,1 trilyon olasılık), saatte 10 hatalı deneme |
| Süresi geçmiş yük ilanının tarihi ileri alınınca ücretsiz ilan sınırı uygulanmıyordu | Sınırın aşılması | Yeniden yayına girişte sınır denetlenir |
| Anonim hesaplar ücretsiz olduğu için 3 sahte hesapla rakip ilan gizlenebiliyordu; kişi kendi ilanını şikâyet edebiliyordu; günlük şikâyet ve anlaşma kaydı sınırı yoktu | Kötüye kullanım, spam | 24 saatten yeni hesabın şikâyeti otomatik gizlemeye sayılmaz (kaydedilir), kendi ilanı sayılmaz, günlük sınırlar (`app_settings`) |
| Profil şikâyet sayısı herkese açık profil tablosuna yazılıyordu | İtibar bilgisinin herkese açılması | Artık yazılmıyor; yönetici `reports` tablosundan görür |
| `security definer` fonksiyonlarda `search_path` içinde `pg_temp` sonda değildi | Arama yolu ele geçirme (en iyi uygulama) | Tümünde `public, pg_temp` (test, bunu her fonksiyon için doğrular) |
| İstemci rolünde TRUNCATE/REFERENCES/TRIGGER yetkileri duruyordu | Satır güvenliğini atlayan yetki | Kaldırıldı |
| Ödeme planı tutarı sayı değilse anlaşılmaz hata; tutarlara üst sınır yoktu | Bozuk kayıt | `BAD_INPUT`, üst sınır |

## 4. Algoritma testleri

- `test/haul_optimizer_test.dart`: Boş/eksik girdi, NaN/sonsuz/negatif değerler, geçersiz parametreler, kapasite tam/yetersiz, döküm ücreti–mesafe dengesi, gün ve maliyet toplamları, nokta sırasından bağımsızlık, **300 rastgele örnekte kaba kuvvetle bulunan en iyi sonuçla birebir karşılaştırma**, dönüş yükü (stok, ihtiyaç, dönen sefer sayısı, kazançsız ocak, birden fazla ocak, paylaşılan stok).
- `test/load_matcher_test.dart`: Bilinmeyen il, büyük/küçük harf ve boşluk, sınır mesafesi (tam sınırda dahil), 0/negatif/NaN sınır, kapalı/gizli/geçmiş ilan, kendi ilanı, araç tipi, puan aralığı, yön ve yakınlık, kararlı sıralama.
- Testlerdeki beklenen değerler algoritmanın birebir Python karşılığıyla ayrıca hesaplandı.
- Ayrıca: `test/sync_queue_test.dart`, `test/offline_sync_test.dart`, `test/validators_test.dart`.

## 5. Hata yönetimi ve geri bildirim

- **Tek tip geri bildirim** (`lib/widgets/feedback.dart`): başarı (yeşil), bilgi, uyarı (sarı) ve hata (kırmızı) ayrı simge ve renkle. Uygulama geneline bağlı olduğundan ekran kapandıktan sonra gelen sonuçlar da (ör. bekleyen ödemenin onaylanması, çevrimdışı işlemlerin gönderilmesi) kullanıcıya ulaşır. Aynı mesaj üst üste tekrarlanmaz.
- Bağlantı ve sunucu kaynaklı hatalarda **"Tekrar dene"** düğmesi.
- Sunucu hataları anlaşılır koda çevrilir (benzersizlik, kısıt, yetki, oturum, sunucu meşgul…). Teknik hata metni kullanıcıya gösterilmez.
- Supabase isteklerine 20 sn zaman aşımı: zayıf çekimde istek asılı kalmaz.
- Yakalanmamış hatalar uygulamayı çökertmez; kaydedilir ve tek, sakin bir mesaj gösterilir.
- **Satın alma (billing_service.dart):** her mağaza/doğrulama hatası için ayrı Türkçe açıklama (zaten sahip olunan ürün, ağ, satın almanın kapalı olması, süresi dolmuş/iade edilmiş/başka hesaba ait satın alma…); çift dokunuşla ikinci ödeme penceresi açılmaz.

## 6. İncelemede bulunan ve düzeltilen diğer hatalar

| Sorun | Etkisi | Düzeltme |
|---|---|---|
| Satın alma doğrulanırken beklenmeyen hata olursa satın alma mağazada tamamlanmıyordu | Google Play ödemeyi 3 gün içinde iade eder; "işleniyor" göstergesi takılı kalırdı | Satın alma her durumda tamamlanır; hak önce cihaza yazılır, sonra doğrulanır |
| Satın alma sonucu yalnızca ödeme ekranı açıkken gösteriliyordu | Bekleyen ödeme sonradan onaylanınca kullanıcı bilgilenmiyordu | Uygulama geneli bildirim |
| "Geri yükle" 4 sn sonra, doğrulama sürerken "abonelik bulunamadı" diyordu | Yanlış mesaj | Doğrulamalar bitene kadar beklenir |
| Bekleyen satın alma doğrulaması yalnızca açılışta deneniyordu | Hak gecikmeli tanımlanıyordu | Bağlantı geri gelince de denenir |
| Demo modunda aynı abonelik her "geri yükle"de süreyi uzatıyordu | Yanlış Premium süresi | Aynı satın alma bir kez işlenir |
| Demo modunda örnek firma, kullanıcının işaretlediği değil ilk ödenmiş satırı onaylıyordu | Yanlış ödeme satırı | İşaretlenen satır onaylanır |
| İnternetsiz açılışta Premium kullanıcı ödeme ekranıyla karşılaşıyor, puanlanmış anlaşmalar yeniden "puan bekliyor" görünüyordu | Yanlış durum | Önbelleğe kullanım hakları ve puanlar eklendi |
| "Okundu" bilgisi gönderilemezse kayboluyordu (kod yorumu tersini söylüyordu) | Okunmuş bildirimler tekrar okunmamış görünüyordu | Gönderim sırasına alınır |
| Kapalı (anlaşması yapılmış) yük ilanı veya sicil kartı düzenlenince kendiliğinden yeniden yayına giriyordu | Kapanmış ilana yeni teklifler | Mevcut durum korunur |
| İlan kaydedildikten sonra liste yenilemesi başarısız olursa hata gösteriliyordu | Kullanıcı tekrar deneyince ilan iki kez oluşuyordu | Kayıt başarılıysa yenileme hatası gösterilmez; kimlik cihazda üretilir |
| Teklif kabulünde anlaşma kimliği dönmezse "Talep reddedildi" yazıyordu | Yanlış bilgi | Doğru mesaj |
| Öne çıkarma ve şikâyet sonrası mesaj kapanan sayfanın bağlamıyla gösteriliyordu | Mesaj bazen görünmüyordu | Uygulama geneli bildirim |
| Kredi/Premium seçildikten sonra hak açılamazsa sessiz kalıyordu | Kullanıcı ne olduğunu anlamıyordu | Uyarı gösterilir |
| Hafriyat: kamyon kapasitesi 0 veya geçersizse `Infinity.ceil()` hatası; 0,4 kamyon 0'a yuvarlanıp süre "0 gün" çıkıyordu | Çökme / yanlış süre | Parametre denetimi ve makul aralıklar |
| Hafriyat: 0,0004 m³ yuvarlama artığı "kapasite yetmeyen 0 m³" uyarısı çıkarıyordu; kazancı ~0 km olan dönüş yükü öneriliyordu; NaN/sonsuz değerler hesabı bozuyordu | Yanıltıcı rapor | Artık temizleniyor; en az 0,5 km kazanç; geçersiz noktalar yok sayılır |
| Hafriyat noktasında negatif ücret/hacim girilebiliyordu | Anlamsız maliyet | Doğrulama |
| Boş dönüş: listede olmayan il adı sessizce İstanbul sayılıyordu; "istanbul" gibi küçük harfle yazılmış il eşleşmiyordu; eşit puanlarda sıra her seferinde değişebiliyordu | Yanlış öneri | Toleranslı il arama, bilinmeyen il atlanır, kararlı sıralama |
| "12,500.50" 12,5005 okunuyordu; "12a" sessizce 0 kabul ediliyordu | Yanlış fiyat/miktar | Katı sayı çözümleme |
| Sabit hat numarasına SMS kodu gönderilmeye çalışılıyordu; kod 6 hane mi denetlenmiyordu | SMS gitmez, gereksiz istek | Cep telefonu ve 6 hane denetimi |
| Anlaşma kodu 6 karakter yazılınca deneniyordu (kod 8 hanelidir) | Gereksiz hatalı deneme | 8 hane ve alfabe denetimi |
| Herkese açık puan yorumu ve anlaşma notu uygunsuz içerik süzgecinden geçmiyordu | Mağaza politikası ihlali riski | Süzgeç eklendi |
| Düğme içindeki yakalanmamış hata işlenmeden kalıyordu | Kullanıcı sonucu bilmiyordu | Düğme hatayı yakalar ve gösterir |
| Supabase isteklerinde zaman aşımı yoktu | Zayıf çekimde dakikalarca bekleme | 20 sn |
| "Tekrar dene" Supabase'i ikinci kez başlatıyor, oturum dinleyicisi çoğalıyordu | Çift olay, olası hata | Bir kez başlatılır |

## 7. Nasıl doğrulandı?

Bu ortamda Flutter/Dart SDK kurulamadı (paket sunucularına erişim yok). Bu yüzden:

- **Dart:** Tüm dosyalar tree-sitter-dart ile sözdizimi denetiminden geçti; yeni/değişen tüm çağrılarda kurucu ve metot parametre adları tanımlarla karşılaştırıldı. Algoritma testlerinin beklenen değerleri, algoritmanın birebir Python karşılığıyla ayrıca hesaplandı. **`flutter analyze` ve `flutter test` çalıştırılamadı**; ilk iş bunları çalıştırın.
- **SQL:** `schema.sql` gerçek PostgreSQL 16 üzerinde sıfırdan kuruldu, iki kez üst üste çalıştırıldı ve v2 şemasının (verili) üzerine yükseltildi. `supabase/tests/10_rls_test.sql` (yaklaşık 80 kontrol) her üç durumda da geçti.

---

# Değişiklikler: v1 → v2

## Özet

v1 iyi bir prototipti: Ekranlar, boş dönüş eşleştirme ve hafriyat hesabı sağlamdı. Ancak üç temel sorun vardı:

1. **Sunucu yoktu.** Her kullanıcı yalnızca kendi telefonundaki verileri görüyordu. Gönderilen teklif ve talepler hiçbir yere ulaşmıyordu.
2. **"Güvenli ödeme / emanet" bölümü gerçek parayla çalıştırılamazdı.** Başkası adına para tutmak lisanslı ödeme kuruluşu olmayı gerektirir. Mağazalar da fiziksel hizmet ödemelerinin uygulama içinden alınmasına izin vermez.
3. **Gelir korunmuyordu.** Deneme süresi ve Premium durumu yalnızca telefonda tutuluyordu. Uygulamayı silip yeniden kurmak denemeyi sıfırlıyordu ve satın almalar sunucuda doğrulanmıyordu.

v2 bu üç sorunu temelden çözer. Gerçek, çok kullanıcılı bir pazar yeridir. Para taraflar arasında doğrudan el değiştirir. Gelir yalnızca mağaza üzerinden satılan dijital özelliklerden gelir ve her satın alma sunucuda doğrulanır.

---

## 1. İş modeli

| | v1 | v2 |
|---|---|---|
| Gelir | 14 gün deneme, sonra her şey Premium | **Freemium:** Temel kullanım ücretsiz. Premium sınırsız kullanım sağlar. Kredi paketleri tek seferlik kullanım içindir. |
| İş bedelleri | Uygulama içi emanet (simülasyon) | Taraflar arasında doğrudan. Uygulama yalnızca ödeme planını **kayıt** olarak tutar. |
| Satın alma doğrulama | Cihazda | Sunucuda (Google Play Developer API, App Store Server API) |
| Sınırlar | Kodun içinde | Sunucudaki `app_settings` tablosunda, panelden değişir |

Ücretsiz kullanıcının da uygulamada değer bulması önemli. İlanlara göz atmak her zaman serbest. Her ay 5 iletişim/teklif hakkı ve 5 aktif ilan ücretsiz. Kullanıcı ihtiyaç duydukça Premium'a geçer. Ödeme duvarı ilk günden önüne çıkmaz.

## 2. Eklenenler

**Altyapı**
- Supabase sunucusu: Tüm tablolarda satır bazlı güvenlik (RLS). Kurallar sunucu fonksiyonlarında olduğu için uygulama değiştirilerek aşılamaz. Bu kurallar: kota, kredi, ilan sınırı, günlük spam sınırı, anlaşma akışı, puan ve şikâyet.
- Mağaza satın alma doğrulama fonksiyonu (Edge Function). Aynı satın alma ikinci kez kullanılamaz. Uygulama yeniden kurulduğunda abonelik yeni hesaba taşınır. Sunucuya ulaşılamazsa satın alma telefonda saklanır ve sonra otomatik tamamlanır, kullanıcı hakkını kaybetmez.
- Canlı bildirimler (Supabase Realtime) ve çevrimdışı açılış için önbellek.
- **Demo modu:** Sunucu kurmadan bütün akış denenebilir. Örnek firmalar teklif ve taleplere birkaç saniyede yanıt verir.

**Güven ve güvenlik**
- Telefon numaraları gizli. Yalnızca iletişim hakkı açan veya anlaşma kaydı olan kişiye görünür. v1'de numara her ilanda herkese açıktı.
- Puan yalnızca **tamamlanmış anlaşmadan sonra**, her taraf için bir kez verilebilir. v1'de bir operatöre iş yapmadan da puan verilebiliyordu.
- Şikâyet: ilan, kullanıcı ve anlaşma için. 3 farklı kişi şikâyet edince ilan otomatik gizlenir.
- Engelleme, uygunsuz içerik süzgeci, telefon doğrulama ve onaylı firma rozetleri, "güvenli ticaret" rehberi.
- Uygulama içinden hesap silme (Apple ve Google zorunluluğu).

**Akışlar**
- Tek tip teklif/talep sistemi: yük teklifi, makine kiralama talebi, malzeme siparişi, iş başvurusu, operatöre iş teklifi.
- **Anlaşma kaydı:** Kabul edilen teklif otomatik olarak kayda dönüşür. Kayıt kod ile davet ederek elle de açılabilir. Akış: onay → iş tamamlandı → teslim alındı → puan. Ödeme planı "ödedim / tahsil ettim" ile işaretlenir. Sorun bildirme, not ekleme, işlem geçmişi, kopyalama ve WhatsApp'tan paylaşma vardır.
- Yük ilanında teklif kabul edilince diğer teklifler otomatik reddedilir ve ilan kapanır.
- İlanı öne çıkarma (24 saat / 7 gün, kredi ile).
- Tüm ilanlarda ortak arama ekranı.

**Arayüz**
- Yeni ana sayfa: Selam, arama, dört kategori, yapılacaklar kartı, role göre öneri ve bölgedeki yeni ilanlar.
- 5 sekmeli sade alt menü: Ana Sayfa · İlanlar · (+) İlan ver · İşlerim · Profil.
- Açık ve koyu tema, büyük yazı boyutlarında bozulmayan düzen, tek elle kullanıma uygun büyük düğmeler.

**Yasal**
- Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni ve Hesap Silme sayfası şablonları (`legal/`).
- İlk açılışta koşulların kabulü. Aydınlatma metni, KVKK'ya uygun olarak "kabul" değil "okudum" şeklinde sunulur.
- Ödeme ekranında abonelik bilgilendirmesi, geri yükleme düğmesi ve yasal bağlantılar.

## 3. Kaldırılanlar

- **Güvenli ödeme / emanet ekranları.** Yerine anlaşma kaydı ve ödeme planı takibi geldi.
- Cihazda tutulan deneme süresi ve cihazda verilen Premium.
- Hiçbir yere gönderilmeyen "Teklifiniz iletildi" türü mesajlar. Artık her teklif karşı tarafa bildirim olarak gidiyor.

## 4. Bu sürümün son kontrollerinde bulunup düzeltilen hatalar

| Sorun | Etkisi | Düzeltme |
|---|---|---|
| Tema, tüm sekme çubuklarına "başa hizala" ayarı veriyordu | "Nasıl çalışır?" rehber ekranı açılınca geliştirme sürümünde çöküyordu. Sabit sekme çubuğunda bu ayar geçersizdir. | Ayar yalnızca kaydırılabilir sekme çubuğuna verildi |
| İlan etiketlerinde tür denetimi alana bağlıydı (`listing is Load && listing.isExpired`) | Derleme hatası. Dart, sınıf alanlarında tür daraltma yapmaz. | Yerel değişkenle düzeltildi |
| Mağaza servis hesabı izin hatası (HTTP 401/403) "geçersiz satın alma" sayılıyordu | Yeni kurulumda izinler oturana kadar ödeme yapan kullanıcı hakkını kalıcı olarak kaybedebilirdi | Bu hatalar geçici sayılıyor, uygulama sonra yeniden deniyor |
| Demo modunda yeni bildirim gelince ekranda bilgi çıkmıyordu | Kullanıcı karşı tarafın yanıtını fark etmiyordu | Bildirim başlığı kısa mesaj olarak gösteriliyor |
| Hafriyat ekranında beklemeden sonra ekranın açık olduğu kontrol edilmiyordu | Kullanıcı o sırada ekrandan çıkarsa hata kaydı oluşuyordu | Kontrol eklendi |
| İlk açılıştaki onay metni "Aydınlatma Metni'ni kabul ediyorum" diyordu | KVKK uygulamasında aydınlatma metni kabul ettirilmez | Metin "Koşulları kabul ediyorum; Aydınlatma Metni'ni okudum" olarak değiştirildi |

## 5. Nasıl doğrulandı?

Bu ortamda Flutter SDK kurulamadığı için doğrulama şu adımlarla yapıldı:

- **Dart sözdizimi:** Tüm dosyalar (tree-sitter-dart).
- **Anlamsal denetim:** Flutter 3.35.0 ve güncel Flutter, Dart SDK ile tüm paketlerin (Supabase, in_app_purchase, flutter_map, provider…) kaynaklarına karşı yapıldı:
  - import ve isim çözümleme
  - kurucu ve fonksiyon parametreleri
  - üye varlığı ve türe göre üye denetimi
  - argüman türleri
  - null güvenliği (nullable alıcı/argüman)
  - enum `switch` eksiksizliği
  - soyut üye uygulamaları
  - `@override` doğruluğu
  - kullanılmayan kod
  - Flutter yerleşim kuralları (Expanded/ListView/TextField yerleşimleri)
  - `flutter_lints` kurallarının çoğu
- **Sunucu:** `schema.sql` gerçek PostgreSQL 16 üzerinde senaryo testleriyle denendi. Senaryolar: kota, kredi, teklif → anlaşma, puan, şikâyet ile gizleme, yetki ihlali denemeleri.
- **Doğrulama fonksiyonu:** TypeScript tür denetiminden geçti. Sahte Google/Apple yanıtlarıyla 14 kontrolde test edildi. Testlerde imzalar gerçek RSA/ECDSA anahtarlarıyla doğrulandı.

Projeyi kendi bilgisayarınızda açınca yine de ilk iş `flutter analyze` ve `flutter test` çalıştırın.
