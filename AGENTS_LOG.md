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

_(Claude (bulut) çalıştırılması gereken bir komut varsa buraya yazar.)_

- (şu an boş)

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
