# Şantiye Ağı — müşteriden gelen ilk mobil sürümün özellik envanteri

İnceleme tarihi: **15 Ekim 2026**. Referans: müşterinin gönderdiği **v2.1.2+5** kaynak arşivi. Bu belge, .NET geçişinden önce uygulamada hangi sayfanın ve işlemin bulunduğunu kayda alır. Yeni backend için özellik koruma kontrol listesi olarak kullanılmalıdır.

## 1. Hangi sürüm kayıt altına alındı?

- Kaynak: `Santiye_Agi_v2.1.2. Güncel.zip` içindeki `santiye_agi/` klasörü.
- Arşivin SHA-256 özeti: `557661ECFA3CB93B8A65BE821F82489668684C928DE3E5FD08BEC0F29209ACC1`.
- Arşivden çıkarılan ilk kaynak kopyası saklandı. İnceleme, ayrı bir çalışma kopyasında yapıldı. **54 Dart kaynak dosyası ve pubspec.yaml, asıl arşivle birebir aynı**; dosya bazındaki özetler [original-source-sha256.json](baseline/original-source-sha256.json) dosyasında.
- Bu sürümde varsayılan Supabase adresi/anahtarı boş; uygulama cihazda çalışan **demo modunda** açılır. Supabase bağlantı kodu ve SQL dosyaları vardır; bağlantısız demoda birden fazla gerçek kullanıcının aynı sunucuda çalışması denenmiş sayılmaz.
- Örnek ilanlar ilk açılışta **kapalıdır**. İncelemede Profil → **Örnek ilanları göster** açılarak örnek içerik de incelendi. Bu, müşterinin ilk sürümünün davranışıdır; boş pazar ekranı bir özellik kaldırılması anlamına gelmez.
- İlk sürümde profil fotoğrafı, yapılan iş fotoğrafı yükleme veya fotoğraf galerisi **yoktur**. Avatarlar ad/firma baş harfleriyle çizilir. Sonradan istenen iş fotoğrafları ayrı bir geliştirmedir.

### İnceleme işaretleri

| İşaret | Anlamı |
|---|---|
| **UI** | Orijinal Flutter arayüzü test ortamında açıldı; ilgili gruptaki belirtilen düğmeler/alanlar kullanıldı. |
| **KURAL** | Orijinal uygulamanın iş mantığı/cihaz demo katmanı veya otomatik testleri incelendi ve çalıştırıldı. |
| **KAYNAK** | Özellik orijinal koddan doğrulandı; o özel dalın düğmesi bu incelemede uçtan uca çalıştırılmadı. |
| **DIŞ** | SMS, mağaza, WhatsApp/arama, harita karosu gibi dış hizmet veya cihaz uygulaması gerekir; gerçek hizmet sonucu doğrulanmadı. |

**UI**, bir bölümün her olası veri durumunun, her cihazda ve gerçek dış hizmetlerle denendiği anlamına gelmez. Sayfa ve düğme kataloğu kaynak kodunun tamamını kapsar; çalıştırılan adımların ayrıca kanıtı tutulur. Gerçek para harcanmadı, gerçek kişilere mesaj/arama yapılmadı, müşterinin canlı sunucusuna bağlanılmadı.

## 2. Ana gezinme ve ilk açılış

Kaynaklar: `lib/main.dart`, `screens/shell.dart`, `screens/onboarding/*`.

| Sayfa / kontrol | Müşterinin ilk sürümündeki işlev |
|---|---|
| Açılış ekranı | Şantiye Ağı logosu ve yükleniyor göstergesi. Başlatma hatasında **Bağlanılamadı → Tekrar dene**. |
| Karşılama | Uygulamanın pazar yeri, doğrudan anlaşma, kayıt/puanlama tanıtımı; demo bilgisi. |
| Koşul onay kutusu | İşaretlenmeden **Başla** pasif. Kullanım koşulları, gizlilik ve KVKK bağlantıları yer alır. Bağlantı adresleri yapılandırılmalıdır. |
| Başla | Varsayılan anonim girişte **Sizi tanıyalım** profil formunu açar. Telefon giriş modu ayrıca kodda bulunur, varsayılan açık değildir. |
| Profil oluşturma | Ad soyad, isteğe bağlı firma, cep telefonu, iş rolü ve çalışılan il; **Kaydet ve başla**. Geçersiz telefon/ad için alan uyarıları. |
| Alt menü | **Ana Sayfa**, **İlanlar**, **İlan ver (+)**, **İşlerim**, **Profil**. İlan ver ayrı bir sekme yerine seçim penceresi açar. |
| Geri davranışı | Android geri tuşu başka ana sekmedeyken önce Ana Sayfa'ya döner. Alt sayfalarda geri dönüş vardır. |
| Uygulamaya geri dönme | İnternet/sıra durumu veya son yenileme zamanına göre verileri yeniler. |
| Kısa bildirim | Uygulama içi olay mesajında **Gör** düğmesi bildirim sayfasını açar. |

**UI:** Koşul onayı, Başla, ad/telefon doldurma, Kaydet ve başla ve beş alt menü kullanıldı. **KAYNAK:** açılış hata dalı, Android fiziksel geri tuşu, yaşam döngüsü ve dış yasal bağlantılar. **DIŞ:** yasal URL'lerin gerçek içerikleri bu sürümde varsayılan boş.

### Rol seçenekleri

Nakliyeci / Tırcı; Yük Sahibi; Makine Sahibi; Müteahhit / Şantiye; Malzeme Tedarikçisi; Operatör / Personel. Rol, ana sayfadaki öneriyi ve ilan verme listesinin sırasını etkiler; kullanıcıyı yalnız bir ilan türüyle sınırlamaz.

### Telefonla giriş dalı

Kodda **Telefonla giriş**, cep telefonu, **Kod gönder**, altı haneli kod, **Doğrula**, **Numarayı değiştir**, 60 saniyelik tekrar gönderme beklemesi ve **Kodu tekrar gönder** vardır. Demoda sabit `123456` açıklaması bulunur. Canlı Supabase telefon modunda SMS sağlayıcısı gerekir. Orijinal varsayılan anonim mod, telefonun gerçekten SMS ile doğrulandığı anlamına gelmez. Bu dal **KAYNAK/DIŞ** olarak kayıt altındadır.

## 3. Ana Sayfa

Kaynak: `screens/home/home_screen.dart`. **UI:** MainShell üzerinden açıldı. Aşağıdaki dinamik dalların tümü ayrıca kaynakta doğrulandı.

