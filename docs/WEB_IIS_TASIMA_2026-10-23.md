# İki web sitesinin IIS'e taşınması — 23 Ekim 2026

Bu hazırlık yalnız **santiyeagi.com.tr** ve **asfaltik.com.tr** içindir. Sunucu **45.59.70.198**. `.xyz` alan adları kapsam dışındadır. Siteler statik HTML'dir; Node, ASP.NET backend veya ayrı veritabanı gerektirmez.

**Aşama:** iki alan adı kullanıcının mevcut Cloudflare hesabına Free planla eklendi. A/CNAME kayıtları kaydedilerek panelde tekrar okundu. Natro her iki nameserver değişikliğine başarı yanıtı verdi. Son kullanıcı çıktısında iki IIS sitesi `HTTP_READY`; dört Host için yerel 200/içerik özeti doğru. Dışarıdan doğrudan sunucu IP'sine aynı Host başlıklarıyla yapılan dört istek de 200 ve paketle birebir içerik özeti döndürdü. Son 1.1.1.1 sorgusu hâlâ Natro NS/park IP'sini gösteriyor: alan adlarının DNS yayılımı ve HTTPS bekliyor. Cloudflare üye daveti gönderilmemiştir. GitHub Pages kapatılmadı.

## Sunucudaki düzen

| İçerik | IIS sitesi ve ayrı uygulama havuzu | İçerik kökü | Alan adları |
|---|---|---|---|
| Şantiye Ağı tanıtım/yasal metinler | `SantiyeAgi-Web` | `C:\inetpub\wwwroot\santiye-web\releases\<sürüm>` | `santiyeagi.com.tr`, `www.santiyeagi.com.tr` |
| Asfaltik destek sayfası | `Asfaltik-Web` | `C:\inetpub\wwwroot\asfaltik-web\releases\<sürüm>` | `asfaltik.com.tr`, `www.asfaltik.com.tr` |

Mevcut `santiye` API sitesi/havuzu, `C:\inetpub\wwwroot\santiye` içeriği ve `https://45.59.70.198` API adresi korunur. Web dosyaları API klasörünün üzerine açılmaz. DNS'teki alan adı, IIS'te host adı içeren binding ile ilgili statik siteye ayrılır; API adresi bu taşıma için değiştirilmez. IIS binding bilgisinde protokol, IP, port ve host adı ayrı öğelerdir. [Microsoft IIS binding belgesi](https://learn.microsoft.com/en-us/iis/configuration/system.applicationhost/sites/site/bindings/binding)

Kurulum betiği paket ve dosya SHA-256 özetlerini doğrular, ayrı sürüm klasörleri oluşturur, IIS yapılandırma yedeği alır ve yalnız bu iki sitenin HTTP bağlamalarını hazırlar. Ad/host/klasör sahipliği başka bir kurulumla çakışırsa durur. Sonuç `HTTP_READY` ise dört host için yerel HTTP 200 ve beklenen içerik doğrulanmıştır; dış DNS ve HTTPS henüz doğrulanmış sayılmaz. Kurulum kaydı `C:\ProgramData\santiye\static-web-deploy\<işlem>\deployment.json` altında tutulur.

## 1. Kısa sunucu kurulumu

Yerel teslim klasörü: `output/web-migration-20261023/`.

- `Web-Siteleri-IIS.zip`: 22.588 bayt, 9 public dosya; SHA-256 `cc16c8799126676a6b853462f3858eab156b485ddc40bc53bc04bfdad3b06f19`.
- `web-kur.ps1`: kaynak kurulum betiğinin yukarıdaki ZIP hash'i varsayılan olarak sabitlenmiş kopyası. ZIP manifesti ve dosya özetleri doğrulandı; sahiplik kaydının gerçek oluşturma/güncelleme/yeniden deneme yazımları dahil 50 yerel kontrol Windows PowerShell 5.1 ve PowerShell 7 ile geçti. Canlı HTTP kurulumu sonraki kullanıcı çıktısıyla doğrulandı; HTTPS henüz kurulmadı.
- Kaynaklar: Şantiye `61c07995f204455b6d8be1dfc74649693303e8fe`, Asfaltik `ef08cb2bff23b3e83b7dbc8f51d0d7af51136795`. Tasarımlar korundu; Şantiye alan adı/hosting metni/metadata ve siteler arası bağlantı uyarlandı. Asfaltik `support.html` kaynakla aynı; kökte açılması için `index.html` kopyası eklendi. Olmayan Şantiye OG/icon dosyalarına bozuk metadata referansları kaldırıldı.

1. **`Web-Siteleri-IIS.zip`** ve **`web-kur.ps1`** dosyalarını sunucuda `C:\ProgramData\santiye` içine kopyala. ZIP'i elle API klasörüne açma.
2. Yönetici PowerShell'de çalıştır:

```powershell
powershell -ep bypass -File C:\ProgramData\santiye\web-kur.ps1
```

3. `HTTP_READY` çıktısını sakla. Hata varsa aynı hostu başka siteye bağlayarak aşma; çakışmayı incele.

**İlk kurulumdaki `Replace` hatasının düzeltmesi:** kullanıcı çıktısında üç argümanlı `File.Replace` çağrısı “Yol geçerli bir biçimde değil” ile durdu. Aynı hata yerel Windows PowerShell 5.1'de üretildi: düz `$null` bu .NET string parametresine boş metin olarak bağlanıyor. Gerçek CLR null için `[System.Management.Automation.Language.NullString]::Value` kullanıldı. ZIP aynıdır; yalnız yenilenmiş `web-kur.ps1` sunucudaki dosyanın üzerine kopyalanıp aynı komut yeniden çalıştırılır. Korumalı PREPARING kaydı ve eski release dosyaları silinmez; yeni deneme ayrı release oluşturur. Önceki 46 kontrol bu gerçek kayıt yazma çağrısını kapsamıyordu; yeni dört regresyon kontrolü gerçek Move/Replace/JSON okumasını çalıştırır (yalnız yetki yükseltme gerektiren ACL işlemleri izole fixture'da taklit edilir). Sonraki başarılı kurulum kaydı aşağıdadır.

