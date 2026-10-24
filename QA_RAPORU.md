# Şantiye Ağı - güncel kontrol raporu

Tarih: 14 Ekim 2026. Sürüm: 2.1.2+5.

## Backend öncesi tamamlanan işler

Rapor maddeleri 1, 2, 4, 14, 15, 16, 17, 18 ve 21'in bu ortamda yapılabilen kısımları uygulandı. Ayrıntılar: [BACKEND_ONCESI_DUZELTMELER.md](docs/BACKEND_ONCESI_DUZELTMELER.md).

Demo örnek ilanları varsayılan açık, canlı bağlantıda kapalıdır. Önceden kaydedilmiş Profil tercihi değişmez. Telefon paylaşım metinleri mevcut kurala göre düzeltildi; sunucu erişim davranışı değiştirilmedi. Malzeme tarihi yayın zamanı olarak etiketlenir.

## Çalıştırılan doğrulamalar

| Kontrol | Sonuç |
|---|---|
| Flutter 3.38.3 / Dart 3.10.1 | Windows ortamında mevcut |
| flutter analyze --fatal-infos --fatal-warnings | Başarılı; sorun yok |
| flutter test | 156 test geçti |
| flutter test tools/generate_app_icons_test.dart | Başarılı; Android/iOS ikonları üretildi |
| flutter build apk --debug | Başarılı; Gradle Unicode yol sorunu için S: kısa yolu kullanıldı |
| tools/prepare_platforms.bat | Eksik iOS oluşturuldu; mevcut Android korundu; tekrar çalışma başarılı |
| Platform senaryo testleri | Manifest-only kurulum, dosya koruma, eksik platform, bilinmeyen kısmi proje ve başarısız --force sonrası geri alma başarılı |
| bash -n tools/prepare_platforms.sh ve verify_project.sh | Başarılı |
| Satır sonları ve iOS ikon referansları | CRLF/LF ve tüm PNG referansları doğrulandı |

## Yapılmayan veya dış ortam gerektiren doğrulamalar

- Gerçek macOS Bash 3.2, Xcode/iOS derlemesi ve cihaz testi bu Windows ortamında yapılmadı.
- Güncel çalışma için SQL/RLS ve Edge Function canlı testleri çalıştırılmadı. Önceki raporun tarihsel kopyası docs/QA_RAPORU_2026-10-12.md içindedir.
- Android release/AAB ve iOS IPA oluşturulmadı; üretim imza, hesap ve canlı yapılandırmalar gerekir.
- Mağaza satın alma, abonelik iptal/iade ve geri yükleme gerçek mağazalarla henüz doğrulanmadı.
- .NET backend, profil iş galerisi, push ve canlı kullanıcı altyapısı bu aşamada uygulanmadı.
- İşletici adı, destek e-postası, yasal bağlantılar, harita sağlayıcısı ve mağaza ürünleri ayrıca tamamlanmalı.

Android debug paketi test içindir; canlı sunucuya bağlı veya mağazaya hazır sürüm olarak değerlendirilmez.

## Emülatör doğrulaması

Android 16 x86_64 emülatörüne daha küçük, mimariye özel debug APK veriler korunarak yüklendi. Uygulama açıldı, demo ilanları görüntülendi ve son loglarda fatal/Flutter hata kaydı bulunmadı. İlk çok-mimarili APK depolama sınırına takıldığı için x86_64 paket kullanıldı.



## 14 Ekim 2026 - .NET backend ilk grup

.NET 10 API, PostgreSQL migration ve Flutter bağlantı katmanı eklendi. İlk kapsamın durumu docs/NET_BACKEND_ILK_ASAMA.md içindedir. 12 .NET testi, 160 Flutter testi ve gerçek API üzerinden mobil akış kontrolü geçti. IIS publish başarılı; müşteri sunucusuna kurulmadı. Önceki bölümdeki "henüz yapılmadı" kayıtları ilk mobil düzeltme aşamasına aittir; güncel kapsam yeni geliştirme notunda listelenir.
# 14 Ekim 2026 - İş fotoğraf galerisi kontrolü

Bu kayıt önceki aşamaların test sonuçlarını değiştirmez; yeni galeri geliştirmesinin ek kontrolüdür.

- API: 14 test başarılı; gerçek yerel PostgreSQL kullanıldı. Sahiplik, engelleme, görüntü normalizasyonu, boyut/adet sınırları, tekrar gönderim ve hesap silme temizliği kontrol edildi.
- Flutter tam test çalışması: 164 test başarılı, canlı API adresi verilmediği için 1 entegrasyon testi atlandı.
- Son galeri düzenlemeleri: ilgili 8 mobil test tekrar başarılı. Statik analiz temiz.
- Yayınlanmış Windows paketine gerçek multipart PNG yüklendi; 1024x1024 JPEG olarak API'den okundu. Görüntü ve liste PostgreSQL'de test hesabında saklandı.
- Android debug APK derleme başarılı. Son galeri kaynaklarının yeni APK'sı ayrıca üretildi.
- Müşteri VDS/IIS ve gerçek iOS cihaz kontrolü henüz yapılmadı.
