# Teklife göre kapsam durumu — 19 Ekim 2026

Esas alınan belge: yerel `output/pdf/Santiye_Agi_Ucret_ve_Yayin_Teklifi.pdf`, 13 Ekim tarihli iki sayfa. Yayın/küçük düzeltmeler ve .NET geliştirmesi, 2.500 TL indirimle toplam 12.500 TL. Önceki 15.000 TL'lik dört sayfalık belge esas alınmadı. Bu inceleme mevcut kod, teslim/kabul kayıtları ve canlı oturum seçenekleri üzerinden yapıldı; yeni bir uçtan uca test turu değildir.

## Kapsam karşılaştırması

| Teklif maddesi | Mevcut durum | Tamamlamak için gereken |
|---|---|---|
| Platform betikleri, demo ayarı, yazım/tarih ve iletişim metinleri; rapor 1, 2, 4, 14, 15, 16, 17, 18, 21 | Düzeltmeler ve mevcut turuncu simge uygulandı. İlk aşama kayıtları `BACKEND_ONCESI_DUZELTMELER.md` içinde. | Gerçek macOS ortamında platform/iOS doğrulaması yayın sırasında yapılacak. |
| .NET API/PostgreSQL; kullanıcı, ilan, teklif, anlaşma | Canlı IIS ve gerçek PostgreSQL bağlı. Beş ilan türü, gelen/giden teklifler, anlaşma ve durum değişimleri daha önce canlı API/emülatörle kontrol edildi. | Son sürümde fiziksel cihaz kabul turu ve testçi geri bildirimleri. |
| Profil iş galerisi | Fotoğraf yükleme, listeleme, büyütme, silme ve başkasının silmesine karşı yetki kontrolü tamamlandı. Canlı Android emülatöründe denendi. | Gerçek iPhone fotoğraf seçme/yükleme testi. Yeni galeri geliştirmesi beklemiyor. |
| Flutter bağlantısı, çevrimdışı işlemler, sunucu erişim kuralları | API bağlantısı, işlem kuyruğu, tekrar gönderim, oturum ve sahiplik kontrolleri kodda ve önceki testlerde mevcut. | Fiziksel Android/iOS'ta ağ kesilmesi, yeniden giriş ve son sürüm kabulü. Tüm işlemlerin çevrimdışı olduğu iddia edilmez; fotoğraf/ödeme gibi işlemler bağlantı gerektirir. |
| Hesap/kredi sınırları, engelleme, müsaitlik, hesap silme, puanlar ve sayfalama | Sunucu kuralları ve mobil bağlantıları tamamlandı; önceki otomatik/canlı kontroller kayıtlı. Ücretli haklar mağaza doğrulamasından önce verilmez. | Ücretli sınırların gerçek satın alma sonrasında sınanması. |
| Android/iOS abonelik ve kredi satın alma; doğrulama, iade/iptal | Mobil satın alma ve sunucuda mağaza doğrulama/iade/yenileme kodu ve yerel testler mevcut. Gerçek müşteri mağazası kurulumu ve kabulü tamamlanmadı. | Aylık/yıllık abonelik ve 5/15/40 kredi ürünleri, servis hesapları/Apple anahtarları, sunucu bildirimleri, doğru uygulama kimlikleri, satın alma/yenileme/iptal/iade/geri yükleme/ağ kesilmesi testleri. Android paket ayarı `com.santiyeagi.app` ile eşleşmeli. |
| Android push | Müşteri sunucusundan eski paketli Android emülatörüne gerçek FCM teslimi doğrulandı. Yeni paketli sürüm 7'de bildirim izni verildi. | Yeni paketli release üzerinde fiziksel Android'e teklif sonrası teslim, arka plan/kapalı işlem ve dokununca doğru açılış. Eski paket teslim testi yeni paket testi yerine geçmez. |
| iOS push | Flutter/backend ortak kodu ve background mode mevcut. Firebase iOS/APNs ve imza yetkileri tamamlanmadı. | Gerçek bundle kaydı, Firebase plist, APNs anahtarı, Push Notifications entitlement/provisioning, gerçek iPhone teslim testi. |
| IIS, HTTPS, log | IIS/.NET/PostgreSQL/HTTPS kuruldu; önceki sağlık ve canlı iş akışı kontrolleri başarılı. | Son hata/log kontrolü, hassas veri içermeyen işletim kayıtları ve sertifika otomatik yenilemesinin teyidi. |
| Yedekleme kurulumu | PostgreSQL yedekleme betiği mevcut. Dağıtım yedeği alınmış olması düzenli veritabanı yedekleme teslimi değildir. | Zamanlanmış görev, kalıcı anahtarlar ve fotoğrafları da kapsayan sunucu dışı yedek, saklama/temizleme takvimi, ayrı test veritabanına gerçek geri yükleme ve sonuç kaydı. |
| Android yayın dosyası ve Google Play gönderimi | İmzalı sürüm 7 AAB, doğru paket, mağaza simgesi/grafiği ve altı gerçek ekran görüntüsü hazır. Console beyanlarında kullanıcıyla ilerleniyor. | CSV'nin Console tarafından kabulü, diğer beyanlar, testçi erişimi, kapalı testin yayınlanması/izlenmesi, üretim başvurusu ve mağaza sonucu. Kapalı testin başladığı bu incelemede teyit edilmedi. |
| iOS derleme ve App Store gönderimi | Native proje iskeleti mevcut. İmzalı IPA, macOS/Xcode derlemesi ve TestFlight sonucu yok. | Apple uygulama kaydı ve yetkiler, nihai bundle ID, signing/provisioning, iPhone testleri, App Store'a özgü mağaza bilgileri/görseller, TestFlight, gönderim ve inceleme düzenlemeleri. |
| Kaynak kodu ve kurulum notu teslimi | Kaynaklar özel GitHub deposunda, rehberler ve sunucu yayın araçları mevcut. Android upload anahtarı yerel/gizli tutuluyor. | Son sürüm kaynak/derleme tesliminin sabitlenmesi, erişimlerin müşteriye devri, upload anahtarının güvenli bilgisayar dışı yedeğinin teyidi. |

