# Backend öncesi mobil düzeltmeler

Tarih: 14 Ekim 2026. Kaynak sürümü: 2.1.2+5.

## Tamamlanan rapor maddeleri

| Madde | Sonuç |
|---|---|
| 1 | Yalnız manifest içeren Android klasörü artık arşivden ilk kurulumu engellemez. Tam Android/iOS projeleri korunur, yalnız eksik platform üretilir. Bilinmeyen kısmi projeler otomatik değiştirilmez. |
| 2 | Shell betiğinde boş dosya listesi Bash 3.2 ile uyumlu ifade üzerinden dolaşılır. |
| 4 | Yeni demo kurulumunda örnek ilanlar açıktır. Canlı Supabase bağlantısında kapalıdır; kullanıcının Profil tercihi korunur. |
| 14 | Kabul ve profil ekranları ile gizlilik/KVKK şablonlarında telefon erişiminin teklif/talep aşamasında başladığı açıklanır. Sunucu paylaşım kuralı bu aşamada değiştirilmedi. |
| 15 | Nakliye teklifleri, kiralama talepleri, sipariş talepleri, iş başvuruları ve iş teklifleri başlıkları doğru çoğul biçimleriyle gösterilir. |
| 16 | Malzeme oluşturulma zamanı "Güncelleme" yerine "Yayın" etiketiyle gösterilir. Gerçek güncelleme tarihi iddiası kaldırıldı. |
| 17 | Windows giriş betiği CRLF kullanır; dosya işlemleri PowerShell içinde, doğrulanmış proje yollarıyla yürütülür. |
| 18 | Mevcut turuncu şantiye simgesi Android ve iOS uygulama ikonlarına uygulandı. Hazır müşteri logosu geldiğinde değiştirilebilir. |
| 21 | README, yayın rehberi, güncelleme notu ve QA raporu çalışma ağacının güncel durumuna göre düzenlendi. Doğrulanmamış sayısal vergi sınırı kesin bilgi olarak verilmez. |

## Ek doğrulama düzeltmeleri

- Release imza kontrolü debug derlemesini engellemez; gerçek release görevinde imza dosyası zorunludur.
- Statik analizdeki import, yorum ve blok uyarıları düzeltildi.
- İlk kurulum widget testleri görünür/hit-test edilebilir kontrolleri kaydırarak kullanır; klavye kapatılarak geçerli ve geçersiz profil akışları doğrulanır.
- Eksik iOS iskeleti üretildi; ikon referansları ve uygulama adı uygulandı. iOS derlemesi yapılmadı.

## Kontroller

- Flutter analiz: uyarı ve bilgi dahil temiz.
- Flutter test: 156 test geçti.
- Android debug APK: başarılı.
- Platform betiği: manifest-only arşiv, anahtar/manifest koruma, mevcut Android'i koruyarak iOS üretme, tekrar çalıştırma, bilinmeyen kısmi projeyi koruma ve zorunlu kurulum hatasında geri alma doğrulandı.
- Shell betikleri: sözdizimi kontrolü başarılı. Gerçek macOS/Bash 3.2 yürütmesi bu Windows ortamında yapılmadı.
- İkonlar: görsel kontrol, PNG bütünlüğü ve iOS Contents.json referansları doğrulandı.

## Sonraki geliştirme aşaması

.NET backend/API, gerçek kullanıcı bağlantısı, profil iş fotoğraf galerisi, push, SMS kimlik doğrulaması, abonelik/iade, sunucu veri kuralları ve üretim kurulumu henüz yapılmadı. Mevcut backend seçimi Supabase/LocalBackend olarak kalır.

Mağaza yayını için işletici bilgileri, yasal URL'ler, upload anahtarı, geliştirici hesapları ve canlı servis erişimleri gerekir. Bu debug APK bir mağaza yayın paketi değildir.