- Kullanıcının ilk adıyla saate göre selamlama; il ve rol bilgisi.
- **Bildirimler** zili ve okunmamış sayısı.
- Varsa sunucudan gelen duyuru metni.
- **Yük, makine, malzeme veya il ara…** genel arama alanı.
- **Yük / Makine / Malzeme / Personel** kategori kartları ve ilan sayıları; ilgili pazar kategorisini açar.
- Bekleyen teklif varsa **yeni teklif/talep** kartı → İşlerim/Gelen; aksiyon bekleyen anlaşma varsa → İşlerim/Anlaşmalar.
- Ücretsiz iletişim hakkı ve kredi bakiyesi; **Premium** bağlantısı.
- İle göre yeni ilanlar, öne çıkanların önceliği, en fazla altı öneri; **Tümü** ile ilanlara geçiş.
- Pazar boşsa **İlan ver** çağrısı; aşağı çekerek yenileme.
- Çevrimdışı/bekleyen işlem bandı: durum, son veri zamanı, bekleyen adet; **Şimdi gönder** veya **Tekrar dene**.

Rolüne göre öneriler:

| Rol | Kart ve yönlendirme |
|---|---|
| Nakliyeci | **Boş dönmeyin** → boş dönüş eşleştirme. |
| Yük sahibi | **Yükünüz için teklif toplayın** → yük formu. |
| Makine sahibi | Makine yoksa ekle; varsa mevcut makine ayrıntısı/müsaitlik güncelleme. |
| Müteahhit | **Hafriyatı planlayın** → hafriyat planlama. |
| Tedarikçi | **Fiyatlarınızı yayınlayın** → malzeme formu. |
| Personel | Sicil yoksa oluştur; varsa iş ilanlarına göz at. |

## 4. Genel arama

Kaynak: `screens/search/search_screen.dart`. **UI:** hazır Ekskavatör araması, temizleme ve bulunamayan sorgu denendi.

- Tüm beş ilan türünde başlık, il, firma ve diğer arama metinlerinde arama.
- İki karakterden önce **Sık aranan** önerileri: Ekskavatör, Silindir, C30/37, Mıcır, Lowbed, İnşaat demiri, Operatör.
- Hazır öneriye basınca arama doldurulur; **Temizle (X)** aramayı sıfırlar.
- Türkçe büyük/küçük harf normalleştirmesi; birden fazla kelimede tüm kelimeler aranır.
- Sonuçlar Yük/Makine/Malzeme/İş ilanı/Operatör başlıklarında gruplanır. Her grupta ilk **20** sonuç gösterilir; sonsuz kaydırma yoktur.
- Sonuç kartı ilan ayrıntısını açar; bulunamazsa açıklamalı boş ekran.

## 5. İlanlar — dört pazar kategorisi

Kaynak: `screens/market/market_screen.dart`, `listings/cards.dart`. **UI:** dört kategori, sıralama menüleri, makine Müsait/Liste/Harita ve personel İş ilanları/Operatörler geçişleri kullanıldı. Her filtre seçeneğinin tüm kombinasyonları çalıştırılmadı; seçenekler **KAYNAK** ile listelendi.

### 5.1 Yük pazarı

- Yük cinsi/firma/il araması.
- **Nereden**, **Nereye** aranabilir il seçicileri; **Tüm Türkiye** ile filtreyi kaldırma; **Yönü değiştir**.
- Araç filtresi: Tır (Tenteli), Frigorifik, Damperli, Kırkayak, Lowbed, Kamyon, Kamyonet; **Tüm araçlar**.
- **Boş dönmeyin** kartı → boş dönüş sayfası.
- Sıralama: **Önerilen**, **En yeni**, **Yükleme tarihi**, **En yüksek navlun**, **Km başı en iyi**.
- Önerilen sırada öne çıkanlar, kullanıcının ilinden çıkanlar, sonra yeniler öne gelir.
- Kartta güzergâh, navlun/teklif usulü, yük cinsi/ton/araç, yükleme günü, yaklaşık mesafe, firma/puan ve etiketler.
- Sonuç yoksa **Yük ilanı ver**; aşağı çekerek yenileme.

### 5.2 Makine pazarı

- Model/firma/il araması; tür filtresi ve **Tümü**.
- Türler: Ekskavatör, Silindir, Greyder, Finişer, Loder, Beko Loder, Dozer, Mobil Vinç, Kamyon / Damper, Diğer.
- **Liste / Harita** görünümü; **Müsait** filtresi.
- Sıralama: **En yakın**, **En ucuz (günlük)**, **En yüksek puan**. Günlük fiyat yoksa karşılaştırmada saatlik × 8 kullanılır.
- Haritada müsait/çalışıyor işaretleri; işarete basınca ilan açılır. Harita karo sağlayıcısına internet gerekir; yerel test gerçek karo indirme doğrulaması değildir.
- Kartta model/tür, kapasite, il/yaklaşık mesafe, günlük/saatlik ücret, operatör ve durum, firma/puan.
- Sonuç yoksa **Makinemi ekle**; listeyi yenileme.

### 5.3 Malzeme pazarı

- Tür: **Hazır Beton / Agrega / Stabilize / Asfalt / Diğer**.
- Türdeki ürünler için ek ürün filtresi; **Tüm ürünler**.
- Sıralama: **Teslim dahil en ucuz**, **Fiyatı en ucuz**, **En yakın**. Öne çıkarılanlar ayrıca başa alınır.
- Belirli tek ürün seçildiğinde tahmini teslim maliyetine göre **En avantajlı** işareti.
- Kartta ürün, tesis/il/mesafe, birim fiyat, tahmini teslim fiyatı, stok, nakliye ve satıcı/puan.
- KDV hariç fiyat ve şehir merkezine göre tahmini nakliye uyarısı. Tahmin, gerçek rota/teklif veya ödeme değildir.
- Boş durumda **Ürün / fiyat ekle**; yenileme.

### 5.4 Personel pazarı

- **İş ilanları / Operatörler** geçişi; ortak pozisyon filtresi ve **Tüm pozisyonlar**.
- Pozisyonlar: Ekskavatör Operatörü, Silindir Operatörü, Greyder Operatörü, Finişer Operatörü, Vinç Operatörü, Tır / Kamyon Şoförü, Ustabaşı / Formen, Saha İşçisi.
- **Sadece [kullanıcının ili]** filtresi.
- Operatör sıralaması: öne çıkan, müsait, yüksek puan. Sicil kartı olmayan kullanıcıya **Operatör müsünüz?** → sicil formu.
- İş kartında başlık/rol/il/ücret/süre/şartlar; operatör kartında kişi/rol/deneyim/belgeler/müsaitlik/puan.
- Boş iş listesinde **Personel ilanı ver**; yenileme iki personel türünü birlikte yeniler.

