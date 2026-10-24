# Şantiye Ağı - Yapılan İşler ve Değişiklik Notları

Bu dosya, projede yapılan değişiklikleri müşterinin takip edebilmesi için hazırlanmıştır. Her yeni geliştirme, yapıldığı tarih ve kontrol sonucu ile bu dosyaya eklenecektir.

**Son güncelleme:** 14 Ekim 2026  
**Uygulama sürümü:** 2.1.2+5  
**Güncel aşama:** Mobil düzeltmeler tamamlandı; .NET backend ilk geliştirme grubu yazıldı ve yerel PostgreSQL ile doğrulandı.

## 14 Ekim 2026 - Tamamlanan değişiklikler

### 1. İlk kurulumda karşılaşılan platform hazırlama hatası düzeltildi

- **Önce:** Kaynak dosyaların içinde Android klasörü bulunması, kurulum aracının işlemi yarıda durdurmasına neden oluyordu.
- **Yapılan:** Yalnız başlangıç dosyalarını içeren klasör artık doğru tanınıyor ve eksik platform dosyaları oluşturuluyor.
- **Sonuç:** Kaynak arşivden ilk kurulum için gereksiz şekilde zorla yeniden oluşturma seçeneği kullanmak gerekmiyor.
- **İlgili rapor maddesi:** 1.

### 2. Mevcut Android ve iOS projelerinin korunması sağlandı

- **Önce:** Eksik bir platformu hazırlamak için mevcut platformu da yeniden oluşturmak gerekebiliyordu.
- **Yapılan:** Tamamlanmış platform korunuyor; yalnız eksik olan platform hazırlanıyor. Tanınmayan özel veya yarım proje dosyaları otomatik olarak değiştirilmeden işlem durduruluyor.
- **Sonuç:** Örneğin Android hazır, iOS eksikse Android projesi korunarak iOS hazırlanabiliyor.
- **İlgili rapor maddesi:** 1.

### 3. Kurulum sırasında özel dosyaların korunması ve hata sonrası geri alma kontrol edildi

- **Yapılan:** Android'in özel ayar dosyası ve varsa uygulama imzalama dosyaları yeniden oluşturma sırasında korunuyor. Kurulum başarısız olursa eski platform dosyalarının geri getirilmesi kontrol edildi.
- **Sonuç:** Kurulum hatasında mevcut proje dosyalarının kaybolması riski azaltıldı.
- **Kontrol:** Özel dosyaları koruma ve başarısız kurulumdan geri dönme senaryoları geçti.

### 4. macOS hazırlama betiğindeki boş liste sorunu giderildi

- **Önce:** Korunacak imza dosyası bulunmadığında kullanılan liste işlemi, eski macOS komut ortamında hata çıkarabiliyordu.
- **Yapılan:** Boş listenin güvenli biçimde işlenmesi için uyumlu kod kullanıldı.
- **Kontrol:** Betiğin yazım kontrolü geçti. Gerçek Mac üzerinde çalıştırma kontrolü iOS aşamasında yapılacak.
- **İlgili rapor maddesi:** 2.

### 5. Windows hazırlama aracı düzenlendi

- **Önce:** Windows komut dosyasının satır biçimi ve klasör taşıma işlemleri kurulum sorunlarına neden olabiliyordu.
- **Yapılan:** Windows'a uygun satır biçimi uygulandı. Dosya işlemleri, işlem yapılacak klasörleri kontrol eden tek bir PowerShell betiğinde toplandı. Zorla yeniden oluşturma seçeneğinin doğru okunması da düzeltildi.
- **Sonuç:** İlk kurulum, tekrar çalıştırma ve hata sonrası geri alma Windows üzerinde kontrol edildi.
- **İlgili rapor maddeleri:** 1 ve 17.

### 6. Demo modunda örnek ilanların başlangıçta görünmesi sağlandı

- **Önce:** Uygulama sunucusuz demo modunda açıldığında örnek ilanlar varsayılan olarak kapalıydı; kullanıcı boş listeler görebiliyordu.
- **Yapılan:** Yeni demo kurulumunda örnek ilanlar otomatik gösteriliyor.
- **Sonuç:** Kullanıcı uygulamayı ilk açılışta örnek ilanlarla deneyebiliyor.
- **İlgili rapor maddesi:** 4.

### 7. Demo ilan ayarı için canlı kullanım ve kullanıcı tercihi korundu

- **Yapılan:** Mevcut Supabase canlı bağlantısı verilmişse örnek ilanlar başlangıçta kapalı kalıyor. Kullanıcının Profil ekranından daha önce yaptığı seçim değiştirilmedi.
- **Sonuç:** Demo kullanımındaki düzeltme, kullanıcının tercihini sıfırlamıyor. .NET bağlantısı eklenirken bu ayar yeni bağlantı modeline de uyarlanacak.
- **İlgili rapor maddesi:** 4.

### 8. Teklif ve talep başlıklarındaki Türkçe çoğul hataları düzeltildi

- **Önce:** “Nakliye teklifler” ve “kiralama talebiler” gibi yanlış ifadeler oluşuyordu.
- **Yapılan:** Başlıklar ilan türüne göre doğru biçimde gösteriliyor:
  - Nakliye teklifleri
  - Kiralama talepleri
  - Sipariş talepleri
  - İş başvuruları
  - İş teklifleri
- **Sonuç:** İlan detayındaki gelen teklif/talep başlıkları anlaşılır ve doğru Türkçe ile görüntüleniyor.
- **İlgili rapor maddesi:** 15.

### 9. Malzeme ilanındaki yanıltıcı tarih etiketi düzeltildi

- **Önce:** “Güncelleme” başlığı altında ilanın oluşturulduğu tarih gösteriliyordu.
- **Yapılan:** Bu satır “Yayın” olarak değiştirildi.
- **Sonuç:** Kullanıcıya ilanın yayın zamanı gösteriliyor; bu bilgi son düzenleme tarihi gibi sunulmuyor.
- **İlgili rapor maddesi:** 16.

### 10. Teklif kabul ekranındaki iletişim açıklaması düzeltildi

- **Önce:** İletişim bilgilerinin yalnız teklif kabul edildiğinde paylaşılacağı yazıyordu. Mevcut uygulama kuralı, teklifin taraflarına kabulden önce de erişim veriyordu.
- **Yapılan:** Kabul ekranındaki açıklama mevcut davranışa uygun hale getirildi. Teklif/talep gönderildikten sonra tarafların iletişim bilgilerine erişebildiği ve ret/geri çekmenin bu erişimi tek başına kaldırmadığı açıklandı.
- **Sonuç:** Ekranda mevcut işleyişi yanlış anlatan ifade kaldırıldı. Bu aşamada paylaşım kuralı değiştirilmedi; yalnız açıklama düzeltildi.
- **İlgili rapor maddesi:** 14.

### 11. Profil oluşturma ekranındaki telefon açıklamaları güncellendi

- **Yapılan:** Profil oluşturma sayfasında ve telefon alanının altında, telefon numarasını hangi kullanıcıların görebileceği daha doğru şekilde açıklandı.
- **Sonuç:** Kullanıcı profilini oluştururken iletişim bilgilerinin paylaşım kapsamını görebiliyor.
- **İlgili rapor maddesi:** 14.

### 12. Gizlilik politikası ve KVKK şablonlarının paylaşım açıklamaları düzeltildi

- **Yapılan:** Telefon bilgisine erişebilen kişiler, uygulamanın mevcut davranışına göre gizlilik politikası ve KVKK şablonunda güncellendi.
- **Sonuç:** Uygulamadaki açıklamalar ile dokümanlardaki telefon paylaşım bilgisi uyumlu hale getirildi.
- **Not:** Bunlar mevcut şablonların teknik işleyişe uygun düzenlemeleridir. İşletici bilgileri ve hukuki metinlerin nihai onayı ayrıca tamamlanmalıdır.
- **İlgili rapor maddesi:** 14.

### 13. Varsayılan Flutter simgesi yerine uygulamanın şantiye simgesi kullanıldı

- **Önce:** Android uygulama dosyalarında varsayılan Flutter ikonu bulunuyordu.
- **Yapılan:** Uygulamanın açılış ekranında zaten kullanılan turuncu zeminli şantiye simgesi, Android ve iOS için gerekli ikon boyutlarında hazırlandı ve uygulandı.
- **Sonuç:** Uygulama ikonu mevcut arayüzle uyumlu hale geldi. Müşteriden farklı bir hazır logo gelirse bu simge değiştirilebilir.
- **Kontrol:** İkonlar görsel olarak incelendi; dosyaları ve iOS ikon referansları kontrol edildi.
- **İlgili rapor maddesi:** 18.

### 14. Eksik iOS proje dosyaları hazırlandı

- **Yapılan:** Mevcut Android projesi korunarak iOS proje dosyaları üretildi; uygulama adı ve ikonlar uygulandı.
- **Sonuç:** iOS tarafının başlangıç dosyaları hazırlandı.
- **Not:** iOS derlemesi, imzalama ve cihaz kontrolleri Mac/Xcode ortamında yapılacak. Bu aşamada App Store yayını yapılmadı.

### 15. Geliştirme sürümünün yayın anahtarı olmadan derlenmesi sağlandı

- **Önce:** Platform ayar aracındaki imza kontrolü, test amaçlı Android derlemesini de engelleyebilecek şekilde çalışıyordu.
- **Yapılan:** Yayın anahtarı kontrolü gerçek yayın derlemesine ayrıldı.
- **Sonuç:** Test sürümü geliştirilebilir; mağaza yayın sürümünde gerçek imzalama dosyası kontrolü devam eder.

### 16. Kod kontrolünde bulunan uyarılar temizlendi

- **Yapılan:** Gereksiz bir import, yorum biçimi ve koşul bloklarına ilişkin kod kontrol uyarıları düzeltildi.
- **Sonuç:** Uygulamanın statik kod kontrolü uyarı ve bilgi mesajları dahil temiz geçti.

### 17. Profil oluşturma testlerinin ekranla doğru etkileşmesi sağlandı

- **Önce:** Otomatik testler ekran dışında veya klavyenin arkasında kalan butona dokunmaya çalıştığı için iki test başarısız oluyordu.
- **Yapılan:** Testler ilgili alana kaydıracak, klavyeyi kapatacak ve görünür butona dokunacak şekilde düzeltildi.
- **Sonuç:** Koşullar kabul edilmeden başlanamaması, geçerli profil oluşturma ve geçersiz telefonla kayıt yapılmaması kontrolleri geçti.

### 18. Teknik belgeler gerçek çalışma durumuna göre güncellendi

- **Önce:** Belgelerde araçların bulunmadığı, testlerin yapılmadığı ve demo ilanların her durumda kapalı olduğu gibi eski bilgiler vardı.
- **Yapılan:** README, yayın rehberi, güncelleme notu ve kontrol raporu güncellendi. Önceki kontrol raporu tarihsel kayıt olarak ayrıca saklandı.
- **Sonuç:** Yapılan işler, çalıştırılan testler ve henüz tamamlanmayan aşamalar belgelerde ayrıldı.
- **İlgili rapor maddesi:** 21.

### 19. Doğrulanmamış vergi tutarı kesin bilgi olarak verilmekten çıkarıldı

- **Yapılan:** Yayın rehberindeki bu çalışma kapsamında doğrulanmamış sayısal vergi sınırı kaldırıldı; güncel tutar ve uygunluğun mali müşavirle teyit edilmesi gerektiği belirtildi.
- **Sonuç:** Teknik belgede doğrulanmamış tutar kesin bilgi gibi sunulmuyor.
- **İlgili rapor maddesi:** 21.

### 20. Android test paketi oluşturuldu ve emülatörde çalıştırıldı

- **Yapılan:** Android test APK'sı başarıyla derlendi. Emülatörün depolama sınırı nedeniyle daha küçük, emülatöre uygun paket oluşturularak yüklendi.
- **Sonuç:** Uygulama açıldı, mevcut profil korundu ve örnek ilanlar ekranda görüntülendi.
- **Not:** Bu test paketi demo modundadır; mağazaya gönderilecek canlı yayın paketi değildir.

## Bu aşamanın kontrol sonuçları

| Kontrol | Sonuç |
|---|---|
| Kod analizi | Sorun bulunmadı. |
| Mevcut otomatik testler | 156 test geçti. |
| Uygulama ikonları | Android/iOS dosyaları üretildi ve kontrol edildi. |
| Platform hazırlama | İlk kurulum, dosya koruma, eksik platform ve hata sonrası geri alma kontrolleri geçti. |
| Android derleme | Başarılı. |
| Android emülatör | Güncel test sürümü açıldı; örnek ilanlar görüntülendi. |
| Gerçek Mac/iOS derleme | Bu aşamada yapılmadı; iOS yayın hazırlığında yapılacak. |

## İlk mobil çalışma sonunda planlanan sonraki işler

Bu liste ilk mobil düzeltme aşamasının sonunda hazırlanmıştır. Aynı gün yapılan backend çalışmasının güncel durumu aşağıdaki yeni kayıtta yer alır:

- .NET backend ve veritabanının geliştirilmesi.
- Mobil uygulamanın yeni sunucuya bağlanması ve gerçek kullanıcı akışlarının doğrulanması.
- Profillere yapılan işlerin fotoğraflarını yükleme ve iş galerisi özelliği.
- Telefon doğrulama ve kullanıcı hesabına bağlı hak/kredi yönetimi.
- Sunucuda müsaitlik, engelleme, anlaşma onayı, hesap silme ve puan kurallarının uygulanması.
- Uygulama kapalıyken ulaşan push bildirimleri.
- Google Play ve App Store abonelik/kredi satın alma, doğrulama, iade/iptal ve bekleyen satın alma işlemleri.
- Canlı sunucu kurulumu, HTTPS, loglama ve yedekleme düzeni.
- Gerçek kullanıcılarla uçtan uca kontroller ve mağaza test/yayın işlemleri.

## Yeni değişiklikler için kayıt biçimi

Sonraki çalışmalar aynı dosyada yeni tarih başlığı altında kaydedilecektir:

- **Değişiklik:** Ne yapıldı?
- **Kullanıcıya etkisi:** Uygulamada ne değişti?
- **Kontrol sonucu:** Hangi test veya kullanım senaryosuyla doğrulandı?
- **Durum:** Tamamlandı / test ediliyor / dış erişim veya onay bekleniyor.


## 14 Ekim 2026 - .NET backend ilk geliştirme grubu

### 21. Yeni .NET 10 sunucu projesi oluşturuldu

- İlan, profil, teklif, anlaşma, kredi ve bildirim işlemleri için API yazıldı.
- Veriler PostgreSQL'de saklanacak şekilde veritabanı yapısı ve kurulum dosyaları hazırlandı.
- Windows Server / IIS yayın dosyaları ve kurulum rehberi oluşturuldu.

### 22. Mobil uygulamanın yeni sunucu bağlantısı hazırlandı

- Mevcut ekranları kullanan .NET bağlantı katmanı eklendi.
- Giriş oturumu güvenli saklama alanında tutuluyor; süresi dolunca yenileniyor.
- Veriler sayfalı okunabiliyor. API adresi verilmezse önceki demo kullanımı korunuyor.

### 23. Kullanıcı ve işlem kuralları sunucuya alındı

- Başkasının ilanını değiştirme/silme engelleniyor.
- Müsait olmayan makineye teklif kabulü ve engellenmiş kullanıcıyla anlaşma engelleniyor.
- Teklif kabulünden anlaşma oluşturma, teslim ve puanlama akışları yazıldı.
- Aktif anlaşmanın iptali karşılıklı onaya bağlandı; sorunu bildiren taraf çözümü onaylıyor.

### 24. Tekrar gönderimler ve hesap silme kontrol edildi

- Aynı işlem tekrar gönderilince ikinci bir kayıt oluşmaması için işlem kimliği kullanılıyor.
- Aynı iletişim hakkı eşzamanlı açıldığında ücretsiz hak bir kez harcanıyor.
- Hesap silinince oturum kapanıyor; karşı tarafa verilen puan anonim olarak korunuyor.

### 25. Gerçek yerel veritabanı ve mobil bağlantı testleri yapıldı

- 12 .NET testi geçti; temel HTTP akışları gerçek PostgreSQL ile doğrulandı.
- Flutter'ın mevcut ve yeni bağlantı testleri toplam 160 testle geçti.
- Mobil durum katmanı gerçek API ile iki kullanıcı, profil, ilan, teklif ve iptal akışını kullandı.
- API bağlantılı Android test sürümü emülatöre yüklendi.

### Bu grubun tamamlanmamış kısımları

Canlı SMS/giriş kararı, profil iş fotoğraf galerisi, uygulama kapalıyken push, gerçek mağaza abonelik/kredi/iade entegrasyonu ve müşteri sunucusu kurulumu henüz yapılmadı. Ödeme doğrulaması tamamlanmadan bu API ücretli hak vermiyor. Bu ilk sürüm henüz canlı yayın teslimi değildir.

Ayrıntılı teknik kayıt: NET_BACKEND_ILK_ASAMA.md. Sunucu kurulum rehberi: backend/README.md.

## 14 Ekim 2026 - Test hesabı ve yeni VDS hazırlığı

### 26. Test hesabıyla sunucu bağlantısı ve doğrulama görünümü gösterildi

