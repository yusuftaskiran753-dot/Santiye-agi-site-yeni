# Şantiye Ağı çalışma kuralları

Bu depo Flutter mobil uygulaması ile backend/ altındaki .NET 10 / PostgreSQL API'yi birlikte içerir. Windows Server / IIS hedeflenir.

- Değişiklikleri müşterinin anlayacağı dille docs/MUSTERI_CALISMA_NOTLARI.md dosyasına kaydet.
- Kullanıcı bu depoda commit ve GitHub'a push ile ilerlenmesini istedi. Tamamlanan, kontrol edilen değişiklikleri anlamlı ayrı commit'lerle kaydet ve gönder; mevcut uzak geçmişi koru, force push kullanma.
- Sırlar, imza anahtarları, yerel test parolaları, veritabanı dosyaları, yüklenen fotoğraflar ve derleme/yayın çıktıları Git'e eklenmez. output/ ve tmp/ yereldir.
- Doğrulama test kodu yalnız Development ortamında kullanılır; Production ortamında telefon doğrulamasını atlatma.
- Mağaza makbuzları doğrulanmadan ücretli hak verme. Tamamlanmamış entegrasyonları açıkça belirt.
- Backend entegrasyon testleri yalnız yerel, kendilerinin oluşturduğu santiye_test_* veritabanlarında çalışır.
- Flutter için anlamlı testler ve flutter analyze, API için dotnet build/test kullan. Canlı IIS veya mağaza kontrolleri yapılmadıysa yapılmış gibi yazma.