## 6. İlan ver (+) ve beş ilan formu

Kaynak: `screens/listings/forms/*`. **UI:** seçim penceresi ve bütün formlar açıldı, boş/varsayılan gönderimler denendi. Makine, malzeme, personel ilanı ve sicil kartı ayrıca doldurulup yayınlandı. Yük formunun seçim/doğrulama dalı UI, kayıt işlevi orijinal AppState testlerinde **KURAL** olarak doğrulandı.

İlan ver penceresinde **Yük ilanı ver**, **Makinemi ekle**, **Ürün / fiyat ekle**, **Personel ilanı ver**, **Sicil kartımı oluştur/düzenle** ve ilan dışı **Anlaşma kaydı oluştur** bulunur. Rolüne uygun seçenek başa gelir. Ücretsiz aktif ilan kotası gösterilir.

| Form | Alanlar / seçimler | Ana düğmeler ve kurallar |
|---|---|---|
| Yük | Yükleme ili, teslim ili, **Yer değiştir**, yük cinsi, ton, isteğe bağlı navlun, araç tipi, yükleme tarihi, açıklama. | **İlanı yayınla / Değişiklikleri kaydet**. Navlun boşsa teklif usulü. İller seçilmeli, tarih geçmiş olmamalı/en fazla bir yıl sonrası. |
| Makine | Tür, marka/model, kapasite, günlük/saatlik ücret, bulunduğu il, **Operatör dahil**, **Şu an kiralamaya müsait**, açıklama. | **Yayınla / Değişiklikleri kaydet**. Saatlik/günlük ücretlerden en az biri pozitif. Konum gerçek GPS seçimi değil; il merkezine yakın yaklaşık nokta atanır. |
| Malzeme | Tür, ürün metni ve hazır öneriler, KDV hariç fiyat, birim, stok, tesis/plent adı, il, en az sipariş, **Nakliye sağlıyoruz**, açıklama. | **Yayınla / Değişiklikleri kaydet**. Birimler ton, m³, adet, kg, torba, palet. Stok var/az/yok. Nakliye kapalıysa alıcı ayarlar. Adet/torba/palette minimum sipariş tam sayı. |
| Personel ilanı | Aranan pozisyon, başlık, çalışma ili, isteğe bağlı ücret, ücret dönemi, süre, virgüllü şartlar, açıklama. | **İlanı yayınla / Değişiklikleri kaydet**. Dönem Günlük/Aylık/Saatlik/Götürü. Şartlarda ilk öneri MYK ve G sınıfı ehliyet; bunlar gerçek belge doğrulaması değildir. |
| Sicil kartı | Profil adı/puanı, pozisyon, çalışma ili, deneyim yılı, virgüllü belgeler, hakkımda, **Şu an iş arıyorum (müsait)**. | **Kaydet**. Kişi başına tek kart güncellenir; ad ve puan profilden gelir. Deneyim 0–60 yıl. Fotoğraf veya belge dosyası yükleme yoktur. |

Malzeme hazır önerileri:

- Beton: C20/25, C25/30, C30/37, C35/45, C40/50.
- Agrega: 0-5 Kum, 5-12 Mıcır, 12-22 Mıcır, 22-38 Mıcır, Filler.
- Stabilize: Ocak Stabilize, Plent-miks Temel (PMT), Alttemel.
- Asfalt: Binder, Aşınma, BSK Bitümlü Temel, Soğuk Asfalt.
- Diğer: Tuğla, Briket, Çimento (torba), İnşaat demiri.

## 7. İlan ayrıntısı ve sahip işlemleri

Kaynak: `screens/listings/listing_detail_screen.dart`. **UI:** beş tür ayrıntısı, ziyaretçi menüsü; kendi makine ilanında müsaitlik, kaldır/yeniden yayınla/sil çalıştırıldı. Diğer dallar **KAYNAK/KURAL**.

Ortak: başlık/alt başlık, durum/Örnek/Öne çıkan etiketleri, türün bilgi satırları, açıklama, firma/kişi/puan/rozetler ve profiline geçiş. İlan yoksa bulunamadı ekranı.

| Tür | Gösterilen ek bilgiler |
|---|---|
| Yük | Navlun, km başı fiyat, yük, ton, araç, tarih, tahmini mesafe, yayın zamanı; **Google Haritalar'da yol tarifi**. |
| Makine | Tür, kapasite, il/mesafe, günlük/saatlik fiyat, operatör, müsait/çalışıyor; **Konumu haritada aç**. Sahipte **Kiralamaya müsait** anahtarı. |
| Malzeme | Ürün, birim ve teslim dahil tahmin, stok, minimum, nakliye, tesis/mesafe; ilk sürümde “Güncelleme” başlığı altında aslında oluşturulma tarihi. |
| Personel ilanı | Pozisyon, yer, ücret/dönem, süre, yayın zamanı, aranan şartlar etiketleri. |
| Sicil | Pozisyon, deneyim, il, müsaitlik, tamamlanan iş sayısı, belgeler, hakkında. |

**Sahip:** alt çubukta **Düzenle / Öne çıkar**. Diğer menüsünde **Düzenle**, açık ilanda **Öne çıkar**, **Yayından kaldır / Yeniden yayınla**, **Sil**. Silmeden onay istenir; bekleyen teklifler kapanır. Kapalı ilanı düzenlemek kendiliğinden yayınlamaz. Sahibe o ilanın **Gelen teklifler/talepler** listesi gösterilir.

**Ziyaretçi:** **Numarayı göster / İletişim** ve türe göre **Teklif ver / Kiralama talebi / Sipariş ver / Başvur / İş teklif et**. Bekleyen teklif varsa **Teklifi güncelle**; kabul edilen teklif için **Anlaşmayı aç**. Kapalı/uygun olmayan makinede teklif düğmesi pasif, durum metni gösterilir. Diğer menüsünde **Şikâyet et / Kullanıcıyı engelle**.

**Paylaş:** WhatsApp'a gönderilecek, telefon içermeyen ilan özeti hazırlanır. İlk sürümde bu gerçek bir uygulama içi sohbet veya doğrulanmış derin bağlantı sistemi değildir. **DIŞ:** WhatsApp ve harita uygulamasının açılması bu testte yapılmadı.

## 8. İletişim hakkı, iletişim penceresi ve teklif formları

Kaynak: `billing/billing_flows.dart`, `listings/contact_sheet.dart`, `listings/request_sheet.dart`.

### İletişim / hak açma

