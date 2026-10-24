# Konum ve asistan için mağaza beyanı — 20 Ekim 2026

Bu belge mevcut Android 2.1.2 (10) özelliklerini ve tek ana kart/güncel onay metni taşıyan sonraki derlemeyi kapsar. Yeni veri türleri eski CSV'deki yaklaşık/tam konum ve kullanıcı içeriği türlerinin kapsamını genişletir; önceki beyanın tamamı silinmez. Gerçek mağaza işlemlerinin durumu aşağıdaki işlem kaydında ayrıca belirtilir.

## Google Play — Veri güvenliği

| Tür | Toplama | İsteğe bağlı mı? | Kısa süreli işleme | Amaç |
|---|---|---|---|---|
| Yaklaşık konum | Evet: kullanıcı ili, harita alanı ve yaklaşık konum izniyle paylaşım | Evet | Hayır; sunucu son ölçümü saklar | Uygulama işlevselliği |
| Tam konum | Evet: elle seçilen noktalar ve izin verilirse süreli canlı GPS | Evet | Hayır; son ölçüm ve yedek kopyası bulunabilir | Uygulama işlevselliği |
| Kullanıcı tarafından oluşturulan diğer içerikler | Evet: ilan/notların yanında onaylı asistan metni | Evet | Hayır; kategoride ilan/notlar kalıcıdır, Google'ın saklaması ayrıca geçerlidir | Uygulama işlevselliği |
| Uygulama işlemleri/etkileşimleri | Evet: anlaşma/paylaşım işlemleri, hesapla bağlantılı AI kullanım kotası | Mevcut beyan korunur | Hayır | Uygulama işlevselliği; ilgili güvenlik kayıtlarında güvenlik |

Konumun anlaşmanın diğer tarafına iletilmesi kullanıcının beklediği, kendisinin başlattığı aktarımdır; Google'ın kullanıcı başlatmalı aktarım istisnasına uyduğu sürece formdaki “Paylaşıldı” sayımına dahil edilmeyebilir. Bu, gerçek aktarımın gizlilik metninden gizlenmesi anlamına gelmez. Harita sağlayıcısı karolardan görüntülenen alanı ve IP'yi görebilir.

Gemini ayrı onaydan sonra metin/il alır. Google'ın ücretsiz hizmette kendi geliştirme/inceleme amacıyla kullanım hakkı bulunduğundan, doğrulanmamış bir hesap için yalnız “hizmet sağlayıcıdır, hiçbir veri paylaşılmaz” denmez. Mevcut belirgin açıklama ve ayrı onayın kullanıcı başlatmalı aktarım istisnası ayrıca dikkate alınır; Google hizmet planı değişirse beyan da yeniden gözden geçirilir. Sunucuya metin kaydetmiyoruz diye bütün kategoriyi kısa süreli işlem işaretlemeyin.

Ad, hesap/cihaz kimliği, telefon, rol/firma, adres, fotoğraf, diğer mesajlar, işlem geçmişi ve diğer finansal bilgiler için mevcut, uygulamanın tamamını kapsayan seçimler korunur. Reklam kimliği, reklam/izleme, mikrofon kaydı, rehber veya SMS kutusu eklenmedi. HTTPS ve uygulama içi/dışı hesap silme mevcut.

Gizlilik URL'si: https://yusuftaskiran753-dot.github.io/-santiye-agi/#gizlilik

Hesap silme URL'si: https://yusuftaskiran753-dot.github.io/-santiye-agi/#hesap-silme

## Google Play — konum ön plan hizmeti için kopyalanabilir açıklama

> Şantiye Ağı, bir iş/anlaşmanın iki tarafının birbirini bulabilmesi için kullanıcının isteğe bağlı başlattığı süreli canlı konum paylaşımını sunar. Kullanıcı anlaşma detayında 1 saat, 8 saat veya teslime kadar (en fazla 24 saat) seçer. Yalnız ilgili anlaşmanın diğer tarafı son ölçümü görebilir; rota geçmişi tutulmaz. Uygulama arka plana geçtiğinde, kullanıcının başlattığı paylaşım süresince konum ön plan hizmeti ve görünür bildirim çalışır. Kullanıcı paylaşımı durdurabilir; süre sonu ve ilgili iş/hesap kapanışı da paylaşımı keser. İşletim sistemi konum izni paylaşım başlangıcında istenir. Android ACCESS_BACKGROUND_LOCATION izni kullanılmaz.

