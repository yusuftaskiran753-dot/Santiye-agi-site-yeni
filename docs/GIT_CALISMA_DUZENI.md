# GitHub çalışma düzeni

Mobil ve API kaynakları tek özel depoda saklanır: https://github.com/TunaCrt/santiye_app

- Flutter: lib/, android/, ios/, test/ ve pubspec dosyaları.
- API: backend/; sunucu yayın/kurulum araçları backend/deploy/.
- Müşteri çalışma kaydı: docs/MUSTERI_CALISMA_NOTLARI.md.
- İlk commit mevcut çalışan geliştirme durumunu korur. Sonraki özellikler, ilgili kontroller geçtikten sonra ayrı commit'lerle GitHub'a gönderilir.
- Yerel test veritabanı/parolaları, üretim ayarları, imza anahtarları, fotoğraf dosyaları, PDF teklifleri ve derleme çıktıları depoya eklenmez.

Git kaynak kodunu korur. Müşteri veritabanı ve yüklediği fotoğraflar için ayrı sunucu yedeği gerekir.
