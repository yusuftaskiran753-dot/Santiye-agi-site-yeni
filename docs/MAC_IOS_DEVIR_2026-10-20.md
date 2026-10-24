# Mac / iOS devir notu — 20 Ekim 2026

## Nereden başlanacak?

Depo: https://github.com/TunaCrt/santiye_app — `main`. Önce en son commit'i alın. Mobil sürüm 2.1.2+11. Ana sayfa müşterinin tek asistan kartına eşitlendi; son tasarım, veri erişimi ve mevcut iş akışları korunacak.

Canlı API: https://45.59.70.198. .NET 10 / PostgreSQL / IIS sunucusunda çalışıyor. Son AI/konum migration'ı uygulandı, gerçek Gemini yanıtı doğrulandı. Yerel otomatik yedek ve güncel web gizlilik metinleri hazır. Bu işler için yeni backend kurulumu gerekmez.

## Hazır kod ile tamamlanmamış kurulumun ayrımı

- Mobil satın alma akışı `lib/services/billing_service.dart`, Apple makbuz/işlem doğrulaması ve abonelik uzlaştırması `backend/SantiyeAgi.Api/Billing/` altında mevcut. iOS istemcisi işlem kimliğini oturumla API'ye gönderir. Mağaza doğrulamasından önce Premium/kredi verilmez.
- Apple App Store ürünleri, Apple API anahtarı/güven kökleri, gerçek Bundle ID eşleştirmesi ve App Store Server Notifications bağlantısı **henüz tamamlanmış değildir**. Bunlar hem Apple hesabında hem mevcut Windows sunucu ayarlarında yapılacak. Bu not canlı satın alma yapıldığı anlamına gelmez.
- Ortak Firebase push altyapısı mevcut; iOS uygulama kaydı/plist, APNs anahtarı, Xcode yetkileri/provisioning ve gerçek Apple bildirim teslimi **bekliyor**. APNs anahtarı ile App Store satın alma API anahtarı farklı amaçlara hizmet eder; birbirinin yerine kullanılmaz.
- iOS 15 hedefi, fotoğraf/konum açıklamaları ve remote-notification/location arka plan modları mevcut. macOS/Xcode derleme ve imzalama henüz yapılmadı.
- SMS ve hesap kurtarma müşteri sağlayıcı bilgilerini bekliyor; bu turda etkinleştirilmeyecek. Production'da sabit SMS kodu veya doğrulama atlatma eklenmeyecek. İnceleme hesabı sırları Git'e yazılmayacak.

## iOS uygulama kimliği

Xcode projesindeki mevcut Runner Bundle ID **com.santiyeagi.santiyeAgi**; Android kimliği **com.santiyeagi.app**. App Store Connect'teki gerçek uygulama kaydı hangisini kullanıyorsa Xcode, Firebase iOS kaydı, provisioning ve sunucudaki `Billing:AppleBundleId` aynı kimliğe eşitlenmeli. Android paket kimliğini değiştirmeyin. Mağaza kaydını kontrol etmeden iOS kimliğinin kesinleştiğini varsaymayın.

## Ürünler ve sunucu bağlantısı

Aynı kimliklerle oluşturun:

- `santiye_premium_aylik`: otomatik yenilenen aylık abonelik.
- `santiye_premium_yillik`: otomatik yenilenen yıllık abonelik; aylıkla aynı abonelik grubunda.
- `santiye_kredi_5`, `santiye_kredi_15`, `santiye_kredi_40`: tüketilebilir kredi paketleri.

Ürün ID'leri mobil ve backend kataloğunda ortak. Fiyat, açıklama, dil, satış bölgeleri ve inceleme görselleri App Store Connect'te tamamlanmalı; ürün ID'leri rastgele değiştirilmemeli.

Sunucu kurulumunun mevcut ayrıntılı belgesi: `docs/ODEME_KURULUMU.md`. Dış ayar dosyası Windows sunucuda `C:\ProgramData\santiye\settings.json`; site `C:\inetpub\wwwroot\santiye`. Diğer veritabanı/SMS/Firebase/Gemini ayarları korunarak `Billing` alanları birleştirilmeli, dosya bütünüyle değiştirilmemeli.