- **Değişiklik:** Kullanıcı isteğiyle gerçek SMS bağlantısı sonraya bırakıldı. Yerel veritabanında Test Kullanıcısı adlı hesap oluşturuldu.
- **Kullanıcıya etkisi:** Android emülatörde yeni .NET sunucusuna bağlanan uygulamayla test hesabına giriş yapıldı; profil ve Telefon doğrulandı rozeti görüntülendi.
- **Kontrol sonucu:** Kod isteği, kodla giriş ve profil okuma API üzerinden çalıştı. Ekran görüntüsü kaydedildi; yerel veritabanı bağlantı kontrolü başarılı.
- **Durum:** Yerel test tamamlandı. Gerçek SMS gönderilmedi; canlı telefon sahipliği teyidi henüz yapılmadı. Test hesabı üretime doğrulanmış müşteri hesabı olarak taşınmayacak.

### 27. Yeni sunucu için kurulum sırası yazıldı

- **Değişiklik:** Windows güncellemeleri, IIS, .NET 10 Hosting Bundle, PostgreSQL, alan adı/HTTPS, uygulama ayarları, veritabanı kurulumu ve mobil bağlantı adımları ayrı bir rehbere yazıldı.
- **Kullanıcıya etkisi:** Yeni VDS'nin hangi sırayla hazırlanacağı ve kurulumda hangi ayarların gerekeceği netleşti.
- **Durum:** Rehber hazır; müşteri sunucusuna kurulum bu aşamada yapılmadı.
- **Dosya:** docs/VDS_KURULUM_REHBERI.md.

## 14 Ekim 2026 - GitHub üzerinden sürüm takibi

### 28. Mobil uygulama ve backend birlikte sürümleniyor

- **Değişiklik:** Kullanıcının sağladığı özel TunaCrt/santiye_app deposuna mobil ve backend kaynakları birlikte gönderildi. İlk commit a07957c mevcut geliştirme durumunu koruyor; sonraki özellikler ayrı commit'lerle ilerliyor.
- **Kullanıcıya etkisi:** Yapılan kaynak değişiklikleri tarihçeden incelenebilir ve önceki sürüme dönülebilir.
- **Kapsam:** Parolalar, anahtarlar, yerel veritabanı, kullanıcı fotoğrafları ve derleme çıktıları kaynak deposuna dahil edilmez. Gerçek kullanıcı verileri için sunucu yedeği ayrı tutulur.

### 29. Kullanıcı profiline yapılan iş fotoğrafları eklendi

- **Değişiklik:** Profil ve herkese görünen profil ekranlarında iş fotoğraf galerisi oluşturuldu. Kullanıcı galerisinden fotoğraf seçebilir, açıklama ekleyebilir, fotoğrafı büyütebilir ve kendi fotoğrafını onay vererek silebilir.
- **Kullanıcıya etkisi:** Kullanıcılar yaptıkları işleri profillerinde gösterebilir. Başkasının fotoğrafını silme yetkisi verilmez. Engellenen kullanıcılar birbirlerinin fotoğraflarına erişemez.
- **Sınırlar:** Hesap başına en fazla 20 fotoğraf, dosya başına en fazla 8 MB giriş. Sunucu görüntüyü doğrular, küçültüp JPEG olarak saklar; konum gibi EXIF bilgileri kaldırılır.
- **Veriler:** Fotoğraflar PostgreSQL'de saklanır. Hesap silindiğinde birlikte temizlenir; GitHub'a kullanıcı fotoğrafları yüklenmez.
- **Kontroller:** Gerçek PostgreSQL ile yükleme, aynı işlemin tekrar gönderimi, yetki, engelleme, silme, hesap silme ve sınır kontrolleri geçti. Mobilde oturum yenileme sırasında fotoğraf yükleme ve galeri görüntüleme/silme/yeniden deneme testleri yapıldı.
- **Durum:** API ve mobil ilk sürüm hazır. Gerçek müşteri IIS kurulumu ve iOS cihaz kontrolleri henüz yapılmadı. Fotoğraf ekleme internet bağlantısı gerektirir.
- **Son kontrol:** 14 .NET testi ve 164 Flutter testi geçti; kod analizinde sorun bulunmadı. Son galeri düzenlemelerinden sonra ilgili 8 mobil test yeniden geçti. Windows yayın paketine karşı gerçek fotoğraf yükleme ve JPEG okuma da başarılı. Android debug APK derlendi ve emülatöre yüklendi.

## 15 Ekim 2026 — backend ve mobil teslim hazırlığı

### 30. Müşterinin verdiği ilk demo kayıt altına alındı

- Orijinal ZIP ve kaynak dosyalarının SHA-256 özetleri kaydedildi. 22 bölümlük envanterde sayfalar, butonlar, alanlar, filtreler, ödeme takibi, Premium araçlar ve çevrimdışı kullanım açıklandı.
- Orijinal kaynak kopyasında 36 arayüz senaryosu çalıştırıldı, 55 ekran/adım kaydı alındı. Gerçek hizmetle çalışan özellikler ile demo simülasyonları ayrıldı.
- **Dosya:** MOBIL_ILK_SURUM_OZELLIK_ENVANTERI.md ve baseline/ kanıtları. İlk sürümde fotoğraf galerisi ve kapalı uygulamaya push olmadığı ayrıca belirtildi.

### 31. Mağaza satın alma ve iade bağlantıları hazırlandı

- Google Play ve App Store makbuzları sunucudan doğrulanıyor. Aynı alışverişle ikinci kez kredi verilmesi ve başka hesap adına kullanılması engelleniyor.
- Premium süreleri mağazadan yenileniyor; iptal ve iade durumları izleniyor. İade edilen krediler düşülüyor; önceden harcanmışsa sonraki kredi alımından mahsup ediliyor.
- Mobilde bekleyen ödemeler hesaplara göre saklanıyor; başka hesapla girişte kaybolmuyor. Doğrulama gelmeden işlem tamamlanmış gösterilmiyor.
- **Canlı durum:** Mağaza ürünleri ve müşteri anahtarları henüz tanımlanmadığından gerçek satın alma/sandbox kabul testi yapılmadı. Ayrıntılar ODEME_KURULUMU.md.

### 32. Telefon doğrulama ve anlık bildirim bağlantıları hazırlandı

- VatanSMS.net için OTP adaptörü, kod süresi, yanlış deneme ve SMS gönderim sınırları eklendi. Test kodu Production ortamında kullanılamıyor.
- Firebase üzerinden anlık bildirim için cihaz kaydı, çıkışta temizleme, kalıcı gönderim kuyruğu ve yeniden deneme eklendi. Mobil bildirim izni ve bildirime dokunarak açılış bağlandı.
- **Canlı durum:** Gerçek VatanSMS gönderimi ve Android/iPhone push teslimatı müşteri hesap ayarları girildikten sonra kontrol edilecek. WhatsApp doğrulaması kapsamı netleşmediği için uygulanmadı. Ayrıntılar BILDIRIM_SMS_KURULUMU.md.

### 33. Demo ile yeni sunucu arasındaki uyumsuzluklar giderildi

- Bekleyen teklif yeniden düzenlenebiliyor. Teklif kabul edilince anlaşmaya ödeme satırı, miktar, tarih ve adres bilgileri taşınıyor.
- Anlaşma koduyla katılım ve tek kişilik başlatılan kayda sonradan katılım korunuyor.
- Hesabını silen kişinin devam eden anlaşmaları karşı tarafı işlem yapılamayan durumda bırakmıyor; tamamlanan işin puanı anonim olarak korunuyor.
- Engeli kaldırma ve iletişim bilgisini yeniden deneme ekranlarında bulunan arayüz hataları düzeltildi. Bağlantısız çıkışta eski profil ekranda kalmıyor.

### 34. IIS için teslim ve kurulum paketi hazırlandı

- .NET 10 Windows x64 yayın ZIP'i, PostgreSQL migration SQL'i, IIS kurulum ve yedekleme betikleri hazırlandı.
- Sunucu parolaları ve anahtarlar yayın dosyalarının dışında tutuluyor. HTTPS, arka plan görevleri için IIS ön yükleme ve kalıcı anahtar klasörü kurulumda ele alınıyor.
- **Kalan aşama:** Müşteri VDS'sine kurulum, DNS/HTTPS, gerçek SMS/mağaza/Firebase ayarları ve gerçek cihaz kabul testleri. Bunlar tamamlanmış gibi raporlanmıyor.
- **Rehber:** SUNUCU_PAKETI_TESLIM.md ve MOBIL_BAGLANTI_VE_YAYIN.md.

### 35. Mobil uygulama canlı IIS sunucusuna bağlandı

- **Değişiklik:** `config/live.json` canlı bağlantı ayarları eklendi. Android uygulaması `https://45.59.70.198` adresini kullanacak şekilde derlenip açık emülatöre kuruldu. Bu sürümde örnek ilanlar ve kurulumu bekleyen Firebase push varsayılan olarak kapalıdır.
- **Sunucu kontrolü:** IP adresine ait HTTPS sertifikası geçerli. Uygulamanın çalıştığı ve PostgreSQL veritabanına erişebildiği dışarıdan kontrol edildi; iki sağlık kontrolü de başarılı (HTTP 200). Oturum açılmadan profil ve ilan verileri istenince sunucu erişimi reddediyor (HTTP 401).
- **Emülatör kontrolü:** Tanıtım ekranından telefonla girişe geçildi. Kod gönderme isteği gerçek sunucuya ulaştı ve sunucu “Telefon doğrulama hizmeti henüz yapılandırılmadı.” yanıtını verdi. TLS doğrulaması kapatılmadı, canlı telefon doğrulaması atlatılmadı.
- **Testler:** İlgili 10 mobil test geçti. `flutter analyze lib test` kontrolünde sorun bulunmadı. Android debug derlemesi başarılı.
- **Kalan aşama:** Gerçek SMS sağlayıcısı etkinleştirilince hesap açma, profil, ilan, teklif ve fotoğraf işlemleri canlı sunucuda giriş yapılarak kontrol edilecek. Bu işlemler mevcut canlı testte tamamlanmış sayılmaz. Mağaza ödemeleri ve Firebase teslimatları da müşteri hizmet ayarlarını bekliyor.

### 36. Hesap değişimi sırasında fotoğraf yükleme düzeltildi

- **Değişiklik:** Fotoğraf gönderilirken çıkış yapılıp başka hesaba geçilirse eski yükleme yeni hesapla yeniden gönderilmiyor. Eski hesaptan geç gelen başarılı yanıt da yeni hesabın galerisine uygulanmıyor.
- **Kullanıcıya etkisi:** Bir hesabın seçtiği fotoğrafın diğer hesabın profiline taşınması önleniyor.
- **Kontrol:** Geç gelen başarılı yanıt ve oturum süresi dolması yanıtı için iki ayrı hata senaryosu önce tekrar üretildi; düzeltmeden sonra ikisi de geçti.

### 37. SMS beklenmeden backend iş akışları uçtan uca kontrol edildi

- **Değişiklik:** Ayrı bir yerel .NET/PostgreSQL test ortamı kuruldu; emülatörde Test Kullanıcısı hesabı açıldı. SMS gönderilmeden kalan işlevlerin incelenebilmesi sağlandı. Canlı doğrulama kapatılmadı.
- **Kapsam:** Beş ilan türü, ilan düzenleme, müsaitlik, ücretsiz haklar, teklif güncelleme, anlaşma, ödeme takibi, sorun/teslim/puanlama, engel/şikâyet, iş fotoğrafları, bildirimler ve oturum işlemleri gerçek API üzerinden kontrol edildi.
- **Emülatör:** Makine ilanı açıldı, adresli kiralama talebi gönderildi, diğer hesabın kabulü anlaşma ekranına geldi ve ödeme bildirimi kaydedildi. Android galerisinden test fotoğrafı seçilip açıklamayla paylaşıldı; profil galerisinde görüntülendi ve büyütülerek açıldı.
- **Testler:** 68 backend testi ve 174 standart mobil test başarılı. Ayrıca gerçek yerel API'ye karşı 2 kabul senaryosu ve ilgili 9 veri katmanı testi geçti. Kod analizinde sorun yok.
- **Sınır:** Gerçek SMS, mağaza ve push sağlayıcıları müşteri hesap ayarlarını bekliyor. Yerel test verileri müşteri sunucusuna taşınmadı.
- **Ayrıntı:** BACKEND_KABUL_KONTROLU.md.

### 38. Test sunucusu açıkken yayın paketi hazırlanması düzeltildi

- **Değişiklik:** PostgreSQL kurulum SQL'i hazırlanırken yayın derlemesiyle aynı Release ayarı kullanılıyor. Çalışan geliştirme API'sinin dosyalarının yeniden derlenmesine gerek kalmıyor.
- **Kullanıcıya etkisi:** Emülatörün kullandığı test sunucusunu durdurmadan IIS teslim paketi hazırlanabiliyor.

### 39. SMS doğrulaması sunucudan açılıp kapanabilir hale getirildi

- **Değişiklik:** Kullanıcının isteğiyle SMS zorunluluğu ayara bağlandı. Yeni IIS teslim paketinde kapalı başlar. Kapalıyken kullanıcı doğrudan profil oluşturur ve normal API oturumuyla işlemlerini kaydeder; telefonu doğrulanmış gösterilmez.
- **Kolay kullanım:** Sunucuda `set-sms-verification.ps1 -Mode On` veya `-Mode Off` yeterlidir. Mobil uygulama ayarı sunucudan okur; açıp kapatmak için yeni APK gerekmez. Rehber: SMS_AC_KAPAT.md.
- **Mevcut kayıtlar:** SMS açılınca doğrulanmamış mevcut oturumlarda da doğrulama istenir. Gerçek kodla aynı telefona ait hesaba dönülür. Başkasının telefonunu yalnız yazarak mevcut hesaba girilemez; aynı telefonla ikinci hesap oluşturulamaz.
- **Sadeleştirme:** Önceki tek kullanımlık test oturumu dosyası aktarma yöntemi kaldırıldı. Production ortamında geliştirme test kodu açılmadı.
- **Kontrol:** 70 backend testi, 177 mobil testi başarılı; standart mobil turunda 2 yerel API testi atlandı. Flutter analizinde sorun yok. Windows PowerShell'de aç/kapat betiğinin diğer ayarları ve dosya izinlerini koruduğu kontrol edildi.
- **Emülatör:** Ayrı yerel gerçek API/PostgreSQL ortamında SMS ekranı atlandı, SMS Test profili kaydedildi ve ana sayfa açıldı. Veritabanında profil tamamlanmış, telefon doğrulanmamış olarak görüldü.
- **Canlı sınırı:** Yeni ZIP müşterinin IIS sunucusuna yüklenmeli. Bu güncelleme henüz müşteri sunucusunda uygulanmış veya canlı giriş sonrası test edilmiş sayılmaz. SMS, mağaza ödemesi ve push için gerçek hizmet ayarları ayrıca bekleniyor.

### 40. Canlı hesaplar oluşturuldu; cihazda kalan hafriyat kayıtları sunucuya bağlandı

- **Canlı hazırlık:** Müşteri, sunucuda yedek alarak hesap verilerini temizleyen aracı çalıştırdı. İşlem öncesi ve sonrası hesap/ilan/anlaşma sayıları sıfırdı; yedek yolu ve COMMIT çıktısı görüldü. Araç mevcut tablo yapısını korur ve başka veritabanlarına işlem yapmaz.
- **Gerçek sunucu:** Emülatörde Tuna Test hesabı açıldı. İkinci hesapla beş ilan türü oluşturuldu; ana ekranda 1 yük, 1 makine, 1 malzeme ve 2 personel/operatör kaydı görüldü. Bu kayıtlar müşterinin HTTPS API'sinde saklanır; demo verisi değildir. İlanlar ticari teklif olmadıkları belirtilen kontrol kayıtlarıdır.
- **İş akışı:** Emülatörden iletişim bilgisi açıldı, adresli kiralama talebi gönderildi. İkinci canlı hesap kabul etti; oluşan 9.500 TL tutarlı anlaşma İşlerim ekranında görüldü. Bu tutar kontrol kaydıdır, gerçek para transferi yapılmadı.
- **Eksik tamamlandı:** Kazı sahası, döküm sahası ve malzeme ocağı kayıtları artık .NET API üzerinden kullanıcıya özel PostgreSQL tablosuna kaydedilir. Başka hesap bunları göremez, değiştiremez veya silemez. Hesap silinince sahaları da silinir. Optimizasyon hesabı cihazda yapılmaya devam eder.
- **Gerçek veri görünümü:** Canlı modda örnek ilan ve örnek saha ekleme seçenekleri kapatıldı. Demo modundaki bu özellikler korunur. Önceden cihazda bulunan ortak hafriyat verileri yeni hesabın sunucu kayıtlarına otomatik taşınmaz.
- **Güvenilir kayıt:** Sunucuya kaydedilemeyen saha başarıyla eklenmiş gösterilmez; hata ekranda açıklanır. Çıkışta saha verisi temizlenir. Sunucudan okunan sahalar hesaba ait çevrimdışı önbelleğe alınır.
- **Kontrol:** 72 backend ve 179 mobil testi geçti, Flutter analizinde sorun bulunmadı. Temizleme aracı ayrı yerel test veritabanında çalıştırıldı; aldığı yedek başka bir yerel test veritabanına geri yüklenerek 4 hesap, 5 ilan, 1 anlaşma ve migration geçmişinin geri geldiği kontrol edildi.
- **Yayın:** Hafriyat kaydı için yeni `AddHaulPoints` migration'ı ve güncel ZIP gerekir. Mevcut sunucuya güncelleme adımları CANLI_GUNCELLEME.md belgesindedir. Bu yeni tablo henüz müşterinin sunucusunda uygulanmış sayılmaz.

