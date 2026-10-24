# iOS teslim notu

Bu paket Şantiye Ağı'nın Flutter kaynak kodunu, analiz/test araçlarını ve iOS native proje iskeletini Flutter SDK ile oluşturan betiği içerir.

1. macOS üzerinde Flutter 3.35+, Xcode ve CocoaPods kurulu olmalıdır.
2. `bash tools/prepare_platforms.sh` çalıştırın (iskelet varsa yeniden üretmek için `--force`; bu durumda Xcode imza ayarlarını yeniden yapmanız gerekir). Betik ana ekran adını `Şantiye Ağı` yapar ve şifreleme beyanını (`ITSAppUsesNonExemptEncryption = NO`) ekler.
3. `flutter pub get`, `flutter analyze`, `flutter test` (veya `bash tools/verify_project.sh`).
4. Xcode'da Runner target için Team, signing ve provisioning ayarlarını yapın; **+ Capability → In-App Purchase** ekleyin. Bundle ID: `com.santiyeagi.santiyeAgi` (Edge Function'daki `APPLE_BUNDLE_ID` ile aynı olmalı).
5. Sandbox satın alma/geri yükleme testlerini tamamlayın; ardından YAYIN_REHBERI.md içindeki yayın ortam değişkenlerini ayarlayıp `bash tools/verify_project.sh ios` ile IPA üretin.

Bu ZIP'te önceden derlenmiş IPA yoktur. IPA üretimi macOS, Xcode ve Apple Developer imzalama ayarları gerektirir.
