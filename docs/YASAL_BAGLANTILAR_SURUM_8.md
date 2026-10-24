# Yasal bağlantılar — Android 2.1.2 (8)

19 Ekim 2026. Kullanıcının talebiyle mevcut müşteri web sitesindeki adresler iki canlı yapılandırmaya eklendi. SMS, push veya mağaza satın alma davranışı değiştirilmedi.

| Bilgi | Değer |
|---|---|
| Hizmet sağlayıcı | Yusuf Taşkıran |
| Destek | yusuftaskiran753@gmail.com |
| Kullanım koşulları | https://yusuftaskiran753-dot.github.io/-santiye-agi/#kullanim-kosullari |
| Gizlilik | https://yusuftaskiran753-dot.github.io/-santiye-agi/#gizlilik |
| KVKK | https://yusuftaskiran753-dot.github.io/-santiye-agi/#kvkk |
| Hesap silme | https://yusuftaskiran753-dot.github.io/-santiye-agi/#hesap-silme |

Sayfa HTTPS ile okundu; dört bölüm kimliği, işletici adı ve destek e-postasının sayfada bulunduğu kontrol edildi. Müşterinin yayımladığı sayfa değiştirilmedi. Önceki kapsam raporunda belirtilen silme/anonimleştirme metni uyuşmazlığı web sayfasında müşteri tarafından düzeltilmeli; bağlantı eklemek hukuki metin onayı değildir.

Profilde mevcut kullanım koşulları, gizlilik, KVKK ve destek alanlarının yanında **Hesap ve veri silme bilgileri** bağlantısı eklendi. Uygulama içindeki gerçek Hesabımı sil işlemi korunur. Karşılama ekranındaki yasal bağlantılar aynı yapılandırmayı kullanır.

Sürüm kodu 7'den **8**'e yükseltildi. Paket `com.santiyeagi.app`, sürüm adı `2.1.2`. Yerel teslim `output/mobile/SantiyeAgi-2.1.2-8-Kapali-Test.aab`.

Doğrulama: Flutter lib/test analizi temiz, mevcut üç onboarding/widget testi başarılı, Dart biçimi temiz, release AAB derlemesi başarılı, bundletool paket doğrulaması başarılı, JAR imzası geçerli ve manifestte doğru paket/sürüm görüldü. AAB SHA-256: `9FC7730AC698404B798D8E3D5400C76811E857469114091CA32DD2BEE4C6D2DC`.

Kullanıcının isteğiyle Android cihaz testi yapılmadı. AAB Google Play'e yüklenmedi; kurulu sürüm 7 bu değişiklikleri kendiliğinden almaz. iOS derlemesi yapılmadı; aynı adresler sonraki iOS canlı derlemesine hazırdır. Kullanıcının mağaza süreçlerini tamamladığı beyanı not edildi, bu turda Console durumu bağımsız denetlenmedi.