### 41. Güncel uygulama canlı sunucuda ve emülatörde kabul edildi

- **Kurulum tamamlandı:** Müşteri yeni backend dosyalarını yükleyip hafriyat tablosunu kurdu. Sağlık kontrolü ve özel saha API'si canlıda doğrulandı. Yeni Android profile sürümü emülatöre kuruldu; uygulama tamamen kapatılıp açıldığında Tuna Test hesabı ve sunucudaki kayıtlar geri geldi.
- **İlanlar ve teklifler:** Ana hesap emülatörden bir makine yayınladı; karşı hesap aynı kaydı okudu. Ana hesaba gelen 13.000 TL / iki günlük talep emülatörden kabul edildi ve ikinci bir anlaşma oluştu.
- **Tamamlanan iş:** İlk 9.500 TL'lik anlaşmada Ödedim, tahsilat, teslim, tamamlama ve test puanı kaydedildi. Karşı tarafın profilinde puan sayısı 1 olarak okundu. Gerçek para transferi yapılmadı.
- **Fotoğraf ve bildirim:** İş fotoğrafı Android galerisinden seçilip canlıya yüklendi, profilde açıldı ve ikinci hesaptan görüldü. Başkası fotoğrafı silemedi. Bildirimler okundu işaretlendi; bu işaretler sunucudan doğrulandı.
- **Hafriyat:** 2.000 m³ kazı sahası ile 5.000 m³ kapasiteli, 150 TL/m³ bedelli döküm sahası emülatörden kaydedildi. Uygulama yeniden açıldıktan sonra ikisi de sunucudan geri geldi.
- **Yetkiler:** Engel sırasında iletişim bilgisi alınamadı; engel kaldırılınca erişim geri geldi. Ayrı geçici hesap silindi ve eski oturumu kullanılamadı. Ana kontrol hesapları ve kayıtları korunur.
- **Bakım düzeltmesi:** IIS güncellenirken gönderdiği bakım sayfası artık geçici sunucu hatası olarak değerlendirilir; uygulama oturumu gereksiz yere kapatmaz. Normal istek ve fotoğraf gönderimi için ayrı testler eklendi.
- **Son doğrulama:** 72 backend testi ve 181 mobil testi başarılı, Flutter analizinde sorun yok. İki yerel API testi standart mobil turunda atlanır. Android x64 ve üç mimarili profile APK derlemeleri başarılıdır. Otomatik entegrasyon testleri müşteri veritabanında çalıştırılmadı.
- **Teslim:** CANLI_KABUL_KONTROLU.md yapılan canlı kontrolleri, CANLI_HESAP_BILGILERI.md hesabın kullanımını açıklar. SMS kapalıyken şifreyle tekrar giriş yoktur; emülatörde cihaz oturumu açık bırakılır. Gerçek SMS, mağaza, push ve iOS yayın kontrolleri ilgili hizmet hesaplarını bekler.

### 42. Android Firebase proje dosyası bağlandı — 16 Ekim 2026

- **Yapılan:** Müşterinin Firebase'den indirdiği Android ayarı kontrol edildi; proje `santiye-agi`, paket adı uygulamayla aynı. Dosya Android'in beklediği konuma yerleştirildi. İndirilen kopya ve uygulama ayarı Git'e eklenmez.
- **Mobil hazırlık:** Android bildirim denemeleri için canlı VDS'ye bağlanan ayrı `config/live-android-push.json` ayarı eklendi. Genel canlı ayarı push kapalı kalır; henüz ayarlanmamış iOS'a Android yapılandırması uygulanmaz.
- **Kontrol:** Bildirim servisinin token yenileme, hesap ayrımı ve izin kapatma davranışlarını kontrol eden 3 testi başarılı. `flutter analyze lib test` sorun bildirmedi.
- **Derleme:** Android x64 profile APK, gerçek Firebase Android ayarı ve push açık yapılandırmayla başarıyla üretildi. Yerel test dosyası `output/mobile/SantiyeAgi-Android-Push-x64-Test.apk`; mağaza imzalı yayın paketi değildir. Bu aşamada emülatöre kurulmadı.
- **Kalan:** Sunucunun Firebase hizmet hesabı anahtarı ve gönderim ayarları henüz sağlanmadı. Gerçek FCM bildiriminin ulaştığı, cihaz kaydının gerçekleştiği veya uygulama kapalıyken teslimatın çalıştığı bu aşamada iddia edilmez.

### 43. Firebase sunucu anahtarı kontrol edildi; tek komutla kurulum hazırlandı — 16 Ekim 2026

- **Anahtar:** Müşterinin sağladığı hizmet hesabının Şantiye Ağı projesine ait olduğu kontrol edildi. Google, anahtarla kimlik doğrulamayı kabul etti (OAuth HTTP 200). Anahtarın içeriği çıktıya yazılmadı; dosya Git dışında, yalnız kullanıcı/yönetici/SYSTEM erişimli yerel konuma alındı.
- **Kolay kurulum:** `set-firebase-push.ps1` mevcut sunucu ayarlarını koruyarak yalnız Firebase gönderimini açar veya kapatır. Özel anahtarı web klasöründe kabul etmez; ilgili IIS havuzuna okuma yetkisi verir ve havuzu yeniden başlatır. API dosyalarını yeniden kopyalama veya migration çalıştırma gerektirmez.
- **Kontrol:** Yerel PowerShell kontrollerinde aç/kapat, veritabanı/SMS/imza ayarlarının ve settings dosya izinlerinin korunması, anahtarın ayarlara yazılmaması, yanlış proje/OAuth adresinin reddedilmesi başarılı.
- **Backend:** .NET derlemesi ve SMS/push sağlayıcılarına ait 11 birim testi başarılı. Gerçek SMS veya müşteri veritabanında otomatik test çalıştırılmadı.
- **Kalan:** Araç henüz müşteri VDS'sinde çalıştırılmadı. Android cihaz kaydı ve teklif sonrası gerçek bildirim teslimi bundan sonra kontrol edilecek; Google'ın anahtarı kabul etmesi bildirim teslim edildiği anlamına gelmez.

### 44. Android bildirimleri VDS'den emülatöre ulaştı — 16 Ekim 2026

- **Canlı kurulum:** Müşteri Firebase kurulum aracını VDS'de çalıştırdı. Android push açık sürümü emülatöre mevcut hesabı silmeden kuruldu; Tuna Test hesabı ve kayıtları korundu. Cihaz kaydı gerçek API'ye yapıldı.
- **Gerçek gönderim:** Diğer kontrol hesabından teknik kiralama talebi gönderildi. Uygulama arka plandayken Android sistem bildirimi geldi; VDS'nin bildirim kimliğiyle aynı olduğu doğrulandı.
- **Kapalı işlem:** Uygulama işlemi çalışmıyorken de talep güncelleme bildirimi geldi. Bildirime dokununca doğru hesabın Bildirimler sayfası açıldı. Android “Zorla durdur” senaryosu uygulanmadı.
- **Gizlilik ve temizlik:** Bildirim panelinde özel teklif/telefon/adres yerine genel metin gösterildi. Test talebi 0 TL ve açık kontrol notuyla kullanıldı; ardından geri çekildi. Gerçek ödeme veya ticari anlaşma yapılmadı.
- **Sınır:** Emülatörde bildirim izni debug aracıyla verildi; fiziksel Android telefon/izin akışı ve iOS/APNs kontrolleri ayrıca yapılacak. Ayrıntılar ANDROID_BILDIRIM_CANLI_KONTROLU_2026-10-16.md belgesindedir.
- **Test dosyası:** Android telefon denemesi için üç mimarili push açık profile APK hazırlandı: `output/mobile/SantiyeAgi-Android-Push-Test.apk`. Mağaza yayın imzası içermez; sunucunun özel anahtarı APK'ye konulmadı.

### 45. Google Play ilk kapalı test AAB paketi hazırlandı — 18 Ekim 2026

- **Teslim:** `SantiyeAgi-2.1.2-5-Kapali-Test.aab` gerçek upload anahtarıyla release olarak üretildi. Canlı VDS bağlantısı ve Android bildirimleri açık, örnek ilanlar kapalı. Yaklaşık 46 MB; sürüm `2.1.2 (5)`, hedef Android API 36.
- **Anahtar:** İlk upload anahtarı ve parolası Git dışında, kullanıcının korumalı yerel sır klasöründe tutulur. Kaynak koduna veya AAB'ye eklenmedi. Sonraki sürümlerde kullanılacak bu dosyaların bilgisayar dışında güvenli yedeği alınmalı.
- **Kontrol:** 181 mobil testi geçti; standart turda 2 yerel API testi atlandı. Flutter analizi temiz. AAB yapısı, imzası ve arşiv bütünlüğü doğrulandı; 64 bit yerel kütüphanelerin 16 KB segment hizalaması geçti. Canlı sunucu sağlık isteğine HTTP 200 döndürdü.
- **Yayın ayrımı:** Dosya henüz Play Console'a yüklenmedi; kapalı test veya 14 günlük süre başlamadı. Gerçek telefonda bu release sürümü henüz denenmedi. Mağaza satın almaları, SMS, nihai yasal bağlantılar/destek bilgileri ve Console beyanları sıradaki yayın işlerine dahildir. Eksik entegrasyonlar tamamlanmış gösterilmez.
- **Rehber:** `GOOGLE_PLAY_ILK_KAPALI_TEST.md` imza dosyalarını, paket özetini ve Console'daki sonraki adımları açıklar. Android yayın örnekleri push açık canlı yapılandırmayla güncellendi; debug imzası kullanıldığına dair eski yorumlar düzeltildi.

### 46. Paket adı mevcut Google Play kaydına eşleştirildi — 18 Ekim 2026

- **Sorun:** Müşterinin Console kaydı `com.santiyeagi.app` istediği için ilk `com.santiyeagi.santiye_agi` paketi reddedildi. Android paket kimliği, namespace, ana etkinlik ve mağaza abonelik bağlantısı mevcut mağaza kimliğine göre düzeltildi.
- **Firebase:** Aynı Firebase projesinde yeni paket için gerçek Android uygulama kaydı oluşturuldu ve Google yapılandırması indirildi. Eski dosyanın paket alanı elle değiştirilmedi. Sunucu Firebase özel anahtarı değiştirilmedi; yeni yapılandırma Git'e eklenmedi.
- **Yeni dosya:** `output/mobile/SantiyeAgi-2.1.2-6-Kapali-Test.aab`, sürüm `2.1.2 (6)`, aynı upload anahtarıyla imzalı. Önceki sürüm 5 AAB'si kullanılmamalı.
- **Kontrol:** 181 mobil testi başarılı, 2 yerel API testi standart turda atlandı; Flutter analizi temiz. Release derlemesi, paket yapısı, imza, manifest kimliği/ana etkinlik ve 64 bit 16 KB segment hizalaması doğrulandı. Bağlı cihaz olmadığı için yeni paketle açılış/push teslim testi yapılmadı; Console'un yeni dosyayı kabul ettiği henüz doğrulanmadı.
- **Ayrıntı:** `GOOGLE_PLAY_PAKET_DUZELTME_2026-10-18.md`. Yeni paket eski emülatör uygulamasından ayrı bir Android kimliğidir; yerel oturumlar kendiliğinden aktarılmaz. Gerçek satın alma kurulurken sunucu mağaza paket ayarı da yeni kimlikle doldurulmalı.

### 47. Tekrar kullanılabilir hesap girişi ve inceleme profili — 18 Ekim 2026

- **Eksik:** SMS kapalı profille kayıt yapılabiliyordu, fakat incelemecinin başka cihazdan aynı hesaba kullanıcı adı/parolayla girişi yoktu. Tanımlanmış hesaplara normal parola girişi eklendi; açılış ekranında sunucu özelliği açtığında “Hesabım var — kullanıcı adıyla giriş” görünür.
- **Gerçek profil:** Canlı VDS API'siyle “Google Play İnceleme” adlı teknik hesap oluşturuldu. Kullanıcı adı `play.inceleme`; parola, oturum bilgileri ve hesaba ait kurulum verisi Git dışında korumalı yerel dosyalardadır. Hesaba ücretli hak verilmedi.
- **Güvenlik:** Parola düz metin olarak sunucuda veya mobilde saklanmaz; tuzlu PBKDF2 hash kullanılır. Telefon doğrulaması verilmez; SMS zorunluluğu açılırsa doğrulanmamış kullanıcı bu girişle kuralı atlayamaz. Hesap silindiğinde parola girişi ve eski oturumlar kullanılamaz.
- **Kontrol:** 77 backend testi yalnız yerel test veritabanlarında, 182 mobil testi başarılı; 2 yerel API testi standart mobil turunda atlandı. Analiz temiz. İki oturumdan aynı hesaba giriş, yanlış parola, silinen hesap ve SMS kuralı denendi. Kurulum aracı diğer sunucu ayarlarını korudu.
- **Yeni mobil paket:** `2.1.2 (7)` imzalı AAB hazır; manifest/paket kimliği, imza, arşiv ve 64 bit 16 KB hizalama kontrolleri geçti. AAB'ye parola eklenmedi.
- **Canlı sınır:** Yeni giriş API'si VDS'ye henüz yüklenmedi. Backend ZIP'i ve hesaba özel kurulum dosyası yüklenmeden mevcut canlı uygulamada parola çalışmaz. Yeni release sürümü cihazda denenmedi. Ücretli bölümlerin inceleme erişimi ayrıca tamamlanmalı. Kurulum ve Play'e giriş adımları `GOOGLE_PLAY_INCELEME_HESABI.md` içindedir.

### 48. Android/iOS ortak test girişi Tuna hesabına bağlanacak — 18 Ekim 2026

- **Müşteri tercihi:** Ayrı Play inceleme profili yerine mevcut Tuna Test hesabı seçildi; kullanıcı adı `test`, kurulum dosyası `Test-Hesabi-Kur.ps1` olarak hazırlandı. iOS sürümünde de aynı API hesabı kullanılabilir; Apple bildirimi ve iPhone testi tamamlandı anlamına gelmez.
- **Doğrulama:** Hedef mevcut hesabın Tuna Test olduğu canlı API'den okundu. Tuna hesabının oturumu yenilenmedi, profili veya kayıtları değiştirilmedi. Yeni özel kurulum dosyası yerelde söz dizimi, doğru kullanıcı adı ve diğer ayarların korunması açısından kontrol edildi; Git dışında tutulur.
- **Kurulum eksikliği:** Kullanıcının sunucu çıktısında dosya bulunamadığı için önceki kurulum başlamamıştı. Yeni dosya komuttan önce sunucuya kopyalanmalı. Kontrol sırasında canlı `/auth/options` yanıtında yeni parola özelliği de henüz görünmüyordu; güncel backend kurulumu/çalışan sürüm ayrıca kontrol edilmeli.

### 49. Sunucu güncellemesi tek kısa komuta indirildi — 18 Ekim 2026

- Uzun PowerShell komutlarını yazmakta zorlanan kullanıcı için `kur.ps1` hazırlandı. Sunucudaki ZIP ve hesap kurulum dosyasını kullanarak güncelleme yapar; önce ZIP kimliğini kontrol eder, eski dosyaları erişimi sınırlı klasöre yedekler. Mevcut veritabanını temizlemez.
- Araç kaynakta `backend/deploy/update-test-server.ps1` olarak kayıtlıdır. Yerel teslim kopyasında güncel ZIP hash'i sabittir. Söz dizimi ve hash kontrolü başarılı; canlı IIS üzerinde çalıştırıldığı iddia edilmez. Kullanıcı dosyayı sunucuya kopyalayıp tek kısa komutla çalıştırmalıdır.

### 50. Windows PowerShell 5.1 Türkçe parola özeti kontrolü düzeltildi — 18 Ekim 2026

- Sunucuda backend kopyalandıktan sonra hesap kurulumu “Kimlik bilgisi bicimi gecersiz” hatasıyla durmuştu. Aynı hata yerelde Windows PowerShell 5.1 ve Türkçe kültürde tekrar üretildi; büyük/küçük harfe duyarsız Base64 düzenli ifade kontrolü geçerli ASCII I karakterlerini yanlış reddediyordu.
- Kontrol büyük/küçük harfe duyarlı yapıldı. Windows PowerShell 5.1 ve PowerShell 7 altında Türkçe kültürde geçerli özet, geçersiz parametre reddi, tekrar kurulum ve diğer sunucu ayarlarının korunması kontrolleri geçti.
- Mevcut kurulumu ZIP'i yeniden kopyalamadan tamamlamak için tek dosyalık `duzelt.ps1` hazırlandı. Önce kontrolü düzeltir, sonra mevcut Tuna test hesabı kurulumunu çalıştırır; başarıdan sonra siteyi bakım modundan çıkarır. Sunucuda henüz çalıştırılmadı, canlı parola girişi doğrulanmış sayılmaz.

### 51. Ortak test hesabına canlı parola girişi doğrulandı — 18 Ekim 2026

- Müşteri düzeltme aracını VDS'de başarıyla çalıştırdı ve site bakım modundan çıktı. Canlı HTTPS API'ye `test` kullanıcı adı/parolasıyla giriş HTTP 200 döndürdü; mevcut Tuna Test hesabının kimliği ve profili doğrulandı.
- Yalnız bu kontrol için açılan ayrı oturum kapatıldı (HTTP 204); diğer cihaz oturumları ve hesap verileri değişmedi. Parola kaynak koduna, belgelere veya AAB'ye eklenmedi.
- Bu kontrol API girişini doğrular; sürüm 7 AAB'sinde fiziksel cihaz açılışı ve iOS testi ayrıca yapılacak. Hesabın ücretsiz yetkileri korunur; mağaza ürünü veya ücretli inceleme erişimi tamamlandı anlamına gelmez.

