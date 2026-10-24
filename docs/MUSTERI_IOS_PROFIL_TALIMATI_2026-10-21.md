# Müşteriye gönderilecek iOS dağıtım profili talimatı

Şantiye Ağı Pro için imzalı TestFlight/App Store paketini hazırlamak üzere uygulamaya özel dağıtım profilini indirmeniz gerekiyor.

1. Kendi Apple Developer hesabınızla https://developer.apple.com/account adresine girin. Doğru geliştirici ekibi: `yusuf taskiran`, Team ID `D49KUWV4VG`.
2. **Certificates, Identifiers & Profiles → Identifiers** bölümünde `com.yusuftaskiran.santiyeagi.pro` kimliğini açın. **Push Notifications** yeteneğinin seçili olduğunu kontrol edin; kapalıysa etkinleştirip kaydedin.
3. Solda **Profiles → +** yolunu açın. **Distribution → App Store Connect** seçip devam edin.
4. App ID olarak `com.yusuftaskiran.santiyeagi.pro` kaydını seçin.
5. Dağıtım sertifikası olarak geliştirme Mac'inde karşılığı bulunan **Apple Distribution: yusuf taskiran (D49KUWV4VG)** sertifikasını seçin. Doğru sertifikayı ayırt etmek için: oluşturulma 10 Ekim 2026, bitiş 10 Ekim 2027; seri numarası `5574FEC206047FA5295ECD30933C482B`.
6. Profile anlaşılır bir ad verin: `SantiyeAgi-AppStore-20261021`. **Generate** ve ardından **Download** ile `.mobileprovision` dosyasını indirin.
7. İndirdiğiniz `.mobileprovision` dosyasını geliştirme Mac'ine iletin. Dosyanın uygulama kimliği, ekip, sertifika ve üretim push yetkisi kontrol edilerek paket imzalanacak.

Listede bu sertifika görünmüyorsa mevcut sertifikaları iptal etmeyin; sertifika listesinin yalnız ad/tarih bilgisini paylaşın, uygun eşleştirmeyi ayrıca yapalım. Bu işlem için Apple parolanızı paylaşmanız gerekmez.

Bu dağıtım profili üretim APNs ortamını kullanan TestFlight/App Store paketi içindir. Apple satın alma sunucu API anahtarı ayrı bir kurulumdur; önceki backend sohbetindeki Apple Billing işlemi de tamamlanmalıdır. Gerçek cihaz bildirimi ve satın alma/geri yükleme testi hâlâ yapılmalıdır.

Resmî kaynaklar: [App Store dağıtım profili](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile), [uygulama yetenekleri](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/).


## Ayrı işlem: Apple satın alma sunucu anahtarı

Bu bölüm abonelik/kredi satın alma doğrulaması içindir. Bağladığımız APNs anahtarı cihaz bildirimi içindir; satın alma doğrulamasının kendi anahtarı gerekir.

1. Hesap sahibi App Store Connect'te **Users and Access → Integrations → Keys → In-App Purchase** yolunu açar.
2. Mevcut kullanılabilir satın alma anahtarı varsa güvenli sunucu kurulumu için o değerlendirilir. Yeni anahtar gerekiyorsa **Generate In-App Purchase Key** (veya +) ile açıklayıcı bir ad verilip oluşturulur. Bu adımı hesap sahibi yürütür.
3. **Download Key** ile indirilen `.p8` dosyası güvenli yerde tutulur; yalnız bir kez indirilebilir. İçeriği sohbet mesajına veya Git'e yapıştırılmaz.
4. Key ID, ilgili Issuer ID ve dosyanın güvenli sunucu yolu, önceki backend Codex sohbetindeki kurulumda kullanılır. Özel anahtar içeriği o sohbetin mesajlarına da yazılmaz; dosya güvenli Windows dizinine yerleştirilir.
5. Önceki backend sohbeti `AppleBundleId=com.yusuftaskiran.santiyeagi.pro`, `AppleAppId=6824034438`, Apple güven kökleri ve TestFlight/Sandbox kabulünü mevcut IIS ayarlarını koruyarak tamamlar. Ürünler aynı kimliklerle hazırdır. Apple üretim/sandbox bildirim adresleri App Store Connect'e kaydedildi; sunucuda gerçek V2 bildirim doğrulaması ayrıca test edilir.

Resmî kaynak: [Apple satın alma anahtarı oluşturma](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases/).