**Düzeltilmiş betikle gerçek kurulum başarılı:** kullanıcı `HTTP_READY`, `StaticWeb-20261023-133326-d616c2c5` yedeği ve `20261023-133326-d616c2c5` release kaydını paylaştı. `SantiyeAgi-Web` site ID **4**, `Asfaltik-Web` site ID **5**; ayrı havuzlar ve planlanan klasörler kuruldu. Dört yerel HTTP kontrolü 200/hash eşleşmesi verdi. Bu sohbetten yapılan dört dış HTTP Host isteğinde de içerik hash'leri teslim paketiyle eşleşti. Başarılı HTTP kurulumu için betiği yeniden çalıştırmak gerekmez. Her iki `HttpsBindingPresent=false`; DNS, Pages, API ve sertifika değişikliği raporlanmadı. Sonraki adım DNS yayılımı ve aşağıdaki HTTPS kurulumudur.

Kaynak kurulum betiği `backend/deploy/install-static-websites.ps1` dosyasıdır; kısa teslim betiği ZIP'in beklenen SHA-256 değeriyle paketlenir. Betik DNS, sertifika, SMS, Firebase, Apple/Google satın alma, TestFlight veya GitHub Pages ayarını değiştirmez. İnternet yayını için IIS Static Content, port 80/443 erişimi ve aşağıdaki DNS/HTTPS adımları ayrıca gerekir.

## 2. DNS: Natro kaydı korunur, Cloudflare kullanılabilir

