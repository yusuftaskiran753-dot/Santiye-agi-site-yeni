# Mobil uygulamayı .NET sunucusuna bağlama

`API_BASE_URL` verilince Flutter uygulaması `DotNetBackend` kullanır. Ekranların mevcut model, alan ve temel iş akışları korunur. Kaynak referansı: `MOBIL_ILK_SURUM_OZELLIK_ENVANTERI.md`.

## Yerel test

```powershell
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:5080
```

Bu adres yalnız Android emülatöründen geliştirme bilgisayarına gider. Müşteri sunucusuna bağlanmaz. Yerel HTTP yalnız debug ve localhost/127.0.0.1/10.0.2.2 için kabul edilir. Adres belirtilmezse demo veya eski Supabase seçimi kullanılır; canlı backend bağlantısı kurulmuş sayılmaz.

SMS kurulmadan kalan işlevleri incelemek için aynı ayarlar `config/local-emulator.json` içinde bulunur. Ayrı Development API ve bu çalışma için oluşturulmuş yerel test veritabanıyla kullanılır. Test hesabı ve kabul sonuçları için `BACKEND_KABUL_KONTROLU.md` belgesine bakın. Bu hesabın yerel doğrulaması müşteri sunucusuna taşınmaz.

## Canlı derleme

Müşterinin IIS sunucusunun HTTPS adresi `config/live.json` dosyasındadır. Bu dosyada sır veya servis anahtarı bulunmaz. Canlı sunucuya bağlı Android emülatörünü açmak için:

```powershell
flutter run -d emulator-5554 --dart-define-from-file=config/live.json
```

Android mağaza derlemesinde bildirimleri de açan canlı yapılandırma kullanılır:

```powershell
flutter build appbundle --release --dart-define-from-file=config/live-android-push.json
```

`android/key.properties` ve gerçek upload keystore gerekir. Kullanılan adresin HTTPS sertifikası geçerli olmalı. Mevcut sunucuda IP adresine ait sertifika kullanılıyor; sertifikanın otomatik yenileme görevi çalışmaya devam etmelidir. Alan adına geçilirse `config/live.json` güncellenip uygulama yeniden derlenir. İlk uygulamaysa mağaza applicationId/bundleId ile kaynak kimlikleri eşleştirilir. Aynı uygulama kaydına güncelleme gönderilecekse önceki paket kimliği ve imza anahtarı korunur.

Genel `config/live.json` ayarında örnek ilanlar ve Firebase push kapalıdır. Android'e özel `config/live-android-push.json` ayarı push bildirimlerini açar; iOS/APNs kurulumu ayrıdır. Mobil, SMS zorunluluğunu `/api/v1/auth/options` üzerinden sunucudan okur. Yeni IIS paketinde zorunluluk kapalıdır; doğrudan profil oluşturulur ve telefon doğrulanmış gösterilmez. Sunucuda açıldığında SMS ekranı geri gelir. Ayrıntılar: `SMS_AC_KAPAT.md`. Development test kodu canlıda kullanılmaz. İlk Android kapalı test paketi ve imza/yayın adımları: `GOOGLE_PLAY_ILK_KAPALI_TEST.md`.

## Firebase anlık bildirimleri

1. Müşteriye ait Firebase projesinde Android paketini Google Play kaydıyla aynı `com.santiyeagi.app` kimliğiyle kaydedin. Bu kayıt 18 Ekim 2026'da mevcut `santiye-agi` Firebase projesine eklendi; yerel Google yapılandırması yeni kayıtla eşleştirildi.
2. Android `google-services.json` dosyasını `android/app/` içine koyun. Gradle eklentisi dosya bulunduğunda uygulanır. Bu dosya Git'e dahil edilmez.
3. iOS uygulamasını kendi bundleId'siyle Firebase'e ekleyin; `GoogleService-Info.plist` dosyasını Xcode'da Runner hedefine ekleyin. Push Notifications yeteneğini etkinleştirin, Background Modes → Remote notifications seçili olsun. Firebase'e APNs anahtarını tanımlayın.
4. Sunucunun Firebase servis hesabını `BILDIRIM_SMS_KURULUMU.md` belgesine göre yapılandırın.
5. Derlemeye `--dart-define=PUSH_ENABLED=true` ekleyin. Örnek:

```powershell
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.sizin-alan-adiniz.com --dart-define=PUSH_ENABLED=true
```

Kullanıcı giriş yaptıktan sonra bildirim izni istenir. Profil → Bildirim ayarları üzerinden tekrar denenebilir. Telefonun sistem ayarlarından kapatılan izin oradan açılır. Çıkışta cihaz hesabından ayrılır. Bildirime dokununca uygulamadaki Bildirimler ekranı açılır; bildirim kartından ilgili işe gidilir. Farklı hesaba ait gelen bildirimle yeni hesabın ekranı açılmaz. Bildirim izni verilmezse uygulama içi liste kullanılabilir.

Firebase yapılandırması sağlanmadan oluşturulan test APK'sında push kapalıdır. API anahtarları, SMS bilgileri ve mağaza servis hesabı Flutter içine konulmaz.

## Mağaza ve telefon kontrolleri

- Telefonla giriş/çıkış, uygulamayı yeniden açma, süresi dolan oturumu yenileme ve profil düzenleme.
- Beş ilan türü; iki hesapla teklif, kabul/ret, anlaşma, teslim ve puanlama.
- Fotoğraf seçme, açıklama, görüntüleme ve silme; iOS izin ekranı.
- Google Play lisans test hesabı / Apple Sandbox ile satın alma, geri yükleme, yenileme, iptal ve iade. Gerçek ürünler kurulmadan tahmini fiyat gösterilmesi satışın hazır olduğunu göstermez.
- Arka planda/kapalı uygulamada FCM teslimatı ve bildirimden geri açılış. Android zorla durdurma ve iOS kullanıcı kısıtlamaları teslimatı etkileyebilir; gerçek cihazda kontrol edin.

Windows ortamındaki Android derlemesi iOS derlemesi yerine geçmez. iOS arşivi ve TestFlight kontrolü macOS/Xcode ve müşterinin Apple hesabıyla yapılmalıdır.