- Önce o ilan için iletişim hakkı açılır. İlk beş hak aylık ücretsiz; Premium sınırsız; hak bitince 1 kredi kullanımı.
- Aynı ilanın açılmış hakkı tekrar tüketilmez. Hak kalmadığında **1 kredi kullan**, **Premium'a geç · sınırsız**, **Kredi satın al** seçenekleri.
- Canlı moddaki örnek ilanla işlem engeli vardır; bağlantısız demoda örnekler üzerinden akış simüle edilir.
- İletişim penceresinde ad, telefon, doğrulandı/doğrulanmadı rozeti, **Ara**, **WhatsApp**, **Numarayı kopyala**, güvenli ticaret uyarısı.
- Telefon yoksa açıklama; geçici yükleme hatasında **Tekrar dene**.
- Talebi alan/sunan kişinin numarasına talep üzerinden de erişim vardır; kabulden önce de paylaşılabilen dallar bulunur. İlk sürümdeki “Kabul edince paylaşılır” ifadesi bu davranışı eksik anlatır.

**KURAL:** ücretsiz hak/kredi/Premium ve önceden hak açma testleri çalıştırıldı. **DIŞ:** gerçek arama/WhatsApp/SMS veya iletişim kotası için para harcanmadı.

### Talep / teklif alanları

**UI:** beş tür için gerekli alanlar doldurulup **Gönder**, İşlerim/Giden'de **Geri çek** ve onayı çalıştırıldı. Makine talebinde **Saatlik** seçildi.

| Tür | Form ve hesap |
|---|---|
| Yük | Nakliye teklifi tutarı, yükleyebileceğim gün, not. İlan navlunu varsa başlangıç değeri olur. |
| Makine | **Günlük / Saatlik**, kaç gün/saat, başlangıç, şantiye konumu/adres, not. Tahmini tutar = ilan birim ücreti × süre; operatör dahil bilgisi. |
| Malzeme | Miktar, teslim tarihi, teslimat adresi, not. Minimum sipariş kontrolü; KDV hariç malzeme toplamı = miktar × birim fiyat; nakliye teyidi. |
| İş başvurusu | Not/deneyim mesajı; sicil kartı yoksa oluşturma önerisi. |
| Operatöre iş teklifi | Ücret, dönem, başlangıç, çalışma yeri, not. |

**Gönder / Güncelle** aynı bekleyen talebi güncelleyebilir. Boş/uygunsuz zorunlu alan, geçmiş tarih, aşırı miktar/tutar doğrulanır. Başarı mesajı yanıtın İşlerim'den takip edileceğini belirtir.

## 9. İşlerim ve gelen/giden teklifler

Kaynak: `screens/work/*`. **UI:** dört sekme ve beş tür giden geri çekme; kabul akışı orijinal testlerde **KURAL**.

- **Gelen:** bekleyenler önde, sonra güncelleme zamanı; sayılı rozet. Boşsa **İlan ver**.
- **Giden:** gönderilen tüm teklifler ve durumları; boşsa **İlanlara göz at**.
- **Anlaşmalar:** **Yeni kayıt**, **Kodla katıl**. Listeler: **Sizi bekleyenler**, **Devam edenler**, **Tamamlanan ve iptal edilenler**.
- **İlanlarım:** açık ilanlar önde, sonra yeni tarih; karta basınca sahip ayrıntısı. Boşsa **İlan ver**.
- Her listede aşağı çekerek yenileme.
- Talep kartı: ilan, karşı taraf/profil, tutar, miktar, tarih, adres, not, durum ve zaman.
- Gelen bekleyen talepte **İletişim / Reddet / Kabul et**, her yanıt öncesi onay.
- Kabul, iki taraflı anlaşmayı otomatik açar. Yük kabulünde yük kapanır ve rakip teklifler reddedilir.
- Giden bekleyen talepte **Geri çek**. Kabul edilen kayıtta **İletişim / Anlaşmayı aç**.
- Durumlar: Bekliyor, Kabul edildi, Reddedildi, Geri çekildi.

## 10. Anlaşma kaydı oluşturma ve kodla katılma

Kaynak: `screens/deals/deal_form_screen.dart`. **UI:** form ve boş doğrulama açıldı; ayrı testte elle oluşturulan kaydın **Kendi kaydım olarak başlat / Başlat** akışı çalıştırıldı. Kodla iki ayrı kişi katılımı **KAYNAK/KURAL**.

- İlan dışında yapılan nakliye, kiralama, taşeron veya malzeme işini elle kaydetme.
- Benim rolüm: **İşi veren / alıcı** veya **Hizmet veren / satıcı**.
- İş tanımı, karşı taraf adı, isteğe bağlı toplam bedel, ödeme şekli, başlangıç tarihi, ödeme koşulu, detaylar.
- Ödeme şekilleri: Havale / EFT, Nakit, Çek / Senet, Kredi kartı (POS), Diğer. **Bunlar ödeme takip etiketidir; uygulamada sanal POS entegrasyonu bulunduğu anlamına gelmez.**
- Bedel girildiğinde ödeme planı seçimi ve tutar önizlemesi: **Tek ödeme**; **%30 avans + %70 teslimde**; **%30 / %40 / %30**; **Aylık 4 hakediş**. Yuvarlama farkı son satıra eklenir.
- **Kaydı oluştur** → anlaşma ayrıntısı. Kod üretimi için canlıda bağlantı gerekir.
- **Kodla katıl** → sekiz karakterli anlaşma kodu, **Katıl**. Boşluk/tire temizlenir ve büyük harfe çevrilir; geçersiz kod uyarılır.

## 11. Anlaşma ayrıntısı — durum, ödeme, not ve puan

Kaynak: `screens/deals/deal_detail_screen.dart`, `deal_widgets.dart`, `logic/deal_rules.dart`. **UI:** tek kişilik anlaşmada başlat, Ödedim, Tahsil ettim, sorun bildir/çözüldü ve tamamla düğmeleri denendi. İki kişilik kabul→ödeme→tamamlama→puan, orijinal testlerde **KURAL**. Diğer özel dallar **KAYNAK**.

Ortak içerik: durum/tür, iş başlığı, kayıt kodu ve **Kopyala**, taraflar, karşı tarafla **İletişim**, bedel/ödeme şekli/koşulu/başlangıç, ödenen-tahsil edilen toplamlar, ödeme planı satırları, detaylar, ters tarihli işlem geçmişi. Aşağı çekerek yenileme.

