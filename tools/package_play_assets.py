from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, zipfile
root=Path('output/google-play')
for path in [root/'02-ozellik-grafigi-1024x500.png', *sorted((root/'screenshots').glob('*.png'))]:
    with Image.open(path) as source:
        source.convert('RGB').save(path,optimize=True)
files=[root/'01-uygulama-simgesi-512.png',root/'02-ozellik-grafigi-1024x500.png',*sorted((root/'screenshots').glob('*.png'))]
for path in files:
    with Image.open(path) as im:
        im.verify()
    with Image.open(path) as im:
        if path.name.startswith('01-uygulama'):
            assert im.size==(512,512) and path.stat().st_size<1024*1024
        elif path.name.startswith('02-ozellik'):
            assert im.size==(1024,500) and im.mode=='RGB' and path.stat().st_size<15*1024*1024
        else:
            assert im.size==(1080,1920) and im.mode=='RGB' and path.stat().st_size<8*1024*1024
font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',19)
sheet=Image.new('RGB',(900,1100),'#e7e5e0')
draw=ImageDraw.Draw(sheet)
for i,path in enumerate(sorted((root/'screenshots').glob('*.png'))):
    x=24+(i%3)*296; y=30+(i//3)*540
    with Image.open(path) as source:
        thumb=source.resize((270,480),Image.Resampling.LANCZOS)
        sheet.paste(thumb,(x,y))
    draw.text((x,y+488),path.stem,fill='#16202a',font=font)
sheet.save('output/google-play-onizleme.jpg',quality=93)
readme='''ŞANTİYE AĞI — GOOGLE PLAY GÖRSELLERİ

Uygulama simgesi alanı:
  01-uygulama-simgesi-512.png — 512 × 512

Özellik grafiği alanı:
  02-ozellik-grafigi-1024x500.png — 1024 × 500

Telefon ekran görüntüleri alanı:
  screenshots klasöründeki 6 PNG dosyasını numara sırasıyla birlikte yükleyin.
  Her biri 1080 × 1920 (9:16), RGB PNG, 8 MB altında.

Video isteğe bağlıdır; bu pakette video yoktur, alanı boş bırakabilirsiniz.

Ekranlar 18 Ekim 2026'da mağazaya hazırlanan sürüm 2.1.2 (7) AAB'sinden
üretilen imzalı release uygulamasının Android emülatöründen alındı.
Canlı sunucudaki mevcut Tuna Test hesabı ve teknik kontrol kayıtları kullanıldı.
Kontrol isimli ilanlar ve tutarlar gerçek ticari işlem/ödeme iddiası değildir.
Ekran içerikleri yeniden çizilmedi; yalnız kayıpsız RGB dosya biçimine çevrildi.
Android durum çubuğundaki saat/simgeler çekim için düzenlendi.

Bu dosyaları mağazaya yüklemek kapalı testi veya 14 günlük süreyi başlatmaz.
'''
(root/'NEREYE_YUKLENECEK.txt').write_text(readme,encoding='utf-8-sig')
archive=Path('output/SantiyeAgi-GooglePlay-Gorseller.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for path in sorted(root.rglob('*')):
        if path.is_file(): z.write(path,path.relative_to(root))
print(json.dumps({'assets':len(files),'phone_screenshots':6,'all_dimensions_and_sizes':'pass','archive_bytes':archive.stat().st_size}))
