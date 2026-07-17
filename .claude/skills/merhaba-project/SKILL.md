---
name: merhaba-project
description: Provides project context, architecture facts, and working conventions for the Merhaba app (a Flutter random video-chat, friends, and messaging app with a Node.js/Socket.IO signaling server on Render). Use whenever working on the Merhaba app or its signaling_server backend, or when Sinan mentions Merhaba, gstack, AGENTS_LOG.md, Render deploys, Firebase/Firestore, or this project's git repos.
---

# Merhaba Projesi — Bağlam ve Çalışma Kuralları

## Proje nedir
Merhaba, Flutter ile yazılmış rastgele görüntülü sohbet + arkadaşlık + mesajlaşma uygulaması. Sinan, tek başına geliştiren sahibi/geliştiricisi — teknik olmayan bir kullanıcı, terminal/git konularında adım adım rehberliğe ihtiyaç duyuyor.

## Depo yapısı (ÖNEMLİ — iki ayrı git deposu var, karıştırma)
- `merhaba-app` (proje kökü, client/Flutter kodu) — GitHub'da **PUBLIC** (`snnydin-byte/merhaba-app`). GitHub Pages `/docs` klasöründen Gizlilik Politikası/Topluluk Kuralları'nı yayınlıyor.
- `signaling_server/` — **AYRI ve PRIVATE** bir git deposu (`snnydin-byte/merhaba-signaling`). Kök `.gitignore` bu klasörü blanket-exclude ediyor ki nested repo gibi görünmesin. Bu klasörde git komutu çalıştırmadan önce oraya `cd` edilmiş olmalı.