### 52. Google Play görselleri hazırlandı; sürüm 7 girişi emülatörde denendi — 18 Ekim 2026

- **Teslim:** 512 × 512 uygulama simgesi, 1024 × 500 özellik grafiği ve 1080 × 1920 ölçülerinde 6 gerçek telefon ekranı tek ZIP'te hazırlandı. Hangi dosyanın nereye yükleneceği pakette yazılıdır. Video hazırlanmadı.
- **Uygulama:** Sürüm 7 AAB'sinden üretilen imzalı release APK emülatöre kuruldu; açılış ekranından `test` ile canlı Tuna hesabına giriş yapıldı. Android bildirim izni gerçek izin ekranından verildi; izin açık olarak doğrulandı. Yeni FCM teslimi bu turda denenmedi.
- **Gerçek içerik:** Mevcut teknik test ilanları ve anlaşmaları görüntülendi; ticari işlem veya ödeme oluşturulmadı. Ekran içerikleri değiştirilmedi. Simge ve özellik grafiği mevcut uygulama kimliğiyle çizildi.
- **Kontrol:** Görsel üretimi ve üretici dosyanın Flutter analizi başarılı; ölçüler, RGB biçimleri, boyut sınırları ve ZIP bütünlüğü kontrol edildi. Altılı ekran kolajı ve özellik grafiği görsel olarak incelendi. Emülatör görüntü ayarları çekim sonunda geri alındı.
- **Sınır:** Görseller mağazaya yüklenmedi. Bu çalışma fiziksel Android, iPhone, satın alma veya mağaza inceleme onayı değildir. Ayrıntılar `GOOGLE_PLAY_GORSELLERI_2026-10-18.md` içindedir.

### 53. Google Play veri güvenliği dosyası dolduruldu — 19 Ekim 2026

- Kullanıcının dışa aktardığı CSV, mevcut Android sürümünün profil, ilan, fotoğraf, konum, teklif, ödeme takip ve bildirim verilerine göre dolduruldu. Firebase kurulum kimlikleri dahil edildi; reklam kimliği kullanıldığı söylenmedi. Mağazaya aktarılacak dosya yerel `output/google-play/` klasöründedir.
- Kaynak dosyanın 782 satırı ve Google Play alanları korunarak koşullu yanıtlar kontrol edildi. Mevcut hesap silme bağlantısı korundu ve sayfanın erişilebilir olduğu görüldü. Dosya henüz Play Console'a aktarılmadı.
- Müşterinin hesap silme sayfasındaki “anlaşmada adınız kalır” ve puanların tamamının silindiği ifadeleri güncel backend davranışıyla uyuşmuyor. Sayfa anonimleştirme ve gerçek saklama uygulamasına göre düzeltilmeli. Ayrıntılar `GOOGLE_PLAY_VERI_GUVENLIGI_2026-10-19.md` içindedir.
- **Aktarım düzeltmesi:** Play Console'un koşullu dış hesap sorusunda kabul etmediği Hayır yanıtı kaldırıldı. Uygulanmayan dış hesap ve UPI alanları boş tutularak `SantiyeAgi-Veri-Guvenligi-v2.csv` yeniden hazırlandı; ilgili boş alanlar yerelde kontrol edildi. Yeniden mağaza aktarımı henüz doğrulanmadı.

### 54. Son teklif ile teslim durumu karşılaştırıldı — 19 Ekim 2026

- İndirimli toplam 12.500 TL'lik son teklifin iki sayfası okundu. İlan/teklif/anlaşma, iş galerisi, kurallar, mobil bağlantı ve sunucu kurulumunun önceki kabul kayıtları mevcut kodla karşılaştırıldı.
- Kalan kapsam; gerçek mağaza satın alma/abonelik testleri, iOS/APNs ve imzalı iOS teslimi, fiziksel cihaz kabulü, düzenli yedek/geri yükleme ve mağaza yayınları olarak ayrıldı. Ana galeri ve ilan modülleri yeniden eksik gösterilmedi.
- Canlı oturum seçeneklerinde SMS zorunluluğunun kapalı olduğu ve yapılandırılmış parola girişinin açık olduğu görüldü. Normal kullanıcı için cihaz değişiminde hesabı geri alma konusu henüz kapanmadı. Yasal/destek web adreslerinin mağaza formuna eklenmesi ile mobil derlemeye eklenmesinin farklı olduğu belirtildi.
- Ayrıntılı karşılaştırma `TEKLIF_KAPSAM_DURUMU_2026-10-19.md` içinde. Bu incelemede yeni uygulama/mağaza testi veya canlı ayar değişikliği yapılmadı; mağaza onayı ve zamanlanmış yedek kurulumu varsayılmadı.

### 55. Yasal bağlantılar sürüm 8'e eklendi — 19 Ekim 2026

- **İstenen kapsam:** Yalnız yasal/destek adresleri ve yedekleme ele alındı. Kullanıcı mağaza süreçlerini yaptığını belirtti; Android cihaz testini, SMS, bildirim ve satın alma işlerini sonraya bıraktı. Bunların tamamlandığı iddia edilmez.
- **Mobil:** Müşterinin GitHub Pages sayfasındaki dört yasal bölüm, destek e-postası ve işletici adı iki canlı derleme ayarına eklendi. Profile hesap/veri silme açıklama bağlantısı eklendi. İmzalı `2.1.2 (8)` AAB hazırlandı; doğru paket, sürüm ve bundletool/imza kontrolleri geçti. Flutter analizi temiz, üç ilgili widget testi başarılı. Fiziksel cihaz veya mağazaya yükleme yapılmadı. Ayrıntılar `YASAL_BAGLANTILAR_SURUM_8.md`.

### 56. Otomatik yerel yedek ve geri yükleme araçları hazırlandı — 19 Ekim 2026

- **Yedek:** Veritabanı/fotoğraflar, dış ayarlar ve kalıcı anahtarları içeren şifreli paket; her yedekte ayrı test veritabanına geri yükleme; 14 günlük yerel saklama ve günlük görev kurucusu hazırlandı. Kullanıcı sunucu dışı kopya istemedi; dış hedef bekleyen iş olarak tutulmaz.
- **Gerçek yerel sınama:** Windows PowerShell 5.1 ve 7 altında PostgreSQL'e yazılan ikili fotoğraf verisi yedekten birebir döndü. Bozulmuş paket/yanlış anahtar, tekrar çalışma, eskileri temizlerken başka dosyayı koruma, kaynak veriyi değiştirmeme ve çalışma klasörü temizliği kontrolleri geçti. Testler yalnız kendilerinin oluşturduğu yerel `santiye_test_*` veritabanlarına yazdı; canlı sunucuya yazılmadı.
- **Sunucuda kalan tek kurulum adımı:** Kullanıcı `output/backend/yedek.ps1` dosyasını mevcut VDS'ye kopyalayıp kısa komutla çalıştırmalı. Kurucu hem ilk yedeği hem SYSTEM hesabındaki zamanlanmış görevi gerçek geri yüklemeyle sınar. Bu çıktı gelmeden canlı zamanlanmış yedek kurulmuş sayılmaz. Kaynak kodun GitHub'da bulunması kullanıcı verilerini yedeklemez. Ayrıntılar `OTOMATIK_YEDEKLEME.md`.

### 57. VDS yedek görevi çalıştı; uygulama şeması kontrolü güçlendirildi — 19 Ekim 2026

- Kullanıcı ilk yedek/geri yükleme, günlük 03.00 görevi ve SYSTEM altında başarılı görev çıktısını iletti. Kurulumun çalışması bu çıktıyla teyit edildi; gelecekteki gecelik çalışmalar henüz izlenmiş değildir.
- Çıktıdaki `Tablo: 1` sayısının public şemasını saydığı görüldü. Uygulama tabloları santiye şemasındadır. Mevcut dump ve restore şema filtresiz tam veritabanı içindir; sayaçtaki eksik yedek kapsamının tek tablo olduğu anlamına gelmez.
- Sayaç tüm sistem dışı şemaları kapsayacak şekilde düzeltildi. Kullanıcı/ilan/anlaşma/fotoğraf tablolarının varlığı ve okunması zorunlu kontrol yapıldı. Eksik uygulama tablosu içeren yedeğin reddedilmesi test edildi. Güncel tek dosya kurucu yeniden hazırlandı; VDS'de yeni kontrolün sonucu henüz görülmedi.

### 58. Güncel yedek kontrolü VDS'de başarılı — 19 Ekim 2026

- Kullanıcı güncel kurucuyu VDS'de tekrar çalıştırdı. Çıktıda **23 tablo**, ayrı test veritabanına başarılı geri yükleme ve SYSTEM görevinin başarılı çalışması görüldü. Yeni kontrol kritik kullanıcı, ilan, anlaşma ve fotoğraf tablolarının varlığını/okunmasını da zorunlu tutar.
- Günlük sunucu saatiyle 03.00 görevi ve 14 günlük yerel saklama kuruldu. Sunucu dışı kopya müşteri tercihiyle kapalıdır. Bu çıktı ilk kurulum ve görev denemesini teyit eder; sonraki gecelerin başarıyla çalıştığına dair izleme kaydı değildir.

### 59. Müşteri tasarımı mevcut backend korunarak aktarıldı — 20 Ekim 2026

- **İnceleme:** Yeni v2.3.0 arşivi ayrı klasörde açılıp mevcut sürümle karşılaştırıldı. Yalnız tasarım olmadığı; Gemini/Supabase asistanı, canlı GPS ve mevcut .NET/giriş/galeri/push kodlarını geriye alan farklar içerdiği görüldü. Arşiv topluca kopyalanmadı.
- **Görünüm:** Yeni palet, açık/koyu tema, simgeler, tek sıra kategori kısayolları ve daha sade ana sayfa aktarıldı. Arama mevcut ilan aramasında kaldı. Teklif ve anlaşmaların ayrı sekmelerine erişim korundu; profil, galeri, satın alma, giriş ve sunucu kuralları değiştirilmedi.
- **Kontrol:** Mevcut 182 Flutter testi ve yeni 7 gezinme/dar ekran testi başarılı; standart turda yerel API isteyen 2 test atlandı. Flutter analizi temiz. Açık/koyu yerel UI önizlemeleri incelendi. Doğru paket kimliğiyle imzalı sürüm 9 AAB üretildi ve doğrulandı.
- **Teslim sınırı:** Kaynaklar GitHub'a gönderilir; AAB ve görseller yalnız yerel output klasöründedir. Canlı sunucu/mağaza değişmedi; gerçek telefon ve iOS testi yapılmadı. Backend güncellemesi gerekmez. Ayrıntılar `MUSTERI_TASARIM_ENTEGRASYONU_2026-10-20.md`.

### 60. Asistan ve canlı konum API'leri mevcut sisteme eklendi — 20 Ekim 2026

- Kullanıcı, müşteri arşivindeki iki ek özelliğin de yapılmasını istedi. Gemini asistanı ve süreli GPS paylaşımı mevcut .NET/PostgreSQL altyapısına eklendi; arşivdeki eski Supabase backend'i kopyalanmadı.
- Asistan anahtarı yalnız sunucuda tutulur. Metin ve model cevabı kendi veritabanımıza/günlüklerimize yazılmaz; günlük kullanım ve eşzamanlı istek sınırları veritabanında korunur. Asistan ilan yayınlayamaz, ücretli hak veremez. Müşterinin Gemini hesabı henüz hazır olmadığından varsayılan kapalıdır; gerçek sağlayıcıya çağrı yapılmadı.
- Konum yalnız gerçek anlaşma taraflarına açıktır. Süre 1/8 saat veya teslim bildirilene kadar en fazla 24 saattir. Yeni ölçümler süreyi uzatmaz; durdurma, engelleme, hesap silme/çıkış ve kapanışta erişim kesilir. Yalnız son ölçüm tutulur. Geciken başlangıçlar sunucu nesliyle; temizlik sırasında geciken veritabanı yazıları eşzamanlılık kontrolüyle engellenir.
- İki ek tablo için migration hazırlandı. Mevcut teklif, karşılıklı iptal/itiraz, telefon doğrulama ve makbuz doğrulama kuralları korunarak **131 API testi** gerçek, ayrı yerel `santiye_test_*` veritabanlarında başarılı oldu. Canlı IIS ve canlı veritabanı bu çalışmada güncellenmedi.

### 61. Asistan ve konum mobil ekranları bağlandı — 20 Ekim 2026

- Ana sayfa ve ilan verme menüsüne cümleyle arama/taslak girişi eklendi. Yük taslağı mevcut formda kullanıcı kontrolüne açılır; otomatik ilan yayımlanmaz. Diğer ilan formları, galeri, bildirimler, satın alma ve normal arama korunur.
- Gemini etkinleşirse metin ancak kullanıcı ayrıca onay kutusunu seçtiğinde gönderilir. Anahtar mobil pakette bulunmaz. Hesap değişirken bekleyen yanıtlar ve eski onaylar taşınmaz. Hesap hazır olana kadar basit yerel anlayıcı çalışır.
- Anlaşma haritası, süre/izin seçimi, paylaşım şeridi, GPS hataları ve çevrimdışı durdurma bilgisi eklendi. Yalnız yeni tam konum görüntüsü gösterilir; kaldırılmış noktalar geç gelen yanıtlarla geri çizilmez. Arka plan paylaşımı izinle, Android'de görünür ön plan hizmetiyle çalışır. Harita mesafe/süre tahmini il merkezine göredir.
- **233 Flutter testi** başarılı; ayrı yerel API isteyen iki test standart turda atlandı. Analiz temiz. İzin, süre sonu, geciken başlangıç/durdurma, engelleme, hesap değişimi ve geri yükleme yarışları sahte GPS/backend ile sınandı. Android sürüm **2.1.2 (10)** hazırlandı. iOS 15/CocoaPods/konum açıklamaları eklendi; Windows'ta iOS derleme ve gerçek telefon testi yapılmadı.

### 62. Yeni özelliklerin sunucu teslimi hazırlandı — 20 Ekim 2026

- Yeni IIS paketiyle birlikte doğrulama değeri içine yazılan `guncelle.ps1` üretilir. Mevcut VDS'de yazmalar durdurulup şifreli yerel yedek/gerçek geri yükleme kontrolü alınır; dış ayarlar korunarak migration uygulanır ve HTTPS hazır olma kontrolü yapılır. Hata halinde bakım durumu korunur. Bu araç canlı sunucuda henüz çalıştırılmadı.
- Gemini anahtarını gizli girişle sunucuya ekleyen ayrı kurucu hazırlandı; SMS, push, satın alma ve veritabanı ayarlarını korur. Anahtar hazır olmadığı için etkinleştirme yapılmadı. PowerShell sözdizimi ve kapama sırasında diğer ayarları koruma yerel sahte dosyayla kontrol edildi.
- Müşterinin gizlilik/hesap silme sayfası ve mağaza konum/ön plan hizmeti beyanları için metin ve gerçek cihaz kabul adımları `ASISTAN_CANLI_KONUM_KURULUMU.md` dosyasında. Aktif konumların yedeklere girebileceği ve mevcut 14 günlük yerel yedek saklama süresi belirtildi. Dış sunucu yedeği müşteri tercihiyle kapalı kalır.
- **Son teslim doğrulaması:** Sürüm 10 AAB doğru paket ve sürümle üretildi; imza, bundletool ve konum ön plan hizmeti manifest kontrolü geçti. IIS ZIP, migration ve ZIP değerini içeren kısa kurucu hazır. Dosyaların SHA-256 değerleri kurulum belgesine kaydedildi. Kaynak değişiklikleri üç anlamlı commit ile GitHub'a gönderildi; yalnız yerel çıktı dosyaları Git'e eklenmedi.

### 63. VDS güncellemesi ve gerçek Gemini araması doğrulandı — 20 Ekim 2026

- Kullanıcının VDS çıktısında güncelleme öncesi 23 tabloluk yedek/geri yükleme kontrolü ve `AddAiAndLiveLocation` migration'ının iki yeni tabloyu oluşturduğu görüldü. HTTPS hazır olma ucu ayrıca `ready` döndü; yeni AI ucunun oturumsuz isteği reddettiği doğrulandı.
- Kullanıcı anahtarı sunucudaki gizli giriş aracına tanımladı ve Gemini ayarı açıldı. Anahtar kaynak koduna veya bu notlara eklenmedi.
- Canlı API'ye bağlı sürüm 10, emülatörde mevcut Tuna oturumu korunarak açıldı. Asistan ekranında açık onay seçilerek “Yarın İstanbul'dan Ankara'ya tır lazım” örneği gönderildi. Gerçek Gemini sonucu güzergâhı, araç türünü ve yarını doğru yorumladı; erişilebilir ilanlardan bir eşleşme gösterdi. Ekran gerçek Gemini kaynağını gösterdi; yerel yedek mod kullanılmadı. Yeni ilan veya anlaşma oluşturulmadı.
- Bu doğrulama gerçek Gemini arama çağrısı ve emülatör açılışı içindir; fiziksel cihazlar arasında canlı GPS/arka plan paylaşımı, iOS derlemesi ve mağaza satın alma kontrolleri ayrıca yapılmalıdır.

### 64. Ana sayfa müşterinin tek asistan kartına eşitlendi — 20 Ekim 2026

