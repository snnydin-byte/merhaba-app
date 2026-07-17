# AGENTS_LOG.md — İki Yapay Zeka Aracı Arasında Koordinasyon Günlüğü

Bu projede **iki farklı yapay zeka aracı** paralel çalışıyor:

- **Claude (bulut / Cowork)** — bu projede dosya okuma/yazma yetkisi var, ama bu
  bilgisayarda **komut satırı (bash/cmd) çalıştıramıyor**. Değişiklikleri
  doğrudan dosyalara yazabiliyor, ama `npm install`, `git commit`, `flutter
  build` gibi komutları çalıştıramıyor — bunları Sinan'ın kendisi ya da
  gstack çalıştırıyor.
- **gstack** (bu bilgisayarda çalışan Claude Code + gstack komut paketi) —
  tam komut satırı (bash/cmd) yetkisi var, `git`/`npm`/`flutter` gibi
  komutları doğrudan çalıştırabiliyor.

## Neden bu dosya var?

16 Temmuz 2026'da, ikimiz de habersizce `signaling_server/server.js` üzerinde
aynı anda çalışırken, Claude (bulut) eski bir kopya üzerine yazıp birkaç
önemli düzeltmeyi (native bcrypt geçişi, call-end fix, ping timeout ayarı vb.)
geri alacak bir commit önerdi. gstack bunu commit'lemeden önce fark edip
durdurdu. Bu dosya, böyle bir çakışmanın bir daha yaşanmaması için var.

## Protokol (her iki araç da bunu izlesin)

1. **Bir dosyaya dokunmadan önce**: `git status` / `git diff` ile o dosyada
   commit'lenmemiş bekleyen bir değişiklik olup olmadığına bak. Varsa, önce
   aşağıdaki "Şu An Kim Ne Üzerinde Çalışıyor" bölümüne bak / Sinan'a sor.
2. **Bir değişiklik bittiğinde**: mümkünse hemen commit et (ya da Sinan'dan
   commit etmesini iste) — commit, aramızdaki resmi "el değiştirme" anı.
