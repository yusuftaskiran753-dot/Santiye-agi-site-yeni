# Google Play ilk kapalı test paketi — 18 Ekim 2026

> Bu belge ilk, mağazanın paket adı kontrolünden geçmeyen `2.1.2 (5)` dosyasının tarihçesidir. Google Play kaydının `com.santiyeagi.app` istediği sonradan görüldü. Güncel paket ve Firebase eşleştirmesi için `GOOGLE_PLAY_PAKET_DUZELTME_2026-10-18.md` belgesini kullanın; eski AAB'yi yüklemeyin.

Bu paket Şantiye Ağı'nın Android kapalı test hazırlığı içindir. Play Console'a yükleme, inceleme onayı veya 14 günlük testin başladığı anlamına gelmez.

## Paket ayarları

- Paket kimliği: `com.santiyeagi.santiye_agi`
- Görünen sürüm: `2.1.2`; sürüm kodu: `5`.
- Derleme: `release` AAB; ayrı gerçek upload anahtarıyla imzalanır.
- Canlı API: `https://45.59.70.198`.
- Firebase Android bildirimleri açık; örnek ilanlar kapalı.
- Yapılandırma: `config/live-android-push.json`.
- SMS zorunluluğu sunucudan okunur. Bu hazırlık sırasında sunucu `false` döndürdü. Development doğrulama kodu eklenmedi.

Yerel teslim dosyası: `output/mobile/SantiyeAgi-2.1.2-5-Kapali-Test.aab`. Bu derleme çıktısı Git'e eklenmez.

## Yapılan kontroller

- `flutter analyze lib test`: sorun yok.
- `flutter test`: 181 başarılı, standart turda 2 yerel API testi atlandı.
- `flutter build appbundle --release --dart-define-from-file=config/live-android-push.json`: başarılı.
- Google bundletool 1.18.3 paket doğrulaması başarılı; AAB manifestinde paket kimliği ve `2.1.2 (5)` görüldü. Minimum API 24, hedef API 36. Debug/testOnly bayrağı yok.
- JDK `jarsigner -verify`: imza geçerli; imzalayan `CN=Santiye Agi Upload`. Upload sertifikası SHA-256: `A8:D8:99:A4:60:1C:7B:41:F8:1A:59:83:5C:2E:3E:3C:C6:26:B3:08:A4:AD:EF:D6:A1:3C:18:F6:EC:E4:14:9D`.
- Arşiv bütünlüğü ve 12 yerel kütüphane kontrol edildi. 64 bit ELF LOAD segmentleri 16 KB hizalamayı geçti. Bu kontrol fiziksel 16 KB cihazda çalıştırma testi yerine geçmez.
- Canlı HTTPS `/health/ready` HTTP 200 döndürdü. Bu turda yeni ticari kayıt oluşturulmadı.
- Dosya boyutu: 47.805.183 bayt. AAB SHA-256: `30DCD44576917BF13D1C01F6DF306A0DB844DB278E618F61C0364FCC1E4C7E2E`.

Play Console'a yüklenmedi; bu imzalı release paketi henüz gerçek telefonda çalıştırılmadı. Önceki emülatör kabul testleri profile sürümüyle yapılmıştı.

## İmza anahtarı ve tekrar derleme

İlk upload anahtarı ve parola dosyası bu bilgisayarda `%USERPROFILE%\.santiye-secrets` altında saklanır:

- `santiye-agi-upload.jks`: özel upload anahtarı.
- `android-upload-credentials.json`: anahtar yolu, alias ve parolalar; özel bilgidir.
- `santiye-agi-upload-certificate.pem`: açık upload sertifikası; özel anahtar içermez.

`android/key.properties` bu anahtara işaret eder ve Git tarafından yok sayılır. Özel anahtarı/parolaları kaynak koduna, AAB'nin içine veya sunucunun web klasörüne koymayın. Sahibi tarafından erişilebilen güvenli, bilgisayar dışı yedeği alın. Sonraki sürümlerde aynı upload anahtarı kullanılmalıdır. Play App Signing kaydında uygulama imza anahtarı ile bu upload anahtarı farklı görevler görür.

```powershell
flutter build appbundle --release --dart-define-from-file=config/live-android-push.json
```

Çıktı `build/app/outputs/bundle/release/app-release.aab` altındadır. Sonraki mağaza yüklemelerinde sürüm kodunu yükseltin. Türkçe karakterli Windows yolunda Java sorunu olursa mevcut çalışma klasörünü `subst` ile boş bir sürücü harfine bağlayıp o kısa yoldan derleyin. Java 17 kullanıldı.

## Console'da sıradaki işler

1. Müşterinin uygulama kaydında Android paket kimliğinin eşleştiğini kontrol edin. Daha önce aynı paket için sürüm yüklenmişse mevcut upload sertifikasıyla karşılaştırmadan yeni anahtar kaydetmeyin.
2. Play App Signing kurulumunu tamamlayıp AAB'yi kapalı test kanalına yükleyin.
3. Gizlilik politikası ve hesap silme web adresi, geliştirici destek bilgileri, içerik derecelendirmesi, veri güvenliği ve gerekli diğer beyanları doğru bilgilerle tamamlayın.
4. Testçi grubunu ve katılım bağlantısını hazırlayıp inceleme/yayın sonucunu takip edin. Hesaba uygulanıyorsa gerekli sayıda testçinin kesintisiz katılım süresi kapalı test üzerinden takip edilir; dosyayı yüklemek tek başına süreyi başlatmaz.
5. Gerçek testçi geri bildirimlerine göre aynı test kanalına daha yüksek sürüm kodlu güncellemeler gönderin.

## Henüz tamamlanmayanlar

- Google Play abonelik ve kredi ürünleri, sunucu mağaza yetkileri ve satın alma/yenileme/iptal/iade testleri.
- Gerçek SMS doğrulaması ve hesap kurtarma. SMS kapalıyken cihaz oturumunun kaybı halinde telefonla aynı hesaba geri giriş hazır değildir.
- İşletmenin onayladığı nihai yasal metinler ve adreslerinin mobil derleme ayarlarına eklenmesi. Mevcut Android yapılandırmasında bu adresler ve destek bilgileri boş kalır; bu paket onların tamamlandığı iddiasını taşımaz.
- Fiziksel Android cihazda son izin, bildirim ve kullanım kontrolü; Play'in ön yayın raporu.
- Play Console yüklemesi, mağaza incelemesi ve üretim erişimi.

iOS/APNs ve App Store işlemleri bu Android paketinden ayrıdır.