| Durum | İlk sürümdeki düğmeler / davranış |
|---|---|
| Onay bekliyor, henüz karşı taraf yok | **WhatsApp ile davet et**, **Kendi kaydım olarak başlat**. Tek kişilik takipte kaydı oluşturan iki rolü de yürütür; karşı taraf daha sonra kodla katılabilir. |
| Karşı taraf katılmış, onay bekliyor | Oluşturan bekler; diğer taraf **Reddet / Onayla**. |
| Devam ediyor | Sağlayıcı **İşi tamamladım / teslim ettim**; alıcı **Teslim aldım, tamamla** (onayla); **Sorun bildir**. |
| Teslim bildirildi | Alıcı **Teslim aldım, tamamla / Sorun bildir**; sağlayıcı onay bekler. |
| Sorun bildirildi | Sorun metni; **Sorun çözüldü**, önceki duruma dönüş. İlk sürümde iki taraftan herhangi biri çözebilir. |
| Tamamlandı | Henüz değerlendirmemiş gerçek karşı taraf için **[Ad] için puan ver**; tek kişilik kayıtta karşı taraf olmadığı için puan yok. |
| İptal edildi | Geçmiş görünür, iş durumu değiştirilemez. |

**Ödeme satırları:** bekliyor/ödendi bildirildi/tahsil edildi; alıcı **Ödedim → İşaretle**, sağlayıcı **Tahsil ettim → Evet, tahsil ettim**. Bunlar banka tahsilatı yapmaz. Tek kişilik kayıtta iki düğme de kullanılabilir.

**Diğer menüsü:** açık anlaşmada **Not ekle**; **Özeti kopyala**; uygun durumlarda **Anlaşmayı iptal et** ve neden; **Şikâyet et**. Üstte **Özeti paylaş** WhatsApp metni hazırlar. İlk sürüm devam eden anlaşmada tek taraflı iptale izin verir; bu mevcut davranışın kaydıdır, yeni tasarım için güvenlik önerisi değildir.

**Puan formu:** 1–5 yıldız düğmesi, isteğe bağlı herkese açık yorum, **Kaydet**. Yalnız tamamlanmış anlaşmada taraf başına bir puan. Profilde ortalama/sayı ve yorumlar görünür. İlk hesap silme davranışıyla puanın kaybolması riski raporda ayrıca bulunmaktadır.

## 12. Boş dönüş eşleştirme

Kaynak: `screens/loads/backhaul_screen.dart`, `logic/load_matcher.dart`. **UI:** sayfa ve il seçilmeden arama uyarısı. Başarılı eşleştirme, araç/yön/mesafe/puan ve kenar durumları orijinal testlerde **KURAL**.

- **Boşaldığım il**, **Dönmek istediğim il** (varsayılan profil ili), araç tipi veya **Fark etmez**.
- **Uygun yükleri bul**; eksik ilde uyarı; sonuç yoksa araç filtresini genişletme önerisi.
- Kendi ilanı/kapalı/geçmiş yükler hariç; varsayılan en fazla 250 km boş gidiş çevresindeki yükler.
- 0–100 uygunluk yüzdesi, Çok uygun/Uygun/Kısmen, boş gidiş mesafesi, eve yaklaştırma/uzaklaştırma, km başına navlun.
- Sonuç kartından ilan ayrıntısı. Güncel ilanlar değişince sonuç yeniden hesaplanır.
- Mesafeler şehir merkezlerinden yaklaşık hesaplanır; gerçek zamanlı GPS, trafik veya canlı rota API'si yoktur.

## 13. Hafriyat planlama ve rota/maliyet hesabı

Kaynak: `screens/haul/haul_screen.dart`, `logic/haul_optimizer.dart`. **UI:** örnek sahaları yükle, yerel Premium testi ve Rotayı Optimize Et sonucunun gösterimi. Matematik/kapasite/geri dolgu testleri **KURAL**. Manuel harita noktası ekleme/silme/paylaşım **KAYNAK/DIŞ**.

- Harita ve kazı/döküm/ocak işaretleri; hesap sonrası saha-döküm/dönüş çizgileri.
- Üst menü **Örnek sahaları yükle**.
- **Nokta ekle** → haritada konuma dokun → **Yeni nokta** formu; ekleme modunu X ile iptal.
- Nokta türleri **Kazı sahası / Döküm sahası / Malzeme ocağı**. Ad, hacim/kapasite/stok; kazıda geri dolgu ihtiyacı; dökümde ücret; ocakta malzeme fiyatı ve tür adı; **Ekle**.
- Saha listesinde tür, hacim, kapasite/ücret, örnek etiketi; çöp kutusu ve silme onayı. Sahalar cihazda tutulur.
- Filo alanları: kamyon hacmi (başlangıç 18 m³), kamyon sayısı (8), yakıt tüketimi (45 L/100 km), motorin (55 ₺/L), günlük çalışma (10 saat). Bunlar ilk sürümün örnek değerleridir, güncel piyasa fiyatı değildir.
- **Rotayı Optimize Et**; en az bir kazı ve döküm gerekir; hesap için Premium istenir.
- Sonuç: toplam sefer, kamyon sayısıyla tahmini gün, yakıt+döküm maliyeti, hacim, toplam km, litre/yakıt bedeli, döküm ücretleri, basit en yakın döküme göre tasarruf, kapasite yetmeyen miktar uyarısı.
- Saha→döküm dağılımı; hacim/sefer/mesafe/sefer süresi/maliyet; uygunsa ocaktan geri dolgu dönüş yükü, km/yakıt tasarrufu.
- **Kopyala** ve **Planı WhatsApp ile paylaş**.
- Hesap maliyet ve kapasiteye dayanır. Yol, kuş uçuşu mesafenin `kRoadFactor` katsayısı ile tahminidir; navigasyon/gerçek yol/trafik garantisi yoktur. Sonuçlar mühendislik onayı yerine geçecek şekilde doğrulanmadı.

## 14. Kendi profilim ve hesap işlemleri

Kaynak: `screens/profile/profile_screen.dart`. **UI:** örnek ilan anahtarı, profil düzenleyip kaydetme ve engellenen listeden engeli kaldırma; diğer seçenekler **KAYNAK/KURAL/DIŞ**.