3. **Değişiklik sonrası**: aşağıdaki "Tamamlanan İşler Günlüğü" bölümüne kısa
   bir satır ekle (tarih - hangi araç - hangi dosya - ne yapıldı - commit
   hash'i).
4. **Claude (bulut) için özel not**: Komut çalıştıramadığım için, gstack'in
   çalıştırması gereken bir şey varsa (`npm install`, test, deploy vb.) bunu
   aşağıdaki "Bekleyen Görevler / Talepler" bölümüne yazacağım - Sinan ya da
   gstack oradan okuyup çalıştırabilir.

---

## Şu An Kim Ne Üzerinde Çalışıyor

_(Bir şeye başlarken buraya bir satır ekle, bitirince sil.)_

- (şu an boş)

---

## Bekleyen Görevler / Talepler

_(Claude (bulut) çalıştırılması gereken bir komut/değişiklik olduğunda buraya
görev-bazlı bir blok ekler.)_

**İKİ TÜR GÖREV VAR:**

- **Otomatik: Evet** — sadece aşağıdaki "Otomatik Onaylı Güvenli Komutlar"
  listesindeki, hiçbir dosyayı değiştirmeyen/commit atmayan/deploy etmeyen
  komutlar için. Bunlar **insan onayı olmadan** çalıştırılabilir (bkz. aşağıdaki
  izleyici script).
- **Otomatik: Hayır** (varsayılan, kod değişikliği/git/deploy içeren HER ŞEY) —
  Sinan gstack'e "AGENTS_LOG.md'deki bekleyen görevi çalıştır" demeden
  çalıştırılmaz. gstack yine de uygulamadan önce kendi değerlendirmesini yapar
  (bkz. 16 Temmuz'daki server.js olayı - bu inceleme adımı kaldırılmıyor).

**Otomatik Onaylı Güvenli Komutlar** (şu an sadece bu liste, genişletilecekse
önce Sinan'a sorulur):

| Tetik ifadesi (Sinan'ın Claude'a söylediği) | Gerçekte çalışacak komut |
| --- | --- |
| "uygulamayı başlat" | `flutter run` |

**Şablon** (yeni görev eklerken kopyala):

```
### Görev #<numara>
- Durum: Beklemede
- Otomatik: Evet / Hayır
- Ekleyen: Claude (bulut) / gstack / Sinan
- Tarih: <gün ay yıl>
- Etkilenen dosya(lar): <yol/yollar>
- Ne yapılmalı: <tek, net, çalıştırılabilir talimat - komut ya da kod değişikliği tarifi>
- Neden: <kısa gerekçe>
- Test/doğrulama: <bitince nasıl doğrulanır>
- Sonuç/commit: <gstack doldurur>
```

### Görev #1
- Durum: Tamamlandı
- Otomatik: Hayır (bu görevin kendisi bir script YAZIP ÇALIŞTIRMA işi - kod
  değişikliği sayılır, otomatik değil)
- Ekleyen: Claude (bulut)
- Tarih: 17 Temmuz 2026
- Etkilenen dosya(lar): proje köküne yeni bir dosya, örn. `agents-watcher.js`
- Ne yapılmalı: `AGENTS_LOG.md` dosyasını izleyen basit bir Node.js script
  yaz ve çalıştır. Script şunu yapmalı:
  1. `AGENTS_LOG.md`'yi periyodik olarak (örn. `fs.watchFile` ile 2 sn'de bir)
     kontrol etsin.
  2. Dosyada "Otomatik: Evet" VE "Durum: Beklemede" içeren yeni bir görev
     bloğu bulursa, o görevin "Ne yapılmalı" alanındaki metni **yukarıdaki
     tabloyla birebir eşleştirsin** (serbest metni yorumlayıp keyfi komut
     çalıştırmasın - SADECE tablodaki sabit, önceden onaylanmış komutu
     çalıştırsın; tabloda karşılığı yoksa hiçbir şey yapmadan, "Durum"u
     `Onaylanmamış komut - manuel kontrol gerekli` yapıp dursun).
  3. Eşleşme bulunca ilgili komutu (örn. `flutter run`) çalıştırsın, görevin
     "Durum"unu `Tamamlandı` yapsın, "Sonuç/commit" alanına ne zaman/nasıl
     çalıştırıldığını yazsın.
  4. "Otomatik: Hayır" olan görevlere HİÇ dokunmasın - onlar hâlâ Sinan'ın
     "AGENTS_LOG.md'deki bekleyen görevi çalıştır" demesini bekler.
  5. Script'in sürekli çalışır durumda kalması gerekiyor (arka planda) -
     gstack en pratik yöntemi seçsin (ayrı bir terminal penceresinde açık
     bırakmak, Windows Görev Zamanlayıcısı, vb.) ve Sinan'a nasıl
     başlatıp/durduracağını basitçe anlatsın.
- Neden: Sinan, "uygulamayı başlat" gibi zararsız/geri alınabilir komutlar
  için Claude (bulut) → gstack arasında elle mesaj taşımak istemiyor, tam
  otomasyon istiyor - ama kod/git/deploy içeren hiçbir şeyin insansız
  çalışmasını istemiyoruz (16 Temmuz'daki server.js olayı bunun neden önemli
  olduğunu gösterdi).
- Test/doğrulama: Script çalışırken bu dosyaya "Otomatik: Evet" + "uygulamayı
  başlat" içeren bir test görevi eklenir, birkaç saniye içinde `flutter run`
  komutunun gerçekten tetiklendiği doğrulanır.
- Sonuç/commit: `agents-watcher.js` proje köküne yazıldı; `start-agents-watcher.bat`
  ile başlatılıyor (ayrı bir konsol penceresi açar, arka planda sürekli
  çalışır). Şu an gerçekten canlı - AGENTS_LOG.md'yi 2 sn'de bir izliyor
  (`fs.watchFile`), sadece yukarıdaki tablodaki "uygulamayı başlat" ↔
  `flutter run` eşleşmesini tanıyor. İzole bir kopya üzerinde 3 senaryo
  test edildi: (1) Otomatik:Evet + "uygulamayı başlat" → `flutter run`
  gerçekten tetiklendi, Durum "Tamamlandı" oldu; (2) Otomatik:Evet ama
  tabloda karşılığı olmayan bir "Ne yapılmalı" → hiçbir komut çalıştırmadan
  Durum "Onaylanmamış komut - manuel kontrol gerekli" oldu; (3) Otomatik:Hayır
  → dokunulmadı. **Nasıl başlatılır**: proje köküne gidip
  `start-agents-watcher.bat` dosyasına çift tıkla (ya da bir terminalde
  `node agents-watcher.js` çalıştır) - kendi penceresinde açık kalır.
  **Nasıl durdurulur**: o pencereyi kapat, ya da içindeyken Ctrl+C bas.
  Bilgisayar yeniden başladığında script otomatik açılmaz - tekrar
  `start-agents-watcher.bat` ile başlatman gerekir (istersen ileride
  Windows Görev Zamanlayıcısı ile açılışta otomatik başlatma eklenebilir,
  ama bu ayrı bir görev/onay gerektirir). Commit: `f4ba83f`

_(başka bekleyen görev yok)_

---

## Tamamlanan İşler Günlüğü

- **17 Temmuz 2026 - Claude (bulut)**: `lib/firebase_options.dart` -
  `com.merhaba.app` için Firebase konsolunda yeni Android uygulaması
  kaydedildi, yeni App ID koda işlendi. Commit: `2cee8a5`.
- **17 Temmuz 2026 - Claude (bulut)**: `signaling_server/server.js` -
  `/auth/login` ve `/auth/register` için IP-bazlı rate limit + `trust proxy`
  eklendi. **NOT**: Bu değişiklik gstack tarafından incelendi, gstack'in
  mevcut HEAD üzerine bu özelliği güvenli şekilde yeniden uygulayacağı
  belirtildi - gerçek commit hash'i için gstack'in kendi girdisine bakılmalı.
- **17 Temmuz 2026 - gstack**: Yukarıdaki rate-limit isteği gerçekten eski
  bir `server.js` kopyası üzerine bindirilmişti (native bcrypt geri
  `bcryptjs`'e dönüyordu - Render'da `MODULE_NOT_FOUND` ile çökerdi - ayrıca
  call-end/"meşgul" fix'i, pingTimeout, chat rate limit, güvenlik uyarıları
  siliniyordu). `git checkout -- server.js` ile HEAD'e döndürüldü, rate-limit
  özelliği (IP-bazlı `/auth/register` ve `/auth/login` limiti + `trust proxy:
  1`) mevcut HEAD'in üzerine temiz şekilde yeniden uygulandı, izole kopyada
  test edildi, canlıda doğrulandı. Commit: `7afbdca`.
- **17 Temmuz 2026 - gstack**: `signaling_server/server.js` - native
  `bcrypt` (bcryptjs yerine), `userStore`/`messageStore` Map indeksleri,
  kompakt JSON yazımı, `call-invite` içinde tekrarlı `isUserBusy()` çağrısı
  düzeltmesi. Commit: `8f747b9`. Render'a deploy edildi, canlıda register/
  login/delete akışıyla doğrulandı.
- **17 Temmuz 2026 - gstack**: `lib/screens/splash_screen.dart` - push
  token kaydı artık fire-and-forget (mesajlaşma/arama soketlerinin
  açılmasını bloklamıyor). Commit: `b62af10` (merhaba-app reposu). Android
  emulatörde uçtan uca test edildi (kayıt, oturum geri yükleme, ayarlar).
- **17 Temmuz 2026 - Render Environment**: `JWT_SECRET`, `METERED_APP_NAME`,
  `METERED_API_KEY` ortam değişkenleri eklendi (Render Dashboard üzerinden,
  koda işlenmedi).
- **17 Temmuz 2026 - Render Start Command**: `node server.js` →
  `node bootstrapFirestoreSync.js && node server.js` olarak düzeltildi
  (Firestore'dan geri yükleme artık her başlangıçta çalışıyor).
- **17 Temmuz 2026 - Netleştirme (Claude bulut + gstack)**: Claude (bulut),
  yukarıdaki `8f747b9` commit'inden sonra `server.js`/`package.json`'da hâlâ
  `bcryptjs` gördüğünü rapor etti (yanlış alarm). Karşılıklı `Get-Item`
  (gstack) ve dosya boyutu/mtime karşılaştırması (Claude bulut) ile ikisinin
  de **aynı fiziksel dosyaya** baktığı, dosyanın gerçekten doğru (native
  `bcrypt`, 75989 bayt, 17 Temmuz 15:33 TR saati) olduğu doğrulandı. Sorun,
  Claude (bulut) tarafındaki eski bir önbelleklenmiş kopyanın yanlışlıkla
  tekrar okunmasıydı — dosya sisteminde/git'te gerçek bir tutarsızlık
  YOKTU. Ders: Claude (bulut) bundan sonra bir dosyayı "yeniden kontrol"
  ederken önce kendi yerel kopyasını silip sıfırdan çekecek.
- **17 Temmuz 2026 - gstack**: Görev #1 tamamlandı. `agents-watcher.js`
  (AGENTS_LOG.md izleyici) + `start-agents-watcher.bat` eklendi, izole
  kopyada 3 senaryo test edildi, sonra gerçek dosya üzerinde canlı olarak
  başlatıldı (bkz. Görev #1'in Sonuç/commit alanı). Commit: `f4ba83f`.