## Sunucu mimarisi (signaling_server)
- Node.js + Express + Socket.IO, Render.com free tier'da (`https://merhaba-signaling.onrender.com`).
- Kimlik doğrulama: JWT (`jsonwebtoken`), şifreler native `bcrypt` ile hash'leniyor (`bcryptjs` DEĞİL — bir keresinde bu ikisi karışıp prod'u çökertebilecek bir commit öneriye neden olmuştu).
- Kalıcı veri (`users.json`, `messages.json`, `reports.json`, `turnCredential.json`) yerel JSON dosyaları + Firestore'a (`merhabaAppData` koleksiyonu) debounced yedek.
- **Render "Start Command" mutlaka** `node bootstrapFirestoreSync.js && node server.js` olmalı, sadece `node server.js` DEĞİL — aksi halde her yeniden başlangıçta Firestore geri yükleme atlanır, kayıtlı kullanıcılar "e-posta/şifre hatalı" hatası alır (gerçek yaşanmış bir prod bug'ıydı).
- TURN/STUN: Metered (metered.live), `/turn-credentials` ucu üzerinden; `METERED_API_KEY`/`METERED_APP_NAME` Render env var olarak ayarlı.
- `JWT_SECRET` de Render env var olarak ayarlı — kodda hardcoded (güvensiz) fallback'ler var ama gerçek env var'lar kullanılıyor.
- Giriş/kayıt uçlarında (`/auth/login`, `/auth/register`) IP-bazlı rate limit var (brute-force koruması), `app.set('trust proxy', 1)` gerekli (Render'ın proxy'si yüzünden).

## Android/Firebase
- `applicationId` (Android) = `com.merhaba.app` (eski `com.example.merhaba`'dan Play Store hazırlığı için değiştirildi; Kotlin `namespace` hâlâ `com.example.merhaba` kalabilir, bu normal/zararsız).
- Firebase projesi: `merhaba-93ddb`. Android app kaydı `com.merhaba.app` paket adıyla YAPILMIŞ durumda, `lib/firebase_options.dart`'taki `appId` buna göre güncel.
- Release keystore (`android/merhaba-release.jks`, `android/key.properties`) Sinan'ın kendi bilgisayarında oluşturuldu, git'e hiç eklenmedi (`.gitignore`'da).

## gstack ile birlikte çalışma (ÇOK ÖNEMLİ)
Bu projede sen (Claude/Cowork, bulutta çalışıyorsun, komut çalıştıramıyorsun — device_bash yok) ile **gstack** (Sinan'ın bilgisayarında VS Code + Claude Code + gstack komut paketi, tam shell/git yetkisi var) PARALEL çalışıyor. Koordinasyon için proje kökünde **`AGENTS_LOG.md`** dosyası var:

- Bir dosyaya dokunmadan önce `AGENTS_LOG.md`'nin "Şu An Kim Ne Üzerinde Çalışıyor" bölümüne bak.
- Kod/git/deploy gerektiren bir iş varsa, "Bekleyen Görevler" bölümüne görev-bazlı bir blok yaz (dosyadaki şablonu kullan), Sinan'a "AGENTS_LOG.md'deki görevi çalıştır" demesini söyle — kendi başına git commit/push/deploy YAPMAYA ÇALIŞMA, zaten yapamıyorsun.
- "Otomatik Onaylı Güvenli Komutlar" tablosundaki komutlar (şu an: "uygulamayı başlat" → VS Code workspace üzerinden görünür/etkileşimli terminalde `flutter run`) `agents-watcher.js` scripti tarafından İNSAN ONAYI OLMADAN otomatik çalıştırılıyor — bu listeye yeni bir şey eklemeden önce MUTLAKA Sinan'a sor, script serbest metni asla yorumlamaz, sadece tablo eşleşmesiyle çalışır.
- **16 Temmuz 2026 olayı**: Sen (Claude bulut) eski bir `server.js` kopyasının üzerine yazıp native bcrypt geçişi/call-end fix/ping timeout gibi birkaç önemli düzeltmeyi geri alacak bir commit önermiştin — gstack bunu commit'lemeden ÖNCE fark edip durdurdu. Ders: gstack'in üzerinde çalıştığı paylaşılan dosyaları düzenlemeden önce HER ZAMAN taze bir kopya çek, gstack'in bağımsız incelemesine güven, asla "ben zaten biliyorum" deyip eski bir kopyanın üzerine yazma.
- **Kritik önbellek dersi**: Kendi dosya okuma aracın (Read) bazen bir dosya yolunu daha önce okuduysan, o yola taze içerik çekmiş (device_stage_files) olsan bile ESKİ içeriği gösterebiliyor — bu yüzden iki kez gstack'in doğru işine karşı yanlışlıkla "sende sorun var" alarmı verilmişti. Bir şeyi doğrularken (özellikle gstack'in az önce değiştirdiği bir dosyada), önce yerel önbelleklenmiş kopyayı SİL (`rm`), sonra taze çek, sonra Read yerine `grep`/`node --check`/`wc -l` gibi komutlarla kontrol et. Bunu atlayıp doğrudan Read'e güvenip gstack'i suçlama.

## Cihaz köprüsü iş akışı (dosya düzenleme deseni)
Komut çalıştıramıyorsun. Bir dosyayı düzenlemek için: `device_stage_files` ile diskten çek → Read/Edit → `SendUserFile` → `device_commit_files` (kör `force:true` yerine, mümkünse `expectedMtimeMs` ile koru) → gerekirse `grep`/boyut karşılaştırmasıyla doğrula. Terminal komutu gerektiren adımlar (git, npm, flutter) için Sinan'a ya da gstack'e tam olarak ne yazması gerektiğini adım adım anlat.

## Standing kullanıcı tercihleri (Sinan)
- Türkçe konuş.
- Teknik detayları/tıklamaları adım adım, sabırla anlat — placeholder bırakma, kod vermeden önce eksik bilgi varsa sor.
- "Google Play'e yayınlanacakmış gibi" kod kalitesi/güvenlik standardı bekleniyor, ama Play Console hesabı/gerçek yayın şimdilik ertelendi — bunu zorlamadan, istendiğinde ele al.
