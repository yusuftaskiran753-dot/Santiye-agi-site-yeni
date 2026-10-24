# Önceki backend sohbetine gönderilecek görev — 21 Ekim 2026

Aşağıdaki metin backend/Windows işini yürüten önceki Codex sohbetine iletilebilir. Bu belge sunucuda herhangi bir ayarın yapıldığını göstermez.

---

Şantiye Ağı iOS yayın hazırlığına devam ediyoruz. `TunaCrt/santiye_app` main dalını mevcut yerel çalışmalarını koruyarak güncelle; `docs/MAC_IOS_DEVIR_2026-10-20.md`, `docs/ODEME_KURULUMU.md` ve `docs/IOS_YAYIN_HAZIRLIK_2026-10-21.md` belgelerini oku. Çalışan Windows/IIS/PostgreSQL sistemini, Firebase/Gemini ayarlarını ve mevcut özellikleri koru; SMS'i şimdilik etkinleştirme.

## 1. Apple satın alma sunucu bağlantısını hazırla ve eksikleri doğrula

- Gerçek iOS Bundle ID: `com.yusuftaskiran.santiyeagi.pro`; Apple App ID: `6824034438`; Apple ekibi: `D49KUWV4VG`.
- App Store Connect'te beş ürün hazır. Türkiye fiyatları: `santiye_premium_aylik` 199,00 TL/ay; `santiye_premium_yillik` 1.599,99 TL/yıl (yıllık peşin); `santiye_kredi_5` 99,99 TL; `santiye_kredi_15` 149,00 TL; `santiye_kredi_40` 419,99 TL. Abonelikler aynı Premium grubunda, krediler tüketilebilir. Ürün kimliklerini/hak miktarlarını değiştirme; mobil fiyatı doğrulama veya yetki kaynağı olarak kullanma.
- Müşteriden yeni bir `.p8` dosyası geldi. Mac'teki dosya `Downloads/AuthKey_L3FC8F5LZ7.p8`; yalnız adından satın alma anahtarı olduğu kesinleşmez. Müşterinin bunu **App Store Connect / Integrations / In-App Purchase** bölümünden oluşturduğunu teyit et; Key ID ve **Issuer ID** eksiklerini belirle. APNs bildirim anahtarını satın alma doğrulamasında kullanma. Özel anahtarın içeriğini sohbet mesajına, Git'e veya loga yazdırma.
- Anahtar henüz güvenli Windows dizinine aktarılmadıysa bunu açıkça eksik olarak bildir; sahte değerle etkinleştirme yapma. Güvenli aktarım ve dosya izinleri hazır olduğunda, mevcut `C:\ProgramData\santiye\settings.json` içindeki yalnız gerekli `Billing` alanlarını birleştir: `AppleBundleId`, `AppleAppId`, `AppleIssuerId`, `AppleKeyId`, `ApplePrivateKeyFile`, `AppleRootCertificateFiles`. Mevcut Google/diğer platform ayarlarını ve Data Protection anahtarlarını koru. Önce etkin yapılandırmayı ve seçilen dış dosya yolunu doğrula.
- Apple güven köklerini resmî Apple PKI kaynağından doğrula; imza/zincir/sertifika iptal denetimini kapatma. Hazırlık bitmeden `Enabled=true` deme.

## 2. TestFlight/Sandbox ortamını güvenli planla

- TestFlight satın alımları Sandbox'tır. Mevcut `AllowSandbox` ve ortam ayrımını incele; canlı kullanıcı haklarıyla sandbox test haklarını karıştırmayan test ortamı veya eşdeğer açık bir izolasyon planı hazırla. Canlı sistemde kontrolsüzce sandbox kabulünü açma.
- Apple Production ve Sandbox Server Notifications URL alanlarına şimdilik aynı mevcut uç kaydedildi: `https://45.59.70.198/api/v1/billing/apple/notifications`. Uygun test ortamı ayrı URL gerektiriyorsa tam yeni URL'yi Mac sohbetine bildir; Apple alanını burada güncelleyeceğiz.
- Mac tarafında üretim push yetkili, imzası doğrulanmış 2.1.2+11 IPA hazır. TestFlight yüklemesi kullanıcı isteğiyle bekletildi; gerçek mağaza işlemi henüz yok. Şimdi yapılabilen yapılandırma ve otomatik kontrolleri tamamla; gerçek mağaza işlemine bağlı testleri beklemede ayır. `POST /api/v1/billing/verify`, `/api/v1/billing/sync` ve Apple V2 bildirim doğrulamasını belgeye göre test et; olmayan makbuzla başarılı satın alma iddia etme. Sahte veya doğrulanmamış işlemle Premium/kredi tanımlama.
- Apple bağlantısı hazır olunca resmî API üzerinden test bildirimi isteği/sonuç kontrolü yapılabiliyorsa tamamla; HTTP kodunu ve hatayı sır/jeton/JWS içermeden özetle. Normal yeniden teslim, yenileme/iptal/geri yükleme ve kredi tekrar işlememe kontrollerinin hangileri gerçek işlem bekliyor açıkça yaz.

