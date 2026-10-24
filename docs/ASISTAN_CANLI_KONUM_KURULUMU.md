# Asistan ve canlı konum — 20 Ekim 2026

Müşterinin yeni tasarım arşivindeki iki özellik, mevcut Flutter / .NET 10 / PostgreSQL sistemine eklendi. Supabase'e dönüş yapılmadı. İlan, teklif, anlaşma, telefon doğrulaması ve makbuz doğrulama kuralları korunur.

## Kullanıcının göreceği değişiklikler

- Ana sayfada **Anlatın, uygun ilanları bulalım** ve ilan verme menüsünde **Anlatın, taslak hazırlayalım** seçenekleri var. Doğal dildeki cümleden güzergâh, il, araç/makine/malzeme/personel, ton, fiyat ve gün çıkarılır. Mevcut erişilebilir ilanlar süzülür; tam eşleşme yoksa yakın sonuçlar açıkça belirtilir.
- Yük ilanı taslağı formda açılır. Kullanıcı kontrol edip **İlanı yayınla** seçmedikçe kayıt oluşmaz. Diğer kategoriler kendi mevcut formlarında açılır; otomatik taslak doldurma yük formundadır.
- Gemini hesabı henüz hazır değil. Uygulama şimdilik cihazda çalışan basit Türkçe yorumlayıcıyı kullanır. Bu mod her cümleyi anlayamaz. Sunucuya anahtar eklendikten sonra, ayrıca kullanıcı onay kutusunu seçerse metin Gemini'ye gider. Onaysız kullanım ve servis hatası yerel moda döner.
- Anlaşma detayından **Canlı konum** açılır. Yalnız iki tarafı da uygulamada olan aktif/teslim edilmiş/itirazlı anlaşmalarda kullanılabilir. Paylaşımı kullanıcı başlatır: **1 saat**, **8 saat** veya henüz teslim edilmemiş işte **teslime kadar, en fazla 24 saat**.
- Konum yalnız anlaşmanın diğer tarafına gösterilir. Paylaşım sürerken alt şerit ve Android ön plan bildirimi/iOS konum göstergesi bulunur. Yaklaşık konum izniyle de çalışır. Haritadaki süre/mesafe, il merkezi ve yaklaşık yol hesabıdır; gerçek navigasyon, trafik veya teslim saati garantisi değildir.
- Durdurma, süre sonu, engelleme, tamamlanma/iptal, hesap silme ve sunucuda başarılı çıkış konum erişimini keser. “Teslime kadar” paylaşım teslim bildirimiyle biter. Yeni ölçüm süreyi uzatmaz. Eski/geciken başlangıç istekleri sunucu paylaşım nesliyle geçersizleştirilir.
- İnternet yokken yeni GPS gönderimi durabilir; son ölçüm karşı tarafta eski olarak işaretlenir. Durdurma isteği çevrimdışıysa cihaz gönderimi hemen keser, sunucu silme isteği bağlantı gelince denenir; sunucudaki süre sınırı her durumda işler. İşletim sistemi uygulamayı tamamen kapatırsa kesintisiz paylaşım garanti edilmez.

## Mevcut VDS'ye güncelleme

Bu paket yeni mobil **2.1.2 (10)** sürümüyle kullanılır. Mevcut kullanıcıları silmez; iki ek tablo ve paylaşım nesli alanını migration ile kurar. Canlı sunucuda henüz çalıştırılmış değildir.