Gereken Apple alanları: `AppleBundleId`, `AppleAppId` (sayısal mağaza uygulama ID'si), `AppleIssuerId`, `AppleKeyId`, `ApplePrivateKeyFile`, `AppleRootCertificateFiles`; ayrıca `Enabled`/kontrollü `AllowSandbox`. Anahtar ve sertifika dosyaları güvenli sunucu dizininde tutulur. `.p8` dosyalarını Git'e, sohbete veya uygulama paketine koymayın. Mevcut ayarların etkinlik durumu yeniden okunmadan “satın alma açıldı” demeyin.

App Store Server Notifications V2 adresi: https://45.59.70.198/api/v1/billing/apple/notifications (Production/Sandbox için aynı doğrulayan uç; sunucu ilgili ortamı kabul edecek şekilde kurulmalı). Bu uç JWS/imza ve uygulama kimliğini doğrular. Firebase push veya APNs adresi değildir.

Oturum isteyen uçlar: `POST /api/v1/billing/verify` ve `/api/v1/billing/sync`. Apple tarafında satın alma tamamlandı görünmesi tek başına uygulamada ücretli hakkın verildiği anlamına gelmez; API doğrulaması başarılı olmalı. Problem varsa doğrulamayı kaldırmak yerine hata/ayar uyuşmazlığı giderilmeli.

## Mac'te çalışma ve yayın sırası

1. Depoyu güncelle, Flutter/Xcode/CocoaPods ortamını ve Apple geliştirici ekibini seç. Mevcut `ios/Runner.xcworkspace` üzerinden imzalama/kimliği kontrol et.
2. Firebase projesi `santiye-agi` altında gerçek iOS kimliğini kaydet, `GoogleService-Info.plist` dosyasını güvenli biçimde Runner hedefine ekle. Push Notifications yetkisini ve imzalı `aps-environment` entitlements/provisioning uyumunu tamamla. APNs anahtarını doğru Firebase iOS uygulamasıyla ilişkilendir.
3. App Store ürünlerini ve mevcut sunucunun Apple Billing yapılandırmasını tamamla. Apple hesabı ayrıntıları hazır olduğunda Windows sunucudaki yapılandırma işi hâlâ gereklidir; yalnız Mac ekranlarına tıklamak bu ayarları otomatik değiştirmez.
4. Canlı .NET yapılandırması için `config/live-android-push.json` dosyasını dart-define kaynağı olarak kullanabilirsin; dosyanın ismi Android olsa da API, push ve yasal URL değerleri ortak. iOS Firebase plist/bundle/provisioning ayrıca gereklidir. Derlemede API tanımı olmadan yerel/demo backend ile paket çıkarma.
5. Xcode Archive / Flutter IPA, TestFlight ve App Store Connect sürecini yürüt. Build numarasını mevcut en yüksek mağaza build numarasından büyük seç. App Store gizlilik beyanları için `docs/KONUM_ASISTAN_GIZLILIK_MAGAZA_2026-10-20.md` dosyasını kullan.

Kullanıcı fiziksel cihaz kontrollerini en son yapacak. Bu not onları tamamlanmış göstermez; bildirim/mağaza satın alma/geri yükleme ve konumun cihazdaki davranışı doğrulanmadan yayın hazır kabul edilmez. Apple sözleşmeleri, vergi/banka ve hesap doğrulama adımları varsa hesap sahibi tarafından tamamlanır.

## Mac'teki asistana gönderilecek kısa mesaj

> Şantiye Ağı projesine devam edeceğiz. `TunaCrt/santiye_app` deposunun main dalını güncelle ve önce `docs/MAC_IOS_DEVIR_2026-10-20.md` dosyasını oku. Canlı .NET backend ve mevcut tasarım hazır; Apple satın alma doğrulama kodu da var ama mağaza ürünleri/anahtarları ve sunucu Billing ayarları henüz bağlanmadı. Önce iOS Firebase/APNs ve Xcode imzalama, sonra mevcut ürün ID'leriyle App Store satın alma bağlantısı, ardından TestFlight/App Store yayını için adım adım yardımcı ol. Ekran görüntülerine göre hangi alana ne yazacağımı kısa anlat; proje dosyası gerekiyorsa depodan incele. Mevcut backend ve özellikleri koru, SMS'i şimdilik beklet; anahtarları Git'e yazma ve tamamlanmayan işi tamamlandı sayma.
