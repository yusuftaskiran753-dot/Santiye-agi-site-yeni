# Mevcut IIS sunucusunu güncelleme

Bu sürüm, hafriyat sahalarını kullanıcı hesabında saklayan yeni bir tablo ekler. Mevcut hesaplar, ilanlar, fotoğraflar ve anlaşmalar korunur. Hesap temizleme aracını tekrar çalıştırmayın; yeni canlı kontrol hesaplarını siler.

1. Sunucuda yönetici PowerShell ile bakım dosyasını oluşturun. IIS sitesi ve havuzu açık kalabilir; bakım dosyası uygulamayı kapatır. 30 saniye bekleyin.

```powershell
Set-Content -LiteralPath 'C:\inetpub\wwwroot\santiye\app_offline.htm' -Value 'Guncelleme yapiliyor.'
```

2. Güncel ZIP'in içeriğini `C:\inetpub\wwwroot\santiye` klasörüne kopyalayıp dosyaları değiştirin. `C:\ProgramData\santiye` içindeki ayarlara ve anahtarlara dokunmayın.

3. Yeni tabloyu kurun. Betik mevcut sunucu ayarlarını kendisi okur; parola yazmanız gerekmez.

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\inetpub\wwwroot\santiye\deploy\apply-migrations.ps1"
```

4. “Veritabani guncellendi” çıktısından sonra bakım dosyasını kaldırın.

```powershell
Remove-Item -LiteralPath 'C:\inetpub\wwwroot\santiye\app_offline.htm'
```

5. `/health/ready` adresinde `ready`, `/api/v1/auth/options` adresinde `phone_verification_required: false` görülmeli. Mobil uygulamayı yeniden açın.

Hafriyat sahaları hesaba özel API kaydıdır. Eski cihaz içi ortak/örnek sahalar otomatik yüklenmez. SMS kapalı olduğu için mevcut canlı hesap cihaz oturumuyla açılır; şu an telefon ve şifreyle tekrar giriş akışı yoktur. SMS sağlayıcısı açılınca aynı telefon gerçek kodla doğrulanabilir. Telefon örnekleri gerçek SMS alacak numaralar yerine geçmez.