| Bölüm | İlk sürümde bulunan seçenekler |
|---|---|
| Profil kartı | Ad/firma, rol/il, puan ve rozetler. Karta basınca kendi herkese açık profili; kalem **Düzenle**. |
| Düzenle | Ad, firma, cep, rol, il; **Kaydet**. Doğrulanmış telefon salt okunur. |
| Demo bilgisi | Veriler bu cihazda, örnek firmalar otomatik yanıtlar açıklaması. |
| Üyelik | Ücretsiz/Premium, geçerlilik, kalan aylık iletişim hakkı, aktif ilan sınırı, kredi; **Kredi al / Premium'a geç** veya **Aboneliği yönet** (mağaza hesap sayfası). |
| Hesap | **Sicil kartı oluştur / Sicil kartım**, **Engellenen kullanıcılar**; telefon modunda doğrulanmadıysa **Telefonumu doğrula**. |
| Araçlar | **Boş dönüş eşleştirme**, **Hafriyat planlama**. |
| Yardım ve güven | **Nasıl çalışır?**, **Güvenli ticaret rehberi**, yapılandırılırsa destek e-postası; **Kullanım koşulları / Gizlilik politikası / KVKK aydınlatma metni**. |
| Uygulama | **Örnek ilanları göster**, **Satın alımları geri yükle**, demoda **Demo verilerini sıfırla**. Sıfırlama ilan/teklif/anlaşmayı temizler; profil ve satın alım korunur. |
| Oturum | Canlı telefon modunda doğrulanmış kullanıcı için **Çıkış yap**; gönderilmemiş sıra varsa kayıp uyarısı. **Hesabımı sil** ve kalıcı silme/aboneliği ayrıca iptal etme uyarısı. |
| Alt bilgi | Uygulama/sürüm, Demo/Canlı, girilmişse hizmet sağlayıcı. |

Hesap silme ve demo sıfırlama farklı işlemlerdir. Orijinal silme metni “karşı tarafın kendi kaydı olarak tutulan anlaşmalarda yalnız adınız kalır” der; metnin gerçek veritabanı saklama davranışıyla tümüyle uyumlu olduğu veya hukuken yeterli olduğu bu envanterde onaylanmaz.

## 15. Herkese açık profil, engelleme ve şikâyet

Kaynak: `screens/profile/public_profile_screen.dart`, `screens/common/report_sheet.dart`.

### Herkese açık profil

Ad/firma, rol/il, puan ortalaması/değerlendirme sayısı, tamamlanan iş, üyelik süresi, telefon/firma/Premium rozetleri; değerlendiren ad/yıldız/yorum/tarih; ilanları. Ekranda ilk **30** değerlendirme gösterilir (Supabase veri sorgusu en fazla 50). Telefon doğrudan bu profilin genel alanı değildir. Başka profilde **Şikâyet et / Engelle / Engeli kaldır**; hata ve ilk profil yoksa **Tekrar dene**. **UI:** örnek profil ve menüsü açıldı.

### Engelleme

İlan ayrıntısından veya profilden onayla engelleme. Pazarda o kullanıcının ilanları gizlenir, teklif alışverişi engellenir. **Profil → Engellenen kullanıcılar → Engeli kaldır**. Boş liste açıklaması. **UI/KURAL:** örnek kullanıcı engellenip listeden kaldırıldı; görünürlük testleri var. İncelemede orijinal engeli kaldır callback'inde debug hatası da görüldü; bölüm 20'de kayıtlı.

### Şikâyet

İlan, profil veya anlaşma hedeflenir; altı neden: Sahte/yanıltıcı ilan, Dolandırıcılık şüphesi, Ödeme/iş yapılmadı, Hakaret/uygunsuz içerik, Spam/tekrar, Diğer. İsteğe bağlı açıklama; sahibi bilinen hedefte **Bu kullanıcıyı da engelle**; **Şikâyeti gönder**. İsim karşı tarafa açıklanmayacağı metni, destek e-postası varsa ek bilgi. Şikâyet metni uygunsuz ifadeyi alıntılayabileceğinden normal ilan içerik filtresinden ayrı tutulur. Çoklu benzersiz şikâyette otomatik gizleme kuralı/SQL vardır; gerçek moderatör paneli bulunmaz. **KAYNAK/KURAL**.

## 16. Premium, kredi, öne çıkarma ve mağaza

Kaynak: `screens/billing/*`, `services/billing_service.dart`, `config.dart`. **UI:** Premium ve Kredi sayfaları açıldı; paketler görüntülendi. **KURAL:** demo Premium/hak tüketimi. **DIŞ:** gerçek satın alma/geri yükleme/iptal/iade yapılmadı.

- Premium: sınırsız iletişim/teklif ve ilan, Premium rozeti, hafriyat planlama.
- **Yıllık / Aylık** plan kartları, mağaza fiyatı varsa fiyat ve yıllık avantaj hesabı; **Yıllık Premium'a geç / Aylık Premium'a geç**; işlem sürerken pasif düğme.
- **Satın alımları geri yükle**, abonelik açıklamaları, yasal bağlantılar.
- Mağazaya erişilemediğinde tahmini fiyat uyarısı. Kaynaktaki yedek fiyatlar: aylık ₺299,99; yıllık ₺2.499,99; kredi 5/15/40 için ₺99,99/₺249,99/₺549,99. Bunlar gerçek yayındaki fiyat taahhüdü değildir.
- Ürün kimlikleri: `santiye_premium_aylik`, `santiye_premium_yillik`, `santiye_kredi_5`, `santiye_kredi_15`, `santiye_kredi_40`.
- Kredi ekranı: bakiye, kullanım yerleri, 5/15/40 paket, varsa kredi başı fiyat ve satın alma düğmeleri.
- İlan **Öne çıkar** penceresi: **24 saat = 1 kredi**, **7 gün = 5 kredi**; aktif sürenin üzerine uzatma, mevcut bitiş, bakiye, **Kredi al**. Yetersiz kredide kredi ekranına yönlendirir.
- Ücretsiz üyelikte **ayda 5 yeni ilan iletişim hakkı** ve **aynı anda 5 aktif ilan**. Sınırda **Premium'u incele / Tamam** uyarısı.
- Satın alma servisinde mağaza ürün sorgusu, bekleyen satın alımları cihazda saklama, geçici doğrulama hatasını tekrar deneme, geri yükleme ve hesap eşleşmesi kontrolü bulunur. Kaynakta bulunması gerçek mağaza hesabı ve sunucu doğrulamasının hazır olduğu anlamına gelmez.
- Demoda yerel satın alma simülasyonu mümkündür; ilk sürümün canlı olmayan bu davranışı .NET Production'a doğrulamasız ücretli hak verme şeklinde taşınmamalıdır.

## 17. Bildirimler

Kaynak: `screens/notifications/notifications_screen.dart`, `state/app_state.dart`.