## Kullanıma açmadan önce çözülmesi gereken ek başlıklar

1. **Normal kullanıcının hesabını geri alması:** Canlı `/api/v1/auth/options` yanıtı bu incelemede telefon doğrulama kapalı, parola girişi açık döndü. Parola girişi yapılandırılmış ortak test hesabına yöneliktir; normal müşterilere genel parola oluşturma/kurtarma sistemi değildir. SMS kapalıyken cihaz oturumu kaybolan sıradan kullanıcı telefonuyla aynı hesaba geri dönemiyor. SMS adaptörü hazırdır; gerçek sağlayıcı ayarı ve gönderim testi bekler. Teklif SMS'i ayrı satırda saymasa da kullanıcı hesabı tesliminde bu davranış netleştirilmeli.
2. **Uygulamanın yasal ve destek bağlantıları:** Müşterinin GitHub Pages sayfası artık var; fakat `config/live-android-push.json` nihai işletici, destek ve yasal URL'leri içermiyor. Console'a web adresi yazılması bunları AAB içine eklemez. Onaylı adresler sonraki derlemeye eklenmeli. Silme sayfasındaki anonimleştirme/puan metinleri güncel API ile eşleştirilmeli. Hukuki onay müşteriye aittir.
3. **İnceleyicinin ücretli bölümlere erişimi:** Ortak test girişi çalışıyor; hesap ücretsiz yetkilerde. Mağaza incelemesi için kısıtlı özelliklerin nasıl inceleneceği çözümlenmeli. Doğrulanmamış makbuzla ücretli hak verilmemeli ve SMS politikası atlanmamalı.

## Önerilen bitirme sırası

1. Google Play beyanları ve yasal/destek adreslerini tamamla; kapalı test kanalını ve testçi erişimini doğrula.
2. Google Play ürünleri/sunucu doğrulaması ve Android satın alma testlerini tamamla; fiziksel Android push/izin/ağ testlerini yap.
3. Apple uygulama, signing, APNs ve satın alma kurulumunu yap; iPhone ve TestFlight turunu tamamla.
4. Normal kullanıcı geri girişi/SMS kararını sonuçlandır; yedek/geri yükleme ve HTTPS yenileme kontrolünü kapat.
5. Son sürümleri iki mağazaya gönder, inceleme düzeltmelerini yap ve nihai kaynak/erişim teslimini tamamla.

Ana uygulama geliştirmesinde yeni bir ilan/teklif/galeri modülü eksik görünmüyor. Ancak satın alma, iOS teslimi ve işletim kabulü teklifin içindedir; yalnız mağazaya dosya yüklemek kaldığı söylenemez.

## Kapsama dahil olmayanlar

Sanal POS ile taraflar arasındaki iş bedelini tahsil etme açıkça hariç. Yeni tanıtım/blog sitesi ayrı bir iş görüşmesidir. Yeni tasarım, ek modüller ve teslim sonrası bakım teklifin parçası değildir. WhatsApp OTP üzerinde anlaşılmış bir kapsam görülmedi. İlk raporun 3. maddesinin iletilmediği teklifin kendisinde belirtiliyor; onun tamamlandığı iddia edilmez.

## Kanıt sınırı

İlk raporun tüm maddelerinin orijinal tam metni bu turda ayrıca bulunup okunmadı; teklif, ilk düzeltme kaydı, orijinal mobil özellik envanteri, güncel kod ve sonraki kabul kayıtları karşılaştırıldı. VDS zamanlanmış görevleri, mağaza konsollarının anlık durumu, fiziksel telefon ve Apple hesabı bu turda açılıp incelenmedi. Eski belgelerdeki ara aşama eksikleri, daha yeni teslim kayıtlarıyla birlikte değerlendirildi.