- Ana sayfadaki arama kartı ve ayrı asistan satırı, müşterinin arşivindeki tek “Ne lazım? Yazın, bulalım” kartına eşitlendi. Kartın ölçüleri, simgesi ve örnek cümlesi müşteri sürümüyle aynı. İlanlar ekranındaki klasik arama kullanılmaya devam eder; backend/iş akışları değiştirilmedi.
- Kart yönlendirmesi, İlanlar içindeki klasik arama ve asistanın onay/hesap değişimi davranışlarına ait 15 test başarılı. Tam Flutter turunda 233 test başarılı, ayrı yerel API isteyen 2 test atlandı. `flutter analyze lib test` temiz; S: eşlemesinden bütün klasörü analiz eden ilk komut, hariç tutulmuş eski tmp/inceleme kopyalarını da tarayıp hatalar verdi; uygulama kaynakları ve testler ayrı doğrulandı.
- Yeni kart açık/koyu Flutter ekran önizlemelerinde üretildi ve açık ekran görsel olarak kontrol edildi; bu fiziksel cihaz testi değildir. Sonraki mobil sürüm kodu 11 olarak ayrıldı.

### 65. Konum/asistan gizliliği webde yayımlandı, mağaza yanıtları kontrol edildi — 20 Ekim 2026

- Gizlilik, KVKK, hesap silme ve kullanım koşulları .NET/PostgreSQL sistemi, isteğe bağlı GPS/Gemini, OpenStreetMap, 14 günlük yerel yedek ve gerçek hesap silme davranışına göre güncellendi. Yanlış Supabase/GPS kullanılmaz ve silindikten sonra ad kalır ifadeleri kaldırıldı. Mevcut sayfadaki işletici ve iletişim bilgileri kullanıldı; varlığı doğrulanmamış aktarım sözleşmesi bulunduğu iddia edilmedi.
- Gemini onayı, yazılan metinle birlikte seçili ilin Google'a gönderildiğini ve hizmet planına göre saklama/geliştirme/insan incelemesi koşullarını açıklar; varsayılan kapalıdır. Açık onay olmadan dış sağlayıcı çağrılmaz.
- Müşterinin `yusuftaskiran753-dot/-santiye-agi` deposuna mevcut yazma yetkisiyle yalnız `index.html` değişikliği gönderildi: `61c0799`. Önceki geçmiş korundu. Canlı GitHub Pages sayfası HTTPS 200 ile yeni 20.10.2026 tarihini, Gemini ve süreli konum metinlerini gösterdi; tarayıcıda ayrıca açıldı. Dört yasal bölüm dışındaki HTML/CSS/JS'nin aynı kaldığı karşılaştırıldı. Kaynak kopyası `legal/web/index.html`.
- Şantiye Ağı Play Console kaydı bizzat açıldı. Veri güvenliğinde yaklaşık/tam konum ve kullanıcı tarafından oluşturulan diğer içerik türleri zaten seçili. Tam konum ve diğer içerikte isteğe bağlı toplama, kısa süreli işlem değil ve uygulama işlevselliği yanıtları doğrulandı. İçerikte mevcut güvenlik amacı da korunur. Kullanıcı başlatmalı aktarım istisnası ve güncellenen açık onay nedeniyle bu mevcut yanıtlar değiştirilmedi; Console'da yeni bir beyan gönderildiği iddia edilmez.
- Konum ön plan hizmeti için kopyalanabilir açıklama, gerçek cihaz inceleme videosu adımları ve daha sonra iOS yayını sırasında kullanılacak Apple veri türleri `KONUM_ASISTAN_GIZLILIK_MAGAZA_2026-10-20.md` dosyasında. Yeni AAB'nin mağazaya yüklenmesi, konum hizmeti alanı/video ve iOS gönderimleri bu çalışmada yapılmadı.

### 66. Sürüm 11 Android teslimi doğrulandı — 20 Ekim 2026

- Tek asistan kartı ve güncellenen Gemini onayını içeren imzalı `output/mobile/SantiyeAgi-2.1.2-11-Tasarim-Gizlilik.aab` üretildi. Paket `com.santiyeagi.app`, sürüm `2.1.2`, kod `11`, boyut 48.312.278 bayt; SHA-256 `8C2584761D95ABE08168EA26C488D1677057A7519078FD812D1800067EEC804D`. Kaynak commit `6b30984`.
- Bundletool doğrulaması ve JAR imza kontrolü başarılı. Manifestte konum türündeki ön plan hizmeti mevcut; AD_ID ve ACCESS_BACKGROUND_LOCATION yok. Sonuçlar yerel manifest JSON'una kaydedildi. AAB mağazaya yüklenmedi; fiziksel Android/iOS testi yapılmadı. Backend değişmediği için yeni IIS paketi/kurulumu gerekmez.
- Uygulama değişiklikleri `eb44e54` ve `6b30984` commit'leriyle GitHub'a gönderildi. Gizli bilgiler ve üretilen çıktılar Git'e eklenmedi.

### 67. Mac / iOS çalışmasına devir — 20 Ekim 2026

- Son uygulama değişikliklerinin GitHub'da olduğu ve çalışma ağacının temiz olduğu kontrol edildi. Mac asistanı için canlı API, mevcut iOS/Android kimlik farkı, ortak ürün ID'leri, APNs ve satın alma anahtarlarının ayrımı ve ilgili kurulum belgelerini içeren devir notu eklendi.
- Backend'in çalışan ana sistemi ile Apple satın alma doğrulama kodunun hazır olduğu; Apple hesap/ürün/anahtar ve sunucu Billing ayarlarının henüz bağlanmadığı açıkça ayrıldı. Yalnız ekran görüntülerinin Xcode/proje ve sunucu yapılandırmasının yerini tutmayacağı belirtildi. SMS müşteri bilgilerini bekliyor.
- Bu tur yalnız belge/devir işidir; kaynak kodu, canlı sunucu ve mağaza ayarları değiştirilmedi. Önceki doğrulamalar tekrarlanmadı.


### 68. Mac iOS hazırlığı ve ilk imzasız derleme — 20 Ekim 2026

- App Store Connect'te Şantiye Ağı Pro kaydının Bundle ID'si `com.yusuftaskiran.santiyeagi.pro`, Apple ID'si `6824034438` olarak görüldü. Runner ve test hedefleri bu iOS kimliğine eşitlendi; Android kimliği değiştirilmedi.
- Mevcut `santiye-agi` Firebase projesine bu kimlikle iOS uygulaması eklendi. İndirilen GoogleService-Info.plist yalnız yerel, Git tarafından dışlanan Runner yoluna alındı ve uygulamanın kaynaklarına bağlandı. Dosya veya anahtar içeriği Git'e eklenmedi.
- Push entitlements ve Background fetch eklendi; mevcut remote-notification/location modları korundu. Flutter 3.41.4'ün otomatik UIScene geçişi ve bu yaşam döngüsü için Firebase Messaging'in erken bildirim temsilcisi kurulumu uygulandı. CocoaPods bağlantıları ve kilit dosyası eklendi; eski yerel spec listesi güncellendi. Flutter SDK'sının zorunlu tuttuğu dört dolaylı Dart bağımlılığı kilit dosyasında güncellendi.
- `flutter analyze lib test` temiz. `flutter test`: 233 başarılı, ayrı yerel API isteyen 2 test atlandı. Canlı API/push tanımlarıyla `flutter build ios --release --no-codesign --dart-define-from-file=config/live-android-push.json` başarılı. Üretilen 2.1.2+11 uygulamasının Bundle ID, Firebase proje/uygulama kimliği ve derleme API/push tanımları kontrol edildi. Bu yalnız imzasız cihaz derlemesidir; imzalı IPA, TestFlight yüklemesi veya gerçek cihaz testi değildir.
- Firebase iOS Cloud Messaging ekranında geliştirme/üretim APNs anahtarı ve sertifikası bağlı olmadığı görüldü. Kullanıcının talimatıyla müşterinin Apple anahtarlarına erişilmeyecek; bireysel hesap sahibinin yapacağı anahtar işlemleri müşteriyle yürütülecek. Apple Developer portalında görülen farklı ekip üzerinden işlem yapılmadı.
- İmzalama/provisioning ve production push entitlement doğrulaması, Apple ürünleri/fiyatları/inceleme bilgileri, satın alma anahtarları, sunucu Billing ayarları ve Server Notifications bağlantısı hâlâ bekliyor. Mağaza build geçmişi ve build numarası yüklemeden önce kontrol edilmeli. App Store ekranında mevcut taslak 1.0 olduğundan hazırlanacak 2.1.2 paketiyle sürüm eşleşmesi de tamamlanmalı.
- Mağaza metinleri, görseller, kategori, yaş/gizlilik beyanları, inceleme hesabı ve sözleşme/vergi/banka durumları tamamlandı sayılmaz. Bildirim teslimi, satın alma/geri yükleme ve fiziksel cihazda konum testleri yapılmadı; yayın hazır değil.
- Backend ve Windows sunucusu değiştirilmedi; SMS beklemede. Sonraki backend işi önceki backend Codex sohbetinde yapılmalı: `Billing:AppleBundleId` gerçek mağaza kimliğiyle, `Billing:AppleAppId` 6824034438 ile eşleştirilmeli; Apple anahtar/güven kökleri ve sandbox/etkinlik ayarları mevcut ayarlar korunarak bağlanmalı. Ayrıntılar `docs/ODEME_KURULUMU.md`; anahtarlar sohbete veya Git'e konulmamalı.


### 69. iOS APNs, mağaza ürünleri ve yayın hazırlığı — 21 Ekim 2026

- Kullanıcının belirttiği yerel APNs dosyası, ayrıca alınan yükleme onayıyla mevcut Firebase iOS uygulamasına üretim anahtarı olarak yüklendi; Firebase tablosunda kayıt doğrulandı. Özel anahtar içerikleri okunmadı, sohbete/Git'e veya uygulama paketine eklenmedi. Bu işlem gerçek iPhone bildirim teslimi testi değildir; geliştirme APNs bağlantısı ayrıca bekler.
- Kullanıcı yalnız Türkiye satışını ve mevcut mobil katalogdaki fiyatları onayladı. Premium grubu, aylık/yıllık ürünler ve 5/15 kredi tüketilebilir ürünleri App Store Connect'te oluşturuldu. İki planın fiyatları/Türkçe açıklamaları ve Türkiye satış seçimleri, 5 kredi fiyatı/açıklaması/Türkiye satışı kaydedildi. 15 kredi Türkçe açıklaması kaydedilirken Apple ekranı beklemede kaldı ve oturum kapandı; son durum yeniden kontrol edilmeli. 40 kredi henüz oluşturulmadı. Ürünler incelemeye gönderilmedi.
- Alt başlık ve Business kategorisi kaydedildi. Kullanıcının isteğiyle aynı sahibin Asfaltik inceleme iletişim alanları okundu; Asfaltik değiştirilmedi. Şantiye Ağı'na aktarım ve diğer mağaza metinleri Apple oturumu yeniden açılınca yapılacak. Giriş bilgilerini kullanıcı kendisi girecek.
- Canlı auth seçenekleri HTTPS GET ile salt okunur kontrol edildi: SMS zorunlu değil ve parolalı giriş açık. Yeni kullanıcı kaydı veya inceleme hesabıyla giriş testi yapılmadı; SMS/üretim doğrulama ayarı değiştirilmedi.
- Varsayılan 1 piksel boş iOS açılış görselleri mevcut uygulama ikonunun aynısıyla değiştirildi; storyboard merkezde 160 punto boyutlandırıldı. Uygulama içi tasarım/özellikler korunur. İlk arşivdeki açılış şablonu uyarısı ikinci başarılı arşivde giderildi.
- Canlı API/push ayarlarıyla imzasız iOS arşivi başarılı: 2.1.2+11, iOS 15, doğru Bundle ID ve Firebase plist. İmzalı IPA, TestFlight yüklemesi, Apple inceleme gönderimi, satın alma/geri yükleme ve gerçek cihaz bildirim/konum testleri yapılmadı. Önceki Flutter analiz/233 test sonucu geçerlidir; bu tur Dart kodu değiştirilmedi.
- Ürün ID/fiyatları, gerçek mağaza kayıtları, hazır yayın metinleri, gizlilikte teyit gerektiren noktalar ve önceki backend sohbetine aktarılacak Apple Billing işi `docs/IOS_YAYIN_HAZIRLIK_2026-10-21.md` dosyasında. Backend/Windows değişikliği yapılmadı. Apple satın alma anahtarı ve sunucu yapılandırması hâlâ bekliyor; APNs anahtarı bu amaçla kullanılmaz.


### 70. App Store metinleri, beş ürün ve müşteri imzalama talimatı — 21 Ekim 2026

- Apple oturumu yeniden açıldıktan sonra 15 kredi açıklaması/Türkiye satışı doğrulandı; 40 kredi tüketilebilir ürün 549,99 TL ile oluşturuldu. Beş ürünün onaylanan fiyatları, Türkçe açıklamaları ve yalnız Türkiye satışı kaydedildi. Premium grubun Türkçe adı doğrulandı. Aylık/yıllık aynı grupta fakat farklı seviyelerde; aynı haklar için seviye düzenlemesi sürükleme denemeleriyle tamamlanamadı ve beklemede bırakıldı.
- iOS mağaza taslağı 2.1.2 yapıldı. Açıklama, tanıtım, anahtar kelimeler, web/destek, copyright ve kullanıcının talimatıyla Asfaltik’ten alınan inceleme iletişimi kaydedildi; diğer uygulama değiştirilmedi. Hesap giriş bilgilerini kullanıcı sonra girecek. Uygulama ücretsiz, satış yalnız Türkiye; 18+ yaş derecelendirmesi ve içerik hakları kaydedildi.
- Apple üretim/sandbox sunucu bildirim adresleri mevcut doğrulama ucuna kaydedildi. Bu işlem canlı bildirim teslimi veya satın alma doğrulama testi değildir. Backend ve Windows sunucusu değiştirilmedi; Apple Billing kurulumu önceki backend sohbetinde tamamlanacak.
- Gizlilik URL’si ve 13 veri türü seçildi; 11 türün işlevsellik/bağlantılı/izleme yok yanıtları kaydedildi. Gemini’ye gidebilen yaklaşık konum/diğer kullanıcı içeriği amaçları, gerçek Google projesinin ücretli faturalandırma ve veri kullanım koşulları doğrulanana kadar bekler. Kullanıcının olası faturalandırma bilgisi kesin teyit sayılmadı. Beyan yayımlanmadı.
- TestFlight açıklaması, iletişim, web adresleri ve inceleme notları kaydedildi. No Builds görüldü; imzalı IPA ve test dağıtımı yok. Beta inceleme hesabı/giriş zorunlu seçimi, mağaza ekran görüntüleri ve ürün inceleme görselleri hâlâ eksik.
- Mac’te bu uygulamaya ait dağıtım profili bulunamadı. Müşterinin Push Notifications etkin App Store Connect profilini doğru mevcut sertifikayla oluşturması ve ayrı satın alma sunucu anahtarını güvenli hazırlaması için MUSTERI_IOS_PROFIL_TALIMATI_2026-10-21.md yazıldı. Anahtar içeriği okunmadı veya Git’e eklenmedi; müşterinin anahtar ekranına girilmedi.
- Önceki analiz/233 test ve imzasız arşiv sonucu geçerlidir; bu tur uygulama kaynak kodu değişmedi. Gerçek cihaz push/satın alma/geri yükleme/konum testleri ve Apple hesap sözleşme/vergi/banka durumu tamamlandı sayılmaz. SMS beklemede, yayın henüz hazır değil.


### 71. Müşterinin yeni fiyatları mağazaya ve mobil tahmini fiyatlara işlendi — 21 Ekim 2026

- Kullanıcı müşterinin son fiyatlarını uygulamamızı onayladı. App Store Türkiye fiyatları aylık 199,00 TL, yıllık 1.599,99 TL, 15 kredi 149,00 TL, 40 kredi 419,99 TL olarak kaydedilip her ürünün fiyat ayrıntısından doğrulandı. Yıllık 1.600 TL ve 40 kredi 420 TL istekleri, Apple’da bulunan birer kuruş düşük seçeneklerle uygulandı. 5 kredi 99,99 TL değişmedi; yalnız Türkiye satış seçimi korundu.
- Mobil uygulamanın mağazaya ulaşılamadığında gösterdiği tahmini/demo fiyatları aynı tutarlara eşitlendi. Gerçek satın alma fiyatı mağaza verisinden okunmaya devam eder. Backend/Windows ve Google Play Console fiyat ayarları değiştirilmedi.
- Gelen müşteri dağıtım profilinin doğru uygulama, ekip ve mevcut yerel sertifikaya ait olduğu doğrulandı; `aps-environment` alanı bulunmadığından bildirim yetkisi içeren yeniden oluşturulmuş profil bekleniyor. Gelen yeni satın alma adayı `.p8` dosyasının içeriği açılmadı, türü/Issuer ID henüz teyit edilmedi.
- Flutter analizi temiz; satın alma doğrulama kuyruğunun hesap ayrımı/eşzamanlılık/kayıt koruma kapsamındaki 3 testi başarılı. Yayın için imzalama, Apple Billing sunucu kurulumu, gizlilikte Gemini teyidi, inceleme hesabı/görselleri, abonelik seviyeleri ve cihaz testleri hâlâ bekler. SMS beklemede.

- Yeni fiyatlarla canlı API/push tanımlı imzasız iOS arşivi yeniden başarılı: 2.1.2+11, 195,2 MB; App Settings Validation geçti. İmzalama yapılmadı, IPA/TestFlight yüklemesi yok.