Cloudflare Free DNS için alan adını başka kayıt kuruluşuna transfer etmek gerekmez; Natro kayıt kuruluşu olarak kalabilir. Cloudflare'ın tam kurulumunda alan adı eklenir, mevcut DNS kayıtları gözden geçirilir ve Natro'da authoritative nameserver'lar Cloudflare'ın **o alan adına verdiği** iki adla değiştirilir. İki alan adının NS çiftinin aynı olduğu varsayılmaz. [Ücretsiz DNS/kayıt kuruluşu açıklaması](https://developers.cloudflare.com/dns/faq/), [tam kurulum](https://developers.cloudflare.com/dns/zone-setups/full-setup/)

Her iki alan adına Cloudflare tarafından ayrı ayrı `pat.ns.cloudflare.com` ve `thomas.ns.cloudflare.com` atandığı görüldü. Natro formlarında alan adı kontrol edilerek bu çift kaydedildi; her ikisi de “Alan adınızın DNS Sunucuları başarıyla güncellendi” yanıtı verdi. Bu, internet DNS yayılımının bittiği anlamına gelmez. Son 1.1.1.1 sorgusunda eski `ns1.natrohost.com`, `ns2.natrohost.com` ve `85.159.66.93` park adresi sürüyor; Cloudflare aktivasyonu bekliyor.

Önce mevcut DNS kayıtlarını dışa aktar veya kaydet. Özellikle **SPF TXT**, MX, DKIM, DMARC ve sahiplik doğrulama kayıtlarını içeri alıp birebir kontrol et; otomatik taramanın hepsini bulduğu varsayılmaz. Web kökü için A kaydını değiştirmek, aynı kökteki SPF TXT kaydını silmeyi gerektirmez. Hâlihazırda DNSSEC/DS etkinse nameserver geçiş prosedürü buna göre tamamlanır. [Cloudflare DNS içe/dışa aktarma](https://developers.cloudflare.com/dns/manage-dns-records/how-to/import-and-export/), [nameserver kurulumu](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/)

Her iki alan adı için hedef kayıtlar:

| Alan adı | Tür | Ad | Değer | İlk geçişte proxy |
|---|---|---|---|---|
| `santiyeagi.com.tr` | A | `@` | `45.59.70.198` | DNS only / gri bulut |
| `santiyeagi.com.tr` | CNAME | `www` | `santiyeagi.com.tr` | DNS only / gri bulut |
| `asfaltik.com.tr` | A | `@` | `45.59.70.198` | DNS only / gri bulut |
| `asfaltik.com.tr` | CNAME | `www` | `asfaltik.com.tr` | DNS only / gri bulut |

`www` için CNAME yerine aynı IP'ye tek A kaydı da seçilebilir; aynı ad altında A ile CNAME birlikte bırakılmaz. Çakışan eski web yönlendirmesi/GitHub IP kaydı veya çalışmayan IPv6 AAAA varsa yalnız ilgili web kaydı düzeltildikten sonra geçilir. E-posta ve diğer alt alanlar korunur. Başlangıçta gri bulut seçimi bilinçlidir: ziyaretçi doğrudan IIS'e gider ve gerçek IIS sertifikası doğrulanır. Cloudflare bu durumda HTTPS trafiğini sonlandırmaz. [Proxy/DNS only açıklaması](https://developers.cloudflare.com/dns/proxy-status/)

Gerekirse müşteriye Cloudflare hesabında yalnız bu iki alan adını kapsayan **Domain DNS** yetkisi verilebilir; başka alan adlarına, faturalandırmaya veya tüm hesaba yönetici erişimi gerekmez. Davet adresi belirlenmeden üye daveti gönderilmez. [Üyeler ve kapsam](https://developers.cloudflare.com/fundamentals/manage-members/), [Domain DNS rolü](https://developers.cloudflare.com/fundamentals/manage-members/roles/)

Mevcut kayıtlarda iki alan adının da SPF TXT değeri `v=spf1 include:_spfcls.natrohost.com include:_netblockshalon.natrohost.com ~all`; Cloudflare'e aynı içerikle aktarıldı. Tarama birer A, www CNAME ve TXT buldu; eski Natro web hedefleri değiştirildi. Kontrol edilen public DNS'te MX/AAAA kaydı bulunmadı; bilinmeyen özel alt alanların tamamının tarandığı iddia edilmez. `.xyz` ve diğer alan adlarında değişiklik yapılmadı. Natro'dan ücretli DNS hizmeti alınmadı.

## 3. HTTP kontrolünden sonra gerçek IIS HTTPS

Önce kök ve `www` adları için public DNS'in doğru IP'ye çözüldüğünü ve HTTP isteğinin doğru siteyi açtığını kontrol et. Yerel `HTTP_READY`, public DNS'in yerine geçmez. Sonra:

1. `docs/SUNUCU_PAKETI_TESLIM.md:60` mevcut API IP sertifikasının **Simple-acme** ile yenilendiğini kaydediyor. Önce mevcut istemcinin gerçek yolunu ve yenileme görevini salt okunur kontrol et; yeni bir istemci kurmak veya çalışan görevi değiştirmek gerekmez. Depoda kesin EXE/görev adı yok; önceki ekran görüntüsünde `C:\SSL` klasörü var. Anahtarları/yenileme JSON içeriklerini veya görev argümanlarını yazdırma.
2. Mevcut **Simple-acme** istemcisiyle yalnız `SantiyeAgi-Web` (**ID 4**) ve `Asfaltik-Web` (**ID 5**) site bağlamalarından ayrı yeni sertifikalar oluştur. Her sitenin kök ve `www` adı kapsamda olmalı; tüm sunucu sitelerini seçme ve mevcut API yenileme kimliğini/adını yeniden kullanma. Program kalıcı klasöründe kalmalı. [Resmî Simple-acme kurulum rehberi](https://simple-acme.com/manual/getting-started), [IIS site/binding seçimi](https://simple-acme.com/reference/plugins/source/iis)
3. HTTPS bağlamaları host adı ve **SNI** ile oluşturulmalı. Mevcut IP tabanlı API HTTPS bağlaması silinmez. Aynı IP üzerinde alan adlarının ayrılması için SNI kullanımı Microsoft tarafından belgelenmiştir. [Microsoft SNI rehberi](https://learn.microsoft.com/en-us/iis/get-started/whats-new-in-iis-8/iis-80-server-name-indication-sni-ssl-scalability)
4. Otomatik yenileme görevinin yeni sertifikaları kapsadığını ve mevcut API yenilemesinin korunduğunu doğrula. Mevcut Simple-acme görevi birden fazla yenilemeyi işler; gereksiz ikinci görevle değiştirme. [Resmî yenileme rehberi](https://simple-acme.com/manual/automatic-renewal)
5. Dört HTTPS hostunu sertifika doğrulamasını kapatmadan aç. Her sertifika ilgili hostu kapsamalı; Şantiye `#gizlilik`, `#hesap-silme`, `#kvkk`, `#kullanim-kosullari` ve Asfaltik `/support.html` ayrıca açılmalı. `https://45.59.70.198/health/ready` de önceki API sağlığına dönmeli.

Cloudflare **Flexible** seçerek veya istemcide sertifika doğrulamasını kapatarak eksik IIS HTTPS kurulumu örtülmez. Gri bulutta TLS doğrudan IIS'tedir. Daha sonra proxy açılırsa geçerli origin sertifikası korunarak Full (strict) ayrıca değerlendirilir; bu teslim proxy açmayı yapmaz. HTTP→HTTPS veya `www`→kök yönlendirmesi bu statik pakete eklenmemiştir; çalışan HTTPS doğrulandıktan sonra ilgili web sitelerine özgü olarak ayrıca kurulabilir. URL Rewrite bu paketin bağımlılığı değildir.

## 4. Eski GitHub bağlantıları kırılmadan kapanış

Yeni sunucu yayına geçince mevcut mobil uygulama kendiliğinden yeni adresi öğrenmez. Şu an `config/live.json` ve `config/live-android-push.json` dosyalarında dört URL derleme tanımı olarak eski `https://yusuftaskiran753-dot.github.io/-santiye-agi/` kökünü kullanır. `lib/config.dart` bunları derleme sırasında alır. App Store destek/pazarlama/gizlilik ve Play hesap silme alanları için eski adresler önceki yayın belgelerinde kayıtlıdır. Asfaltik mobil/mağaza ayarları bu depoda bulunmadığı için ayrıca kontrol edilmelidir.

Yeni HTTPS yayın doğrulandıktan sonra:

- Her iki canlı derleme yapılandırmasının dört yasal URL'sini `https://santiyeagi.com.tr/#...` olarak güncelle; yeni Android/iOS derlemesi üret. Kanonik `legal/web/index.html` ve yasal markdown'lardaki eski barındırma açıklamalarını da taşımayla tutarlı güncelle.
- Play ve App Store destek, pazarlama, gizlilik, kullanım koşulları ve hesap silme adreslerini ilgili yeni alan adına geçir. Formda URL değiştirmek, eski kurulu uygulamanın derleme sabitini değiştirmez.
- Eski Şantiye Pages `index.html` yerine sabit yeni alan adına, `location.hash` değerini koruyan küçük bir geçiş sayfası bırak. Asfaltik eski `/support.html` için yeni `https://asfaltik.com.tr/support.html` adresine karşılık oluştur. Bunun için yeni site içeriklerinin GitHub'da barındırılması gerekmez; yalnız eski bağlantıyı karşılayan yönlendirme kalır.
- GitHub Pages tamamen kapatılırsa eski `github.io` bağlantıları 404 olur. Eski uygulama sürümleri bu bağlantıları kullanabildiği sürece geçiş sayfası korunur veya bağlantı kaybı kullanıcı tarafından açıkça kabul edilir. `.com.tr` DNS değişikliği, GitHub'ın `github.io` adresini yönlendiremez.

Yönlendirme önerisinin özü (henüz uzak depoya uygulanmış değildir):

```html
<link rel="canonical" href="https://santiyeagi.com.tr/">
<a href="https://santiyeagi.com.tr/#gizlilik">Gizlilik</a>
<a href="https://santiyeagi.com.tr/#hesap-silme">Hesap silme</a>
<script>
const target = new URL('https://santiyeagi.com.tr/');
target.hash = location.hash;
location.replace(target.href);
</script>
```

## Kapanışta raporlanacak kanıt

Yerel tarayıcıda Şantiye ana sayfa/hesap silme hash yönlendirmesi ve Asfaltik ana destek sayfası açıldı; ekranlar teslim klasörüne kaydedildi. Asfaltik kaynağında destek adresi `yusuftaakiran753@gmail.com` olarak yazıyor; Şantiye'deki `yusuftaskiran753@gmail.com` adresinden farklı. Müşterinin içerik adresi doğrulanmadan sessizce değiştirilmedi.

Paket özeti ve `HTTP_READY` çıktısı; iki alan adının aktif authoritative NS/DNS sonucu; dört HTTPS hostunun geçerli sertifikayla doğru içeriği açması; API sağlığı ve eski sertifika yenilemesinin korunması; yeni yasal adreslerin mağaza/mobil derlemelere geçirilmesi; eski Pages için uygulanan uyumluluk kararı. Henüz yapılmayan adım tamamlanmış olarak raporlanmaz.
