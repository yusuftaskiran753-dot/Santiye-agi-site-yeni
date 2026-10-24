# Şantiye Ağı

**Kaynak sürümü: 2.1.2+5 — 16 Ekim 2026.** Flutter mobil ve .NET 10 / PostgreSQL backend aynı depoda geliştirilir. Güncel uygulama `https://45.59.70.198` adresindeki IIS API'sine bağlanır. Canlı hesap, ilan, anlaşma, fotoğraf ve hafriyat kayıtları emülatörde kontrol edilmiştir. Android Firebase push teslimatı da gerçek VDS üzerinden emülatörde doğrulanmıştır. SMS zorunluluğu kapalıdır; gerçek SMS/mağaza hizmetleri, fiziksel Android cihaz ve iOS yayın kontrolleri kalır.

Canlı bağlantıyla çalıştırma:

```powershell
flutter run --profile -d emulator-5554 --dart-define-from-file=config/live.json
```

Güncel sonuçlar: [canlı kabul](docs/CANLI_KABUL_KONTROLU.md), [hesap bilgileri](docs/CANLI_HESAP_BILGILERI.md), [IIS güncelleme](docs/CANLI_GUNCELLEME.md). Sunucu adresi verilmeden yapılan `flutter run` önceki cihaz içi demo modunu açar.

Şantiye ve lojistik işleri için bir ilan ve buluşma uygulaması: yük, iş makinesi, malzeme ve operatör/personel ilanları. Taraflar uygulamada buluşur, teklifleşir, yaptıkları işi dijital olarak kayıt altına alır ve **ödemeyi birbirine doğrudan yapar**.

İşin bedeli taraflar arasında ödenir; uygulamada ödeme takibi tutulur. Premium abonelik ve kredi paketleri için Google Play / App Store doğrulama kodu bulunur. Gerçek ürünler, hizmet erişimleri ve işletici/yasal yayın bilgileri yayın aşamasında tamamlanmalıdır.

## Gelir modeli

| | Ücretsiz | Premium (aylık / yıllık) | Kredi paketleri (5 / 15 / 40) |
|---|---|---|---|
| İlanlara göz atma, arama, filtre | ✔ | ✔ | |
| İletişim / teklif hakkı | Ayda 5 | Sınırsız | Hak bitince 1 kredi = 1 hak |
| Aynı anda yayında ilan | 5 | Sınırsız | |
| İlanı öne çıkarma | | | 24 saat = 1 kredi, 7 gün = 5 kredi |
| Hafriyat planlama aracı | | ✔ | |
| Premium rozeti | | ✔ | |

Güncel .NET bağlantısında ücretsiz hak, ilan sınırı ve öne çıkarma bedelleri API'nin kullanım yanıtından okunur; satın alma hakkı sunucuda doğrulanır. Eski Supabase dosyaları kaynak referansı olarak korunmuştur.

## Ne yapılabiliyor?

**Ana Sayfa:** Kişiye özel selam, tek kutuda arama, dört kategori (yük, makine, malzeme, personel), yanıt bekleyen işler, kullanıcının rolüne göre tek öneri (ör. nakliyeciye "Boş dönmeyin", müteahhide "Hafriyatı planlayın") ve bölgedeki yeni ilanlar.

**İlanlar**
- **Yük:** Nereden/nereye, araç tipi, metin araması, 5 sıralama (önerilen, en yeni, yükleme tarihi, navlun, km başı). **Boş dönüş eşleştirme:** Boşaldığınız ilden evinize doğru giden yükleri uygunluk puanıyla sıralar.
- **Makine:** Liste ve harita, müsaitlik, operatörlü/operatörsüz, saatlik/günlük fiyat, en yakın/en ucuz/en yüksek puan sıralaması.
- **Malzeme:** Hazır beton, agrega, stabilize, asfalt. Ürün bazında fiyat karşılaştırma, **teslim dahil tahmini fiyat**, "en avantajlı" işareti, stok durumu.
- **Personel:** İş ilanları ve operatör sicil kartları, pozisyon ve il filtresi.

**İlan ver (+):** Beş ilan türü için sade formlar. Kendi ilanlarını düzenleme, kapatma, yeniden açma, silme, öne çıkarma.

**İletişim ve teklif:** Telefon numaraları herkese açık değildir. "İletişim hakkı" açan kullanıcı arayabilir, WhatsApp'tan hazır mesajla yazabilir ve teklif/talep gönderebilir. İlan sahibine bildirim gider.

**İşlerim**
- Gelen ve giden teklif/talepler: kabul et, reddet, geri çek, karşı tarafı ara.
- **Anlaşma kaydı:** Kabul edilen teklif otomatik olarak anlaşma kaydına dönüşür. Karşı taraf uygulamada değilse kayıt elle de açılabilir; kodla davet edilir. Akış: onay → iş tamamlandı → teslim alındı → puan. Ödeme planı satırları "ödedim" / "tahsil ettim" diye işaretlenir. Sorun bildirme, not ekleme, iptal ve tüm işlem geçmişi kayıtta durur. Özet tek dokunuşla kopyalanır veya WhatsApp'tan paylaşılır.
- **Puanlama:** Yalnızca tamamlanmış anlaşmadan sonra, her taraf bir kez. Sahte puan önlenir.

