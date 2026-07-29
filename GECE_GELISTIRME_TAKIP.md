# Gece Geliştirme Takibi — 17-18 Temmuz 2026

**NOT (22 Tem 2026 gece, gstack)**: Bu dosyadaki madde 2-7'nin TAMAMI aslında
20 Temmuz 2026'da (`OZELLIK_BACKLOG_UYGULAMA.md`'nin "Batch D" bölümü) zaten
tamamlanıp E2E test edilmişti - bu dosya o zaman güncellenmemiş, "Beklemede"
etiketleri YANLIŞ/ESKİ kalmıştı. Madde 2'yi ("Tekrar eşleş") bu gece tekrar
inceleyip düzeltirken fark edildi (bkz. AGENTS_LOG.md 22 Tem "DÜZELTME"
kaydı). **Bu dosyada gerçekten yapılacak bir şey KALMADI** - yeni bir
oturum bu dosyayı görürse doğrudan `OZELLIK_BACKLOG_UYGULAMA.md`'nin Batch D
bölümüne bakıp orada zaten "TAMAMLANDI" yazdığını doğrulasın, buradaki
"Beklemede" etiketlerine GÜVENMESİN.


Bu dosya, Sinan uyurken saatlik/iki saatlik aralıklarla tetiklenen ayrı Claude
(bulut) oturumlarının SIRAYLA, TEK TEK işlediği bir kontrol listesidir. Her
oturum bu dosyayı okur, sıradaki "Beklemede" maddeyi alır, uygular, test eder,
cihaza yazar, AGENTS_LOG.md'ye (Otomatik: Evet ile) işler, bu dosyada maddeyi
"Tamamlandı" yapar ve biter. Sonraki tetiklenme kaldığı yerden devam eder.

**ÖNEMLİ KURALLAR (her oturum için):**
1. Başlamadan önce ilgili tüm dosyaları `rm` + `device_stage_files` ile TAZE
   çek (önbellek riski var, bkz. AGENTS_LOG.md'deki geçmiş "stale cache"
   olayları) - gstack aradan bir şey commit'lemiş olabilir.
