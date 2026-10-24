# Yayın Rehberi

Bu rehber, uygulamayı **şirket kurmadan**, tek başınıza Google Play ve App Store'da yayınlamanız için gereken her adımı sırayla anlatır. Her bölümün sonunda bir kontrol listesi var.

> Vergi ve hukuk bölümleri genel bilgidir, danışmanlık değildir. Yayından önce bir mali müşavir ve bir avukatla kısa bir görüşme yapın. Bu rehberle hazırlıklı giderseniz görüşme kısa sürer.

---

## 0. Model neden şirketsiz çalışıyor?

| Konu | Bu uygulamada | Neden önemli |
|---|---|---|
| İş bedelleri (navlun, kira, malzeme) | Taraflar arasında **doğrudan** ödenir. Uygulama parayı görmez. | Başkası adına para toplamak, tutmak veya aktarmak lisanslı ödeme kuruluşu olmayı gerektirir (6493 sayılı Kanun). Eski sürümdeki "emanet hesabı" bu yüzden kaldırıldı. |
| Uygulamanın geliri | Yalnızca **Google Play / App Store** satın alımları (Premium, kredi). | Parayı mağaza tahsil eder, KDV ve tüketici ödeme süreçleri mağazanın sistemindedir. Size net hakediş yatar. |
| Mağaza kuralları | Fiziksel mal ve hizmet bedeli mağaza dışında, dijital özellikler mağaza içinden ödenir. | Google Play, fiziksel mal ve hizmet ödemelerinde mağaza ödeme sisteminin **kullanılmamasını** şart koşar. Dijital özelliklerde ise kullanılmasını zorunlu tutar. Apple'ın kuralı da aynıdır. Bu model iki kurala da uyar. |
| Sorumluluk | Uygulama bir ilan ve buluşma platformudur, işin tarafı değildir. | Kullanım Koşulları, ilk açılış ekranı ve her anlaşma kaydında bu açıkça yazılır. Taraflar puan, şikâyet ve engelleme ile birbirini denetler. |

---

## 1. Hesaplar

1. **Google Play Console**: Kişisel hesap açın (tek seferlik 25 USD). Kimlik doğrulaması istenir.
   - 13 Kasım 2023'ten sonra açılan **kişisel** hesaplarda, uygulamayı herkese açmadan önce **en az 12 test kullanıcısıyla 14 gün kesintisiz kapalı test** yapmak zorunludur. Bu süreyi takviminize ekleyin: Test kullanıcılarınızı (sürücüler, müteahhit tanıdıklar, aileniz) şimdiden toplayın.
2. **Apple Developer Program**: Bireysel üyelik (yıllık 99 USD). App Store Connect'te **Paid Apps Agreement**, banka ve vergi formlarını (W-8BEN) doldurun. Bunlar olmadan uygulama içi satış açılmaz.
3. **Supabase**: Ücretsiz plan başlangıç için yeterlidir. Ücretsiz projeler bir hafta kullanılmazsa uykuya geçer. Gerçek kullanıcı gelince Pro plana geçin.
4. **Harita sağlayıcısı** (ör. MapTiler): Ücretsiz katmanla başlayın (bkz. 6. bölüm).

---

## 2. Sunucu kurulumu (Supabase)

