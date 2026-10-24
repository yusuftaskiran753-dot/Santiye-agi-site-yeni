# Android teslim notu

Bu paket Şantiye Ağı'nın Flutter kaynak kodunu, analiz/test araçlarını ve Android native proje iskeletini Flutter SDK ile oluşturan betiği içerir.

1. Flutter 3.35+ ve Android Studio/Android SDK kurulu bilgisayarda klasörü açın.
2. `tools\prepare_platforms.bat` (Windows) veya `bash tools/prepare_platforms.sh` (macOS/Linux) çalıştırın. İskelet daha önce üretildiyse yeniden üretmek için `--force` ekleyin; `android/key.properties` ve `.jks` dosyaları korunur.
3. `flutter pub get`, `flutter analyze`, `flutter test` (veya `bash tools/verify_project.sh`).
4. Yükleme anahtarı: `android/key.properties.example` → `android/key.properties` (içindeki `keytool` komutuyla anahtarı oluşturun, yedekleyin).
5. Canlı sunucu ayarları tamamlandıktan sonra `bash tools/verify_project.sh android` (YAYIN_REHBERI.md içindeki gerekli ortam değişkenleri ayarlandıktan sonra) ile Play Store AAB üretin. `tools/verify_project.sh android` geçerli `android/key.properties` ve keystore yoksa derlemeyi güvenli biçimde durdurur. Yayın betiği ayrıca canlı Supabase, yasal bağlantılar, destek e-postası ve harita sağlayıcısı değişkenlerini zorunlu tutar.

Bu ZIP'te önceden derlenmiş APK/AAB yoktur. Gerçek derleme Android SDK ve imza ayarları gerektirir.