2. Sadece TEK bir madde işle, sonra dur (küçük/test edilebilir/gözden
   geçirilebilir parçalar halinde ilerlemek, büyük/riskli tek seferlik
   commit'lerden daha güvenli).
3. Gerçek test yap (mümkünse gerçek `node`/`npm install` ile sunucu ayağa
   kaldırıp gerçek istekler atarak, Dart tarafında en azından parantez/süslü
   parantez dengesi + mevcut desenlerle tutarlılık kontrolü) - uydurma test
   iddiası YOK.
4. AGENTS_LOG.md'ye YENİ bir Görev olarak ekle: `Otomatik: Evet` (Sinan 18
   Temmuz'da bu yetkiyi verdi - bkz. AGENTS_LOG.md Protokol bölümü), tam
   "Ne yapılmalı"/"Test/doğrulama" alanlarıyla - gstack bunu kendi
   incelemesinden (flutter analyze/test/build) sonra commit'leyebilir.
5. Sır/API anahtarı gerektiren bir özellikse (ör. çeviri API'si), Cloudinary/
   photoStorage.js desenindeki gibi GRACEFUL DEGRADATION ile yaz - env var
   yoksa özellik sessizce devre dışı kalsın, sunucu çökmesin. Sırrı SEN
   asla üretme/varsayma - Sinan'ın kendisi ekleyecek.
6. Şüpheli/beklenmedik bir durumla karşılaşırsan (ör. gstack'in az önce
   değiştirdiği bir dosyada beklenmedik içerik) DUR, bu dosyaya bir not
   düş, AGENTS_LOG.md'nin "Şu An Kim Ne Üzerinde Çalışıyor" bölümüne yaz,
   o maddeyi atla.
7. **Bitirme koşulu (GÜNCELLENDİ - Sinan 10 saatlik bir pencere istedi)**: Eğer
   bu dosyadaki TÜM maddeler "Tamamlandı"/"Ertelendi" ise, YA DA sunucu
   saatine göre (bkz. `date -u` komutu) **2026-07-18 09:45 UTC**'yi (Türkiye
   saatiyle ~12:45) geçtiyse: `list_triggers` ile "gece-gelistirme-dongusu"
   adlı tetikleyiciyi bul, `delete_trigger` ile durdur, Sinan için bu
   dosyanın en altına kısa bir özet yaz, bitir. Bu pencere içinde ~5
   tetiklenme olacak (her 2 saatte bir) - aşağıdaki listede en az 5 aktif
   madde bulunmasına dikkat edildi ki hiçbir tetiklenme "yapacak iş yok"
   diye erken durmasın.
8. **Kapsam sınırı (Sinan "tüm rakip özelliklerini ekleyin, onay bekleme"
   dedi ama bu SINIRSIZ bir yetki DEĞİL)**: Kumar-benzeri sanal
   hediye/jeton ekonomileri, zayıf/sahte yaş doğrulama, gerçek para
   akışı/ödeme entegrasyonu, yeni native bağımlılık gerektiren riskli
   paketler (kamera/ML SDK'ları) bu gece turuna DAHİL DEĞİL - bunlar
   `RAKIP_ANALIZI_VE_YOL_HARITASI.md`'de "kaçınılması gerekenler" olarak
   zaten işaretlendi ve gündüz, Sinan aktifken ele alınmalı. Aşağıdaki
   liste zaten yalnızca güvenli/bounded maddeler içeriyor - listeye YENİ
   bir madde EKLEME, yalnızca var olanları işle.

---

## Kontrol Listesi (sırayla işlenecek)

### 1. Sesli-yalnız mod (kamerasız, yalnızca ses ile eşleşme)
- Durum: Tamamlandı (18 Temmuz 2026, Claude bulut - canlı oturumda, Sinan'ın
  "döngüyü aç, o özellikleri hemen ekle" talimatı üzerine döngü beklenmeden
  uygulandı) - bkz. AGENTS_LOG.md Görev #7, gstack incelemesi/commit'i
  bekliyor.
- Ne: Eşleşme öncesi (pre_call_screen.dart) kullanıcı "yalnızca sesli" modunu
  seçebilsin - seçilirse kamera hiç açılmasın/akışa dahil olmasın, yalnızca
  ses akışı gönderilsin. Sunucu tarafında (server.js/webrtc_service.dart)
  eşleşen taraflara bu tercihin bildirilmesi gerekebilir (karşı taraf video
  beklemesin).
- Mevcut ilgili dosyalar: `lib/screens/pre_call_screen.dart`,
  `lib/services/webrtc_service.dart`, `lib/screens/video_chat_screen.dart`.

### 2. "Tekrar eşleş" — önceki partnere dönme
- Durum: Tamamlandı (22 Tem 2026 gece, gstack tarafından DOĞRULANDI - kod
  zaten önceki bir oturumda tam yazılmıştı ama hiç canlı test edilmemişti,
  bu yüzden bu madde yanlışlıkla "Beklemede" kalmıştı). `call_service.dart`
  `requestRematch()` -> sunucudaki `rematch-invite` (call-invite/
  pendingCallInvites altyapısını yeniden kullanıyor) -> karşı tarafa
  `call-invite-received` (isRematch:true) -> kabul/red `call-invite-response`
  -> ikisi de `matched`. `video_chat_screen.dart`'ta karşı taraf ayrılınca
  gösterilen snackbar'daki "Tekrar Eşleş" aksiyonu bunu tetikliyor.
  Production'a karşı gerçek E2E testle (davet gönderme/ulaşma/kabul/
  yeniden eşleşme) doğrulandı. `merhaba-signaling` commit: `7d6f53c`
  (yalnızca zararsız bir `establishMatch()` refactor'ü + bu maddeyle
  ALAKASIZ, yanlışlıkla eklenip geri alınan bir kod - detay AGENTS_LOG.md).

### 3. Uygulama içi hızlı tepkiler (görüşme sırasında emoji tepkisi)
- Durum: Beklemede
- Ne: video_chat_screen.dart'a küçük bir emoji tepki çubuğu (ör. 👍 😂 ❤️ 👋) -
  basılınca karşı tarafın ekranında kısa süreliğine animasyonlu şekilde
  belirsin. WebRTC veri kanalı ya da mevcut socket.io bağlantısı üzerinden
  basit bir event ile taşınabilir (bkz. mevcut `report-user` gibi socket
  event'i desenleri).

### 4. İlgi alanı etiketleriyle eşleştirme
- Durum: Beklemede
- Ne: settings_screen.dart'ta zaten var olan cinsiyet/yaş/onaylı filtrelerinin
  yanına, kullanıcının profilindeki `interests` (zaten AppUser modelinde var)
  alanına göre rastgele eşleşmede öncelik/filtre eklenmesi - EmeraldChat
  tarzı. Sunucu tarafında eşleştirme kuyruğu mantığının (server.js
  `tryMatch()` civarı) güncellenmesi gerekiyor.

### 5. Çeviri altyapısı (gerçek zamanlı mesaj çevirisi — graceful degradation)
- Durum: Beklemede
- Ne: chat_screen.dart'taki mesajlara opsiyonel bir "çevir" butonu - sunucu
  tarafında yeni bir `translationService.js` (Google Translate ya da DeepL
  API, env var `TRANSLATE_API_KEY` yoksa sessizce devre dışı - photoStorage.js
  ile AYNI desen). Sır SEN üretme, yalnızca altyapıyı hazırla.

### 6. Sohbette "yazıyor..." göstergesi
- Durum: Beklemede
- Ne: chat_screen.dart'ta karşı taraf yazarken küçük bir "... yazıyor"
  göstergesi (WhatsApp/Instagram tarzı). Socket.IO üzerinden basit bir
  `typing`/`stop-typing` event'i (mevcut mesajlaşma event'leriyle aynı
  desende, `messageStore.js`/`server.js`'teki ilgili bölüme bakılabilir),
  istemci tarafında debounce'lu (kullanıcı yazmayı bırakınca ~2 sn sonra
  otomatik kaybolan) bir gösterge.

### 7. Günlük giriş serisi / rozet sistemi (saf uygulama-durumu, parasal değil)
- Durum: Beklemede
- Ne: Kullanıcı art arda kaç gün giriş yaptığını gösteren basit bir "seri"
  sayacı (ör. profile_screen.dart'ta küçük bir rozet: "5 günlük seri 🔥").
  Sunucu tarafında userStore.js'e `lastLoginDate`/`streakCount` alanları
  eklenip her `/auth/me` ya da girişte güncellenmesi yeterli - HİÇBİR
  parasal ödül/jeton YOK, yalnızca görsel bir rozet (Chamet/MICO tarzı
  jeton ekonomilerinden kasıtlı olarak kaçınılıyor, bkz. madde 8 kural).

### 8. AR yüz filtreleri — GECE İÇİN UYGUN DEĞİL, ATLA
- Durum: Ertelendi (gece turuna dahil etme)
- Neden: Yeni native bağımlılıklar (kamera/ML paketleri) ve olası platform
  uyumluluk sorunları içeriyor - bu, Sinan uyanıkken/aktifken ele alınmalı,
  gece unattended bir oturumun riske atmaması gereken bir kapsam.

---

## Oturum Özetleri (her oturum kendi özetini buraya ekler)

- **18 Temmuz 2026 - Claude (bulut), canlı oturum (Sinan uyanıkken, "döngüyü
  aç, o özellikleri hemen ekle" talimatıyla, otomatik gece döngüsünün
  DIŞINDA)**: Madde #1 (Sesli-yalnız mod) tamamlandı. `webrtc_service.dart`,
  `pre_call_screen.dart`, `video_chat_screen.dart` ve `server.js` düzenlendi;
  gerçek 2-istemcili socket.io testiyle (3 senaryo, 6/6 doğrulama) sunucu
  tarafı doğrulandı, Dart tarafı parantez dengesi + mantık satır satır
  gözden geçirilerek doğrulandı (Flutter SDK'sı bu ortamda yok, gstack'in
  `flutter analyze`/`test`/`build` incelemesi hâlâ gerekiyor). Detaylar için
  AGENTS_LOG.md Görev #7'ye bak. Otomatik gece döngüsü (`gece-gelistirme-
  dongusu` tetikleyicisi) Sinan'ın isteğiyle yeniden etkinleştirildi -
  sıradaki tetiklenmede madde #2'den devam edilecek.