### 2.1 Proje ve veritabanı
1. [supabase.com](https://supabase.com) → **New project**. Bölge olarak **Frankfurt (eu-central-1)** seçin. Türkiye'ye en yakın bölge budur.
2. **SQL Editor → New query**: `supabase/schema.sql` dosyasının **tamamını** yapıştırıp **Run** deyin. Dosya tekrar çalıştırılabilir. Yeni sürümde güncellemek için yine tamamını çalıştırmanız yeterlidir.
3. **Table Editor → app_settings**: Ücretsiz hak sayısı, ilan sınırı, öne çıkarma bedeli, şikâyet eşiği ve duyuru buradan değişir. Uygulamayı güncellemeniz gerekmez.
   v2.1 ile gelen ayarlar: `daily_deal_limit` (günlük elle anlaşma kaydı), `daily_report_limit` (günlük şikâyet), `report_min_account_age_hours` (bundan yeni hesapların şikâyeti otomatik gizlemeye sayılmaz, varsayılan 24) ve `join_attempts_per_hour` (saatte en fazla hatalı anlaşma kodu denemesi).

> **v2'den güncelliyorsanız:** `schema.sql` dosyasını yine tamamen çalıştırın. Uygulamanın v2.1 sürümü yeni sunucu fonksiyonlarını (çevrimdışı kuyruk için `p_op_id` parametresi) kullanır; önce şemayı, sonra uygulamayı güncelleyin. Eski uygulama sürümleri yeni şemayla çalışmaya devam eder.

**Güvenlik kurallarını yükleme öncesi denemek (isteğe bağlı):** Bilgisayarınızda PostgreSQL 15/16 varsa:

```bash
createdb santiye_test
psql -v ON_ERROR_STOP=1 -d santiye_test -f supabase/tests/00_supabase_stub.sql
psql -v ON_ERROR_STOP=1 -d santiye_test -f supabase/schema.sql
psql -v ON_ERROR_STOP=1 -d santiye_test -f supabase/tests/10_rls_test.sql   # "TÜM GÜVENLİK TESTLERİ GEÇTİ"
```
Bu betikleri **asla canlı veritabanında çalıştırmayın** (test kullanıcıları ekler, tabloları temizler).

### 2.2 Giriş yöntemi
`lib/config.dart` → `authMode` iki seçenek sunar:

| | `AuthMode.anonymous` (varsayılan) | `AuthMode.phone` |
|---|---|---|
| Kullanıcı ne yapar | Profilini doldurur, hemen başlar | SMS kodu girer |
| Maliyet | Ücretsiz | SMS başına ücret (Twilio, Vonage vb.) |
| Güven | "Telefon doğrulanmadı" görünür | "Telefon doğrulandı" rozeti |
| Uygulama silinirse | Hesap kurtarılamaz | Aynı numarayla geri gelir |

- **Anonim için:** Authentication → Sign In / Providers → **Allow anonymous sign-ins** açık olmalı.
  > Auth ayarlarındaki **CAPTCHA**'yı açmayın. Uygulama bu sürümde CAPTCHA anahtarı göndermiyor, açarsanız kayıt çalışmaz. Kötüye kullanıma karşı **Rate Limits** bölümündeki anonim giriş sınırı yeterlidir.
- **Telefon için:** Authentication → Providers → **Phone**'u açın ve SMS sağlayıcısını bağlayın. Aynı sayfada **Test phone numbers** bölümüne mağaza incelemesi için bir test numarası ve sabit kod ekleyin (ör. `905550000000` → `123456`). Bu numarayı mağaza inceleme notlarına yazın. Ardından `config.dart`'ta `authMode = AuthMode.phone` yapın.

### 2.3 Bağlantı bilgileri
**Project Settings → API Keys**: Proje adresini (`https://xxxx.supabase.co`) ve **publishable** anahtarı kopyalayın. Eski projelerde bu anahtarın adı `anon` olabilir. **Secret / service_role anahtarını asla uygulamaya koymayın.**

Yayın derlemesinde değerler `tools/verify_project.sh` tarafından zorunlu kontrol edilir ve Dart derlemesine aktarılır. Anahtarları kaynak koda yazmayın; yerel terminal ortam değişkeni veya CI secret kullanın:

```bash
export SUPABASE_URL='https://xxxx.supabase.co'
export SUPABASE_KEY='sb_publishable_xxxxxxxx' # veya eski projelerde anon JWT anahtarı
export OPERATOR_NAME='Ad Soyad / İşletme'
export SUPPORT_EMAIL='destek@ornek.com'
export TERMS_URL='https://ornek.com/kullanim-kosullari'
export PRIVACY_URL='https://ornek.com/gizlilik'
export KVKK_URL='https://ornek.com/kvkk'
export ACCOUNT_DELETION_URL='https://ornek.com/hesap-silme'
export MAP_TILE_URL='https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=KISITLANMIS_ANAHTAR'
export MAP_ATTRIBUTION='© MapTiler © OpenStreetMap katkıda bulunanlar'
bash tools/verify_project.sh android
```

`verify_project.sh` önce `flutter pub get`, analiz ve testleri çalıştırır. Yayın paketi oluştururken canlı Supabase, yasal bağlantılar, destek e-postası ve ticari kullanım koşullarına uygun harita ayarları eksikse derlemeyi durdurur. İstemciye `service_role` veya `sb_secret_` anahtarı vermeyin.

### 2.4 Satın alma doğrulama fonksiyonu
Satın alımların sahte olmadığını sunucu, mağazaya sorarak doğrular. Premium ve kredi yalnızca bu adımdan sonra tanımlanır.

```bash
npm i -g supabase            # veya: brew install supabase/tap/supabase
supabase login
supabase link --project-ref xxxx          # xxxx: proje adresindeki kimlik
supabase functions deploy verify-purchase --project-ref xxxx

supabase secrets set --project-ref xxxx \
  ANDROID_PACKAGE_NAME=com.santiyeagi.santiye_agi \
  GOOGLE_SERVICE_ACCOUNT_JSON="$(cat play-servis-hesabi.json)" \
  APPLE_BUNDLE_ID=com.santiyeagi.santiyeAgi \
  APPLE_IAP_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  APPLE_IAP_KEY_ID=XXXXXXXXXX \
  APPLE_IAP_PRIVATE_KEY="$(cat SubscriptionKey_XXXXXXXXXX.p8)"
```

Anahtarların nereden alınacağı 4. ve 5. bölümlerde anlatılıyor. Yalnızca Android ile başlayacaksanız Apple anahtarlarını sonra ekleyebilirsiniz.

**Kontrol listesi**
- [ ] `schema.sql` hatasız çalıştı (güncellemede de tamamı yeniden çalıştırıldı)
- [ ] Anonim giriş (veya telefon + test numarası) açık
- [ ] `verify-purchase` yüklendi, gizli anahtarlar girildi
- [ ] Uygulama `--dart-define` ile canlı modda açıldı. İki telefonla ilan → teklif → kabul → anlaşma akışı denendi.

---

## 3. Uygulama ayarları (`lib/config.dart`)

| Alan | Ne yazılır |
|---|---|
| `OPERATOR_NAME`, `SUPPORT_EMAIL` | Yayın derlemesinde ortam değişkeni olarak adınız/işletmeniz ve destek e-postanız |
| `TERMS_URL`, `PRIVACY_URL`, `KVKK_URL`, `ACCOUNT_DELETION_URL` | `legal/` klasöründeki dört metnin yayımlandığı HTTPS adresleri (bkz. 7. bölüm) |
| `premiumMonthlyId`, `premiumYearlyId`, `creditPacks` | Mağazadaki ürün kimlikleri. Varsayılanları kullanırsanız değiştirmeyin. |
| `fallback...Price` | Mağazaya ulaşılamazsa gösterilecek fiyatlar. Mağazadaki fiyatlarla aynı yapın. |
| `MAP_TILE_URL`, `MAP_ATTRIBUTION` | Harita sağlayıcınızın HTTPS adresi ve doğru kaynak notu |
| `showSamplesByDefault` | Demo bağlantısız kullanımda varsayılan `true`, canlı Supabase bağlantısında `false`. `SHOW_SAMPLE_LISTINGS` ile değiştirilebilir; Profil tercihi korunur. |

**Paket kimlikleri:** `flutter create --org com.santiyeagi --project-name santiye_agi .` komutu Android için `com.santiyeagi.santiye_agi`, iOS için `com.santiyeagi.santiyeAgi` üretir. Farklı bir kimlik isterseniz `packageName` ve sunucudaki `ANDROID_PACKAGE_NAME` / `APPLE_BUNDLE_ID` değerlerini de aynı yapın.

**İmzalama ve derleme**
- Android: Bir yükleme anahtarı (`upload-keystore.jks`) oluşturun ve `android/key.properties.example` dosyasını `android/key.properties` olarak doldurun (komutlar dosyanın içinde). `tools/prepare_platforms` betiği Gradle dosyasını bu dosyayı okuyacak şekilde zaten ayarlar; `tools/verify_project.sh android` gerçek `key.properties` ve keystore bulunmadan yayın derlemesine başlamaz. Anahtarı ve şifresini **yedekleyin**: kaybederseniz güncelleme yükleyemezsiniz. Bu dosyalar `.gitignore`'dadır, depoya eklemeyin. Sonra tüm yayın değişkenlerini ayarlayıp `bash tools/verify_project.sh android` komutunu çalıştırın.
- iOS: Ana ekrandaki ad (`Şantiye Ağı`) ve şifreleme beyanı (`ITSAppUsesNonExemptEncryption = NO`, yalnızca standart HTTPS) hazırlama betiğiyle ayarlanır. Xcode'da `ios/Runner.xcworkspace` → Signing & Capabilities → Team seçin ve **+ Capability → In-App Purchase** ekleyin. Sonra tüm yayın değişkenlerini ayarlayıp `bash tools/verify_project.sh ios` ile derleyin ve Transporter ile yükleyin.
- Uygulama simgesi için `flutter_launcher_icons` paketini kullanabilirsiniz (1024×1024 simge yeterli).

---

## 4. Google Play

### 4.1 Ürünler
Ürünler, Play Console'a en az bir sürüm (dahili test yeterli) yüklendikten sonra tanımlanabilir.

**Para kazanma → Ürünler → Abonelikler**
| Ürün kimliği | Temel plan |
|---|---|
| `santiye_premium_aylik` | Otomatik yenilenen, 1 ay |
| `santiye_premium_yillik` | Otomatik yenilenen, 1 yıl |

İsterseniz bir **ücretsiz deneme teklifi** (ör. 7 gün) ekleyebilirsiniz. Uygulama fiyat olarak her zaman temel planı gösterir.

**Para kazanma → Ürünler → Uygulama içi ürünler**
| Ürün kimliği | Kredi |
|---|---|
| `santiye_kredi_5` | 5 |
| `santiye_kredi_15` | 15 |
| `santiye_kredi_40` | 40 |

Krediler tüketilebilir ürünlerdir. Uygulama her satın almadan sonra ürünü tüketir, böylece aynı paket tekrar alınabilir.

### 4.2 Doğrulama için servis hesabı
1. [Google Cloud Console](https://console.cloud.google.com)'da bir proje açın. **Google Play Android Developer API**'yi etkinleştirin.
2. **IAM → Service Accounts → Create**. Hesaba **Keys → Add key → JSON** ile bir anahtar oluşturup indirin. Bu, `GOOGLE_SERVICE_ACCOUNT_JSON` değeridir.
3. Play Console → **Kullanıcılar ve izinler → Yeni kullanıcı davet et**: Servis hesabının e-posta adresini girin. Uygulamanız için **Uygulama bilgilerini görüntüleme**, **Finansal verileri görüntüleme** ve **Siparişleri ve abonelikleri yönetme** izinlerini verin.
4. İzinlerin geçerli olması birkaç saat (bazen 24 saat) sürebilir. Bu sürede doğrulama `INVALID`/`SERVER` hatası verebilir.

### 4.3 Test
- **Ayarlar → Lisans testi**: Kendi Gmail adresinizi ekleyin. Test satın alımları ücretlendirilmez.
- **Kapalı test** kanalı açın, en az 12 test kullanıcısını ekleyin ve 14 gün boyunca kullanılmasını sağlayın. Ardından üretime erişim başvurusu yapın.

### 4.4 Mağaza kaydı
- **Uygulama içeriği → Gizlilik politikası**: `privacyUrl`
- **Hedef kitle**: 18 yaş ve üstü
- **İçerik derecelendirmesi**: Anketi doldurun. Kullanıcılar arası etkileşim var, kullanıcı içeriği var, konum paylaşımı yok.
- **Uygulama erişimi**: Anonim modda giriş gerekmez. Telefon modunda test numarasını ve kodunu yazın.
- **Veri güvenliği formu** (bu sürüm için):
  | Veri türü | Toplanıyor mu | Amaç | Paylaşılıyor mu |
  |---|---|---|---|
  | Ad | Evet | Uygulama işlevi, hesap yönetimi | Hayır* |
  | Telefon numarası | Evet | Uygulama işlevi | Hayır* |
  | Satın alma geçmişi | Evet | Uygulama işlevi | Hayır |
  | Kullanıcı kimlikleri | Evet | Uygulama işlevi, hesap yönetimi, dolandırıcılık önleme | Hayır |
  | Uygulama içi diğer içerik (ilan, teklif, puan) | Evet | Uygulama işlevi | Hayır* |
  | Konum (GPS) | **Hayır** | | |

  \* Bilgilerin uygulama içinde diğer kullanıcılara gösterilmesi, Google'ın tanımında "paylaşım" sayılmaz.
  Veriler aktarım sırasında şifrelenir: **Evet**. Kullanıcı veri silme isteyebilir: **Evet** (`accountDeletionUrl`).

---

## 5. App Store

1. **App Store Connect → Uygulamalar → +**: Bundle ID `com.santiyeagi.santiyeAgi` (Flutter iOS şablonunun varsayılanı; Xcode'daki gerçek Bundle ID ile `APPLE_BUNDLE_ID` birebir aynı olmalı).
2. **Uygulama İçi Satın Alma → Abonelikler**: "Premium" adında bir abonelik grubu oluşturun. İçine `santiye_premium_aylik` (1 ay) ve `santiye_premium_yillik` (1 yıl) ekleyin.
3. **Uygulama İçi Satın Alma → Tüketilebilir**: `santiye_kredi_5`, `santiye_kredi_15`, `santiye_kredi_40`.
4. **Kullanıcılar ve Erişim → Entegrasyonlar → Uygulama İçi Satın Alma**: Bir anahtar oluşturun. Issuer ID, Key ID ve indirilen `.p8` dosyası sunucudaki üç `APPLE_IAP_*` değeridir.
5. **Kullanıcılar ve Erişim → Sandbox**: Test hesabı oluşturup cihazda deneyin.
6. **İnceleme notu** (önerilen metin):
   > Uygulama inşaat ve lojistik ilanları için bir pazar yeridir. Taşıma, kiralama ve malzeme bedelleri uygulama dışında, taraflar arasında doğrudan ödenir (Kural 3.1.3(e)). Uygulama bu ödemelere aracılık etmez. Uygulama içinde satılan dijital özellikler (Premium, kredi) yalnızca App Store üzerinden satılır. Kullanıcı içeriği için içerik süzgeci, şikâyet ve engelleme özellikleri vardır (Kural 1.2). Hesap silme: Profil → Hesabımı sil.
7. **App Privacy**: 4.4'teki tabloya göre doldurun. İzleme (tracking): **Hayır**.

---

## 6. Harita

`tile.openstreetmap.org` ücretsizdir ama yoğun ticari kullanıma izin vermez. Yayında bir sağlayıcı kullanın:

Yayın derlemesinde `MAP_TILE_URL` ve `MAP_ATTRIBUTION` ortam değişkenlerini ayarlayın; `tools/verify_project.sh` bu değerleri Dart derlemesine geçirir. Harita API anahtarını sağlayıcı panelinde uygulamanızla kısıtlayın.

MapTiler panelinde anahtarı yalnızca uygulamanızın paket kimliğiyle kullanılabilecek şekilde kısıtlayın.

---

## 7. Yasal metinler

`legal/` klasöründe dört şablon var: **Kullanım Koşulları**, **Gizlilik Politikası**, **KVKK Aydınlatma Metni** ve **Hesap Silme**.

1. Köşeli parantezli alanları (`[AD SOYAD]`, `[E-POSTA]`, `[ADRES]`, sunucu bölgesi, harita/SMS sağlayıcısı) doldurun.
2. Bir avukata kontrol ettirin. Özellikle KVKK'daki **yurt dışına aktarım** bölümüne baktırın: Supabase, Google ve Apple sunucuları yurt dışındadır.
3. Ücretsiz bir yerde yayımlayın (GitHub Pages, Google Sites, Notion herkese açık sayfa). Adresleri `config.dart`'a ve mağaza kayıtlarına yazın.

**Uygulamada hazır olanlar:** İlk açılışta koşulların kabulü (aydınlatma metni ayrıca "okudum" olarak sunulur, rıza ile karıştırılmaz), ödeme ekranında abonelik bilgilendirmesi ve bağlantılar, uygulama içinden hesap silme, uygunsuz içerik süzgeci, şikâyet, otomatik gizleme ve engelleme.

---

## 8. Vergi (şirketsiz)

**Mobil uygulama geliri istisnası (GVK mükerrer 20/B)**
- Uygulama mağazaları üzerinden elde edilen kazanç, şartlar sağlanırsa şahıs olarak, şirket kurmadan elde edilebilir.
- Şartlar: Mağaza ödemelerinin **Türkiye'de bu amaçla açılmış ayrı bir banka hesabına** yatması. Banka her ödemeden **%15 gelir vergisi kesintisi** yapar. Bu kesinti nihai vergidir ve beyanname verilmez.
- **Yıllık istisna sınırı ve uygulanma koşulları:** Güncel tutarı ve bu iş modeli için uygunluğu mali müşavirinizle teyit edin. Önceki belgede bulunan 2026 tutarı bu teknik çalışmada doğrulanmamıştır; burada kesin vergi sınırı verilmez.
- Yapılacaklar: Bankaya gidip "20/B kapsamında hesap" açın. Google Play Console (Ödeme profili) ve App Store Connect (Banka bilgileri) bu hesaba yönlendirilsin. Vergi dairesi işlemleri ve istisna belgesi için mali müşavirle bir kez görüşün.
- Mağaza ayarları: Play Console'da ödeme profiline vergi bilgilerinizi girin. App Store Connect'te W-8BEN formunu doldurun. Form eksik olursa Apple ödemelerinizden ABD stopajı kesebilir.

**KDV:** Türkiye'deki kullanıcılara yapılan uygulama içi satışlarda KDV'yi mağazalar kendileri tahsil edip öder. Ekranda gördüğünüz fiyat KDV dahildir. Mali müşavirinizle teyit edin.

**Diğer yükümlülükler (danışın):**
- **ETBİS:** İnternet üzerinden aracılık hizmeti sunanların E-Ticaret Bilgi Sistemi'ne kaydı gerekebilir. Kayıt e-Devlet'ten ücretsiz yapılır.
- **KVKK / VERBİS:** Küçük ölçekli veri sorumluları çoğunlukla VERBİS kaydından muaftır. Aydınlatma ve yurt dışı aktarım yükümlülükleri ise herkes için geçerlidir.
- **5651 sayılı Kanun:** Hukuka aykırı içerik size bildirildiğinde içeriği kaldırmanız gerekir. Uygulamadaki şikâyet ve gizleme araçları bunun için var (bkz. 9. bölüm).

---

## 9. Yayından sonra yönetim

Supabase **SQL Editor**'da işe yarayan komutlar:

```sql
-- Son şikâyetler
select * from reports order by created_at desc limit 50;

-- Yanlışlıkla gizlenen bir ilanı geri açmak
update loads set hidden = false, report_count = 0 where id = '...';

-- Bir firmaya "Onaylı firma" rozeti (vergi levhası vb. gördükten sonra)
update profiles set company_verified = true where id = '...';

-- Herkese duyuru (boş bırakınca kaybolur)
update app_settings set announcement = 'Yeni: Hafriyat planlama aracı!' where id = 1;

-- Ücretsiz hakları değiştirmek
update app_settings set free_monthly_unlocks = 8, free_active_listings = 6 where id = 1;

-- En çok şikâyet edilen profiller (profil şikâyet sayısı gizlilik için herkese açık tabloda tutulmaz)
select target_id, count(*) from reports where target_type = 'profil' group by 1 order by 2 desc limit 20;

-- Bakım: eski kuyruk ve deneme kayıtlarını temizlemek (ayda bir yeterli)
delete from client_ops where created_at < now() - interval '30 days';
delete from rate_events where created_at < now() - interval '7 days';
```

Bir kullanıcının satın alması hiç tanımlanmazsa: Supabase → **Edge Functions → verify-purchase → Logs** bölümüne bakın. Hata kodları: `ACCOUNT_MISMATCH` (satın alma başka bir hesaba ait), `EXPIRED`, `INVALID`, `SERVER`.

---

## 10. Yayın öncesi son kontrol

- [ ] `flutter analyze` temiz, `flutter test` geçiyor
- [ ] `config.dart`: yasal bağlantılar, destek e-postası ve harita sağlayıcısı dolu
- [ ] Canlı modda iki telefonla: ilan ver → iletişim hakkı aç → teklif → kabul → anlaşma → ödeme işaretleri → tamamla → puan
- [ ] Gerçek kartla değil, test hesabıyla Premium ve kredi satın alındı. Uygulama silinip yeniden kurulunca **Satın alımları geri yükle** çalıştı.
- [ ] Şikâyet → 3 farklı hesaptan şikâyet edilen ilan gizlendi (test hesapları en az 24 saatlik olmalı ya da `report_min_account_age_hours` geçici olarak 0 yapılmalı)
- [ ] Çevrimdışı: uçak modunda ilan verildi ve anlaşma adımı işaretlendi; uygulama kapatılıp açıldı; internet açılınca kayıtlar bir kez gönderildi
- [ ] Hesap silme çalıştı
- [ ] Profil → **Örnek ilanlar** kapalıyken yalnızca gerçek ilanlar görünüyor (gerçek ilanlar çoğalınca `showSamplesByDefault = false`)
- [ ] Google Play: 12 test kullanıcısıyla 14 günlük kapalı test tamamlandı
- [ ] 20/B banka hesabı açıldı, mağaza ödemeleri bu hesaba yönlendirildi

---

## Kaynaklar

- Google Play ödeme politikası: https://support.google.com/googleplay/android-developer/answer/9858738
- Google Play yeni kişisel hesaplar için test şartı: https://support.google.com/googleplay/android-developer/answer/14151465
- Apple App Store İnceleme Kuralları (3.1.1, 3.1.3(e), 1.2, 5.1.1): https://developer.apple.com/app-store/review/guidelines/
- Supabase anonim giriş: https://supabase.com/docs/guides/auth/auth-anonymous
- Supabase Edge Functions gizli anahtarlar: https://supabase.com/docs/guides/functions/secrets
- 2026 yılı 20/B sınırı (332 Seri No.lu GVK Genel Tebliği): https://www.muhasebenews.com/?p=169372
