# Müşterinin yeni tasarımının mevcut uygulamaya aktarılması

20 Ekim 2026. Müşterinin `Santiye_Agi_v2.3.0_yenitasarim.zip` arşivi mevcut .NET bağlantılı sürüme seçilerek uygulandı. Arşiv kaynak dosyalarının üzerine topluca açılmadı; önce yerel `tmp/` altında ayrı çıkarıldı ve satır biçimlendirmesi eşitlenerek karşılaştırıldı.

Arşiv SHA-256: `93554989901508F6AFC14F3AAD7F77BFF9AA34ACAF0C166EF4DE96761AF8605C`.

## Aktarılan tasarım

- Müşterinin yeni renk paleti; açık/koyu zeminler, ince kenarlıklar ve daha soluk simge/etiket arka planları.
- Koyu temada düğme, yükleniyor simgesi ve alt menüdeki artı simgesinin yazı/zemin kontrastı.
- Ana sayfada büyük arama kartı, tek sırada dört kategori kısayolu ve daha kompakt rol önerisi.
- Bekleyen işler kartı sadeleştirildi. Hem teklif hem anlaşma beklerken ikisine de ayrı düğmeyle erişim korunur; mevcut Gelen ve Anlaşmalar sekmelerine giderler.
- Yeni ilan önizlemesi müşterinin düzenindeki gibi dört kayıt gösterir. Tümü bağlantısı ve pazar listeleri korunur. Üyelik hatırlatması müşterinin düzenindeki gibi aşağıya taşındı ve ücretsiz iletişim hakkı tükendiğinde görünür; kota, kredi ve Premium işlemleri Profil'de her zaman mevcut kalır.

Gerçek UI değişiklikleri `lib/theme.dart`, `lib/widgets/common.dart`, `lib/screens/home/home_screen.dart` ve `lib/screens/shell.dart` ile sınırlı. Diğer ekranlar yeni ortak temayı kullanır. Profil ve ilan ekranlarındaki arşiv farklarının çoğu satır biçimlendirmesi veya mevcut geliştirmelerin eski sürüme dönmesidir; bunlar yeni tasarım diye aktarılmadı.

## Tasarıma eşlik eden işlev değişiklikleri aktarılmadı

Arşiv yalnız görünüm içermiyor: Supabase/Gemini asistanı ve gerçek zamanlı GPS konumu ekliyor, .NET bağlantısı ile bazı mevcut mobil geliştirmelerimizi içermiyor. Bunlar ayrıca sunucu, izin ve veri işleme çalışması gerektirir. Kullanıcının bu talebi tasarım aktarımı olduğundan yeni işlevler eklenmedi.

Yeni arama kartı mevcut `SearchScreen` aramasına bağlıdır. Yapay zekâ çalışıyormuş gibi bir ifade veya doğal dilden otomatik ilan oluşturma sözü verilmez. Başlık “Ne lazım? İlanlarda arayın” olarak uyarlanmıştır.

Arşivin doğrudan kopyalanması şu korumaları kaldıracaktı; mevcut kod korunmuştur:

- .NET API seçimi, güvenli oturum ve çalışma anındaki telefon doğrulama politikası.
- Ortak kullanıcı adı/parola girişi ve mevcut giriş ekranı.
- Fotoğraf galerisi, yükleme/silme ve sahiplik kontrolleri.
- Android push kaydı ve bildirimden uygulamayı açma yönlendirmesi.
- Hesap sahibine bağlı satın alma kuyruğu ve makbuz doğrulanmadan mağaza işlemini tamamlamama kuralı.
- Karşılıklı anlaşma iptal onayı, sorun çözme yetkisi ve 10 karakterlik eski .NET anlaşma kodu desteği.
- Canlı hafriyat kayıtlarının UUID kimlikleri ve sunucuda saklanması.
- Yasal/destek bağlantıları, hesap silme açıklaması ve canlı sürümde örnek verilerin kapalı olması.

`backend/`, mobil servisler/state/modeller/config, canlı yapılandırmalar ve Android/iOS native dosyaları değişmedi. Firebase/Google Play paket kimliği `com.santiyeagi.app` olarak kaldı. Yeni paket/izin/SQL veya migration eklenmedi. Sunucu kurulumu gerekmez.

## Doğrulama ve teslim

| Kontrol | Sonuç |
|---|---|
| Mevcut Flutter test takımı | 182 başarılı; yerel API gerektiren 2 entegrasyon testi standart turda atlandı |
| Yeni tasarım gezinme testleri | 7 başarılı: dört kategori, arama, yalnız teklif/yalnız anlaşma/ikisi birlikte erişim, 320 px ve 1,4 yazı ölçeğinde açık/koyu görünüm |
| Flutter `analyze --no-pub lib test` | Sorun yok |
| Görsel inceleme | Yerel örnek verilerle açık/koyu Flutter UI render'ları incelendi; kart/metin taşması görülmedi |
| Release AAB | Başarılı; bundletool doğrulaması ve JAR imzası geçti |
| Paket/sürüm | `com.santiyeagi.app`, `2.1.2 (9)` |

Sürüm adı, sunucu işlevlerini eski Supabase sürümüne döndürmemek için mevcut dalın `2.1.2` adıyla korundu; mağaza sürüm kodu **8 → 9** artırıldı. Müşterinin arşivindeki daha düşük sürüm kodu alınmadı.

Yerel teslimler:

- `output/mobile/SantiyeAgi-2.1.2-9-Tasarim-Test.aab`
- `output/design-review/home-light.png`
- `output/design-review/home-dark.png`

AAB SHA-256: `F5EB5A64C7FB58793A79891A0D5A6715C3856DBE4D01489B63A88B69C95E6F2C`.

Önizlemeler Flutter test ortamında, yalnız yerel ve örnek etiketli verilerle üretildi; gerçek telefon/mağaza ekran kaydı değildir. Canlı API'ye yeni işlem yazılmadı, sunucu veya mağaza yayını yapılmadı. Gerçek cihaz ve iOS derlemesi bu turda denenmedi. Önceden kalan SMS, mağaza satın alma ve iOS/APNs işleri tasarım aktarımıyla tamamlanmış sayılmaz.
