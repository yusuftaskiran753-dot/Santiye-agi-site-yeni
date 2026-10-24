# Google Play veri güvenliği CSV'si — 19 Ekim 2026

Şantiye Ağı Android 2.1.2+7 için kullanıcının Play Console'dan dışa aktardığı 782 yanıt satırlı dosyanın yalnızca yanıt sütunu dolduruldu. Teslim dosyası yerelde `output/google-play/SantiyeAgi-Veri-Guvenligi.csv` içindedir; kaynak dosyanın üzerine yazılmadı. Play Console'a aktarım ve Google incelemesi yapılmadı.

## Beyanın dayanağı

- Ad, hesap kimliği, telefon, rol/firma bilgisi ve çalışılan il profil formu ile API'den kontrol edildi. Ad, telefon, hesap kimliği, rol ve il temel kullanım için zorunlu; firma isteğe bağlıdır. Diğer kişisel bilgiler kategorisi zorunlu rol alanını da kapsar.
- Adresler, elle seçilen ilan/saha koordinatları, fotoğraflar, ilanlar, yorumlar, teklif/talep notları, işlem geçmişi ve ödeme takip tutarları ilgili özellikler kullanıldığında toplanır. Konum beyanı canlı GPS takibi yapıldığı anlamına gelmez. Kullanıcının kendi saha konumunu da girebilmesi nedeniyle hassas konum kategorisi dahil edildi.
- İlan/teklif/anlaşma işlemleri, iletişim açma, engel/şikâyet ve bildirim okuma durumları sunucuda tutulduğu için uygulama işlemleri seçildi. Bu, reklam analitiği kullanıldığı anlamına gelmez.
- Firebase Messaging ve Firebase Installations nedeniyle cihaz/kurulum kimlikleri seçildi. Firebase, bildirim izninden önce başlatılabildiğinden bu kategori tümüyle isteğe bağlı kabul edilmedi. Reklam kimliği, Google Analytics veya Crashlytics kullanıldığı beyan edilmedi.
- Kart/banka hesabı bilgisi, e-posta adresi, rehber, SMS kutusu, mikrofon, sağlık bilgisi ve tarama geçmişi seçilmedi. Mağazanın kendi ödeme ekranında işlediği kart verisi uygulama tarafından alınmaz. İşlem geçmişi ve diğer finansal bilgiler, anlaşma/ödeme takibini de kapsar; tamamlanmamış mağaza entegrasyonunun çalıştığı iddia edilmez.
- Veriler kalıcı kaydedildiğinden kısa süreli işleme seçilmedi. HTTPS aktarımı seçildi.
- Amaçlar uygulama işlevselliği; ilgili türlerde hesap yönetimi ve kötüye kullanımı önleme olarak dolduruldu. Reklam, pazarlama veya analiz amaçları seçilmedi.

## Paylaşım yorumu

Google'ın hizmet sağlayıcı ve kullanıcının başlattığı, beklediği aktarımlar için tanımladığı istisnalar uygulandı. Kullanıcının yayımladığı ilan/fotoğraf ve gönderdiği teklifin muhatabına iletilmesi bu kapsamdadır. Telefon başka bir kullanıcının iletişim açmasıyla da gösterildiğinden, bu kategori için yalnız istisnaya güvenmek yerine paylaşım da açıkça beyan edildi. Bu ayrım telefonların reklam şirketlerine verildiği anlamına gelmez.

## Hesap ve silme alanları

- Mevcut kullanıcı adı/parola işareti korundu; parolasız profil oluşturma için Diğer ve açıklaması eklendi. OAuth veya SMS doğrulaması çalışıyor diye işaretlenmedi.
- Hesap silme bağlantısı dışa aktarımdaki haliyle korundu: https://yusuftaskiran753-dot.github.io/-santiye-agi/#hesap-silme . Sayfa HTTPS üzerinden erişilebilir ve uygulama içinden silme ile destek e-postasına talep adımlarını içeriyor.
- Hesabı koruyarak genel veri silme talebi için ayrı bir destek akışı teyit edilmediğinden bu isteğe bağlı soruda Hayır seçildi. Bu, ilan veya fotoğrafın uygulama içinden ayrı ayrı silinemediği anlamına gelmez. Otomatik 90 gün silme taahhüdü verilmedi.
- Bağımsız güvenlik denetimi, UPI rozeti ve çocuklara yönelik Aileler taahhüdü verilmedi. Ortak test hesabı mevcut uygulama hesabına bağlı olduğundan ayrı bir kurumsal/dış hesap sistemi olarak sunulmadı.

### CSV aktarım düzeltmesi

Play Console, hesap oluşturma yöntemleri seçiliyken `PSL_HAS_OUTSIDE_APP_ACCOUNTS` sorusuna yanıt kabul etmiyor. İlk dosyadaki `false` kaldırıldı; dış hesap alt soruları boş tutuldu. İlgisiz UPI rozeti alanı da boş bırakıldı. Yeni teslim `SantiyeAgi-Veri-Guvenligi-v2.csv` olarak ayrıldı; asıl teslim dosyası da güncellendi. Bu alanların boş olduğu üretim sırasında ayrıca denetlenir. Play Console'a yeniden aktarım kullanıcı tarafından yapılacak.

## Müşteri sayfasında düzeltilmesi gereken metin

Sayfada silinmiş kullanıcının adının karşı tarafın anlaşmasında kalacağı yazıyor. Güncel `SafetyService` adı **Silinen kullanıcı** yapar, kimlik bağlantısını kaldırır ve serbest notları temizler. Kullanıcının verdiği bazı puanların sayısal değeri anonim olarak kalabilir; yazdığı yorumlar temizlenir. Sayfa, tüm puanların kesin silindiğini ve şikâyetlerin her durumda anonim saklandığını söylememeli. Gerçek saklama süreleri müşteri tarafından işletme uygulamasıyla uyumlu biçimde belirtilmeli. CSV'nin oluşturulması bu web metnini değiştirmez.

## Kontrol

782 satır, beş sütun, tüm soru/yanıt kimlikleri ve Türkçe soru etiketleri korundu. Seçili 14 veri türünün her biri için toplama, tek zorunluluk tercihi, kalıcı işleme ve amaç yanıtları kontrol edildi. İlgisiz koşullu sorular boş bırakıldı. Uygulama kodu ve canlı sunucu ayarları değiştirilmedi; bu belge/CSV işi için derleme veya canlı işlem testi yapılmadı.

Kaynaklar:
- [Google Play veri güvenliği ve CSV biçimi](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en)
- [Firebase Android veri açıklamaları](https://firebase.google.com/docs/android/play-data-disclosure)
- Depo: profil formu, veri modelleri, push servisi ve backend silme servisi.