- Bildirim zili ve rozet; liste/boş ekran, başlık, metin, zaman, türün rengi/simgesi, okunmamış vurgusu.
- Yeni teklif, kabul/ret, anlaşma, puan ve moderasyon bildirimleri.
- **Tümünü okundu say**; sayfadan çıkınca da okundu işaretleme; aşağı çekerek yenileme.
- Bildirime basınca ilgili anlaşma, ilan veya İşlerim/Gelen-Giden açılır.
- Orijinal canlı bağlantı Supabase olaylarını uygulama açıkken dinler; demoda yerel olaylar vardır. **Kapalı uygulamaya işletim sistemi push bildirimi yoktur.**
- Demodaki yerel bildirim listesi en fazla 200 kayıt tutar. Bu, canlı Supabase bildirim tablosunda temizleme/saklama işi kurulduğu anlamına gelmez.
- **UI:** boş sayfa açıldı; olay/iş akışı testleri **KURAL**. Gerçek arka plan push'u orijinal özellik olarak işaretlenmez.

## 18. Rehber, ortak seçimler ve doğrulama

- **Nasıl çalışır? / Güvenli ticaret** sekmeleri: ilan, iletişim kotası, anlaşma, doğrudan ödeme, puan; profil/belge kontrolü, peşin ödeme uyarısı, evrak ve şikâyet anlatımı. **UI:** iki sekme kullanıldı.
- **İl seçici:** aranabilir Türkiye il listesi, filtrede Tüm Türkiye, seçimden vazgeçme. Şehirler yerleşik merkez koordinatlarına dayanır.
- **Tarih seçici:** yük/talep için bugün–bir yıl, anlaşmada geçmiş tarih seçme izni.
- **Ortak form:** gerekli alan, uzunluk, sayı/tam sayı/pozitiflik, Türkçe virgüllü sayı, telefon, il, tarih, anlaşma kodu, virgüllü belgeler; otomatik yeniden doğrulama ve ilk hataya kaydırma.
- İlan/isim/not/yorumda uygunsuz kelime filtresi ve görünmez karakter/boşluk temizliği; bu kapsamlı insan moderasyonu değildir.
- Başlıca metin sınırları: ad 80; firma 120; ilan başlığı/yük cinsi 120; açıklama/hakkımda 500; adres 300; anlaşma başlığı 160, detay 1500; puan yorumu 300; belgeler en fazla 20 × 60 karakter.
- Hata pencereleri: bağlantı/sunucu için tekrar dene; yetki/kota/engelli/kendi ilanı/kapalı kayıt gibi kullanıcı açıklamaları. Kayıt işlemlerinde bekleme göstergesi ve tekrar basmayı sınırlama.
- Tema açık/koyu sistem temasını izler; uygulama içi ayrı tema seçme ekranı yoktur.

## 19. Çevrimdışı çalışma ve demo simülasyonu

Kaynak: `state/app_state.dart`, `services/sync_queue.dart`, `local_store.dart`, `local_backend.dart`. **KURAL:** orijinal offline ve kuyruk testleri çalıştırıldı; gerçek mobil ağ kesintisi/canlı Supabase oturumu denenmedi.

### Cihaz demosu

Profil, kendi ilanları, hak/kredi, teklifler, anlaşmalar, puan, engel/şikâyet ve bildirimler cihaz yerel deposunda tutulur. Diğer telefonla ortak canlı veri oluşmaz. Örnek firmaların otomatik teklif/kabul/teslim davranışları zamanlayıcılarla simüle edilir; bunlar gerçek kullanıcı değildir. UI inceleme testinde deterministik kayıtlar için otomatik karşı taraf zamanlayıcıları kapatıldı; kaynak uygulama değiştirilmedi. Otomatik yanıt davranışı ayrıca koddan kayıt altındadır.

### Canlı bağlantı için hazırlanmış çevrimdışı kuyruk

- Son veriler cihaz önbelleğinden gösterilir; yeniden açılınca sıra korunur.
- İlan oluştur/düzenle/kapat/sil; önceden iletişim hakkı açılmış teklifi gönder/güncelle/yanıtla/geri çek; anlaşma durum/ödeme/not/sorun işlemleri; puan, şikâyet, engel, profil ve okundu değişiklikleri sıraya alınabilir.
- Bazı ekranlar işlem sonucunu önce cihazda gösterir; “bağlantı gelince gönderilecek” bilgisi ve ana sayfada adet görünür.
- İşlem kimliğiyle tekrar gönderimde çift kaydı önleme; aynı kayda ait birleştirilebilir yazıların son halini koruma; anlaşma adımlarını sırayla ayrı tutma.
- Geçici hata/oturum/hız sınırında bekleyip tekrar deneme; kalıcı reddi sıradan kaldırma ve kullanıcıyı bilgilendirip sunucu durumuna dönme.
- **Bağlantı isteyenler:** yeni iletişim hakkı/kredi harcama, öne çıkarma, yeni anlaşma kodu üretme/katılma, satın alma doğrulama. Bunların çevrimdışı kesin başarılı gösterilmesi vaat edilmez.
- Çıkışta gönderilmemiş işlemler için uyarı; başka hesabın sırası gönderilmez.

## 20. İlk sürümün sınırları ve karıştırılmaması gerekenler

Bu bölüm eksiklerin geliştirici tarafından sonradan kaldırılmış özellik gibi değerlendirilmesini önlemek içindir.