İnceleme videosu gerçek cihazdan hazırlanmalı: iki test hesabı, anlaşma detayı, süre seçimi/izin, diğer tarafın haritası, arka planda görünür bildirim, durdurunca konumun kaybolması. Hazır/sınanmış bir video bağlantısı olmadığı için örnek URL yazılmadı. Yeni AAB Console'a yüklenince izin beyanı açılabilir; mevcut sürüm izinleri farklıysa alan henüz görünmeyebilir.

## App Store Connect — daha sonra iOS yayını sırasında

| Apple veri türü | Amaç | Kullanıcıya bağlı | Takip |
|---|---|---|---|
| Precise Location / Coarse Location | App Functionality | Evet (anlaşma/hesap bağlantısı) | Hayır |
| Other User Content | App Functionality (ilan, not, isteğe bağlı asistan girdisi) | Evet; uygulamanın tamamındaki içerik kategorisi | Hayır |
| User ID / Product Interaction | App Functionality (hesap, işlem/kota) | Evet | Hayır |

Bunlar tüm Apple formunun yerine geçmez; telefon/ad, fotoğraflar, satın alma ve bildirim kimlikleri dahil mevcut özellikler de beyan edilir. iOS gerçek SDK/derleme kontrolü ve App Store Connect işlemi bu turda yapılmaz. Google'a hesap kimliği otomatik gönderilmemesi, konum ve içerik kategorilerinin uygulamanın bütünü açısından hesaba bağlı olmadığı anlamına gelmez.

## Web teslimi ve doğrulama

`legal/web/index.html`, müşterinin mevcut GitHub Pages sayfasının yalnız dört yasal bölümünü değiştirir; tanıtım bölümleri, CSS, JS ve aynı #gizlilik/#kvkk/#hesap-silme/#kullanim-kosullari bağlantıları korunur. Kaynak metinler `legal/` altındadır. Veri sorumlusu/iletişim bilgileri mevcut yayımlanmış müşteri sayfasından alınmıştır. Supabase ve GPS işlenmediği yönündeki eski ifadeler kaldırılmıştır. Sunucunun barındırma şirketi/ülkesi ve aktarım sözleşmeleri kaynak kodundan doğrulanamaz; varlığı bilinmeyen imzalı standart sözleşme bulunduğu iddia edilmez.

## Resmî kaynaklar

- [Google Play veri güvenliği tanımları, geçici işleme ve aktarım istisnaları](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Google Play ön plan hizmeti beyanı](https://support.google.com/googleplay/android-developer/answer/13392821)
- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Gemini veri işleme koşulları](https://ai.google.dev/gemini-api/terms)

## Bu turdaki gerçek işlem kaydı

- Müşterinin web deposuna `61c0799` gönderildi; mevcut GitHub Pages URL'sinde yeni metinler ve 20.10.2026 tarihi HTTP 200 ve tarayıcı ile doğrulandı. Bu bir taslak tesliminden ibaret değildir; web metni yayındadır.
- Play Console'da Şantiye Ağı (`com.santiyeagi.app`) kaydı açıldı. Konum ve diğer kullanıcı içeriği türleri zaten seçili; tam konum/diğer içerik için isteğe bağlı, kısa süreli olmayan işleme ve işlevsellik yanıtları mevcut. Diğer içerikte güvenlik amacı da seçili. Mevcut yanıtlar korundu; yeni bir Console gönderimi yapılmadı.
- Yeni izinlerin ön plan hizmeti beyanı, yeni AAB'nin yüklenmesi ve gerçek cihaz inceleme videosu ile tamamlanır; henüz yapılmış sayılmaz. iOS/App Store beyanı yukarıdaki tabloyla sonraki yayın turuna bırakıldı.
- Uygulama kaynakları ve testleri için `flutter analyze lib test` temiz; 233 test geçti, ayrı yerel API isteyen 2 test atlandı. Backend bu turda değiştirilmedi.