### 72. Abonelik seviyeleri, canlı gizlilik sitesi ve inceleme hazırlığı — 21 Ekim 2026

- Kullanıcının Safari'de sürükleme desteğiyle aylık ve yıllık aynı seviye 1'e alındı; kaydedilip sayfa yenilenerek kalıcılığı doğrulandı. İki planın hakları aynı kalır; gerçek plan geçişi TestFlight testi bekler.
- Müşterinin GitHub Pages gizlilik adresi Safari'de açıldı. 20.10.2026 tarihli Gemini/konum/FCM/satın alma/hesap silme/yedek açıklamaları mevcut; kullanım koşulları ve hesap silme bağlantıları da var. App Store'da doğru adresler zaten kayıtlı. Sitede sabit eski ücret bulunmadığından gereksiz web değişikliği yapılmadı. Gemini planı yine sunucu/proje teyidi bekler.
- Windows/backend işini önceki sohbette yürütmek için BACKEND_IOS_YAYIN_GOREVI_2026-10-21.md hazırlandı: gerçek uygulama kimlikleri, son fiyat/ürünler, satın alma anahtarının türü ve Issuer ID teyidi, güvenli aktarım, Apple güven kökleri, test ortamı/sandbox izolasyonu, Apple V2/verify/sync, Gemini veri kullanımı ve iOS push kontrolleri. Bu sohbet backend veya Windows ayarlarını değiştirmedi.
- Ayrı oluşturulan iPhone/iPad simülatörlerinde, yalnız yerel örnek hesap ve uygulamanın Örnek etiketli verileriyle gerçek arayüz görüntüleri alındı; canlı API'de hesap/ilan oluşturulmadı. Kaynak tasarım korunur. Yerel çıktılar output/mobile/app-store-2026-10-21 altında, Git dışında tutulur. TestFlight dağıtımı/gerçek mağaza satın alımı/gerçek cihaz bildirimi değildir.
- İnceleme sırasında mağaza ürünleri henüz dönmemişken sabit yüzde 30 tasarruf gösterildiği görüldü. Doğrulanmış mağaza fiyatı yoksa yüzde rozeti gösterilmez; Premium ve kredide fiyat alınmadığında tahmini olduğu açıklanır. StoreKit erişilebilir ama ürün sorgusu boşken de uyarı görünür. İlgili arayüz regresyon testi eklendi. Tam Flutter turu 234 başarılı, ayrı yerel API isteyen 2 atlandı; analiz temiz. Güncel canlı API/push tanımlı imzasız arşiv 2.1.2+11 başarılı; imzalı IPA üretilmedi.

- Mağaza Media Manager'a iPhone orta/büyük ve iPad 13 için beşer görsel yüklendi; her grupta 5/10 görüldü. Aylık/yıllık referans inceleme görselleri ve notları kaydedildi. Kredi 5/15 görsel/not kalıcılığı doğrulanamadı; son ekranda boş not/etkin Save görüldüğünden tamamlandı sayılmadı. Kredi 40 işlemi başlamadı. Hiçbir ürün incelemeye gönderilmedi.
- Kullanıcı token bütçesi nedeniyle diğer hazırlıkları durdurup not almamızı istedi. Ayrıntılı son durum, açık ekran, dosyalar, profil tekrar kontrolü ve devam sırası MAC_IOS_DEVAM_2026-10-21.md dosyasına kaydedildi; kalan yayın işi durduruldu.


### 73. Yeni push profili ve imzalı iOS paketi — 21 Ekim 2026

- Müşterinin son gönderdiği profil doğru uygulama/ekip/sertifikayla eşleşiyor ve üretim bildirim yetkisini içeriyor. Profil eksikliği çözüldü; özel anahtar içerikleri açılmadı.
- 2.1.2+11 imzalı arşiv ve IPA üretildi. Son paketin imzası, üretim push yetkisi ve gömülü profili doğrulandı. Yerel paket `output/mobile/ios-app-store-2026-10-21/signed/santiye_agi.ipa`; Git'e alınmadı. Geçici imzalama proje ayarları geri alındı.
- Xcode otomatik yüklemesi müşteri Developer ekip hesabı bulunamadı hatasıyla durdu; bu, App Store Connect yükleme yetkisinin olmadığına dair kesin sonuç değildir. Alternatif Transporter lisansı ayrıca kullanıcı onayıyla kabul edildi; giriş beklenirken kullanıcı yüklemeyi şimdilik bekletti. TestFlight yüklemesi yapılmadı.
- 40 kredi inceleme alanları da denendi; Apple görseli Processing durumunda bıraktı, Save sonrasında not kalıcılığı doğrulanamadı. 5/15/40 kredi inceleme alanları henüz tamamlanmadı. Safari oturumu da yeniden giriş istiyor. Ürün veya sürüm incelemeye gönderilmedi.
- Backend'e iletilecek görev ve devam notları güncellendi. Backend/Windows değiştirilmedi; SMS beklemede. Gemini gizlilik teyidi, satın alma sunucu kurulumu, inceleme hesabı ve gerçek cihaz testleri yayından önce tamamlanmalı. Bu tur uygulama kodu değişmedi; önceki temiz analiz ve 234 başarılı/2 atlanan test sonucu geçerli.

### 68. Mac iOS görevi ve Apple/Firebase/Gemini sunucu kontrolü — 21 Ekim 2026

- Mac'in `main` değişiklikleri `e3013f2`'ye fast-forward ile alındı; yerel çalışma kaybı veya force push yok. Gerçek iOS kimliği `com.yusuftaskiran.santiyeagi.pro`, Apple App ID `6824034438`, hazır IPA/TestFlight bekleme durumu korundu.
- Canlı API ready=200, SMS zorunluluğu kapalı, parolalı giriş açık. Korumalı yerel hesapla gerçek giriş/profil ve etkin AI seçenekleri doğrulandı; kimlik bilgileri yazdırılmadı. Hesap `phone_verified=false`; satın alma kodunun PhoneVerified şartı korunuyor. SMS açılmadı; yeni hak tanımlanmadı.
- Apple callback CONFIG/503; In-App Purchase anahtarının amacı, Issuer ID, güvenli Windows aktarımı ve etkin dış ayarlar doğrulanmadan hazır sayılmadı. Firebase konsolunda doğru iOS kaydı/FCM v1/production APNs anahtarı görüldü. Yerel servis hesabı ve Android projesi eşleşiyor; canlı servis hesabı dosyası doğrudan okunamadı.
- Salt okunur IIS ayar kontrol betiği ve yalnız resmî Apple TEST bildirimi gönderen CLI/wrapper eklendi. Sırlar, test tokeni, JWT/JWS çıktıya alınmaz; eski DLL'de komut yanlışlıkla sunucu başlatmasın diye paket yetenek/DLL hash kontrolü yapılıyor. Gerçek Apple TEST çağrısı anahtar/Issuer ve kurulum eksikleri yüzünden yapılmadı.
- Kontrolsüz canlı AllowSandbox açılmadı. Ayrı IIS/API, DB, ayar ve oturum/anahtar alanı planlandı; önerilen sandbox URL'si henüz kurulmuş değil. Mac mevcut IPA'nın API hedefinin otomatik değişmeyeceği konusunda bilgilendirildi.
- Gerçek Gemini anahtar projesi ve o projedeki aktif Billing doğrulanamadı; görünen başka Free tier/Spark projeleri kanıt sayılmadı. Uygulama kodunda prompt/cevap DB/log yazımı görülmedi; sağlayıcı planı ve haricî günlükler teyit bekliyor. Web/Apple formuna sahte ücretli-plan teyidi verilmedi.
- 140 API testi yerel izole PostgreSQL ile başarılı; son küçük polling düzenlemesinden sonra Apple testlerinin 23'ü tekrar geçti. Salt okunur PS fixture/sır sızmaması ve script sözdizimleri geçti. Canlı sunucu ayarı değiştirilmedi. Ayrıntılı hazır/eksik/gerçek işlem bekleyen ayrımı `BACKEND_IOS_YAYIN_SONUC_2026-10-21.md` içinde.

### 69. iOS kontrol araçlarının IIS paketi hazırlandı — 21 Ekim 2026

- `9328621` kaynağından yeni IIS paketi üretildi: `output/ios-backend-audit-20261021/SantiyeAgi-Backend-IIS.zip`, 30.404.432 bayt; SHA-256 `AE379CF01C99204ABC8573421D3FC3EA9DFFD0BEC0D528D9615212F32D1E33C3`. Aynı hash'i bekleyen kısa güncelleyici hazır. Özel anahtar veya üretim ayarı paketlenmedi.
- Paket DLL/yetenek hash'i eşleşti; paketlenmiş Apple CLI Billing kapalı yerel fixture ile CONFIG/503 döndürüp güvenli kapandı. Paket canlı sunucuya kurulmadı; anahtar/Issuer/proje teyit eksikleri raporda açık. Salt okunur `kontrol.ps1` kuruluma gerek olmadan mevcut sunucuda çalıştırılabilir. Yerel test PostgreSQL'i durduruldu.

### 74. Windows raporu ve satın alma anahtarının erişim kontrolü — 21 Ekim 2026

- Kullanıcı Windows'ta Firebase sunucu hesabının santiye-agi ile eşleştiğini, Gemini'nin etkin, Apple Billing'in kapalı ve Apple alanlarının yapılandırılmamış olduğunu bildirdi. Sunucuda bu sohbet tarafından işlem yapılmadı. Gemini'nin etkinliği ücretli faturalandırma/veri kullanım koşullarının kesin teyidi sayılmadı.
- Safari'ye yeniden girişten sonra müşteri hesabının Integrations ekranında yalnız Shared Secret görüldü; In-App Purchase anahtarı ve Issuer ID görüntülenemedi. Mevcut dosya adı anahtar türünü ispatlamaz; özel anahtar içeriği açılmadı. Müşteriden doğru bölümdeki Key ID/Issuer ID ve anahtar türü teyidi gerekiyor.
- Kullanıcının talimatıyla TestFlight yüklemesi ve SMS beklemede. Kimlikler doğrulandıktan sonra Windows yapılandırması önceki backend sohbetinde yapılacak.

### Apple satın alma anahtarı için kontrollü kurulum — 21 Ekim 2026

- Kullanıcının sunucuda çalıştırdığı rapor Firebase proje eşleşmesini doğruladı; Apple Billing hâlâ kapalı ve ayarları boş. Yeni Key ID/Issuer alındı; özel anahtar Mac'te, güvenli Windows aktarımı bekliyor. App Manager yazısı yetki kanıtı sayılmadı.
- Resmî Apple API'sine gerçek erişimi sınayan, ancak başarılı yanıttan sonra mevcut ayarlara Apple bağlantısını birleştiren kurulum aracı hazırlandı. Sırlar, JWT ve test belirteci çıktıya alınmaz. Eski DLL, yetkisiz anahtar veya ağ hatasında Billing açılmaz. Test isteği para harcamaz/hak tanımlamaz; callback teslimi ve gerçek satın alma ayrı kontrollerdir.
- 24 Billing birim testi başarılı. SMS'siz giriş çalışsa da doğrulanmamış inceleme hesabına satın alma hakkı verilemiyor. Üretimde telefon doğrulaması atlatılmadı; PhoneVerified koşulu korundu. SMS/TestFlight açılmadı. Gerçek Apple anahtar isteği ve IIS kurulumu henüz yapılmadı; kullanıcı dosya aktarımı/komut çıktısı bekleniyor. Ayrıntılar APPLE_BILLING_KURULUM_2026-10-21.md içinde.

### Apple kurulum paketi teslimi — 21 Ekim 2026

- Kaynak commit 2c773cd; paket output/apple-billing-20261021/SantiyeAgi-Backend-IIS.zip (30.411.404 bayt). SHA-256: D520CE693B6379DBBA8A9F6AAEE1A9900A3E519494F1800E4ADC85E91655E2DC. ZIP ile birlikte hash'e bağlı guncelle.ps1 ve kısa apple.ps1 hazırlandı. Özel anahtar veya üretim ayarı pakette yok.
- apple.ps1 anahtar aktarılmadan durur; sonrasında mevcut yedekli güncelleme, gerçek yetki kontrolü/başarılıysa kurulum ve bağımsız callback teslim kontrolünü sıralar. Canlı kurulum/Apple isteği kullanıcı komutu bekliyor; başarılı yapılmış gibi işaretlenmedi.
- PowerShell 5.1 ve 7 salt okunur fixture/sözdizimi kontrolleri geçti. Unicode dosya yollarındaki JSON için UTF-8 açık okuma eklendi. API derlemesi başarılı, 24 Billing testi geçti; yapılandırmasız yeni CLI CONFIG/503 ve çıkış 1 ile HTTP sunucusu/DB başlatmadan durdu. DLL yetenek hash'i ve paket kaynak kimliği doğrulandı.

### Canlı Apple kurulumunda durma ve güvenli tanı — 21 Ekim 2026

- Kullanıcı yeni paketi sunucuda çalıştırdı: 25 tabloluk yedek/ayrı test DB geri yükleme başarılı, migration güncel, API yeniden açılmış. Apple erişim isteği aşamasında durdu; Apple ayarları kaydedilmedi. Bu çıktı anahtarın kesin yanlış olduğunu kanıtlamaz. Paket güncelleyicideki genel AI mesajı mevcut Gemini ayarının kapatıldığının kanıtı değildir.
- Kurulum aracına yalnız kontrol seçeneği, JSON'u alan bazında okuma ve güvenli hata sınıfı/çıkış kodu eklendi. Windows PowerShell 5.1'in yönlendirilmiş native stderr çıktısı kontrolü erken kesmesin diye bellekte yakalanır; ham çıktı, JWT, özel anahtar gösterilmez. Bu davranışın önceki hatanın nedeni olduğu henüz doğrulanmadı.
- output/apple-billing-20261021/apple-kontrol.ps1 tek dosyalık teslimi varsayılan olarak yalnız kontrol yapar; mevcut kurulu DLL/inspector kullanılır, güncelleme tekrarlanmaz, Billing ayar dosyası yazılmaz. Windows PowerShell sözdizimi/fixture kontrolü başarılı. Gerçek Apple sonucu yeni kullanıcı çıktısını bekliyor; SMS/TestFlight beklemede.

### Apple CONFIG ayrımını yapan bağımsız tanı — 21 Ekim 2026

- Kullanıcının ikinci çıktısında gerçek CLI CONFIG/çıkış 1 döndü. Bu kod yerel anahtar okuma/format hatası ile Apple 401/403 yanıtını ayırmadığı için anahtarın yanlış olduğu ileri sürülmedi. Önceki SAFE_JSON_YOK etiketi başarısız fakat geçerli hata JSON'unda da görünüyordu; düzeltildi.
- DB/IIS/ayar dosyalarından bağımsız .NET 10 tanı aracı eklendi. Yalnız belirtilen P8'i okur, P-256 özel anahtar imzasını üretir ve bu uygulama için resmî Production TEST isteği gönderir. Çıktı sabit hata sınıfı, aşama ve gerçek HTTP koduyla sınırlı; özel anahtar/JWT/Apple gövdesi/test belirteci loga veya sohbete alınmaz. Ağ/TLS/zaman aşımı ayrı sonuç verir.
- Yerel HTTP sahteleriyle 6 test geçti: doğru uygulama/Issuer/Key ID ve ES256 imzası, 200/401/403/429/500 ayrımı, bozuk anahtarda ağ isteği yapılmaması ve sır sızmaması. Derleme başarılı; eksik dosya CLI kontrolü KEY_FILE_MISSING döndü. Gerçek Apple yetkisi hâlâ Windows çıktısı bekliyor.
- Tek dosya teslim output/apple-probe/apple-tani.ps1 (29.544 bayt). İçine yalnız açık derlenmiş program ve çalışma tanımları gömülüdür; özel anahtar yok. Sunucuda C:\ProgramData\santiye içine kopyalanıp powershell -ep bypass -File C:\ProgramData\santiye\apple-tani.ps1 çalıştırılır. Mevcut ZIP/güncelleme tekrarlanmaz. Geçici program dosyaları yönetici/SYSTEM erişimiyle oluşturulup silinir; Billing, SMS, TestFlight değişmez.

### Gerçek Apple yanıtı: 401 — 21 Ekim 2026

- Kullanıcı bağımsız tanı aracını sunucuda çalıştırdı: APPLE_HTTP / APPLE_AUTH_REJECTED / HTTP 401 / ApiErisimiDogrulandi=false. Dosya okuma ve P-256 imzalama aşamaları geçildi; gerçek Production Apple API kimlik doğrulaması başarısız. Billing hâlâ etkinleştirilmedi. SMS/TestFlight değişmedi.
- Kesin neden yalnız 401 ile ayrıştırılamaz: In-App Purchase yerine App Store Connect API anahtarı kullanılması, P8–Key ID–Issuer/ekip/bundle eşleşmemesi, iptal edilmiş anahtar veya sunucu saat sapması kontrol edilmeli. Access: App Manager ifadesi anahtarın türünü kanıtlamaz. Önce Mac'te Users and Access > Integrations > In-App Purchase ekranında CY8L78UR5Q aktifliği ve indirilen dosya eşleşmesi doğrulanmalı; eski anahtarlar körlemesine iptal edilmemeli.
- Resmî belge satın alma Server API anahtarının In-App Purchase bölümünden alınmasını ister: https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests . Gerçek özel anahtar/JWT/Apple yanıt gövdesi paylaşılmadı; hak tanımlanmadı. Kontrol tamamlanmadan bağlantı hazır sayılamaz.

