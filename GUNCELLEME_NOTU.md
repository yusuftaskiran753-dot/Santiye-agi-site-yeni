# Backend öncesi mobil düzeltmeler - 14 Ekim 2026

- Demo modunda örnek ilanlar başlangıçta görünür; canlı mod ve kullanıcı tercihi korunur.
- Teklif/talep başlıkları doğru Türkçe çoğul biçimleri kullanır.
- Malzeme oluşturulma tarihi "Yayın" olarak gösterilir; güncelleme zamanı gibi sunulmaz.
- Kabul ve profil ekranları ile gizlilik/KVKK şablonları mevcut telefon paylaşım davranışını açıklar.
- Platform hazırlama, manifest-only arşivi destekler; mevcut tam platformları koruyup yalnız eksik platformu üretir.
- Windows dosya işlemleri PowerShell ile yapılır; betik CRLF, shell betiği LF satır sonları kullanır.
- Boş dosya listesi Bash 3.2 uyumlu biçimde dolaşılır.
- Uygulamadaki turuncu şantiye simgesi Android/iOS launcher ikonlarına aktarılmıştır.
- Release imza kontrolü yalnız release görevinde devreye girer; demo debug kurulumu anahtar istemez.
- Güncel kontroller ve sınırlar QA_RAPORU.md içindedir.

.NET backend, profil fotoğraf galerisi, push ve gerçek mağaza satın alma/iade entegrasyonu bu aşamada uygulanmamıştır.

## Önceki arşiv teslimatının tarihsel notu

Aşağıdaki bölüm önceki paketin durumunu anlatır; bu çalışma ağacındaki güncel doğrulama sonuçları için QA_RAPORU.md kullanılmalıdır.

# Güncelleme notu — Şantiye Ağı v2.1.2

Bu bakım sürümü, önceki v2.1.1 kaynak ağacına kritik satın alma ve yayın güvenliği düzeltmeleri ekler.

- Kredi satın alma doğrulaması: satın alma kaydı, cüzdan bakiyesi ve kredi defteri tek atomik SQL fonksiyonunda işlenir; aynı makbuz ikinci kez kredi vermez.
- Yayın doğrulama betiği: canlı Supabase, destek/yasal URL'ler, harita sağlayıcısı ve Android imza dosyası eksikse release derlemesini durdurur; doğru `--dart-define` parametrelerini otomatik aktarır.
- Yapılandırma: destek, işletici, yasal bağlantılar ve harita adresi build-time parametreleriyle ayarlanabilir; örnek ilanlar varsayılan kapalıdır.
- Platform hazırlama betiği: shell sürümünde aynı disk üzerinde staging ve başarısızlıkta geri alma eklendi; Windows betiği kısmi platform klasörünü artık tam kurulum sanmaz.
- Sürüm: `2.1.2+5`.

**Doğrulama sınırı:** Bu ortamda Flutter/Dart, Android SDK, Xcode ve canlı Supabase/mağaza kimlik bilgileri bulunmadığından `flutter analyze`, `flutter test`, Android AAB/APK, iOS IPA ve canlı satın alma testleri çalıştırılmadı. Bu nedenle bu ZIP “kusursuz” veya “mağazaya hazır” olarak nitelendirilmez. İlk olarak `bash tools/prepare_platforms.sh`, ardından `bash tools/verify_project.sh` çalıştırılmalıdır. Yayın için `YAYIN_REHBERI.md` içindeki gerçek işletici, URL, harita ve mağaza ayarları gereklidir.