## 3. Gemini gizlilik teyidini şimdi yap

- Canlı sunucunun kullandığı Gemini anahtarının ait olduğu gerçek Google Cloud projesini, anahtar içeriğini açıklamadan belirle.
- Projede Cloud Billing'in gerçekten aktif olup olmadığını ve kullanılan Gemini API hizmetinin ücretli veri işleme koşullarına tabi olup olmadığını doğrula. Kullanıcı yalnız “faturaya bağlı olması lazım” dedi; kesin teyit sayılmıyor. Yalnız kart bulunması veya başka Google projesinde faturalandırma açık olması yeterli değildir.
- Girdilerin/çıktıların sağlayıcı tarafından ürün/model geliştirme veya insan incelemesi amacıyla kullanılıp kullanılmadığını, varsa güvenlik amaçlı saklamayı kullanılan hizmet ve güncel resmî koşullara göre açıkla. Konsol/hesap erişimin yoksa doğrulanamayan noktayı ve hesap sahibinin bakacağı ekranı belirt; tahmin etme.
- Mevcut uygulama ayrı onayla en fazla 400 karakterlik metin ve seçili ili Gemini'ye gönderiyor. Uygulama/API günlükleri ve veritabanında istek metni/model cevabı saklanmadığını yeniden doğrula; uyuşmazlık varsa hatayı ve gereken düzeltmeyi bildir.
- Yayındaki gizlilik sayfası: `https://yusuftaskiran753-dot.github.io/-santiye-agi/#gizlilik`. App Store gizlilik formunda 13 veri türünden 11'i hazır; yaklaşık konum ve diğer kullanıcı içeriğinin amaçları bu teyidi bekliyor. Sonucu Mac sohbetine ilet; web metni ve Apple beyanı bu bilgiye göre tamamlanacak.

## 4. İnceleme ve bildirim hazırlığını raporla

- SMS zorunluluğu açılmadan parola ile inceleme hesabı kullanılabilmeli. Hesap bilgilerini kullanıcı App Store Connect'e kendisi girecek; parolayı Git'e/sohbete yazma. Mevcut bir hesap varsa çalışmasını doğrula; yeni hesap gerekiyorsa kullanıcıyla güvenli oluşturma yolunu netleştir.
- Firebase `santiye-agi` iOS uygulamasına üretim APNs anahtarı Mac tarafında bağlandı. Sunucunun mevcut FCM proje/servis hesabı eşleşmesini ve iOS kurulum token kaydı/gönderim yolunu kontrol et; sırları açıklama. Gerçek iPhone henüz test edilmediğinden teslimi başarılı sayma.
- Sonuçta “hazır”, “eksik bilgi/dosya”, “TestFlight/cihaz bekliyor” ayrımıyla kısa rapor ver. Yapılan sunucu değişikliklerini ve kontrolleri müşteri notlarına işle; mevcut ayarları koru ve hataları açıkça yaz.

---

Mac tarafında yeni dağıtım profili ve üretim push yetkili imzalı IPA (2.1.2+11) doğrulandı. Xcode otomatik yüklemesi müşteri ekibi hesabı bulunamadı hatası verdi; bu, App Store Connect yükleme yetkisinin bulunmadığını kesinleştirmez. Transporter alternatifinde oturum açma beklenirken kullanıcı yüklemeyi şimdilik durdurdu. TestFlight yüklemesi, kredi inceleme alanlarının kalıcılığı, Gemini teyidine bağlı gizlilik beyanı, inceleme hesabı ve fiziksel cihaz kabul testleri bekliyor. Bunları backend hazırmış gibi işaretleme.