### Apple 401'in varsayım yapmadan ayrıntılı incelenmesi — 21 Ekim 2026

- Müşterinin anahtarının yanlış olduğu sonucuna varılmadı. Önceki gerçek ölçüm yalnız aday dosyayla Production Apple API'nin 401 döndürdüğünü kanıtlıyor. SHA-256, etkin IIS dosya seçimi ve sunucu saat farkı önceki çıktılarda yok; uzaktan doğrudan dosya/saat erişimi bulunmuyor.
- Kaynak JWT alanları/ES256-P1363/300 saniye süre ve Apple adresi resmî belgelerle karşılaştırıldı; bağımsız kod incelemesinde de belirgin hata bulunmadı. Canlı Billing ayarının boş kalması, dış ayarlardan bağımsız aday dosya testinin 401 sebebi olarak sunulmadı.
- Tek dosyalık output/apple-probe/apple-detay.ps1 (54.336 bayt) hazırlandı. Verilen SHA-256 ile aday dosyayı, etkin dosya/ID eşleşmesini, incelenen DLL hash'ini, gerçek JWT'nin yerel açık anahtarla imzasını/alanlarını ve Apple HTTPS Date'e göre yaklaşık saat farkını ayrı raporlar. HTTP yönlendirmesi kapalı; özel anahtar/JWT/yanıt gövdesi yazdırılmaz. Ayarlar okunur, değiştirilmez; SMS/TestFlight/anahtar iptali yapılmaz.
- 9 tanı testi başarılı; özet uyuşması/uyuşmaması, 200/401 ayrımı, JWT imzası/alanları, sentetik 900 saniye saat farkı ve sır sızmaması kontrol edildi. PowerShell 5.1 ayrıştırma, eksik IIS ve sentetik ayar önceliği kontrolleri geçti. Derleme başarılı. Gerçek sunucu özeti/saat ve kesin kök neden kullanıcı çıktısını bekliyor; APPLE_401_INCELEME_2026-10-21.md ayrıntılı raporu hazır.

### Dosya/saat/JWT doğrulandı; Production yayın öncesi erişim ayrımı — 21 Ekim 2026

- Gerçek Windows raporunda SHA-256 birebir eşleşti, kurulu DLL incelenen paketle aynı, JWT alanları ve yerel imzası doğru (64 bayt/300 saniye), Apple saatine fark ölçüm hassasiyetinde 0 sn (RTT 627,4 ms). IIS ayar dosyası değişmemiş; Billing ve Apple alanları kurulumun kaydedilmemesi nedeniyle kapalı/boş. Production hâlâ 401. Müşteri anahtarı yanlış denmedi.
- Apple mühendisinin resmî forum yanıtında ilk üretim yayınına kadar Production API erişiminin kapalı olabildiği bulundu: https://developer.apple.com/forums/thread/806452 . Önceki yalnız Production başarısını zorunlu kılan kurulum kapısı yayın öncesinde fazla kısıtlayıcı olabilir. Bu uygulamanın 401 nedeni henüz kesinleştirilmedi; Sandbox kabulüyle ayrıştırılacak.
- Tek dosya apple-sandbox.ps1, yalnız Sandbox bildirim geçmişine son 60 saniye için okuma isteği yapar. Callback/satın alma/test hakkı üretmez; AllowSandbox/SMS/TestFlight/IIS/ayar değişmez. JWS/gövde/JWT yazdırılmaz. 10 yerel tanı testi ve derleme başarılı. Gerçek Sandbox cevabı kullanıcı çıktısını bekliyor. Ayrıntılı rapor güncellendi; anahtarlar iptal edilmedi.

### Gerçek Sandbox kabulü ve yayın öncesi Apple kurulumu — 21 Ekim 2026

- Kullanıcının sunucudaki gerçek Sandbox geçmiş isteği HTTP 200 döndü; aynı P8 özeti/Key ID/Issuer/Bundle ve doğru JWT ile ApiAccessVerified=true. Saat farkı yaklaşık 0,1 sn. Anahtarın bu uygulama için Sandbox yetkisi doğrulandı. Production 401 ilk yayın öncesi kısıtla uyumlu, Production kabulü henüz kanıtlanmış değil.
- Önceki yalnız Production başarısını zorunlu kılan kurulumun ön yayın engeli düzeltildi. Yeni apple-kur.ps1 gömülü program hash'ini, sabit kimlikleri ve P8 özetini kontrol edip yeniden Sandbox salt okuma yetkisi ister; ancak tam başarılı kayıt/çıkış 0 sonrası Apple ayarlarını kaydeder. Production AllowSandbox=false, SMS/PhoneVerified ve diğer mevcut ayarlar korunur. IIS yeniden başlatıldıktan sonra etkin ayarlar ve HTTPS hazır durumu kontrol edilir.
- Tek dosya output/apple-probe/apple-kur.ps1 (65.344 bayt) hazır; yeni ZIP gerekmez. Bu komut ayar yazan kurulumdur, henüz kullanıcı sunucusunda çalıştırılmadı. Production TEST çağrısı, TestFlight veya gerçek satın alma yapılmaz. Ayrı Sandbox test ortamı ve doğrulanmamış inceleme hesabının PhoneVerified engeli açık madde olarak korundu.
- PS5.1 ve PS7 politika/birleştirme testleri geçti: geçerli yetki kabul, 13 başarısız/tip/adres/HTTP alanı reddi, Google ve tüm diğer ayarların korunması. Üretilen betik ve salt okunur fixture kontrolleri geçti; mevcut C# tanı testlerinin 10 başarılı sonucu geçerli. Belgeler gerçek ölçüm ve kurulum bekliyor ayrımıyla güncellendi.

### Gerçek sunucu kurulumu başarılı — 21 Ekim 2026

- Kullanıcı apple-kur.ps1'i Windows sunucusunda çalıştırdı. Yeni Sandbox okuma yetki kontrolü çıkış 0 ile geçti; Apple alanları ve Billing.Enabled kaydedildi, Production AllowSandbox=false kaldı. Betiğin başarılı son mesajına göre kayıt sonrası etkin ayar ve HTTPS ready kontrolleri geçti. Doğrudan uzaktan sunucuya erişildiği iddia edilmez; kanıt kullanıcının paylaştığı komut çıktısıdır.
- SMS/telefon doğrulama, Firebase, Gemini, Google ve veritabanı ayarları korundu. SMS/TestFlight başlatılmadı, mevcut anahtarlar iptal edilmedi. Production API'nin ilk yayın sonrası kabulü ve gerçek makbuz/callback/satın alma akışı hâlâ doğrulanmış değil.
- Son durum: Apple bağlantı ayarlarının yayına hazırlık kurulumu tamamlandı; aynı anahtarın Sandbox API yetkisi gerçek HTTP 200 ile kanıtlandı. TestFlight satın almaları için ayrı Sandbox API/veritabanı ortamı ve doğrulanmamış inceleme hesabındaki PhoneVerified engeli açık kalıyor. Üretimde Sandbox makbuzu kabul edilmez. Telefon doğrulaması atlatılmadı.


### Mac mağaza kayıtları ve bağlı iPhone kontrolü — 21 Ekim 2026

- Main Windows sohbetinin son değişikliklerine fast-forward güncellendi; yerel çalışma kaybı yok. Backend/Windows bu sohbette değiştirilmedi. Windows raporundaki başarılı Sandbox yetki/ön yayın Billing kurulumu dikkate alındı; eski 401 üzerinden müşteri anahtarı yanlış iddiası yapılmaz.
- Aylık/yıllık abonelik ve 5/15/40 kredi ürünlerinin inceleme görselleri/notları taze Safari sayfalarında kalıcı doğrulandı. Önceki kredi kayıt belirsizliği çözüldü; gereksiz görsel yüklenmedi. İki abonelik seviye 1; iOS metin/iletişim alanları ve iPhone medium/iPad beşer görseli kayıtlı. Hiçbir ürün/sürüm incelemeye gönderilmedi.
- Kullanıcı iPhone 13'ü USB ile bağladı; cihaza erişim doğrulandı. Şantiye Ağı yüklü değil. Mevcut müşteri profili yalnız App Store dağıtımı içindir; USB kurulumu için Development/Ad Hoc profili yok. Kullanıcının backend hazır olana kadar TestFlight bekleme sınırı korundu. Gerçek push teslimi henüz test edilmedi; mevcut Asfaltik uygulaması değiştirilmedi.
- Gizlilikte yaklaşık konum/diğer kullanıcı içeriği Gemini gerçek proje/veri kullanım teyidini, inceleme giriş bilgileri Windows hesabını bekliyor. Son build/satın alma/geri yükleme ve yayın gönderimi yapılmadı. SMS beklemede; sırlar paylaşılmadı. Bu tur mobil kaynak değişmedi, önceki analiz/234 başarılı ve 2 atlanan test sonucu geçerli.

### iPhone tek cihaz push testi hazırlığı — 22 Ekim 2026

- Kullanıcı TestFlight uygulamasına giriş yaptığını ve anlık bildirimlerin açık göründüğünü bildirdi; sorularak hesabın test / Tuna Test olduğu açıkça teyit edildi. Bu bilgi önceki Mac notlarındaki “uygulama cihazda yüklü değil/TestFlight bekliyor” durumunu kullanıcı beyanı açısından günceller; gerçek iPhone teslimi henüz kanıtlanmadı.
- Uzak sunucuya komut/DB erişimi bu sohbetten doğrudan bulunmuyor; mevcut HTTP API cihaz listesi veya test gönderim ucu sunmuyor. Henüz canlı cihaz seçildiği veya FCM'ye istek gönderildiği iddia edilmez.
- output/ios-push-test/ios-bildirim.ps1 tek dosya aracı hazır. Kurulu incelenmiş API DLL hash'ini kontrol eder, IIS'in etkin dış ayarlarını yalnız okur ve Auth AccountLogin içinde benzersiz test bağını çözer. PostgreSQL işlemi READ ONLY: ilgili hesabın aktif oturumlu son iOS kaydı seçilir. Aynı tarihli belirsiz kayıt, başka hesap/platform, kayıtsız cihaz veya 1 saatten eski kayıt halinde göndermez. Token/anahtar/bağlantı bilgisi gösterilmez.
- Mevcut kurulu FcmPushSender ve GooglePushAccessTokenProvider kullanılır; tek işlem için bellekte yalnız bildirim metni “Şantiye Ağı — Bildirim testi” olarak değiştirilir. Aynı hesap/tek token guard'ı vardır; topic/condition/toplu hedef yoktur. DB'ye bildirim/outbox yazılmaz, worker toplu genişletmesi tetiklenmez. Sunucu ayarı, IIS ve SMS değiştirilmez; ayar hash'i sonunda kontrol edilir.
- İşlem kimliği 879ffe9b-cec5-4efb-9819-1c7e24c2c4af; korunmuş push-test-attempts kaydı aynı dosyanın tekrar çalıştırılmasının yeniden göndermesini engeller. Otomatik FCM tekrar denemesi yok; belirsiz ağ sonucunda gönderilmedi denmez. Çıktı yalnız hesap/cihaz UUID ve kayıt zamanı, FCM HTTP kodu, güvenli sonuç kodu/kabul bilgisidir. FCM kabulü iPhone'da görüntülenme kanıtı değildir.
- 3 anlamlı yerel test geçti: hesap/platform/son kayıt/tarih belirsizliği/eski kayıt guard'ı, mevcut FCM göndericisiyle tam test başlığı ve tek hedef/APNs verisi, ikinci istek/yanlış hedef/toplu hedefin engellenmesi. Derleme uyarısız, PS5.1 ayrıştırma başarılı. Eski kurulu paket DLL'leriyle izole runtime smoke eksik hesapta ACCOUNT_AMBIGUOUS ve sıfır FCM isteğiyle kapandı. Canlı hedef/FCM kabulü kullanıcı sunucu çıktısını bekliyor.
- Mac'in e506bf7 not güncellemesi fast-forward ile alındı; mevcut çalışmalar korundu. Yeni backend dağıtımı veya ZIP kurulumu gerekmez. Ön planda alert/sound kapalı tasarım nedeniyle görünür teslim testi uygulama arka plandayken yapılmalı.

### Gerçek iPhone bildirimi teslim edildi; StoreKit ürün sorgusu açık — 22 Ekim 2026

- Kullanıcı sunucuda ios-bildirim.ps1'i çalıştırdı. test hesabı (6cdadd60-f73f-494b-aa2d-7b59528bc4b2), son aktif iOS cihazı (4f9eb8a6-21ab-4cf5-843c-0dffb43993ac), kayıt 2026-10-21T21:59:03.213404Z. Tam bir FCM isteği, HTTP 200, FcmAccepted=true, SENT. Sunucu ayarları hash'i değişmedi. Kullanıcı “telefonuma geldi” diyerek gerçek iPhone görüntülenmesini doğruladı. SMS/anahtar/ayar değişikliği ve toplu gönderim yok. TestFlight uygulamasının telefonda kurulu/giriş yapılmış olduğu kullanıcı beyanıyla güncellendi; kurulu build sürümü bu tur doğrudan okunmadı.
- Yeni satın alma belirtisi “Bu ürün mağazada henüz tanımlı değil”. Kaynakta bu uyarı _products içinde istenen ürün yokken çıkıyor; queryProductDetails sonucu ürün sözlüğüne girmemiş. Apple'ın doğrudan hata mesajı veya backend makbuz hatası değil. Kesin neden henüz kanıtlanmadı: ürün ID/bundle, satış uygunluğu/lokalizasyon/fiyat, Paid Apps Agreement ve hesap storefront/sorgu hatası Mac tarafında incelenmeli.
- Mac devam notuna gerçek push kanıtı ve ürün sorgusu inceleme görevi eklendi. Ürünler daha önce oluşturulmuş; körlemesine yeniden oluşturma önerilmedi. Apple TN3186 esas alındı. Gerçek satın alma/makbuz doğrulaması, Sandbox izolasyonu ve PhoneVerified/inceleme hesabı hâlâ tamamlanmış sayılmaz. Bu tur uygulama/sunucu kodu veya mağaza ayarı değişmedi; yeni canlı bildirim gönderilmedi.


### Gerçek iPhone StoreKit katalog incelemesi — 22 Ekim 2026

- Main `625b690`'ye mevcut çalışmalar korunarak güncellendi; gerçek push tesliminin başarılı olduğu Windows notu okundu. iPhone'daki 2.1.2 (11) ve bundle doğrulandı.
- Kullanıcının yeniden açılışında StoreKit beş doğru ürün ID'sini istedi; boş ürün cevabı ve Flutter'da beş notFoundIDs doğrudan ölçüldü. Storefront TUR. Gerçek fiyatlar henüz gelmiyor; backend makbuz aşamasından önceki katalog sorunu.
- Beş ürünün ID/Türkçe bilgileri/güncel Türkiye fiyatları Apple sayfalarından doğrulandı. Ürünler silinmedi, yeniden oluşturulmadı veya incelemeye gönderilmedi. Paid Apps Agreement/banka/vergi durumu, Business sayfasının veri yükleme hatası nedeniyle kesinleştirilemedi; kullanıcı şu an hesap sahibinden kontrol alamıyor. Müşteri hatası olduğu iddia edilmedi.
- Mevcut build hata alanını kaydetmediğinden error=null varsayılmadı. Mobil kaynakta sonraki build için yalnız güvenli requested/returned/notFoundIDs/error source/code tanısı ve daha doğru hata mesajı hazırlandı. Sırlar, hesaplar veya makbuz günlüklenmez. Analiz temiz; yeni IPA/yükleme ve satın alma/geri yükleme yok. Tanı değişikliği katalog sorununun çözüldüğü anlamına gelmez.
- Ayrıntılı kanıt/erişim sınırı/devam sırası IOS_STOREKIT_URUN_SORGUSU_2026-10-22.md içinde. Backend/Windows değiştirilmedi; SMS açılmadı.

### İki web sitesi için IIS paketi ve ücretsiz DNS geçişi — 23 Ekim 2026