1. Birlikte üretilen `output/backend/SantiyeAgi-Backend-IIS.zip` ve `output/backend/guncelle.ps1` dosyalarını sunucuda `C:\ProgramData\santiye` klasörüne kopyalayın. Önceki ZIP'i güncel olanla değiştirin.
2. Yönetici PowerShell'de kısa komut:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\guncelle.ps1
```

Kurucu paket SHA-256 değerini kontrol eder; site yazmalarını durdurur, mevcut şifreli yerel yedek aracını gerçek geri yükleme kontrolüyle çalıştırır, site/ayar kopyası alır, migration uygular ve HTTPS hazır olma kontrolü yapar. Hata olursa bakım dosyasını bırakır ve yedek yolunu gösterir. Hata görülürse bakım dosyasını rastgele silmeyin. Yeni kod kopyalanmış ve migration uygulanmış olabilir; durum incelenmeden eski veritabanı geri yüklenmez. Önceki yedekleme düzeni (yerel, 14 gün) ve harici `settings.json` korunur.

Sunucunun günlük yedek kurulumunun `C:\ProgramData\santiye\backup` altında bulunması ve `santiye` IIS havuzu beklenir. Bu, mevcut VDS'ye özel güncelleyicidir; yeni sunucu kurucusu değildir.

## Gemini hesabı hazır olduğunda

Anahtar uygulamaya, GitHub'a veya sohbet mesajına eklenmez. Müşterinin kendi Google projesinden alınan anahtar sunucudaki mevcut dış ayarlara yazılır. Güncel paketteki şu araç yönetici PowerShell'de çalıştırılır:

```powershell
& C:\inetpub\wwwroot\santiye\deploy\set-ai-assistant.ps1
```

Anahtar gizli girişte istenir. Araç diğer ayarları korur ve IIS havuzunu yeniden başlatır. Başlangıç sınırları kullanıcı başına günlük 30, geçerli Premium için 200; tüm sunucu için günlük 200 istektir, eşzamanlı en fazla 2 çağrı yapılır. Bunlar para cinsinden kesin harcama sınırı değildir; Google hesabındaki ücretlendirme/kota ayrıca kontrol edilir. Başarısız sağlayıcı çağrıları da günlük deneme bütçesine sayılır. Gerçek Gemini yanıtı uygulamada onay kutusuyla ayrıca denenmelidir. Kapama: aynı araç `-Mode Off`.

Model: `gemini-3.5-flash-lite`; REST sözleşmesi ve model [Google model belgeleri](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite) / [generateContent](https://ai.google.dev/api/generate-content) üzerinden doğrulandı. Anahtar yokken dış sağlayıcı çağrılmaz.

## Gizlilik sayfası ve mağaza beyanı

Müşterinin yayımladığı gizlilik/hesap silme sayfasına gerçek davranışa göre şu bilgiler eklenmeli; sayfa bu çalışmada yayımlanmadı:

> Kullanıcı isteğe bağlı, süreli canlı konum paylaşımını başlatabilir. Son konum, ölçüm zamanı, doğruluk ve varsa yön/hız bilgileri hizmetin sunulması için sunucumuza gönderilir ve yalnız ilgili anlaşmanın diğer tarafına gösterilir. Geçmiş rota kaydı oluşturulmaz. Paylaşım sonlandığında erişim kesilir ve aktif veritabanındaki koordinatlar temizlenir; koordinatsız işlem metadatası en fazla 7 gün tutulur. Mevcut şifreli yerel yedeklerde kalan kopyalar 14 günlük yedek saklama süresinin sonunda silinir. Çevrimdışı durdurma isteği bağlantı gelince işlenir; sunucu süre sınırını kendisi uygular.
>
> Gemini özelliği etkinleştirildiğinde kullanıcı ayrıca onay verirse yazdığı en fazla 400 karakterlik metin ve seçili il, isteği yorumlamak için Google Gemini hizmetine gönderilir. Kimlik/telefon ve başka kişisel bilgiler yazılmamalıdır. Uygulamanın kendi veritabanına veya günlüklerine istek metni/model cevabı kaydedilmez; kısa ömürlü kullanım kotası metadatası tutulur. Gemini kullanımı isteğe bağlıdır; onaysız kullanımda yerel yorumlayıcı çalışır. Sağlayıcının kendi veri işleme koşulları ayrıca geçerlidir.

Harita sağlayıcısına harita döşemesi istekleri gider; sağlayıcı bu istekler ve IP gibi teknik verilerden görüntülenen alanı çıkarabilir. “Haritalarda aç” seçilirse koordinatlar kullanıcının açtığı harita hizmetine aktarılır. Bu teknik harita akışı da gizlilik metninde kullanılan sağlayıcıyla birlikte açıklanmalıdır.

Play Veri Güvenliği/App Store gizlilik beyanı, isteğe bağlı hassas/yaklaşık konumun toplanması ve kullanıcı isteğiyle anlaşma tarafına aktarılması dikkate alınarak güncellenmeli. AI etkinleştirilirse yazılı girdinin sağlayıcıya aktarımı ve kullanım amacı da değerlendirilmelidir. Reklam/takip amacı eklenmedi. Play Console'da konum türünde ön plan hizmeti beyanı ve istenirse paylaşımı gösteren inceleme videosu gerekir. Android `ACCESS_BACKGROUND_LOCATION` istemez; paylaşım uygulama açıkken başlatılan konum ön plan hizmetidir. iOS “kullanılırken” izni ve konum arka plan modu hazırlandı; App Store incelemesi kullanım gerekçesini ayrıca değerlendirir.

## Kontrol sınırları

Yerel Flutter testleri ve analiz; gerçek yerel PostgreSQL üzerinde izole `santiye_test_*` veritabanlarıyla API testleri; imzalı Android AAB derlemesi kontrol edilir. Sahte Gemini HTTP ve GPS kaynakları kullanılır. Canlı Gemini, canlı IIS güncellemesi, fiziksel iki Android cihazda arka plan/GPS/pil davranışı, gerçek iPhone, iOS derleme/imzalama ve mağaza incelemesi bu kontrollerin yerine geçmez. Önceki SMS, APNs, abonelik ve hesap kurtarma işleri ayrıca sürer.

Bu sürüm için 233 Flutter testi başarılı; yalnız ayrı çalışan yerel API isteyen 2 Flutter testi standart turda atlandı. API'nin 131 testi gerçek izole yerel PostgreSQL ile başarılı. Firebase iOS SDK'sının gerektirdiği en düşük iOS 15 hedefi ve CocoaPods konum izin ayarı eklendi; Windows ortamında iOS derlendiği iddia edilmez.

## Doğrulanan teslim dosyaları

- Android: `output/mobile/SantiyeAgi-2.1.2-10-Asistan-Konum-Test.aab` — `com.santiyeagi.app`, sürüm kodu 10, 48.312.780 bayt. SHA-256: `A373AC66EA568C7EFD7E52D313E3A06E85D9577B9E59838994AFFD187EFFB89F`. İmza, bundletool ve birleştirilmiş manifest kontrolü geçti; konum türünde ön plan hizmeti mevcut. Reklam kimliği veya sürekli arka plan konum izni eklenmedi.
- Sunucu: `output/backend/SantiyeAgi-Backend-IIS.zip`. SHA-256: `A647B5109F14784379FC943EDB649542BB49A7E548B8603865AE439318CE3E9E`. Aynı paketi bekleyen `output/backend/guncelle.ps1` üretildi; betiğin içine bu değer yazılmıştır. Migration dosyasında paylaşım nesli alanı kontrol edildi. Kaynak derleme commit'i `4f184ec`; sonraki belge ekleri uygulama kodunu değiştirmez.