**Hafriyat planlama (Premium):** Kazı, döküm ve ocak noktalarını haritaya ekleyin. Döküm kapasitelerini aşmadan **en düşük maliyetli** dağıtım (ulaştırma problemi, tam çözüm), sefer, yakıt, gün ve döküm ücreti hesabı, dönüş yükü önerileri.

**Güvenlik:** Uygunsuz içerik süzgeci, ilan/kullanıcı/anlaşma şikâyeti (3 farklı şikâyette ilan otomatik gizlenir), engelleme, telefon doğrulama rozeti, onaylı firma rozeti, "güvenli ticaret" rehberi, hesap silme.

**Bildirimler:** Yeni teklif, kabul/ret, anlaşma işlemleri ve puanlar .NET API'den okunur. Ekran açıkken değişiklikler düzenli yoklanır. Android push için `config/live-android-push.json` kullanılır; gerçek VDS'den arka plan ve kapalı işlem teslimatı emülatörde kontrol edilmiştir. Fiziksel Android cihaz ve iOS/APNs kontrolleri kalır; [canlı Android kontrolü](docs/ANDROID_BILDIRIM_CANLI_KONTROLU_2026-10-16.md).

**Çevrimdışı çalışma (şantiyede çekim yokken):** Uygulama son verilerle internetsiz açılır. İnternet yokken yapılan ilan kaydı/düzenleme/kapatma/silme, teklif gönderme ve yanıtlama, anlaşma adımları (teslim, ödeme işaretleri, not, sorun bildirme), puan, şikâyet, engelleme, profil değişikliği ve "okundu" bilgisi kaybolmaz: cihazdaki gönderim sırasına alınır, ekranda hemen görünür ("Gönderilmeyi bekliyor" etiketi) ve bağlantı gelince sırayla otomatik gönderilir. Her işlemin kimliği olduğundan, yanıtı kaybolup yeniden gönderilen istek sunucuda bir kez uygulanır. Sunucu bir işlemi reddederse (ör. anlaşma bu arada iptal edilmiş) kullanıcıya bildirilir. Kredi harcayan veya sunucunun kod ürettiği işlemler (iletişim hakkı, öne çıkarma, anlaşma kodu, satın alma) yalnızca çevrimiçidir.

## İki çalışma modu

| | Demo modu | Canlı mod |
|---|---|---|
| Ne zaman | API veya Supabase adresi verilmezse | `API_BASE_URL` veya `config/live.json` ile |
| Veriler | Yalnızca o cihazda | .NET API / PostgreSQL; gerçek hesaplar arasında |
| Karşı taraf | Örnek firmalar teklif/talebinize birkaç saniyede yanıt verir | Gerçek kullanıcılar |
| Satın alma | Geliştirme sürümünde mağaza olmadan denenebilir | Mağaza + sunucu doğrulaması |

Demo modunda telefon doğrulama kodu her zaman `123456`'dır.

## Çalıştırma

Gerekenler: **Flutter 3.35 veya üstü** (`flutter --version`).

```bash
cd santiye_agi

# 1) Android/iOS platform klasörlerini üretin (lib/ ve mevcut dosyalar korunur;
#    release imzası ve iOS uygulama adı da ayarlanır). Windows: tools\prepare_platforms.bat
bash tools/prepare_platforms.sh

# 2) Paketler
flutter pub get

# 3) Kontrol ve testler
flutter analyze
flutter test

# 4) Demo modunda çalıştırma
flutter run

# 5) Güncel IIS / PostgreSQL sunucusuna bağlı çalıştırma
flutter run --profile --dart-define-from-file=config/live.json
```

> **Güncel kontrol:** 72 backend testi, 181 mobil testi başarılı; Flutter analizinde sorun yok. Otomatik entegrasyon testleri yalnız yerel test veritabanlarında çalışır. Gerçek VDS'deki elle yürütülen kabul ve kalan hizmet ayarları `docs/CANLI_KABUL_KONTROLU.md` içinde açıklanır.

## Klasörler

```
lib/
  config.dart              Yayın öncesi doldurulacak tüm ayarlar (ürün kimlikleri, yasal bağlantılar…)
  main.dart                Açılış, tema, sağlayıcılar
  models/                  Veri modelleri (ilan türleri, teklif, anlaşma, puan, kullanım hakları)
  services/
    backend.dart           Veri katmanı arayüzü
    local_backend.dart     Demo modu (cihazda, örnek firmalarla)
    dotnet_backend.dart    Güncel canlı .NET API bağlantısı
    supabase_backend.dart  Önceki Supabase bağlantısı
    billing_service.dart   Google Play / App Store satın alma
  state/app_state.dart     Ekranların kullandığı tek durum sınıfı
  logic/                   Boş dönüş eşleştirme, hafriyat optimizasyonu
  screens/                 Ekranlar
  widgets/                 Ortak bileşenler, harita, il seçici
backend/                   .NET 10 / PostgreSQL API, migration, test ve IIS teslim betikleri
supabase/                  Önceki altyapı kaynak referansı
  schema.sql               Veritabanı, güvenlik kuralları ve sunucu fonksiyonları
  functions/verify-purchase/index.ts   Mağaza satın alma doğrulama
legal/                     Kullanım koşulları, gizlilik, KVKK, hesap silme şablonları
test/                      Mantık, durum (uçtan uca iş akışları), çevrimdışı kuyruk, doğrulama ve arayüz testleri
supabase/tests/            Güvenlik (RLS / yetki) testleri: yerel PostgreSQL'de çalışır
tools/                     Platform hazırlama (prepare_platforms), platform ayarları (patch_platforms.dart), doğrulama (verify_project.sh)
```