- Kullanıcı yalnız santiyeagi.com.tr ve asfaltik.com.tr adreslerini mevcut 45.59.70.198 sunucusuna taşımayı seçti; IP'yi ayrıca doğruladı. İki açık GitHub deposunun statik HTML içerikleri alındı. Şantiye tasarımı/JS/SVG korunarak yeni alan adı, yasal barındırma açıklaması ve siteler arası bağlantı uyarlandı. Asfaltik destek dosyası korundu, ana sayfada da açılacak kopya eklendi. Asfaltik kaynak destek e-postasının farklı yazımı belgede açık bırakıldı; müşterinin adresi varsayılarak değiştirilmedi.
- API'den ayrı SantiyeAgi-Web ve Asfaltik-Web IIS siteleri/havuzları için kurulum betiği hazırlandı. Dosyalar santiye-web/asfaltik-web altında ayrı sürüm klasörlerine yerleşir. Paket/dosya hash'i, yol/host/pool sahipliği ve korumalı tekrar kurulum kontrolü yapılır; IIS yapılandırma yedeği ve dört yerel HTTP içerik kontrolü vardır. Hata halinde yalnız kendi IIS değişikliklerini geri alır, dosya silmez. API/DB/SMS/bildirim/mağaza/HTTPS ayarları bu betikle değiştirilmez.
- output/web-migration-20261023/Web-Siteleri-IIS.zip: 22.588 bayt, 9 public dosya; SHA-256 cc16c8799126676a6b853462f3858eab156b485ddc40bc53bc04bfdad3b06f19. Yanındaki web-kur.ps1 bu hash ile hazır. 46 yerel paket/path/sahiplik/çakışma kontrolü ve Windows PowerShell 5.1 ayrıştırması geçti; gerçek teslim ZIP'i manifestiyle doğrulandı. İki site yerel tarayıcıda açıldı. Canlı IIS kurulumu/ACL/HTTP/HTTPS testi yapılmış sayılmaz; kullanıcı sunucu komutu bekleniyor.
- Natro A kaydı yönetimi ücretli hizmet istediği için satın alma yapılmadı. Kullanıcının kendi açık Cloudflare hesabında iki alan adı Free plana eklendi; A @=45.59.70.198, www CNAME=kendi kök alan adı, DNS only kaydedilip yeniden okundu. Mevcut SPF TXT aynen aktarıldı. İki alan adı için ayrı ayrı atanan pat.ns.cloudflare.com/thomas.ns.cloudflare.com Natro'ya kaydedildi; iki form da başarı yanıtı verdi. Cloudflare Pending ve 1.1.1.1 hâlâ eski Natro NS/park IP'sini gösteriyor: DNS yayılımı tamamlanmadı. .xyz veya diğer alan adları değiştirilmedi; üye daveti gönderilmedi. Müşteriye sonradan yalnız bu iki alan adı için Domain DNS kapsamı verilebilir.
- GitHub Pages kapatılmadı: kurulu mobil sürümler ve mağaza alanlarında eski github.io yasal bağlantıları var. Yeni IIS HTTPS açılınca mağaza/mobil derleme adresleri güncellenmeli; eski sürümler için yalnız yeni adrese hash koruyan geçiş sayfası tutulmalı. Şimdi Pages'i kapatmak eski gizlilik/hesap silme adreslerini bozar. Ayrıntılar docs/WEB_IIS_TASIMA_2026-10-23.md dosyasında. Sonraki adımlar sunucuda kısa kurulum komutu, DNS yayılımı ve mevcut API sertifikasını koruyarak yeni web sitelerine IIS HTTPS kurulumu.

### Web kurulumundaki dosya yazma hatası düzeltildi — 23 Ekim 2026

- Kullanıcının ilk sunucu denemesi sahiplik JSON kaydının File.Replace çağrısında durdu. Kurulum başarılı sayılmadı. Hata aynı biçimde Windows PowerShell 5.1'de ve boş yol mesajıyla PowerShell 7'de yeniden üretildi: düz $null, .NET string parametresine boş yol olarak bağlanıyordu. Betikteki bu satır gerçek CLR null sağlayan NullString.Value ile düzeltildi.
- Gerçek Save-StaticOwnershipRecord oluşturma, PREPARING→COMPLETE güncellemesi, sonraki yeniden deneme kaydı ve geçici dosyanın tüketilmesi regresyonları eklendi. Yalnız admin gerektiren ACL işlemleri izole test kapsamı içinde taklit edildi; JSON, File.Move, File.Replace ve kayıt okuması gerçektir. 50 yerel kontrol Windows PowerShell 5.1 ve PowerShell 7'de geçti. Canlı IIS davranışı veya yeni sunucu sonucu doğrulanmış sayılmaz.
- Teslim ZIP'i değişmedi; SHA-256 cc16c8799126676a6b853462f3858eab156b485ddc40bc53bc04bfdad3b06f19 yeniden kontrol edildi. output/web-migration-20261023/web-kur.ps1 yenilendi. Kullanıcı yalnız bu dosyayı sunucudaki dosyanın üzerine kopyalayıp aynı kısa komutu yeniden çalıştırır. Sahiplik kayıtları/release klasörleri silinmez; yarım PREPARING kaydı mevcut kontrollü yeniden deneme yoluyla korunur. API, DNS, SMS, veritabanı ve sertifika ayarı bu düzeltmeyle değiştirilmedi.

### İki web sitesi sunucuda HTTP ile kuruldu — 23 Ekim 2026

- Kullanıcı düzeltilmiş web-kur.ps1 sonucunu paylaştı: HTTP_READY, IIS yedeği StaticWeb-20261023-133326-d616c2c5, aynı tarihli ayrı release klasörleri. SantiyeAgi-Web ID 4 ve Asfaltik-Web ID 5 ayrı havuzlarla kuruldu. Kök/www olmak üzere dört yerel HTTP 200 ve index hash kontrolü geçti; sunucuda doğrudan oturum açıldığı iddia edilmez, bu kurulum kanıtı kullanıcı çıktısıdır.
- Bu sohbetten ayrıca 45.59.70.198 IP'sine dört ayrı Host başlığıyla dış HTTP istekleri yapıldı: hepsi HTTP 200 ve teslimdeki ilgili index.html SHA-256 özetiyle birebir eşleşti. Böylece port 80 üzerinden iki sitenin dışarıdan doğru ayrıldığı doğrulandı. Genel DNS çözümlemesi kullanılarak alan adıyla yayın henüz doğrulanmadı.
- Son 1.1.1.1 sorgusunda iki alan adı da eski Natro NS ve 85.159.66.93 park IP'sini gösteriyor. Her iki HttpsBindingPresent=false; DNS yayılımı/aktivasyon ve HTTPS bekliyor. Başarılı HTTP kurulumunu tekrarlamak gerekmez. API/DNS/Pages/sertifika ayarlarının kurulum betiğiyle değişmediği sonuçta raporlandı.
- Eski teslim belgesinde mevcut IP API sertifikasının Simple-acme ile yenilendiği bulundu. HTTPS devam planı yeni win-acme kurulumu yerine mevcut Simple-acme istemcisi/görevini koruyacak şekilde güncellendi; kesin EXE/görev yolu henüz sunucuda okunmadı. DNS tamamlanınca yalnız yeni site 4/5 ve dört hostname için SNI sertifika kurulumu yapılmalı; API'nin boş hostname/SNI kapalı IP bağlaması ve yenilemesi korunmalı. Bu tur sertifika değişmedi, GitHub Pages kapatılmadı.

### VatanSMS gerçek doğrulama kurulumu hazırlandı — 24 Ekim 2026

- Kullanıcı VatanSMS API bilgileri, SANTIYEAGI gönderici başlığı ve kendi test numarasını sağladı. Anahtar ve gerçek telefon numarası kaynak/Git/bu belgeye eklenmedi. Resmî VatanSMS.NET OTP belgesi mevcut adaptörün endpoint/payload biçimini doğruluyor; .com XML/SOAP servisine geçilmedi. Gerçek anahtar/gönderici sorgusu veya SMS henüz bu bilgisayardan yapılmadı.
- SMS kullanılabilirliği ile genel telefon zorunluluğu ayrıldı. Sağlayıcı açık ve yapılandırılmışken normal OTP akışı, mevcut parola/inceleme hesabının erişimini değiştirmeden denenebilir. Üretimde geliştirme kodu veya telefon doğrulama atlatması yok. Mevcut numara doğru kodla doğrulanır; farklı numara mevcut inceleme hesabına otomatik bağlanmaz.
- Salt okunur --sms-review-readiness aracı, tüm etkin parola/inceleme hesaplarının mevcut kullanıcılarında gerçek telefon doğrulaması ve tamamlanmış profil durumunu kontrol eder. PostgreSQL READ ONLY işlemi ve loglamayan bağlam kullanır; yalnız sayılar/boole sonuç döner. Doğrulanmamış bir inceleme hesabı varken genel SMS zorunluluğu açılmaz, PhoneVerified alanı doğrudan değiştirilmez.
- Sunucu kurulum betiği maskeli anahtar girişi, gerçek /senders yetki/gönderici ön kontrolü, korumalı yedek/atomik yazma, mevcut ayarların korunması, yalnız API havuzunun yeniden başlatılması ve etkin ayar/sağlık kontrolünü içerir. Bilinmeyen/çelişkili provider cevabı kabul edilmez. Stage mevcut giriş politikasını korur; Enable kayıtlı anahtarı tekrar istemeden salt okunur inceleme kontrolüyle çalışır. Sağlayıcı yanıt şeması resmî belgede verilmediğinden gerçek kabul/teslim kullanıcı sunucu çıktısını bekliyor.
- Tek alıcı test betiği normal request/verify uçlarını kullanır; otomatik yeniden SMS göndermez, kodu konsolda maskeli ister ve token/kod/telefonu ham olarak yazdırmaz. Sonuç inceleme hesabıyla eşleşme bilgisini yalnız boolean verir. SMS testinden sonra tüm inceleme hesapları hazırsa zorunluluk açılabilir; farklı hesap doğrulandıysa mevcut inceleme girişi korunarak durur.
- API/test projesi derlendi; yerel, kendisi oluşturulan santiye_test_* veritabanlarında tüm 167 backend testi geçti. Yeni gerçek OTP staging/aynı hesabın korunması/kodun tek kullanımı/inceleme bayrağı sorgusu entegrasyonu ve 12 salt okunur hazırlık birim testi dahil. PowerShell kurulum ve tek SMS test senaryoları sahte ağ/ACL sınırlarıyla kontrol edildi; gerçek IIS/VatanSMS/telefon teslimi yapılmış sayılmaz. Flutter kaynağı değişmedi; runtime sunucu ayarı mevcut istemci tarafından okunur. Kısa kurulum ve açık kalan gerçek kontroller docs/VATANSMS_KURULUM_2026-10-24.md içinde.
- Kaynak kod 30403a9/c592cf1 ile main'e gönderildi. output/vatansms-20261024 altında 30.433.012 baytlık SantiyeAgi-Backend-IIS.zip ve kısa sms-kur.ps1 hazırlandı. ZIP SHA-256 a0ad6bbdaa121f741ec46363e9581d999033ed98b81517a2cc69d330b67fddd9; 65 manifest dosyası ve yetenek/DLL özeti doğrulandı. PowerShell'de 130+35 yerel kontrol geçti; yayınlanmış DLL'nin yalnız yerel fixture ile salt okunur CLI smoke kontrolü tek JSON/çıkış 0 verdi. Gerçek API anahtarı pakete konmadı; sunucuda maskeli istenecek. Canlı kurulum ve kullanıcıya tek SMS teslimi hâlâ kullanıcı sunucu komutu bekliyor.

### Müşteriye temiz kaynak kod teslimi — 24 Ekim 2026

- Müşterinin düzenleyip geri gönderebilmesi için güncel Git kaynaklarından temiz ZIP hazırlandı. Flutter uygulaması, backend kaynakları, testler ve kurulum belgeleri birlikte bulunur. Paket, çalışma klasörünün tamamı kopyalanarak değil Git'in izlediği dosyalardan üretilir.
- Derleme klasörleri, APK/AAB/IPA, yayın paketleri, Git geçmişi, gerçek sunucu ayarları, servis hesabı dosyaları ve imza anahtarları teslim ZIP'ine alınmaz. Örnek yapılandırmalar kaynakta kalır; kaynak teslimi canlı sunucuya kurulum veya SMS'in etkinleştirilmesi anlamına gelmez.
- Yerel teslim yeri output/customer-source-20261024/Santiye_Agi_Temiz_Kaynak_2026-10-24.zip. ZIP dosya listesi izlenen kaynaklarla karşılaştırıldı; build/yerel ayar/imza anahtarı dosyaları için dışlama kontrolü yapıldı. Bu işlem uygulama davranışını değiştirmediğinden yeni uygulama derlemesi veya canlı test yapılmadı.

### Şantiye Akışı, İhale ve güvenlik eksikleri tamamlandı — 24 Ekim 2026

Mevcut yük, makine, malzeme ve personel ilanlarına dokunulmadı; yalnızca ekleme yapıldı. Değişikliklerin hepsi Türkçe metinlerle hazırlandı.

**1. İhale (ticaret) kuralları**
- İhaleye teklif verildiğinde telefon numarası kimseye gösterilmez. Yalnızca ihaleyi açan, teklif sahibi için "Telefon paylaşımını onayla" derse iki taraf birbirinin numarasını görebilir. Teklif vermeyen üçüncü kişiler diğer tekliflerin tutarını da göremez.
- Fiyat teklifinde açıklama zorunlu oldu (en az 15 karakter, küfür içeremez). Açıklamasız teklif kaydedilmez. Aynı kişi bir ihaleye bir kez teklif verebilir.
- İhaleye "teklif verme son günü" eklendi. Süre dolunca ya da ihaleyi açan "Teklif almayı bitir" deyince ihale teklif almaz.
- Yeni "En iyi teklifi seç" ekranı: teklifler en düşükten yükseğe sıralanır, en düşük teklif önerilir, ihaleyi açan kazananı seçer. Kazanan seçilince ihale "Verildi" olur, kazananla telefon paylaşımı otomatik onaylanır, diğerleri "Seçilmedi" işaretlenir.
- İhale listesi, ihale detayı, teklif verme ve ihale açma (müteahhit / şantiye şefi) ekranları eklendi. Ana sayfaya "Şantiye Akışı" ve "İhaleler" düğmeleri konuldu.

**2. Şantiye Akışı (sosyal)**
- Sade, beyaz zeminli, kartlar arasında bol boşluk bırakan, büyük düğmeli (Beğen, Yorum, İhaleyi gör) Instagram benzeri akış ekranı yapıldı. Meslek ve sektör seçimi akıştan değiştirilebilir.
- Yorum yazarken küfür varsa anında uyarılır ve gönder düğmesi kapanır; küfürlü yorum kaydedilmez.
- Her yorumda "Bu kişiyle çalıştınız mı? Evet / Hayır" sorusu zorunlu. "Hayır" denirse kanıt (fotoğraf veya açıklama) istenir; kanıtsız yorum kaydedilmez. Olumsuz yorum için kanıt yoksa yorum eskisi gibi incelemeye düşer.

**3. Güvenlik ve yasal**
- Küfür / argo listesi 100'den fazla Türkçe kelimeyle genişletildi. "a.m.k", "s.k", "s i k t i r", "s*ktir", "siiiktir", "s1kt1r" gibi harf sansürlü yazımlar da yakalanır. "sık sık", "sıkıntı", "götür", "alçak gerilim", "mal sahibi" gibi normal sözler engellenmez. İlan metinlerindeki eski süzgeç aynen duruyor.
- "Mesajlar 24 saat içinde silinir, hakaret yasaktır." uyarısı yorum, paylaşım, teklif, ihale, ihale açma ve engelleme ekranlarında hep görünür. Sözün tutulması için cihazdaki mesajlar 24 saat sonra gerçekten silinir.
- Engelleme artık sebep seçimi ve kanıt fotoğrafı olmadan yapılamıyor (profil, ilan detayı ve şikâyet ekranındaki "da engelle" seçeneği dahil). Kanıt fotoğrafı yalnızca bu cihazdaki güvenlik kaydında tutulur, karşı tarafa gösterilmez.

**4. Sabit listeler**
- Sektörler: İnşaat, Hafriyat, Altyapı, Nakliye, Mermer, Maden, Orman eklendi/düzenlendi (eski sektörler duruyor).
- Meslekler: Ustabaşı, Bekçi, güvenlik görevlisi, tüm operatör ve şoför türleri, ustalar, mühendisler, maden / mermer / orman meslekleri dahil 82 meslek gruplanarak listelendi. Personel ilanı rol listesi de genişletildi.
- Makineler: Tır, dorse, eklemli damper, hiyap, örümcek vinç, asfalt freze, TBM, orman ve mermer makineleri dahil 88 makine türü. Eski makine adları ve sıraları değişmedi, kayıtlı ilanlar aynen çalışır.

**Kontrol sonucu**
- flutter test: 326 test geçti (başlangıçta 234). flutter analyze: yalnızca eskiden var olan 2 uyarı kaldı. Yeni testler küfür süzgecini, yorum/ihale/engelleme kurallarını ve ekranları kontrol eder.
- Telefonda ya da emülatörde elle deneme yapılmadı; ekranlar yalnızca otomatik widget testleriyle kontrol edildi.

**Açık kalanlar (yapılmış sayılmaz)**
- Sunucu tarafı: ilan oluşturma doğrulaması (backend/SantiyeAgi.Api/Domain/ListingRules.cs) yeni makine ve rol adlarını kabul edecek şekilde güncellendi, ancak bu bilgisayarda .NET SDK olmadığı için derlenmedi ve backend testleri çalıştırılmadı. Yeni makine / rol seçenekleri ilan verirken kullanılmadan önce backend derlenip test edilmeli ve IIS'e yayınlanmalı; aksi halde sunucu yeni türleri reddeder. Not: eski sunucu zaten uygulamadaki 32 makine türünden yalnızca 10'unu kabul ediyordu; bu fark da aynı güncellemeyle kapanır.
- Şantiye Akışı, yorumlar, ihaleler, engelleme kayıtları ve kanıt fotoğrafları şimdilik yalnızca cihazda tutulur (sunucuya bağlı değil). Başka telefondaki kullanıcıların birbirinin ihale tekliflerini görmesi ve karşı tarafın gerçek telefon numarasının onay sonrası gösterilmesi için sunucu bağlantısı gerekir; şu an numara yalnızca örnek kullanıcılar için gösterilebilir. Mesaj / sohbet ekranı henüz yok (yalnızca 24 saat silme kuralı ve uyarı hazır).
- Küfür süzgeci kelime listesine dayanır; her yazımı yakalamayı garanti etmez, şikâyet ve inceleme akışı yine gereklidir. Yasal uyarı metinleri avukat onaylı değildir.
- Canlı IIS, mağaza veya gerçek telefonla kontrol yapılmadı.