1. **Fotoğraf yükleme/galeri yok:** profil/sicil metni vardır; yapılan iş fotoğrafları yeni taleptir.
2. **Push yok:** uygulama içi bildirim, kapalı uygulamaya push ile aynı değildir.
3. **SMS varsayılan değil:** anonim profilde yazılan numara, telefon doğrulandı rozeti garantilemez. Sabit kod yalnız eski demo dalındadır.
4. **Gerçek tahsilat yok:** anlaşmadaki POS/havale/nakit alanları ödeme takibidir. Premium/kredi mağaza akışı ayrı bir sistemdir.
5. **Harita canlı rota/GPS değil:** varsayılan şehir koordinatları, yaklaşık mesafe ve karo harita; trafik/rota motoru yok.
6. **Supabase kodu var, hazır canlı hizmet kanıtı yok:** adres/anahtar yokken demo kullanılır. Mevcut arşivde ayrı .NET backend yoktur.
7. **Örnek ilanlar başta kapalı:** Profil'den açılınca örnek pazar görünür. Demodaki firmalar gerçek değildir.
8. **Sınırlı listeleme:** Supabase sorgusu genel türlerde 300, malzemede 400 kayıt; aramada grup başına 20, profilde ekranda 30 yorum. Sayfalama/sonsuz kaydırma yoktur.
9. **Tek taraflı anlaşma kararları:** eski kurallarda açık anlaşmayı tek taraf iptal edebilir, diğer tarafın sorununu çözülmüş yapabilir. Sonraki güvenlik düzeltmesi özellik silme sayılmaması için ayrıca değişiklik notuna yazılmalıdır.
10. **Veri silme/puan saklama:** eski silme davranışının gizlilik/puan tutarlılığı sorunları ayrı inceleme gerektirir. Bu belgenin amacı hukuki uygunluk onayı vermek değildir.
11. **Yasal bağlantılar yapılandırılmamış:** metin düğmeleri bulunur; boş URL veya örnek şablonun bulunması müşterinin tüm KVKK/yasal işlemlerinin tamamlandığını göstermez.
12. **Firma rozeti otomatik doğrulama değil:** modelde/örneklerde rozet gösterilir; kullanıcı belge yükleyerek otomatik şirket doğrulama iş akışı yoktur.
13. **Yönetim paneli/uygulama içi sohbet yok:** arama ve WhatsApp dış uygulama açma kodları vardır.
14. **İlk kaynakta görülen UI sorunu:** Engellenen kullanıcılar ekranında engeli kaldırma state'te gerçekleşti fakat `setState` callback'inin Future döndürmesi debug hata mesajı üretti. Herkese açık profilin hata-yenileme callback'i de aynı kod kalıbını içeriyor; o hata dalı runtime'da ayrıca zorlanmadı.
15. **Dar test ekranı bulgusu:** 480 px genişlikli Flutter testinde harita kaynak notu taştı; envanter gezinmesi 1000 × 2000 mantıksal test yüzeyinde tamamlandı. Test fontu/ortamı etkili olabilir; bu, her gerçek telefonda taşma olduğunu kanıtlamaz. Native cihaz yerleşimi ayrıca denenmelidir.
16. **Kurulum paketi:** orijinal arşiv Android manifestini içeriyor fakat tam Android/iOS iskeleti yok; platform hazırlama araçları var. İlk teslimdeki platform betiği sorunları, sonradan yapılan kurulum düzeltmelerinden ayrı tutulur.

## 21. .NET geçişinde korunacak özellik kontrol listesi

Bu liste ilk sürümün kabul referansıdır. Bir kutunun burada bulunması yeni backend tarafının tamamlandığı anlamına gelmez. Sonraki entegrasyon doğrulamasında her kutuya test kanıtı ve varsa bilinçli davranış değişikliği eklenmelidir.

- [ ] F01 — İlk açılış/onay, profil oluştur/düzenle, alt menü ve rol önerileri.
- [ ] F02 — Beş ilan türü; tüm alanlar, sahiplik, düzenle/kapat/aç/sil ve sicil tek kayıt kuralı.
- [ ] F03 — Pazar kategorileri, arama/filtre/sıralama, liste/harita, stok/müsaitlik ve kart bilgileri.
- [ ] F04 — Aylık ücretsiz hak, aktif ilan kotası, Premium/kredi, iletişim açma ve özel telefon erişimi.
- [ ] F05 — Beş teklif/talep formu, tutar hesapları, güncelle, gelen/giden, kabul/ret/geri çek ve anlaşmaya dönüş.
- [ ] F06 — Elle anlaşma, kodla katıl, tek kişilik kayıt, taraf rolleri ve durum adımları.
- [ ] F07 — Ödeme planı ve ödedim/tahsil ettim, not, sorun, iptal, özet/işlem geçmişi.
- [ ] F08 — Tamamlanan anlaşmada tek puan, herkese açık profil/yorum/iş sayıları ve rozetler.
- [ ] F09 — Şikâyet/engelleme/engeli kaldırma, içerik doğrulama, hesap silme.
- [ ] F10 — Bildirim listesi, yönlendirme ve okundu durumu; yeni push gereksinimi ayrı izlenir.
- [ ] F11 — Boş dönüş eşleştirme ve Premium hafriyat sahaları/optimizasyon/özetler.
- [ ] F12 — Offline önbellek/sıra/yeniden deneme/çift işlem koruması ve yeniden oturum.
- [ ] F13 — Mağaza ürünleri, gerçek makbuz doğrulama, bekleyen alışveriş/geri yükleme; yeni iade/iptal kontrolü ayrı doğrulanır.
- [ ] F14 — Rehber, yasal/destek bağlantıları, dış arama/WhatsApp/harita geçişleri.

## 22. Çalıştırma kaydı ve tekrar inceleme

İnceleme aracı: `tools/customer_demo_audit_test.dart`. Araç yalnız **orijinal kopyanın ayrı test çalışma dizinine** kopyalanır; güncel mobil uygulamanın yeni backend ekranlarıyla karıştırılmamalıdır. Orijinal `lib/` ve `pubspec.yaml` değiştirilmez. Arşivde kilit dosyası yoktur; bağımlılıklar Flutter 3.38.3 / Dart 3.10.1 ortamında çözümlendi.

- Orijinal test takımı: **154 başarılı, 2 başarısız**. İki eski widget testi, ekrandaki Başla düğmesine kaydırmadan dokunmaya çalışması nedeniyle başarısız; ilk açılış yeni inceleme aracında ekrana getirip dokunarak ayrıca kontrol edildi. Bu yüzden orijinal takım “tamamı geçti” diye raporlanmaz.
- İlave UI incelemesindeki **36 senaryonun tamamı geçti**. Çalıştırılan senaryolar [customer-demo-ui-run.txt](baseline/customer-demo-ui-run.txt) ve [customer-demo-ui-evidence.json](baseline/customer-demo-ui-evidence.json) dosyalarındadır. Çıktıdaki “Geri bildirim gösterilemedi” satırları bazı sayfaların tek başına test iskeletine bağlanmasından kaynaklanır; ilgili kayıt durumları ayrıca assert edilir.
- UI kayıtları (55 ekran/adım kaydı), ekranda bulunan metinler ile gerçekten çalıştırılan adımların açıklamasını içerir. Bir düğmenin yalnız etiketi kayıtta bulunuyorsa gerçek dış hizmet sonucu doğrulanmış sayılmaz.
- Orijinal iş mantığı, eşleştirme, optimizasyon, form doğrulama ve çevrimdışı testler arşivdeki `test/` altındadır. Test dosyalarının varlığı tek başına canlı hizmetin çalıştığına kanıt sayılmadı.
- Native Android/iOS uygulaması, gerçek mağaza hesabı, canlı SMS, gerçek WhatsApp/arama, müşterinin IIS'i ve çok kullanıcılı Supabase hizmeti bu envanter turunda kullanılmadı.

Arşiv özeti ve kaynak manifesti ile daha sonra “ilk sürümde var mıydı?” sorusu dosya düzeyinde tekrar karşılaştırılabilir. Güncel geliştirme durumu ve bilinçli değişiklikler ayrıca `docs/MUSTERI_CALISMA_NOTLARI.md` içinde izlenir.