### Testler

| Dosya | Ne denetler? |
|---|---|
| `test/haul_optimizer_test.dart` | Hafriyat dağıtımı: boş/eksik girdi, NaN/sonsuz değerler, kapasite sınırları, kaba kuvvetle doğrulanmış en düşük maliyet (300 rastgele örnek), dönüş yükü sınırları |
| `test/load_matcher_test.dart` | Boş dönüş eşleştirme: bilinmeyen il, büyük/küçük harf, sınır mesafesi, puan aralığı, kararlı sıralama |
| `test/sync_queue_test.dart` | Gönderim sırası: kalıcılık, sıra, geçici/kalıcı hata ayrımı, birleştirme, kullanıcıya özel kayıt |
| `test/offline_sync_test.dart` | Bağlantısı kesilen sahte sunucuyla uçtan uca: çift kayıt olmaması, yeniden açılışta korunma, sunucunun reddi |
| `test/validators_test.dart` | Form doğrulamaları, Türkçe sayı girişi, sunucu hata kodlarının eşlenmesi, anlaşma kuralları |
| `supabase/tests/10_rls_test.sql` | Oturumsuz erişim, başkasının verisi, iç fonksiyonlar, kota/kredi, tekrar gönderim, kod tahmini, şikâyet kötüye kullanımı |


## Belgeler

- [backend/README.md](backend/README.md): Yeni .NET 10 / PostgreSQL API, yerel testler ve IIS yayını.
- [docs/MUSTERI_CALISMA_NOTLARI.md](docs/MUSTERI_CALISMA_NOTLARI.md): Müşteriye yönelik yapılan işlerin güncel kaydı.
- [docs/GIT_CALISMA_DUZENI.md](docs/GIT_CALISMA_DUZENI.md): Mobil ve backend'in birlikte GitHub üzerinden sürümlenmesi.

Profil iş fotoğrafları ve kullanıcıya özel hafriyat sahaları aynı .NET API üzerinden kaydedilir. Kaynak demo envanteri `docs/MOBIL_ILK_SURUM_OZELLIK_ENVANTERI.md`, güncel canlı durum `docs/CANLI_KABUL_KONTROLU.md` dosyasındadır. Android profile test APK'sı gerçek sunucuya bağlıdır; mağaza imzalı yayın derlemesi ve dış hizmet kabul kontrolleri ayrı aşamadır.

- [YAYIN_REHBERI.md](YAYIN_REHBERI.md): Sunucu kurulumu, mağaza ürünleri, yayın adımları, vergi ve yasal notlar
- [DEGISIKLIKLER.md](DEGISIKLIKLER.md): Önceki sürümlere göre değişenler ve düzeltilen hatalar (v2.1: çevrimdışı kuyruk, doğrulama, güvenlik)
- [GUNCELLEME_NOTU.md](GUNCELLEME_NOTU.md): Bu teslimatta güncellenen araçlar ve doğrulama sınırları

## Platform iskeleti ve doğrulama araçları

Bu çalışma ağacında Android ve iOS platform iskeletleri bulunmaktadır. Manifest dışında iskelet içermeyen kaynak arşivlerde de hazırlama betiği ilk kurulumu otomatik yapar. Proje kökünde `bash tools/prepare_platforms.sh` (macOS/Linux) veya `tools\prepare_platforms.bat` (Windows) çalıştırın. Bu adım Flutter SDK gerektirir; `android/` ve `ios/` klasörlerini üretir, özel `AndroidManifest.xml` dosyasını yerine koyar ve `tools/patch_platforms.dart` ile Android release imzasını (`android/key.properties` varsa) ve iOS uygulama adını ayarlar.

Tam platform iskeleti varsa korunur; yalnız eksik platform üretilir. Bilinmeyen kısmi/özel platform dosyaları otomatik değiştirilmez. Mevcut platformu yeniden üretmek için `--force` ekleyin. `android/key.properties` ve `.jks`/`.keystore` imza dosyaları her durumda korunur. Yükleme anahtarı için şablon: `android/key.properties.example` (kaynağı `tools/android/`).

Sonra `bash tools/verify_project.sh` ile bağımlılıkları, statik analizi ve testleri çalıştırın. Android AAB için `bash tools/verify_project.sh android`; iOS IPA için macOS/Xcode üzerinde `bash tools/verify_project.sh ios` kullanın. Statik inceleme ve çalıştırılabilir kontrollerin mevcut durumu `QA_RAPORU.md` dosyasındadır.
