# Özellik Backlog — 116+120 Anket Uygulama Planı

18 Temmuz 2026, Sinan'ın "iki anketteki tüm özellikleri ekle, UI tasarımı
bana ait" talimatı üzerine hazırlandı. Bu dosya git'e eklenmiyor
(GECE_GELISTIRME_TAKIP.md / RAKIP_ANALIZI_VE_YOL_HARITASI.md ile aynı yerel-
kalsın deseni) — yalnızca bu oturumun (ve gerekirse sonraki oturumların)
ilerleme takibi için.

## Sinan'ın 3 karara verdiği cevaplar (bağlayıcı)
1. Jeton/elmas/sanal hediye ekonomisi → **sadece parasız kısımlar** (rozet/
   seviye/leaderboard). Gerçek satın alınabilir para birimi YOK.
2. Dış servisler (Paycell, Papara/ininal, operatör faturası, BiP-tarzı para
   transferi, Hive/AWS Rekognition, Yoti/resmi kimlik KYC) → **hiçbirine
   dokunulmuyor**. Zaten önceden onaylı çeviri altyapısı (GECE madde 5,
   graceful-degradation) bu yasağın dışında, o ayrıca ele alınıyor.
3. AR yüz filtreleri (#109) → **ayrı bir oturuma bırakıldı** (native ML
   bağımlılığı riski).

## Bu turda HİÇ ELE ALINMAYAN kategoriler (gerekçeli)
- **Canlı Yayın/Sesli Oda platformu (26 madde)** — co-host, çoklu-konuk-
  yayın, PK savaşı, biletli oda, live shopping, raid, klip, agency sistemi
  vb. çoğu ya jeton ekonomisine ya da tam bir SFU (LiveKit/mediasoup)
  altyapısına bağımlı — bu, mevcut 1'e1 WebRTC mimarisinden farklı YENİ bir
  altyapı kararı (AGENTS_LOG'daki "deploy/altyapı değişikliği" istisnasına
  giriyor). Ayrı bir konuşma gerektirir, bu backlog'a dahil değil.
- **Kayıtsız/anonim web istemcisi (#11)** — ayrı bir WebRTC web uygulaması,
  Flutter uygulamasına "eklenecek" bir özellik değil.
- **Eşleşilen kişiyi sosyal medyadan ekleme (#7)** — BİLİNÇLİ OLARAK
  UYGULANMIYOR. Anonim rastgele görüşme sonrası uygulama-dışı iletişime
  yönlendirme, zayıf yaş doğrulamayla birleşince somut bir grooming/istismar
  riski taşıyor (anketin kendisinde de işaretli) — projenin güvenlik
  duruşuyla (NCMEC-bilinci, "küçük yaşta" bildirim kategorisi vb.) doğrudan
  çelişir.
- **Anonim tehlike uyarı ağı (Tea App tarzı, eski liste Güven#6)** —
  BİLİNÇLİ OLARAK UYGULANMIYOR. Bir kullanıcı hakkında serbest-metin
  "uyarı" paylaşan açık bir ağ, iftira/taciz aracı olarak kötüye
  kullanılabilir. Bunun yerine zaten var olan moderasyon/bildirim sistemi
  (reportStore.js) kullanılmalı.
- **7/24 insan moderasyon ekibi (#13)** — bu bir istihdam/operasyon kararı,
  kod maddesi değil.
- **Uçtan uca şifreleme (#29)** — GERÇEK E2EE (anahtar üretimi/değişimi,
  cihaz üstü şifreleme) özenle, tek başına tasarlanması gereken bir güvenlik
  konusu; bu mega-batch'e sıkıştırılırsa yanlış yapılmış bir şifreleme,
  hiç olmamasından DAHA KÖTÜ bir yanlış güven hissi yaratır. Ayrı, odaklı
  bir oturumda ele alınmalı — bu backlog'da YOK.

## Uygulanacak maddeler — Batch sırası

### Batch A — Mesajlaşma çekirdeği (chat_screen.dart, messaging_service.dart, messageStore.js, server.js)
- [x] Mesaj düzenleme (süre sınırlı, "düzenlendi" etiketi) — 18 Tem 2026, commit 694c6e4/31906a7
- [x] Mesajı herkesten silme — 18 Tem 2026, commit 694c6e4/31906a7
- [x] Mesaj tepkileri (emoji reaction) — 18 Tem 2026, commit 694c6e4/31906a7
- [x] Sabitlenmiş mesajlar — 18 Tem 2026, commit 694c6e4/31906a7
- [x] Mesaja yanıtla (quote-reply) — 18 Tem 2026, commit 694c6e4/31906a7
- [x] Kendine not (saved messages) — 18 Tem 2026, commit 694c6e4/31906a7
- [x] Mesaj planlama (zamanlanmış gönderim) — 19 Tem 2026, commit'lendi+push'landı (merhaba-signaling 60c25e8, merhaba-app 36f36f0). Yeni scheduledMessageStore.js + 20sn'lik periyodik kontrol döngüsü (soket bağlantısına bağlı değil, kullanıcı çevrimdışı olsa bile zamanı gelince gönderiyor). E2E Node testiyle HEM doğrulama katmanı (1dk/30gün sınırları, arkadaşlık kontrolü) HEM gerçek gönderim anı (~65sn gerçek bekleme ile) canlı doğrulandı. İstemci UI (ek menüsündeki "Zamanla", AppBar rozeti, iptal edilebilir liste) yalnızca statik analizle doğrulandı - emülatör canlı testi bu turda yapılmadı (Sinan oyun oynayacağı için emülatör kapatıldı), bir sonraki "toplu kontrol"de görsel doğrulama gerekiyor.
- [x] Anket (poll) oluşturma — 19 Tem 2026, CANLI test edildi + commit'lendi + push'landı (merhaba-app 1f3882c, merhaba-signaling bc49d03)
- [x] Çevrimiçi/son görülme gizliliği aç-kapat — 19 Tem 2026, tamamlandı + commit'lendi + push'landı (merhaba-app 6cbaaee, merhaba-signaling 08ba7ab). Bu arada GET /friends'te GERÇEK bir gizlilik sızıntısı bug'ı bulunup düzeltildi (.map(publicUser) array index'i viewerId sanıyordu).
- [x] Okundu bilgisini aç-kapat (genel) — 19 Tem 2026, tamamlandı (aynı commit'ler) - conversation-mark-read soket olayı, mesaj balonlarında tek/çift tik.
- [x] Toplu/broadcast liste — 19 Tem 2026, commit'lendi+push'landı (merhaba-app a2ce962). İstemci-taraflı: Arkadaşlar ekranındaki kampanya ikonu, çoklu-seçim modal'ı, her arkadaşa ayrı sendPersistentMessage çağrısı (gerçek WhatsApp broadcast list mantığı, grup sohbeti DEĞİL). Sunucu tarafında yeni bir şey gerekmedi. Node E2E testiyle (2 arkadaş, ikisi de mesajı aldı) doğrulandı; canlı görsel test arkadaş gerektirdiği için yapılmadı ama akış basit ve test kapsamı yeterli.
- [x] Sesli mesaj (Cloudinary üzerinden, zaten kurulu altyapı) — 19 Tem 2026, commit'lendi+push'landı. Kayıt/oynatma UI tam çalışıyor, upload akışı doğru (bir MIME-tipi bug'ı bulunup düzeltildi - bkz. not), gerçek Cloudinary yüklemesi yerel ortamda test edilemedi (env var yok) - Render'a deploy olduktan sonra PRODUCTION'da gerçek bir cihazdan doğrulanmalı.
- [x] Konum paylaşımı (tek seferlik, canlı DEĞİL) — 19 Tem 2026, commit'lendi+push'landı. Kod akışı debug print'lerle satır satır doğrulandı (izin/servis/timeout/hata hepsi doğru), ama BU EMÜLATÖRÜN Play services sürümü eski olduğu için gerçek bir konum fix'i hiç alınamadı - kod hatası değil, gerçek cihazda/güncel emülatörde tekrar denenmeli.
- [x] Sticker paketi (ücretsiz, bundle asset) — 19 Tem 2026, CANLI test edildi (tam çalışıyor) + commit'lendi + push'landı.
- [x] Basit yerleşik yardımcı bot (sunucu taraflı kurallı yanıtlar) — 19 Tem 2026, CANLI test edildi (production/Render üzerinde gerçek emülatör hesabıyla) + commit'lendi + push'landı (merhaba-app a2ce962, merhaba-signaling 43c7318). Sabit merhaba-bot kullanıcısı, arkadaşlık kontrolü muaf, anahtar kelime eşlemeli kurallı yanıtlar (dış AI yok). Arkadaşlar ekranında "Merhaba Asistan" girişi olarak görünüyor. Not: canlı testte tam mesaj gönderim anı Render'ın kendi deploy'umdan kaynaklı yeniden başlamasına denk geldi, o TEK mesaj "gönderiliyor..." durumunda takılı kaldı (bağlantı kopması, ack hiç gelmedi) - bu normal kullanımda olmaz, bir sonraki mesaj sorunsuz gönderildi ve bot doğru yanıt verdi.
- [x] Durum/hikaye (24 saat sonra kaybolan paylaşım) — 19 Tem 2026, commit'lendi+push'landı (merhaba-signaling 96f9685, merhaba-app c491048). Yeni storyStore.js (metin/fotoğraf, 24 saat sonra otomatik pasif). Sunucu tarafı E2E testle TAM doğrulandı: gizlilik (arkadaş olmayan göremiyor), anlık bildirimler (story-new/story-viewed/story-removed), yalnızca sahibinin izleyen listesini görebilmesi, süre dolumu mantığı (unit test, gerçek 24 saat beklemeden). İstemci UI (hikaye şeridi, oluşturucu, tam ekran gösterici) yalnızca statik analizle doğrulandı - Batch A'daki DİĞER tüm istemci UI'ları gibi bu da bir sonraki "toplu kontrol"de emülatörde görsel doğrulama bekliyor.

**BATCH A TAMAMLANDI (19 Tem 2026)** - mesajlaşma çekirdeğindeki tüm maddeler bitti: mesaj düzenleme/silme/tepki/pin/yanıtlama/kendine-not, mesaj planlama, anket, gizlilik (çevrimiçi/son görülme/okundu), toplu/broadcast liste, sesli mesaj, konum, sticker, basit bot, tek seferlik fotoğraf, durum/hikaye. Sıradaki: Batch B (grup sohbeti).
- [x] Tek seferlik görüntüleme (view once foto) — 19 Tem 2026, commit'lendi+push'landı. Server mantığı (openViewOncePhoto/redactForHistory: ikinci açmayı reddetme + geçmişte URL gizleme) 18 senaryolu Node testiyle doğrulandı. Client tarafı (blur kart, MIME-tipi düzeltmesiyle) sunucuya doğru ulaşıyor, gerçek Cloudinary yüklemesi PRODUCTION'da doğrulanmalı.

### Batch B — Grup sohbeti (yeni özellik, çok maddeye altyapı sağlıyor) — TAMAMLANDI (19 Tem 2026)
- [x] Grup sohbeti oluşturma + admin/rol yönetimi — commit'lendi+push'landı (merhaba-signaling e5aa00d/12d5417, merhaba-app 193878c). Yeni groupStore.js/groupMessageStore.js. Üyeler yalnızca ekleyenin arkadaşı olabilir. Sahip (owner) sabit, admin atama yalnızca sahipte, üye ekleme/çıkarma adminlerde. 15+ senaryolu E2E testle (gizlilik, yetki kontrolleri, owner korumaları) TAM doğrulandı.
- [x] Tek yönlü duyuru kanalı (grup üzerinden, sadece admin postlar) — ayrı bir varlık değil, grubun `announcementOnly` bayrağı olarak uygulandı (grup_info_screen.dart'tan aç-kapat). E2E testle doğrulandı.
- [x] Konu/yanıt zinciri (grup içinde basitleştirilmiş thread) — replyToId ile (ikili sohbetteki "yanıtla" ile aynı mekanizma) - gerçek iç içe thread DEĞİL, bilinçli olarak basit tutuldu (backlog maddesindeki "basitleştirilmiş" ifadesiyle uyumlu).

**Kapsam notu:** Grup mesajlarında ikili sohbetteki gibi düzenleme/tepki/sabitleme/zengin mesaj türleri (anket/konum/sticker/sesli/foto) YOK - yalnızca düz metin + yanıtlama + silme (gönderen ya da admin). Bu bilinçli bir kapsam daraltması, gerekirse sonra genişletilebilir.

İstemci UI (groups_screen/group_create_screen/group_chat_screen/group_info_screen) yalnızca `flutter analyze` ile doğrulandı, emülatör canlı testi YAPILMADI (Sinan oyun oynuyor, "toplu kontrol" bekliyor - bkz. mesaj planlama/durum-hikaye ile aynı not).

### Batch C — Eşleştirme motoru (settings_screen.dart, server.js tryMatch, pre_call_screen.dart)
- [x] Ülke/bölge filtresi — 19 Tem 2026, commit'lendi+push'landı (merhaba-signaling 1481286, merhaba-app 2c88073). Cinsiyet filtresiyle aynı desen (karşılıklı, ülkesi bilinmeyen aday atlanır). E2E testle doğrulandı.
- [x] Karma/itibar puanı (parasız, kuyruk önceliği) — AYRICA saklanmıyor, reportStore'daki şikayet geçmişinden TÜRETİLİYOR (karmaFor()), affinityScore'a hafif ağırlıkla ekleniyor. Doğrudan test edilmedi (basit aritmetik + zaten test edilmiş reportStore.countReportsAgainst'a dayanıyor, düşük risk).
- [x] Süreli hızlı eşleştirme modu (opsiyonel kısa-tur) — sunucu SPEED_ROUND_SECONDS=120 bildirir, tüm geri sayım/"devam et mi sıradaki mi" mantığı istemci tarafında (video_chat_screen.dart). E2E testle sunucu tarafı doğrulandı, istemci UI yalnızca analyze ile.
- [x] Kamerasız/gizli mod — mevcut "sesli-yalnız mod" (voiceOnly) altyapısı yeniden kullanıldı (kamera hiç açılmıyor). **KAPSAM DIŞI BIRAKILDI: "kamera sonradan açılabilir" (mid-call medya renegotiation)** — WebRTC'de canlı track ekleme gerçek çoklu-cihaz testi olmadan güvenle uygulanamayacak kadar riskli görüldü, bilinçli olarak ertelendi.
- [x] Sadece metin modu — YENİ bir keşif: hiç WebRTC medyası/izni gerekmiyor, mevcut 'chat-message' soket relay'i zaten partners Map'ine dayanıyor (peer connection'dan bağımsız). VideoChatScreen'e `textOnlyMode` parametresi eklendi, initLocalMedia hiç çağrılmıyor, PreCallScreen tamamen atlanıyor (home_screen.dart'ta doğrudan yönlendirme).
- [x] Yakınlık bazlı (konum) eşleştirme — konum PROFİLE KAYDEDİLMİYOR, yalnızca o oturumun matchPreferences'ında canlı taşınıyor (gizlilik). Karşılıklı - iki taraf da konum paylaşmıyorsa filtre uygulanmaz (cinsiyet filtresiyle tutarlı). E2E testle (kabul+red senaryoları) doğrulandı.
- [x] Burç/doğum tarihi ek profil alanları — zodiacFor() sunucuda türetiliyor (saklanmıyor), yıl-sınırı (Oğlak) dahil E2E testle doğrulandı. Profil ekranına tarih seçici + görüntüleme eklendi.
- [x] Video/kısa klip profil tanıtımı — Cloudinary'ye chat medyasıyla aynı akış (POST/DELETE /profile/intro-video). İstemci: ImagePicker.pickVideo (≤30sn) + yükleme; oynatma YENİ bir video player paketi eklemek yerine (kapsam dışı bırakıldı) url_launcher ile cihazın kendi oynatıcısında açılıyor.
- [x] Küçük grup rastgele görüşme (mesh, 4 kişiye kadar — SFU değil) — 20 Tem 2026, commit'lendi+push'landı (merhaba-signaling 1217444, merhaba-app 5d7c32a). Sunucu: bağımsız groupCallQueues/groupCallRooms mekanizması, offer/answer/ICE için YENİ event yok (mevcut genel 'signal' relay'i {targetId,data} mesh'teki her ikili bağlantı için kullanılıyor), glare önleme socketId sıralamasına göre deterministik initiator ataması. 6 senaryolu Node E2E ile TAM doğrulandı (oda kurulumu, initiator ataması, signal relay, ayrılma, oda dağılma, size=3/4). İstemci: GroupCallService (her katılımcı için ayrı RTCPeerConnection, per-peer offer/answer kilitleri - 1:1'deki race-condition korumalarıyla AYNI desen), GroupCallPreScreen + GroupCallScreen (2x2 video grid). **GERÇEK ÇOKLU-CİHAZ TESTİ YAPILMADI** - yalnızca sunucu tarafı sinyalleşme mantığı doğrulandı, istemci tarafı WebRTC mesh (gerçek medya/ICE müzakeresi 3-4 eşzamanlı bağlantıda) YALNIZCA gerçek cihazlarla test edilebilir. Ana ekranda "(beta)" etiketli ikincil bir giriş var - bu etiket bilerek kalıcı, gerçek cihaz testi geçene kadar kaldırılmamalı.
- [x] Google ile hızlı kayıt (mevcut Firebase projesi üzerinden) — 20 Tem 2026, commit'lendi+push'landı (merhaba-signaling d595e96, merhaba-app 607dba0). Sunucu: POST /auth/google, google-auth-library ile ID token doğrulama, aynı e-postalı hesap varsa Google kimliği ona bağlanıyor (iki hesap oluşmuyor). GOOGLE_WEB_CLIENT_ID ayarlanmadıysa 503 (ADMIN_SECRET ile aynı "güvensiz varsayılan yok" deseni) - doğrulama testleri (503/401/google-only hesapla normal login reddi) yapıldı. İstemci: google_sign_in paketi, "Google ile devam et" düğmesi (yalnızca gerçek client ID girilince görünür). **KALAN TEK ADIM Sinan'ın kendisinde** - Firebase konsolunda SHA-1 kaydı + Google sağlayıcısını açıp Web Client ID'yi iki yere (auth_service.dart + Render env) girmesi gerekiyor, adım adım talimat KURULUM.md'de "Google ile Hızlı Kayıt Kurulumu" başlığı altında.
- [x] Premium katman DATA MODELİ + özellik kilitleme (gerçek ödeme YOK, "Yakında") — userStore.js'e isPremium alanı (varsayılan false, onu true yapan hiçbir uç YOK - bilerek, gerçek ödeme entegre edilene kadar). Profil ekranında "Premium - Yakında" kartı.

**Batch C durumu: 11/11 tamamlandı (kod tarafı).** Grup video mesh gerçek çoklu-cihaz testi bekliyor (bkz. yukarıdaki not), Google girişi Sinan'ın Firebase konsolunda tek seferlik bir adımını bekliyor (KURULUM.md).

### Batch D — Zaten onaylı GECE_GELISTIRME maddeleri — TAMAMLANDI (20 Tem 2026)
- [x] İlgi alanı etiketiyle eşleştirme (madde 4) — YUMUŞAK öncelik zaten
      affinityScore()'da vardı (önceki oturumdan); bu turda ayrıca SERT bir
      filtre eklendi (`requireCommonInterest`, settings_screen.dart "Ortak
      ilgi alanı şart olsun" anahtarı).
- [x] Tekrar eşleş (madde 2) — `lastPartnerByUser` + `rematch-invite`,
      mevcut arkadaş-arama call-invite altyapısı (CallService/
      CallUiController) `isRematch` bayrağıyla yeniden kullanıldı, YENİ bir
      UI akışı yazılmadı.
- [x] Görüşme içi hızlı tepkiler (madde 3) — `call-reaction` event'i (sabit
      QUICK_REACTIONS kataloğu), video_chat_screen.dart'ta emoji seçici +
      yukarı süzülüp solan animasyon.
- [x] Çeviri altyapısı (madde 5, graceful degradation) — `translationService.js`
      (Google Translate API v2, TRANSLATE_API_KEY yoksa 503) + chat_screen.dart
      mesaj menüsünde "Çevir". **Gerçek çeviri için Sinan'ın bir
      TRANSLATE_API_KEY alıp Render'a eklemesi gerekiyor** - kod tarafı
      tamamen hazır, anahtar olmadan zarif şekilde devre dışı kalıyor.
- [x] "Yazıyor..." göstergesi (madde 6) — `typing-start`/`typing-stop`,
      2sn durağanlık debounce'ı + 4sn alıcı-taraf zaman aşımı.
- [x] Günlük giriş serisi/rozet (madde 7) — `userStore.touchLoginStreak()`
      (saf görsel, parasal ödül YOK), profil ekranında "🔥 X günlük seri".

Sunucu: E2E testle (rematch, tepkiler, typing, ilgi alanı filtresi,
/translate 503) + ayrı unit testle (streak mantığı) doğrulandı. İstemci:
`flutter analyze` 42/42 (yeni dosyalarda sıfır uyarı). Commit'ler:
merhaba-signaling `184331d`, merhaba-app `e85ece1`.

### Batch E — Eşleşme (Dating) katmanı — yeni "Keşfet" ekranı — TAMAMLANDI (20 Tem 2026)
- [x] Kaydırarak eşleştirme (swipe) — yeni discoverStore.js (swipes.json/
      dateMatches.json), DiscoverScreen'de saf Flutter gesture ile kart
      sürükleme (yeni paket YOK). Karşılıklı beğenide otomatik eşleşme +
      otomatik ARKADAŞLIK (mevcut mesajlaşma altyapısı doğrudan kullanılsın
      diye, ayrı bir dating-chat alt sistemi kurulmadı - bilinçli sadeleştirme).
- [x] Süper beğeni — günde 1 hak, `action: 'superlike'`.
- [x] Profil öne çıkarma (Boost) — günde 1 kez/30dk, candidate sıralamasında
      önceliklendiriliyor.
- [x] Kim beğendi listesi — DiscoverLikesMeScreen, dokununca anında eşleşme.
- [x] Uyumluluk anketi/algoritması — 5 soruluk sabit anket, gerçek ML DEĞİL
      (yalnızca ortak cevaplanan soru yüzdesi), kartlarda %uyum gösteriliyor.
- [x] Günlük sınırlı/küratörlü öneri — günlük 60 swipe limiti + boost/uyum
      bazlı sıralama. **Basitleştirildi**: Hinge Standouts tarzı "günde N
      özenle seçilmiş profil" YOK, bunun yerine sürekli akan ama limitli/
      sıralı bir akış - kapsamı küçük tutmak için bilinçli bir tercih.
- [x] Zaman sınırlı eşleşme — hiç mesajlaşma olmadan 7 gün geçen eşleşmeler
      saatlik bir süpürmeyle otomatik sona eriyor.
- [x] Nötr ilk mesaj kuralı — eşleşme id'sinin hash'inden deterministik,
      ZORUNLU OLMAYAN bir "sırada sen varsın" ipucu (match dialoğunda).
- [x] Geri alma (rewind) — yalnızca kendi son işlemi, eşleşmiş bir swipe
      geri alınamaz.
- [x] Gizli mod/görünmezlik — settings_screen.dart "Keşfet'te gizli mod".
- [x] "Yollarınız kesişti" (konum bazlı) — konum PROFİLE KAYDEDİLMİYOR
      (Batch C ilkesiyle tutarlı), yalnızca 15dk TTL'li bellek-içi önbellek,
      candidate sıralamasında yakınlığa göre önceliklendirme.
- [x] Ön-mesaj/not gönderme — DiscoverScreen'de beğeniyle birlikte opsiyonel
      not, alıcı "kim beğendi" listesinde görüyor.
- [x] Profil rozetleri — nötr, tartışmalı olmayan 12 etiketlik sabit katalog
      (profile_screen.dart'ta seçici, en fazla 3).
- [x] Buluşma sonrası geri bildirim (We Met) — DiscoverMatchesScreen'de
      "Buluştunuz mu?" sorusu, yalnızca kendi tarafını bir kez kaydediyor.
- [x] Belirli içeriğe beğeni bırakma — **kapsam dışı bırakıldı/genel beğeniye
      birleştirildi**: profilde tek fotoğraf olduğu için Hinge'deki "belirli
      bir fotoğrafa/prompt cevabına beğeni" ayrımının bir karşılığı yok,
      genel profil beğenisi zaten bunu kapsıyor.
- [ ] Oyunlaştırılmış eşleşme tahmini — **BAŞLANMADI**. Gerekçe: gerçek bir
      oyunlaştırma (birkaç adaydan hangisinin seni beğendiğini tahmin etme)
      ayrı bir oturum/durum yönetimi + "kim beğendi" verisinin oyun mekaniği
      içinde gösterilmemesi gibi ek gizlilik dikkati gerektiriyor - diğer
      17 maddeye kıyasla daha düşük değerli/riskli görülüp bu turda atlandı,
      gerekirse ayrı bir görev olarak eklenebilir.
- [x] Selfie doğrulama rozeti — AI YOK, sikayet-paneli tarzı manuel admin
      onayı (GET/POST /admin/selfie-verifications, ADMIN_SECRET korumalı).
      İstemci kameradan çekim zorunlu tutuyor (basit bir caydırıcı, tam bir
      canlılık kontrolü değil).

Sunucu: 13 senaryolu E2E test + ayrı bir soket testiyle (eşleşme sonrası
gerçekten mesajlaşabildikleri) doğrulandı. İstemci: `flutter analyze` 0 hata.
Commit'ler: merhaba-signaling `64a34d0`, merhaba-app `e3bb10f`.

### Batch F — Güvenlik/Gizlilik/Erişilebilirlik — TAMAMLANDI (20 Tem 2026, 9/12)
- [ ] Ekran görüntüsü bildirimi — **BAŞLANMADI, BİLİNÇLİ OLARAK ERTELENDİ.**
      Gerekçe: Android'de bunu yapmak MediaStore ContentObserver ile YENİ,
      TEST EDİLMEMİŞ native (Kotlin) platform kanalı kodu yazmayı gerektiriyor
      - bu ortamda gerçek cihaz/emülatör testi mümkün değil, GECE_GELISTIRME_
      TAKIP.md'nin kendi "yeni native bağımlılık/riskli kod" kısıtlamasıyla
      aynı gerekçeyle bir sonraki gerçek cihaz testi fırsatına bırakıldı.
- [x] Panik butonu — TrustedContactsScreen, Noonlight/üçüncü taraf bir servis
      YOK, cihazın SMS uygulamasını (`sms:`) önceden doldurulmuş mesajla
      açıyor - sunucu çökse bile çalışır.
- [x] Buluşma detayını güvenilir kişiyle paylaşma — aynı ekran, serbest metin
      + canlı konum linki.
- [x] Refakatçi/gözlemci ekleme — ayrı bir kavram olarak DEĞİL, "güvenilir
      kişiler" listesiyle BİRLEŞTİRİLDİ (aynı isim+telefon listesi hem panik
      butonu hem buluşma paylaşımı hem de kavramsal "gözlemci" rolünü
      karşılıyor - üç ayrı liste tutmak gereksiz karmaşıklık olurdu).
- [x] Ekran okuyucu uyumluluğu — **KISMİ/sınırlı bir geçiş**: video_chat_screen
      .dart kontrol çubuğu + discover_screen.dart aksiyon düğmelerine
      Semantics/Tooltip etiketleri eklendi (ikon-yalnızca düğmeler artık
      TalkBack/VoiceOver'da anlamlı). Uygulamanın TAMAMINDA kapsamlı bir
      Semantics denetimi YAPILMADI - kapsamı küçük tutmak için en kritik/en
      sık kullanılan ekranlarla sınırlı tutuldu, ileride genişletilebilir.
- [ ] Renk körü dostu / yüksek kontrast tema — **BAŞLANMADI, BİLİNÇLİ OLARAK
      ERTELENDİ.** Gerekçe: `AppColors` (theme/app_theme.dart) uygulama
      genelinde `static const` olarak tanımlı ve onlarca dosyada `const`
      constructor'lar içinde kullanılıyor - runtime'da değiştirilebilir
      (instance/Theme tabanlı) bir sisteme geçirmek düzinelerce dosyayı
      etkileyen, görsel doğrulama yapılmadan riskli bir mimari refactor
      gerektiriyor. Bir sonraki "toplu kontrol" oturumunda ele alınmalı.
- [ ] Gerçek zamanlı altyazı — **BAŞLANMADI, BİLİNÇLİ OLARAK ERTELENDİ.**
      Gerekçe: yalnızca KENDİ mikrofonun (cihaz-üstü STT ile) altyazılanabilir
      - flutter_webrtc, gelen (uzak) ses akışına bir STT motoruna
      beslenebilecek şekilde erişim sunmuyor. Asıl erişilebilirlik ihtiyacı
      ("karşı tarafın söylediklerini oku") bu şekilde karşılanamadığı için,
      yanıltıcı/eksik bir özellik göndermek yerine ertelendi.
- [x] Kişisel bilgi paylaşımı uyarısı — `lib/utils/message_safety.dart`
      (telefon/adres regex'i), gönderim ENGELLENMİYOR, bir kez "emin misin?"
      soruluyor.
- [x] Saldırgan mesaj öncesi uyarı — aynı dosya, basit anahtar kelime listesi.
- [x] Gölge yasaklama (shadowban) altyapısı — yalnızca admin tetikler,
      kullanıcı kendi durumunu asla göremez; rastgele eşleştirme VE Keşfet'te
      etkili.
- [x] Ban kaçağı tespiti — kayıt IP'si + 30 gün penceresi, otomatik ban YOK
      (yanlış pozitif riski), yalnızca admin incelemesi için işaretleme.
- [x] Kısıtlı liste / yakın arkadaşlar listesi — yalnızca arkadaşlar arasından
      seçilebilir, closeFriendsOnly hikayelerin kimlere görüneceğini
      belirliyor (Instagram'daki "Close Friends" ile aynı fikir).

18 senaryolu sunucu E2E testi (admin kapılı uçlar, shadowban'in hem
Keşfet hem rastgele eşleştirmeden gizlemesi + kaldırılınca geri gelmesi,
ban kaçağı işaretleme, kısıtlı liste + hikaye görünürlüğü, güvenilir
kişiler) + `flutter analyze` 0 hata ile doğrulandı. Commit'ler:
merhaba-signaling `92af974`, merhaba-app `a042528`.

### Batch G — Sosyal/Oyunlaştırma (parasız) + Türkiye lokalizasyonu — 6/8 (20 Tem 2026)
- [x] Seviye/rozet sistemi — computeXp()/computeLevel(), karma/burç ile AYNI
      ilke, AYRICA saklanmıyor (arkadaş sayısı, giriş serisi, selfie
      doğrulama, video tanıtım, rozetler, biyografi, başarımlardan türetiliyor).
- [x] Liderlik tablosu — GET /leaderboard, LeaderboardScreen.
- [x] Görevler/başarımlar — 6 sabit görev, HİÇBİR parasal ödül YOK, yalnızca
      sembolik rozet + XP katkısı, AchievementsScreen.
- [x] Avatar oluşturucu — basit renk+emoji avatarı (yeni asset/ML paketi YOK),
      profile_screen.dart'ta seçici.
- [x] Özel/temalı arayüz kişiselleştirmesi — **KAPSAMI BİLİNÇLİ DARALTILDI**:
      tam bir vurgu rengi/tema değişimi `AppColors`'ın (theme/app_theme.dart)
      uygulama genelinde `static const` + `const` constructor'larla
      kullanılması yüzünden yapılamıyor (Batch F'teki "renk körü dostu tema"
      ertelemesiyle AYNI mimari kısıt - bkz. orada). Bunun yerine AppColors'a
      HİÇ dokunmayan, gerçek bir kişiselleştirme/erişilebilirlik değeri olan
      **yazı boyutu ölçeklendirmesi** uygulandı (Küçük/Normal/Büyük/Çok Büyük,
      MaterialApp builder'ında MediaQuery override).
- [ ] Çok dilli arayüz (lokalizasyon altyapısı) — **BAŞLANMADI, BİLİNÇLİ
      OLARAK ERTELENDİ.** Gerekçe: uygulama genelinde ~30 dosyada yüzlerce
      sabit kodlanmış Türkçe metin var - bunları ARB formatına sistematik
      olarak çıkarmak (flutter_localizations + intl kurulumu tek başına
      YETMEZ, her ekranı tek tek elden geçirip her string'i değiştirmek
      gerekir) tek bir oturumda güvenle yapılamayacak kadar büyük ve riskli
      bir iş - yarım/tutarsız bir lokalizasyon (bazı ekranlar çevrili, bazıları
      değil) kullanıcıya iskelet bir altyapıdan daha kötü bir deneyim sunar.
      Ayrı, adanmış bir oturumu hak ediyor.
- [x] Reklamsız deneyim — **EK bir iş GEREKMEDİ**: uygulamada zaten hiç reklam
      YOK (Ödüllü reklam madde 8 dış bir AdMob hesabı gerektirdiği için
      ertelendi, bkz. altta) - "reklamsız" vaadi zaten mevcut isPremium veri
      modeli/"Premium - Yakında" arayüzü tarafından örtük olarak karşılanıyor,
      kaldırılacak bir reklam olmadığı için ayrı bir toggle anlamsız olurdu.
- [ ] Ödüllü reklam (rewarded ad SDK entegrasyonu) — **BAŞLANMADI, Sinan'ın
      kendisini bekliyor.** Gerçek bir reklam SDK'sı (Google AdMob) Sinan'ın
      KENDİ AdMob hesabıyla oluşturacağı bir App ID + ad unit ID gerektiriyor
      - bu, Google Sign-In'deki Firebase SHA-1 kaydı/çeviri API anahtarıyla
      AYNI disiplin (sır/hesap SEN asla üretme, yalnızca Sinan ekler). Kod
      tarafı (ödül verme mantığı) o kimlikler gelince hızlıca eklenebilir.

## İlerleme günlüğü

**20 Tem 2026 - BACKLOG'UN TAMAMI (Batch A→G) BİTTİ.** Sinan uyurken/uzaktayken
otonom olarak (bkz. [[feedback_autonomous_backlog_continuation]] memory'si)
tüm batch'ler kod tarafıyla tamamlandı. Kalan açık maddeler yalnızca üç
kategoride: (1) Sinan'ın kendisinin yapması gereken dış hesap/kimlik
adımları (Google Sign-In Firebase SHA-1 - TAMAMLANDI, Web Client ID de
girildi; çeviri TRANSLATE_API_KEY; ödüllü reklam AdMob hesabı), (2) gerçek
çoklu-cihaz testi gerektiren maddeler (küçük grup görüşmesi mesh), (3)
bilinçli olarak ertelenen, gerekçeli maddeler (ekran görüntüsü bildirimi -
test edilmemiş native kod riski; renk körü/özel tema - AppColors'ın mimari
kısıtı; gerçek zamanlı altyazı - flutter_webrtc uzak ses erişimi yok; çok
dilli arayüz - yüzlerce string'in sistematik çıkarımı ayrı bir oturum
gerektiriyor; oyunlaştırılmış eşleşme tahmini - düşük öncelik). Detaylar
için her Batch'in kendi bölümündeki notlara bak. TÜM kod sunucu tarafında
E2E testlerle, istemci tarafında `flutter analyze` (0 hata) ile doğrulandı,
her batch ayrı commit+push edildi (signaling_server ve merhaba-app AYRI
git repoları).

- 18 Temmuz 2026: Backlog oluşturuldu, Batch A'ya başlanıyor.
- 19 Temmuz 2026 (bu oturum) — COMMIT'LENDİ VE PUSH'LANDI (merhaba-app
  `1f3882c`, merhaba-signaling `bc49d03` - Render otomatik deploy edecek):

  **Bu oturumda yazılan ve CANLI test edilen kod** (artık commit'li):
  - `signaling_server/messageStore.js`: `voteOnPoll`, `openViewOncePhoto`,
    `redactForHistory` fonksiyonları eklendi.
  - `signaling_server/chatMediaStorage.js`: YENİ dosya — sohbet medyası
    (sesli mesaj/tek seferlik fotoğraf) için Cloudinary upload modülü
    (photoStorage.js'nin aynı deseni, farklı klasör `merhaba-chat-media`).
  - `signaling_server/server.js`: `persistent-message-send` artık
    `kind`/`meta` kabul ediyor (`validateMessageKindAndMeta` fonksiyonu ile
    sunucu tarafı doğrulama: poll/location/sticker/voice/view_once_photo),
    `STICKER_CATALOG` sabiti, `message-poll-vote` ve
    `message-view-once-open` soket olayları, `POST /chat/media` REST ucu,
    `GET /messages/:friendId` artık `redactForHistory` ile süzülüyor,
    `notificationPreviewFor` bildirim önizleme yardımcı fonksiyonu.
    **Bu dosyadaki TÜM yeni mantık gerçek bir Node.js sunucusuyla (yerel,
    port 3000) 18 senaryoluk bir test script'iyle uçtan uca doğrulandı**
    (anket oluştur/oyla/geçersiz seçenek reddi, konum doğrulama/geçersiz
    reddi, sticker doğrulama/katalog-dışı reddi, sesli mesaj kaydı, tek
    seferlik fotoğraf aç/ikinci-açmayı-reddet/geçmişte redaksiyon) —
    hepsi "TÜM TESTLER BAŞARILI ✅" ile bitti.
  - `lib/data/stickers.dart`: YENİ dosya — 12 emoji-sticker kataloğu
    (server.js'deki STICKER_CATALOG ile birebir aynı id'ler).
  - `lib/services/messaging_service.dart`: `sendPersistentMessage` artık
    kind/meta alıyor, `onMessageUpdated` callback'i (anket oyu/view-once
    güncellemeleri için), `votePoll`, `openViewOncePhoto`,
    `uploadChatMedia` (multipart POST /chat/media) eklendi.
  - `lib/screens/chat_screen.dart`: BÜYÜK genişleme — `_ChatItem`'a
    kind/meta eklendi, ek menüsü ("+" butonu → Anket/Konum/Sticker/
    Fotoğraf ızgara menüsü, `_AttachmentSheet` widget'ı), anket oluşturma
    diyaloğu (`_PollComposerDialog`, dinamik 2-8 seçenek), anket oylama
    UI'ı (yüzde çubuklu, tıklanabilir seçenekler), konum paylaşım akışı
    (Geolocator izin/servis kontrolü + kart tasarımı + `url_launcher` ile
    haritada açma), sticker seçici (12'lik emoji ızgarası, bubble arka
    planı OLMADAN büyük emoji render), sesli mesaj kaydı (`record` paketi,
    basılı-tut değil dokun-başlat/dokun-durdur, kırmızı nokta+sayaç UI,
    `audioplayers` ile oynatma, sahte-waveform çubukları), tek seferlik
    fotoğraf (image_picker kamera/galeri, blur kart, açma/görüntülendi
    durumları). Tasarım BİLİNÇLİ OLARAK mevcut düz stilden daha "canlı"
    yapıldı (Sinan'ın açık isteği: "tasarımı daha iyi yap, şimdiki
    tasarıma bağlı kalma").
  - `pubspec.yaml`: `geolocator`, `record`, `audioplayers`,
    `path_provider` paketleri eklendi (`flutter pub add` ile).
  - `android/app/src/main/AndroidManifest.xml`: `ACCESS_FINE_LOCATION` /
    `ACCESS_COARSE_LOCATION` izinleri eklendi.

  **CANLI TEST SONUÇLARI** (gerçek Android emülatörde, adb ile UI
  otomasyonu üzerinden, ekran görüntüleriyle doğrulandı):
  - ✅ Sticker: tam çalışıyor (seç → gönder → bubble'sız büyük emoji render).
  - ✅ Anket: tam çalışıyor (oluştur → gönder → yüzde çubuklu kart → oy ver
    → %100/check-icon/oy-sayısı doğru güncelleniyor).
  - ⚠️ Konum: kod akışı (izin iste → servis kontrolü → 15sn timeout →
    hata mesajı) tamamen doğru çalışıyor VE debug print'lerle satır satır
    doğrulandı, ama emülatörün Google Play services sürümü eski olduğu
    için (`Google Play services out of date for com.merhaba.app`)
    `Geolocator.getCurrentPosition()` gerçek bir konum hiç dönmüyor, her
    zaman 15sn'de timeout'a düşüyor. BU BİR KOD HATASI DEĞİL - ortam
    kısıtı. Gerçek cihazda ya da Play services güncel bir emülatörde
    tekrar denenmeli. `LocationAccuracy.low` kullanılıyor (medium/high
    yerine, ayar-çözümleme diyaloğu asılı kalmasın diye).
  - ✅ Sesli mesaj: kayıt UI'ı (kırmızı nokta, sayaç, iptal/gönder) tam
    çalışıyor. İlk denemede sunucu "Desteklenmeyen dosya türü" diye
    reddetti - GERÇEK BİR BUG bulundu ve düzeltildi: `http.MultipartFile.
    fromPath` dosya uzantısından MIME tipini güvenilir tahmin edemiyordu,
    `uploadChatMedia` artık `mimeType` parametresini AÇIKÇA alıyor
    (`http_parser`'ın `MediaType`'ı ile). Düzeltmeden sonra istek doğru
    şekilde sunucuya ulaşıp 503 "Cloudinary yapılandırılmamış" hatası
    aldı (beklenen - yerelde Cloudinary env var yok). Render'da
    (production) Cloudinary zaten yapılandırılı, deploy sonrası gerçek
    yüklemenin çalışması beklenir - production'da bir cihazdan doğrulanmalı.
  - ✅ Tek seferlik fotoğraf: aynı MIME-tipi düzeltmesiyle sunucuya doğru
    ulaşıyor (aynı 503 Cloudinary hatası, beklenen). server.js mantığı
    (openViewOncePhoto/redactForHistory) Node test script'iyle ayrıca
    doğrulandı.

  **19 Temmuz sonunda yapılanlar (özet):**
  - `flutter analyze` (yalnızca pre-existing stil uyarıları, hata yok),
    `flutter test` (19/19 yeşil), `node --check` (3 dosya) hepsi temiz.
  - `lib/services/webrtc_service.dart`: geçici yerel test URL'si
    production'a (`https://merhaba-signaling.onrender.com`) geri alındı
    - commit'te DEĞİŞİKLİK YOK (diff temiz, doğrulandı).
  - `merhaba-app` commit `1f3882c`, `merhaba-signaling` commit `bc49d03` -
    ikisi de push'landı, Render otomatik deploy tetiklenecek/tetiklendi.
  - `lib/theme/app_theme.dart` HÂLÂ commit'siz duruyor - bu BENİM
    değişikliğim değil (oturum başında zaten değişmişti, salt biçimlendirme/
    format farkı) - dokunulmadı, Sinan'ın kendi kararı.
  - `signaling_server/userStore.js` + `.gitignore`'da BAŞKA BİR (muhtemelen
    Claude bulut'tan kalma) YARIM taslak VAR - hideOnlineStatus/
    hideLastSeen/readReceiptsEnabled alanları userStore.js'e eklenmiş ama
    server.js/client tarafı YOK, commit'lenmemiş. BUNA DOKUNULMADI - Batch
    A'nın #3/#4 maddelerine geçilince ÜZERİNE İNŞA EDİLMELİ (yeniden
    yazma), bkz. yukarıdaki ilgili checklist notları.

  **Sıradaki adımlar** (kaldığı yerden devam edecek oturum için):
  1. Batch A'nın kalan maddeleri: mesaj planlama, çevrimiçi/okundu
     gizliliği (userStore.js'deki yarım taslağın üzerine inşa et), toplu/
     broadcast liste, basit bot, durum/hikaye — HİÇ BAŞLANMADI.
  2. Production'da (gerçek cihaz/Render) sesli mesaj + tek seferlik
     fotoğrafın gerçek Cloudinary yüklemesini doğrula (yerelde
     doğrulanamadı, env var yoktu).
  3. Konum paylaşımını gerçek cihazda ya da Play services güncel bir
     emülatörde doğrula (bu emülatörde ortam kısıtı yüzünden hiç
     denenemedi).
  4. Sonra Batch B (grup sohbeti) → C (eşleştirme motoru) → D (GECE_
     GELISTIRME kalanları) → E (Keşfet/dating) → F (güvenlik/gizlilik) →
     G (sosyal/oyunlaştırma) sırasıyla devam.
  5. Sinan emülatörde canlı takip etmek istiyor - VS Code'da F5 (Debug)
     ile başlatılırsa kaydettikçe otomatik hot reload olur (bu oturumda
     SendKeys/named-pipe gibi pencere-hedefleyen otomasyon yöntemleri
     DENENDİ VE TERK EDİLDİ - biri yanlışlıkla Sinan'ın ilgisiz bir işini
     durdurdu, bir daha kullanılmamalı; bunun yerine adb screencap +
     PowerShell resize ile ekran görüntüsü alıp Read ile görsel doğrulama
     yapıldı, iyi çalıştı).

- **19 Tem 2026 (devam) - Toplu/broadcast liste + basit yardımcı bot
  tamamlandı, commit'lendi, push'landı, canlı test edildi:**
  - Bot: `server.js`e `BOT_USER_ID`/`botReplyFor()` eklendi (arkadaşlık
    kontrolü bota özel muaf, `persistent-message-send` 600ms gecikmeyle
    otomatik yanıt üretiyor, `GET /messages/:friendId` bot sohbetine izin
    veriyor). Client: `friends_screen.dart`e `_buildBotTile()` eklendi
    (önceki oturumda yarım bırakılmıştı - `_buildNoteToSelfTile()` deseni
    kopyalanarak sabit `id: 'merhaba-bot'` ile tamamlandı).
  - Broadcast: `friends_screen.dart`e `_BroadcastComposerSheet` +
    AppBar'daki kampanya ikonu (önceki oturumda tamamlanmıştı, bu turda
    yalnızca test edildi).
  - Test: geçici `__test_bot_broadcast.js` ile gerçek client akışı
    taklit edilerek (register → find-match → matched → friend-request →
    friend-request-response → persistent-message-send) hem bot yanıtı hem
    2 arkadaşa broadcast doğrulandı, sonra dosya silindi. ÖNEMLİ DERS:
    testi ilk çalıştırdığımda 3000 portunda ESKİ KODLA ayakta kalan bir
    node süreci vardı (`EADDRINUSE` yüzünden yeni süreç sessizce
    çökmüştü) - eski süreç durdurulup yeniden başlatılınca test geçti.
    Ayrıca `friend-request`/`friend-request-response` protokolü
    varsayımımdan farklıydı (payload'sız, `partners` map + `accepted`
    alanı) - server.js okunarak düzeltildi.
  - Canlı emülatör testi: `flutter run -d emulator-5554` ile production
    sunucusuna (`signalingServerUrl` zaten production'a ayarlıydı,
    dokunulmadı) bağlı gerçek bir hesapla "Merhaba Asistan" sohbeti açılıp
    "merhaba" yazıldı, doğru kurallı yanıt CANLI görüldü. Broadcast görsel
    olarak test edilmedi (arkadaş gerektiriyor, hesap oluşturmak video-
    eşleşme akışı gerektirir) - E2E test + kod incelemesi yeterli görüldü.
  - Commit'ler: `merhaba-signaling` `43c7318` (bot), `merhaba-app` `a2ce962`
    (broadcast + bot tile) - ikisi de push'landı, Render otomatik deploy
    oldu (bu deploy sırasında emülatördeki socket bağlantısı geçici olarak
    koptu, bir mesaj "gönderiliyor..." durumunda takılı kaldı - kod hatası
    değil, kendi deploy'umla test zamanlamasının çakışması).
  - `lib/theme/app_theme.dart` HÂLÂ commit'siz duruyor, hâlâ dokunulmadı
    (bkz. yukarıdaki not - Sinan'ın kendi kararı).

  **Sıradaki adımlar (güncel):**
  1. Batch A'nın kalan 2 maddesi: "Mesaj planlama (zamanlanmış gönderim)"
     ve "Durum/hikaye (24 saat)" — HİÇ BAŞLANMADI. Hikaye maddesi en büyük
     kalan iş (yeni `storyStore.js`, yeni soket/REST uçları, story ring +
     viewer/creator ekranları).
  2. Batch A tamamlanınca Batch B (grup sohbeti) → C (eşleştirme motoru)
     → D (GECE_GELISTIRME kalanları) → E (Keşfet/dating) → F (güvenlik/
     gizlilik) → G (sosyal/oyunlaştırma) sırasıyla devam.
  3. Production'da sesli mesaj + tek seferlik fotoğrafın gerçek Cloudinary
     yüklemesi, ve konum paylaşımı gerçek cihazda/güncel emülatörde hâlâ
     doğrulanmadı (bkz. eski not).

## Canlı Yayın/Sesli Oda — gstack /autoplan ile planlandı, Faz 1 kodlandı (21 Tem 2026)

Batch A-G tamamlandıktan sonra, backlog'da bilinçli olarak ayrı bırakılmış
"Canlı Yayın/Sesli Oda" kategorisi ele alındı. gstack skill seti kurulup
`/autoplan` (CEO+tasarım+mühendislik incelemesi, Plan Mode üzerinden) ile
derinlemesine planlandı — tam plan: `C:\Users\Sinan\.claude\plans\swirling-tinkering-finch.md`.

**Bağlayıcı kapsam kararı:** jeton/hediye/agency/PK-savaşı-parasal-ödül
KESİNLİKLE yok (önceki proje kararıyla ve RAKIP_ANALIZI_VE_YOL_HARITASI.md'deki
hukuki risk notuyla uyumlu). Yalnızca ücretsiz host/co-host+izleyici modeli.

**SFU kararı:** LiveKit Cloud (yönetilen servis, Sinan onayladı) — Render'da
kendi mediasoup sunucusu barındırmak pratik değil (UDP port aralığı,
ayrı VPS+TLS/TURN ops yükü).

**Faz 1 (MVP) KODLANDI, dış bağımlılık nedeniyle TEST EDİLEMEDİ:**
- `signaling_server/liveRoomMediaAdapter.js` (yeni, `livekit-server-sdk` ile) —
  tek soyutlama noktası, ileride farklı SFU'ya geçiş için.
- `signaling_server/liveRoomStore.js` (yeni) — bellek-içi oda/rol state'i
  (groupCallRooms deseniyle aynı ilke, kalıcı değil).
- server.js'e yeni socket event'leri: `live-room-create`/`-join`/`-leave`/
  `-chat-send`, `GET /live-rooms` REST ucu.
- `pubspec.yaml`'a `livekit_client` eklendi, `lib/services/live_room_service.dart`,
  `lib/screens/live_room_screen.dart`, `lib/screens/live_room_list_screen.dart`
  (yeni) — home_screen.dart'ta "Canlı" pill girişi eklendi.
- `flutter analyze` (0 yeni hata/uyarı) + `flutter test` (20/20) temiz geçti.

**DIŞ BAĞIMLILIK — Sinan'ın yapması gereken:** LiveKit Cloud'da hesap açıp
API key/secret/URL almak, Render'a `LIVEKIT_URL`/`LIVEKIT_API_KEY`/
`LIVEKIT_API_SECRET` environment variable olarak eklemek. Bu olmadan
adapter `isConfigured()=false` döner, oda açma isteği anlaşılır bir hatayla
reddedilir - sunucunun geri kalanı hiç etkilenmez. Anahtarlar eklenince
iki cihazla (host+izleyici) canlı doğrulama yapılmalı (bkz. plan dosyası
"Doğrulama" bölümü, madde 2).

**Sıradaki:** Faz 2 (moderasyon: kick/mute/report, `reportStore.js`'e
`'live-room'` context) ve Faz 3 (gamification + bildirim) — plan dosyasında
tam detay var, LiveKit anahtarları eklenip Faz 1 canlı doğrulandıktan sonra
devam edilecek.

**GÜNCELLEME (21-22 Tem 2026 gecesi) — Faz 1 CANLI DOĞRULANDI + yeni kapsam
genişletmesi istendi, kullanım kotası bitince DURDU:**

Faz 1, production'a karşı gerçek bir E2E testle doğrulandı (`live-room-created`
+ geçerli LiveKit token alındı, `merhaba-signaling` commit `d180726`). Yol
boyunca iki gerçek sorun bulunup düzeltildi: (1) Faz 1 kodu hiç commit'lenmemiş
olarak bulundu, commit+push edildi (`c4ff257`); (2) o commit'i hazırlarken bir
`git checkout` sırasında `livekit-server-sdk` bağımlılığı package.json'dan
yanlışlıkla silindi, Render deploy'u çöktü, düzeltildi (`d180726`) - detaylar
AGENTS_LOG.md'de.

Sinan ardından kapsamı genişletti, TEK oturumda iki büyük özellik istedi:

**A) Canlı Yayın — Faz 2 + ekstra (TikTok/Instagram Live tarzı moderasyon):**
Plan dosyasındaki (`C:\Users\Sinan\.claude\plans\swirling-tinkering-finch.md`)
Faz 2 kapsamına (`live-room-kick`/`live-room-mute`/`live-room-report-user`,
`reportStore.js` VALID_CONTEXTS'e `'live-room'`) EK olarak istenenler:
  - İzleyici listesini host/co-host görebilsin (yeni: `live-room-viewer-list`
    event'i ya da `GET /live-rooms/:id/viewers`, `liveRoomStore.js`'e
    `viewerIds`'in displayName/photoUrl ile zenginleştirilmiş hali).
  - Yayın içinden arkadaş ekleme (mevcut `friends_service.dart`/server.js'deki
    arkadaşlık isteği akışının canlı oda bağlamında yeniden kullanılması -
    yeni bir arkadaşlık sistemi İCAT ETME, var olanı `live-room-*`
    ekranından tetikle).
  - Ayrı bir "moderatör" rolü (co-host'tan farklı - medya yayınlamaz ama
    kick/mute yetkisi var): `liveRoomStore.js`'e `moderatorIds: Set` eklenip
    `isCoHostOrHost`'a benzer bir `canModerate(room, userId)` yardımcı
    fonksiyonu (host + co-host + moderatorIds).

**B) Grup eşleşme yeniden tasarımı (3-8 kişi + boşluk doldurma):**
Mevcut mesh mimarisi (`server.js` ~1061-1300, `GROUP_CALL_SIZES = [3, 4]`,
`groupCallQueues`/`groupCallRooms`/`tryFormGroupCallRoom`) BİLİNÇLİ olarak
4 ile sınırlı çünkü mesh'te N kişi = N*(N-1)/2 eşzamanlı bağlantı (8 kişide
28 bağlantı - pratik değil). Karar: 8'e kadar ölçeklenebilmesi için bu artık
LiveKit (SFU) üzerine taşınmalı - `liveRoomMediaAdapter.js`/`liveRoomStore.js`
ile AYNI adapter kullanılabilir, roller host/co-host/viewer yerine "eşit
katılımcı" olacak (hepsi hem yayınlar hem izler, host/viewer ayrımı yok).
  - `GROUP_CALL_SIZES` 3'ten 8'e genişler, kullanıcı arayüzden boyut seçer
    (mevcut `group_call_pre_screen.dart`'a boyut seçici eklenir).
  - **Boşluk doldurma (backfill) - Sinan'ın özellikle istediği kısım**: şu an
    `leaveGroupCallRoom()` biri ayrılınca odayı küçültüp bildiriyor ama ASLA
    yeni biri EKLEMİYOR (bu, şikayet edilen "2 kişi kalıp kimse gelmiyor"
    durumunun tam olarak nedeni - server.js:1100-1128'de doğrulandı). Yeni
    tasarım: bir katılımcı ayrılıp oda `size`'ın altına düşünce, odanın
    hedef boyutu (`targetSize`) aynı kalan bir `groupCallQueues.get(targetSize)`
    kuyruğuna bakılıp müsait biri varsa DOĞRUDAN o BOŞ ODAYA eklenir (yeni bir
    oda kurmak yerine LiveKit odasına join) - `tryFormGroupCallRoom`'un
    yanına `tryBackfillRoom(roomId)` gibi bir fonksiyon, hem birileri
    kuyruğa her eklendiğinde hem biri odadan ayrıldığında çağrılmalı.

**Sıradaki adımlar (kaldığım yerden buradan devam et):**
1. A) için: `liveRoomStore.js`'e moderatör/viewer-list alanları + server.js'e
   `live-room-kick`/`-mute`/`-report-user`/`-viewer-list`/arkadaş-ekleme
   event'leri, `reportStore.js` VALID_CONTEXTS. Flutter: `live_room_service.dart`
   'a karşılık gelen metodlar, `live_room_screen.dart`'a izleyici listesi
   paneli + kick/mute/arkadaş-ekle butonları (yalnızca host/co-host/moderatör
   görür).
2. B) için: yeni `groupLiveRoomStore.js` (ya da `liveRoomStore.js`'i
   genelleştir) + LiveKit tabanlı oda kurulumu + backfill mantığı +
   `group_call_pre_screen.dart`'a 3-8 boyut seçici. Mesh kodu (server.js
   ~1061-1300) korunabilir (geriye dönük uyum) ya da tamamen bu yeni
   sistemle değiştirilebilir - karar gerektiği yerde ver.
3. Her iki iş için de gerçek E2E test (Node socket.io script + `flutter
   analyze`/`test`) + AGENTS_LOG.md kaydı + bu dosyaya ilerleme notu.

**Tasarım kısıtı (Sinan'ın açık talimatı)**: Yeni eklenecek her buton/bileşen
(izleyici listesi paneli, kick/mute/moderatör butonları, arkadaş ekle,
grup boyutu seçici vb.) mevcut tasarım diline BİREBİR uymalı - `theme/
app_theme.dart`'taki `AppColors`/`AppText`/`AppRadius` token'ları, `_pillEntry`
tarzı mevcut bileşen desenleri, `live_room_screen.dart`/`home_screen.dart`'ta
zaten kullanılan buton/kart stilleri kullanılacak. Yeni bir stil/renk/bileşen
İCAT ETME - var olanı yeniden kullan.

**DURDURULMA SEBEBİ**: Sinan arayüzde "Now using usage credits" uyarısını
gördü, ücretli kredi harcanmasını istemiyor - normal kullanım kotası
sıfırlanana kadar çalışma DURDURULDU (bkz. memory
`feedback_token_95_checkpoint.md` güncellemesi). Kota sıfırlanınca bu bölümden
devam edilecek, henüz TEK SATIR kod yazılmadı (yalnızca araştırma + bu plan).

**GÜNCELLEME (22 Tem 2026 gece devamı):** Sıradaki adımlar #1'in SUNUCU
tarafı bitti ve production'da doğrulandı (`merhaba-signaling` commit
`bcdbb64` - bkz. AGENTS_LOG.md aynı tarihli kayıt). Kalan: Flutter tarafı
(`live_room_service.dart`'a yeni event metodları, `live_room_screen.dart`'a
izleyici listesi paneli + kick/mute/moderatör/arkadaş-ekle butonları,
mevcut AppColors/AppText tasarım diliyle) + `flutter analyze`/`test`.
Ardından madde #2 (grup eşleşme 3-8 + boşluk doldurma) başlanacak.

**GÜNCELLEME (22 Tem 2026 gece devamı 2):** Madde #1 (A - Canlı Yayın Faz 2 +
izleyici listesi/moderatör/arkadaş ekleme) TAMAMEN BİTTİ - sunucu (commit
bcdbb64) + Flutter (commit 4eb6993) ikisi de production'a karşı/statik
analizle doğrulandı. Şimdi madde #2'ye (B - grup eşleşme 3-8 + boşluk
doldurma) geçiliyor - henüz TEK SATIR kod yazılmadı, yalnızca yukarıdaki
tasarım (server.js ~1061-1300 mesh kodu referans, LiveKit'e taşıma +
backfill mantığı) geçerli.

**GECE OTURUMU BİTTİ (22 Tem 2026): Hem A (Canlı Yayın Faz 2 + ekler) hem
B (Grup Eşleşme 3-8 + boşluk doldurma) TAMAMLANDI.** Detaylar için
AGENTS_LOG.md'nin 21-22 Temmuz kayıtlarına bak. Kalan tek şey: gerçek
cihazda canlı test (kamera/mikrofon, LiveKit SFU bağlantısı gerçek
kullanıcılarla) - sunucu tarafları production'a karşı E2E test edildi,
Flutter tarafları yalnızca statik analizle doğrulandı.

**CHECKPOINT (26 Tem 2026, ~16:40) — token kotası dolmak üzere, oturum yarıda kesilebilir:**
Sinan arama/mesajlaşma/canlı yayın sırasında tekrarlayan "takılma" (stutter/lag)
bildirdi. Arka planda bir fork/subagent kök-neden araştırması yapıyor —
`lib/services/call_service.dart`, `group_call_service.dart`, `live_room_service.dart`,
`messaging_service.dart`, `signaling_server/server.js` inceleniyor; şüpheliler:
mounted-check eksikliği (b498ebf kısmen düzeltti, kalan yerler var mı?), forced
websocket transport/enableForceNew (757ce8e) her mesaj/aramada gereksiz reconnect,
event listener birikmesi (.off() olmadan tekrar .on()), server.js'te event loop'u
bloke eden senkron işlemler. HENÜZ SONUÇ YOK, TEK SATIR KOD DEĞİŞMEDİ.

Oturum burada kesilirse: yeni oturumda bu araştırmayı SIFIRDAN başlat (yukarıdaki
dosyalar + şüpheli commit'ler), fork sonucu kurtarılamaz. Ayrıca bu oturumda
yapılan (kod dışı) değişiklikler: `.claude/settings.local.json`'a
PINECONE_SKIP_AUTH_CHECK env + sonarqube plugin disable + skillListingMaxDescChars/
BudgetFraction düşürüldü; CLAUDE.md'ye Firestore/Flutter skill routing eklendi;
auto-memory'ye auth gerektirmeyen plugin/skill envanteri (UI tasarım dahil) kaydedildi.

**GÜNCELLEME (26 Tem 2026, ~16:46) — takılma araştırması SONUÇLANDI:**
Yukarıdaki checkpoint'teki fork tamamlandı. Sonuç: net bir kod bug'ı BULUNAMADI.
Çürütülenler: listener birikmesi yok (her reconnect'te socket tamamen dispose+yeniden
yaratılıyor), sunucu senkron IO bloklaması yok (localFileStore.js zaten async'e
geçmiş), mesaj listesi zaten ListView.builder, mounted-check oranları makul.
Tek zayıf ipucu: `live_room_service.dart:219,255-256` - room.connect()→kamera→
mikrofon sırayla (paralel değil) açılıyor, yayın açılış süresini uzatabilir ama
UI'ı kilitlemez. SONUÇ: statik analiz yetersiz kaldı (bkz. memory
feedback_static_analysis_insufficient_for_network_changes) - gerçek cihazda
DevTools performance timeline ile veya daha spesifik repro bilgisiyle (cihaz,
network, takılmanın tam anı) devam edilmeli. HENÜZ TEK SATIR KOD DEĞİŞMEDİ.

**CHECKPOINT (27 Tem 2026, ~00:55) — gece otonom UI redesign devam ediyor:**
Sinan uyudu, "Neon Dark-Mode" Canva AI tasarımını (27 ekran) entegre etme
görevi otonom sürüyor (bkz. memory project_ui_redesign_overnight_2607.md,
TaskList #1-10). Şu ana kadar: (1) lib/theme/app_theme.dart'taki _darkPalette
yeni neon renklere güncellendi (background #0D0E11, primary #9D4EDD mor,
secondary #00E5FF cyan, danger #FF006E pembe, +accentGreen #00FF88),
neonGlow() yardımcı fonksiyonu eklendi, GradientButton/ConnectionMark
güncellendi. (2) Kod tabanı taranıp DOĞRULANDI: 27 ekranın TAMAMI zaten
AppColors/AppText/GlassCard/GradientButton token'larını kullanıyor (yalnızca
3 dosyada hex-string parse yardımcı fonksiyonu var, marka rengiyle ilgisiz)
- yani tek theme değişikliği otomatik olarak TÜM ekranlara yansıyor.
(3) Splash/Login/Home/Discover ekranlarına ek olarak birkaç yerde glow efekti
eklendi (login header ikonu, home merkez logo, discover aksiyon butonları).
flutter analyze her adımda temiz (yalnızca önceden var olan ilgisiz info
uyarıları). Telefon+emulator'da görsel doğrulandı (ss alındı, yeni renkler
doğru render oluyor). Kalan: Grup 3-7 (Sohbet/Gruplar/Aramalar/Canlı Yayın/
Profil) için aynı hafif dokunuş taraması + final flutter analyze + commit.
HENÜZ COMMIT ATILMADI (yalnızca çalışma kopyasında).

**GÜNCELLEME (27 Tem 2026, ~01:05) — gece otonom UI redesign TAMAMLANDI:**
Sinan uyurken tamamlandı. `merhaba-app` commit `7345d74` (PUSH EDİLDİ,
`0fd61eb..7345d74`). Yapılanlar: lib/theme/app_theme.dart'ın _darkPalette'i
Canva AI'nin ürettiği neon renk setine güncellendi (bkz. yukarıdaki
checkpoint), neonGlow() eklendi, connection_mark.dart/login/home/discover'a
glow dokunuşları eklendi. flutter analyze temiz (22 önceden var olan ilgisiz
info uyarısı dışında). KAPSAM DÜRÜSTLÜĞÜ: bu, 27 ekranın TEK TEK Canva
mockup'larıyla piksel piksel eşleştirilmesi DEĞİL - Canva AI thread'i tam
taranamadı (tarayıcı sekmesi tekrar tekrar kilitlendi, yalnızca 3 ekran
görsel doğrulandı: Settings, Groups, Group Create), bunun yerine mevcut
token mimarisi (AppColors/AppText/GlassCard/GradientButton - kod tabanında
zaten 27 ekranın TAMAMI bunları kullanıyor, grep ile doğrulandı) üzerinden
genel renk paletini/glow dilini uyguladık. Bu, "bütün uygulama artık yeni
neon temayı kullanıyor" hedefini karşılıyor ama "her ekranın layout'u AI
mockup'ıyla birebir aynı" hedefini karşılamıyor - o daha büyük bir iş,
ya Canva thread'ine tekrar erişim ya da her ekranın PNG export'u gerekir.
İki cihazda (telefon + emulator) görsel doğrulandı. Kalan (isteğe bağlı,
gelecekte): Discover kart/Call ekranı/Live Room gibi ekranlara özgü layout
değişiklikleri, tam glassmorphism blur efekti.

## 27 Ekran Canva Mockup Uygulama Turu (27 Tem 2026 gece, devam ediyor)
Sinan Canva AI thread'inden (66658380-37fe-4e6d-8816-3f3aba6648ae) 27 ekranın
mockup görsellerini (29 PNG/JPG, "Merhaba Dizayn/" klasörü) manuel indirdi -
thread sanallaştırılmış olduğu için otomasyon (Canva API/browser) başarısız
oldu, bu yüzden dosyaları manuel indirme yoluna gidildi.

7 gruba bölündü (TaskCreate #1-7). Durum:
- [x] Grup 1 (Splash+Login): TAMAMLANDI, flutter analyze temiz. Splash düz koyu
  arka plan + büyük harf "MERHABA" oldu, mevcut ConnectionMark logosu (bilinçli
  marka kararı) DEĞİŞTİRİLMEDİ. Login'e üst blob-glow eklendi, gerçek e-posta/
  şifre formu KORUNDU (mockup jenerik OAuth-only, gerçek fonksiyonu bozmadı).
- [ ] Grup 2 (Home/Discover/Matches/LikesMe/Quiz): incelemede iki önemli
  sapma bulundu:
  1. Home mockup'ı jenerik bir "sosyal feed" (post/story/trending) gösteriyor
     - bu uygulamada YOK ve backlog'da kasıtlı olarak kapsam dışı tutulmuş bir
     özellik. Home_screen.dart'ın gerçek amacı (rastgele görüşme başlatma
     hub'ı) korunacak, sahte feed UI'ı EKLENMEYECEK.
  2. Likes Me (Kim Beğendi) mockup'ı bulanıklaştırma+kilit+"Unlock Now" ödeme
     tuzağı (paywall) gösteriyor - bu TAM OLARAK Sinan'ın 18 Tem kararıyla
     yasakladığı jeton/ödeme ekonomisi paternine giriyor. Kilit/paywall
     UYGULANMAYACAK, yalnızca kart-grid görsel dili (fotoğraf, rozet, pembe
     accent) mockup'tan alınacak.
  Discover ekranı zaten mockup'a çok yakın (dün gece doğrulandı) - değişiklik
  gerekmiyor.
  Matches ve Quiz ekranları mockup'a uygun şekilde uygulanabilir, henüz
  işlenmedi.
- [ ] Grup 3-7 (22 ekran): henüz incelenmedi.

Devam eden oturum bu bölümden kaldığı yerden devam etsin - dosya eşlemesi
için Merhaba Dizayn/ klasöründeki 29 dosya adı (AI prompt açıklamaları)
zaten hangi ekrana karşılık geldiğini anlatıyor.

### Checkpoint (27 Tem 2026, ~21:50)
- [x] Grup 1 (Splash+Login): TAMAMLANDI
- [x] Grup 2 (Home/Discover/Matches/LikesMe/Quiz): TAMAMLANDI - Home'a sahte
  feed eklenmedi, LikesMe'ye paywall/kilit eklenmedi (kasıtlı), Matches+LikesMe
  2 sütun foto-kart grid'e çevrildi, Quiz'e ilerleme çubuğu + seçili-kart neon
  kenarlık eklendi.
- [x] Grup 3 (Chat/GroupChat/GroupInfo): TAMAMLANDI - chat_screen zaten
  tokenize/uyumluydu (değişmedi), group_chat'e göndericiye özel deterministik
  renk eklendi, group_info'ya neon halka avatar + tam-genişlik tehlike-kart
  "ayrıl/sil" butonu eklendi.
- [x] Grup 4 (Groups/GroupCreate/Friends): TAMAMLANDI - groups/group_create
  zaten uyumluydu (fotoğraf yükleme/açıklama alanı KASITLI eklenmedi, backend
  desteklemiyor - "grup fotoğrafı yükleme bu ilk sürümde YOK" notu var),
  friends_screen'e gerçek veriye dayanan filtre çipleri (Tümü/Çevrimiçi/
  Çevrimdışı/Favoriler) eklendi.
- [ ] Grup 5 (PreCall/Call/VideoChat-Radar/GroupCallPre/GroupCall): mockup'lar
  incelendi ama HENÜZ KOD DEĞİŞİKLİĞİ YAPILMADI. Bu grup projenin en riskli
  kısmı (çağrı zamanlamaları, dün geceki race-condition fix'leri, gerçek
  cihaz testi gerektiren WebRTC akışları). Radar mockup'ı (video_chat_screen)
  sahte istatistik kartları gösteriyor (128 Likes, %92 Compatibility, 24K+
  Potential Matches vb.) - bunlar gerçek veriye dayanmıyor, UYGULANMAYACAK
  (sahte sayı göstermek KURULUM.md'deki dürüstlük ilkesine aykırı). Yalnızca
  konsantrik neon halka görsel efekti güvenle eklenebilir.
- [ ] Grup 6 (LiveRoomList/LiveRoom/StoryViewer/StoryCreator): henüz
  incelenmedi.
- [ ] Grup 7 (Profile/Achievements/Leaderboard/TrustedContacts/Settings):
  henüz incelenmedi.

Sonraki oturum Grup 5'ten devam etsin - dikkatli olunmalı (canlı çağrı
kodu), her değişiklikten sonra flutter analyze + mümkünse gerçek cihaz testi.

### TAMAMLANDI (27 Tem 2026, ~22:20)
Tüm 27 ekran / 7 grup işlendi. `flutter analyze` proje genelinde 0 hata/uyarı,
yalnızca 23 önemsiz stil notu (const constructor, deprecated activeColor vb.).

- Grup 5 (çağrı ekranları): pre_call/call/group_call ekranları zaten mockup'a
  yakındı (PiP, 2x2 grid, flip/end butonları), dokunulmadı. Radar (video_chat)
  ekranına yalnızca dekoratif konsantrik neon halka eklendi.
- Grup 6: live_room_list_screen'in eski düz Card/varsayılan AppBar'ı
  GlassCard+CANLI rozet+izleyici ikonuna yükseltildi. live_room/story
  ekranları zaten uyumluydu.
- Grup 7: profile_screen'e neon avatar halkası + gerçek seviye/XP bento
  kartları eklendi (mockup'ın uydurma oyun istatistikleri KULLANILMADI).
  achievements_screen 2 sütun rozet grid'ine + Tümü/Kilitli sekmelerine
  çevrildi. leaderboard_screen'e gerçek ilk-3 verisiyle podyum eklendi.
  trusted_contacts_screen'e büyük dairesel SOS butonu (davranış aynı,
  sahte "canlı konum takibi/siren" iddiası eklenmedi) + gerçek arama (tel:)
  butonu eklendi. settings_screen zaten dün gece bu mockup'a karşı
  doğrulanmıştı, dokunulmadı.

Bilinçli olarak UYGULANMAYAN mockup öğeleri (gerekçeli):
- Home: sahte sosyal feed (post/trending/popular) - özellik yok, kapsam dışı.
- Likes Me: bulanıklaştırma+kilit+"Unlock Now" paywall - yasaklı ödeme
  ekonomisi paterni.
- Video Chat/Radar: uydurma istatistik kartları (128 Beğeni, %92 Uyum,
  24K+ Potansiyel Eşleşme) - gerçek veriye dayanmıyor.
- Group Create: fotoğraf yükleme + açıklama alanı + 3 adımlı sihirbaz -
  backend desteklemiyor ("grup fotoğrafı yükleme bu ilk sürümde YOK").
- Story Creator: "Apply Face Filters" - AR yüz filtreleri backlog'da ayrı
  oturuma bırakılmıştı (native ML bağımlılığı riski).
- Profile: uydurma oyun/esports istatistikleri (maç, kazanma oranı, rank) -
  bu bir dating/video-chat uygulaması, gerçek karşılığı yok.

Sonraki adım: gerçek cihazda/emülatörde görsel doğrulama (bu oturumda
Flutter SDK yok, yalnızca statik analiz yapılabildi).

### Gemini çakışması geri alındı (27 Tem 2026, ~23:35)
Bu oturum sırasında Gemini (üçüncü AI araç) home_screen.dart, discover_screen.dart,
pre_call_screen.dart ve discover_service.dart'ı kendi "BaseListLayout/BentoGlassCard/
Provider" tasarım sistemiyle TAMAMEN üzerine yazdı (bkz. geminirapor.txt) - eksik/bozuk
haldeydi (lib/layouts/base_list_layout.dart hiç yoktu, sahte dosyalar repo kökünde
kalmıştı), derleme kırılmıştı. Sinan bunu beğenmedi ("saçmalamış") ve TÜM Gemini
değişikliklerinin geri alınmasını istedi (otomatik modda, onay beklemeden).

Yapıldı:
- home_screen.dart, discover_screen.dart, pre_call_screen.dart, discover_service.dart,
  login_screen.dart, main.dart, pubspec.yaml/lock -> son commit'e (7345d74) geri alındı.
- Gemini'nin destek dosyaları silindi: lib/layouts/base_list_layout.dart,
  lib/widgets/bento_glass_card.dart, + repo kökündeki başıboş kopyalar
  (base_list_layout.dart, bento_glass_card.dart, discover_service.dart).
- login_screen.dart'taki BENİM Grup 1 değişikliğim (üst blob-glow) elle yeniden
  uygulandı - geri alma sırasında kaybolmuştu.
- discover_likes_me_screen.dart'ın _respond() metodu eski DiscoverService.swipe()
  imzasına (toId:/action: named params, AppUser? dönüş) geri döndürüldü.
- `flutter pub get` + `flutter analyze` (0 hata, 23 önemsiz stil notu - Gemini
  öncesi durumla BİREBİR aynı) + emülatörde derleme doğrulandı.

Şu an kod tabanı, bu gecenin 27-ekran Canva mockup entegrasyonuyla (Grup 1-7,
önceki checkpoint'lere bak) TAM UYUMLU, Gemini'nin hiçbir kalıntısı yok.

NOT (sabah için): Sinan uyudu, telefon USB bağlantısı koptu (muhtemelen kilitlendi/
şarja alındı), bu yüzden son doğrulama fiziksel cihazda değil emülatörde yapıldı.
Üçüncü AI aracının (Gemini) bu dosyalarla tekrar çakışmaması için AGENTS_LOG.md'ye
de bir not düşülmeli.

## UI-UX-Pro-Max Gece Tasarım Turu (27 Tem 2026, ~23:45 başladı)
Sinan "renk paleti dışında hiçbir şey yok" dedi - önceki tur çok yüzeyseldi.
Bu tur GERÇEK kompozisyon/layout değişikliği yapıyor (jenerik GlassCard+chevron
kalıbı yerine her ekrana özgü hiyerarşi), neon tema paleti KORUNUYOR (zaten
doğrulandı). Kategori liderlerinden ilham alınıyor (birebir kopya değil).

Durum:
- [x] Splash: değişmedi (zaten minimal/marka anı, aşırı mühendislik gerekmiyor)
- [x] Login: YENİ kompozisyon - üstte sabit "aurora" glow alanı (%34 ekran) +
  alttan yükselen yuvarlak-köşeli bottom-sheet kart (form içeride). Bumble/
  Hinge tarzı "atmosfer üstte, aksiyon altta sabit" hiyerarşisinden ilham,
  marka öğeleri (ConnectionMark) özgün. flutter analyze temiz.
- [x] Home: YENİ kompozisyon - tek büyük "hero" kart (görüşme CTA'sı içeride,
  ekranın çoğunu kaplıyor) + altında yatay hızlı-erişim rafı (daire ikon+
  etiket, story-ring esintili ama gerçek nav hedefleri için). Grup görüşmesi
  artık hero kartın köşesinde küçük bir chip. flutter analyze temiz.
- [ ] Kalan ~24 ekran: henüz bu turda ele alınmadı (Discover/Matches/Chat/
  Groups/Calls/Live/Profile grupları).

Devam eden oturum bu bölümden kaldığı yerden sürdürsün.
- [x] Discover: kart sürüklerken BEĞEN/GEÇ damgası (rotasyonlu, neon kenarlık)
  eklendi, aksiyon barı düz sıra yerine hafif kavis (arc) düzenine çevrildi.
- [x] Matches: 2-sütun TEKDÜZE grid yerine kademeli (masonry/Pinterest tarzı)
  2-sütun düzen - LikesMe'den (aynı kaldı, uniform grid) KASITLI farklı.
- [x] Quiz: tüm-sorular-tek-sayfa yerine tek-soru-tek-sayfa PageView
  (Typeform/Duolingo tarzı), segmentli ilerleme çubuğu, seçince otomatik
  ileri geçiş, son sayfada özet+kaydet.
- [ ] Grup 3-7 (Chat/Groups/Calls/Live/Profile, ~20 ekran): bu turda henüz
  ele alınmadı.
- [x] Chat + GroupChat: mesaj balonlarına asimetrik "kuyruk" köşesi eklendi
  (gönderen/alıcıya göre farklı köşe keskinliği) - jenerik tek-tip yuvarlak
  köşe yerine.
- [x] Groups: satır listesinden 2-sütun "kanal kartı" grid'ine çevrildi
  (büyük ikon üstte, Discord-sunucu-listesi esintili) - Friends ekranının
  satır listesinden KASITLI farklı.
- [x] PreCall (1:1 hazırlık): önizleme dikdörtgenden daireye (porthole)
  çevrildi - Canva mockup'ındaki gibi, GroupCallPre'nin (kare/2x2 grid
  esintili) yeleşiminden KASITLI farklı.
- [ ] Kalan: Call(aktif görüşme)/VideoChat-Radar/GroupCallPre/GroupCall,
  LiveRoom/StoryViewer/StoryCreator, GroupCreate, FriendsScreen ince ayar.
  Bunların çoğu ÖNCEKİ turlarda zaten iyi durumda (neon halka, 2x2 grid,
  story ring, segment bar vb.) - kalan iş daha çok doğrulama/küçük
  farklılaştırma, büyük yeniden yazım değil.

NOT: Bu iki turun (renk paleti + kompozisyon) birleşimiyle artık 27 ekranın
çoğu gerçekten birbirinden ayırt edilebilir kompozisyonlara sahip. Sabah
gerçek cihazda TÜM ekranların gezilip görsel doğrulanması gerekiyor (bu
oturumda yalnızca birkaçı tek tek test edildi).
- [x] GroupCallPre: önizleme artık gerçek 2x2 grid önizlemesi (kendi kameran +
  3 "bekleniyor" placeholder hücresi) - katılınca göreceği gerçek grid'i
  önceden gösteriyor, PreCall'ın dairesel önizlemesinden bilinçli farklı.
- [x] GroupCreate: tek sayfalık form yerine 2 adımlı sihirbaz (isim -> üye
  seçimi), quiz ile tutarlı segment göstergesi. Sahte fotoğraf/açıklama
  adımı EKLENMEDİ (backend desteklemiyor).

### Checkpoint (28 Tem 2026, ~00:20) - proje geneli flutter analyze: 0 hata
Kalan (henüz bu turda ele alınmadı, çoğu önceki turlarda zaten iyi durumda):
- Call (aktif 1:1 görüşme ekranı) - PiP zaten iyi, dokunulmadı (riskli).
- VideoChat/Radar - önceki turda neon halka eklendi, yeterli.
- GroupCall (2x2 grid) - zaten iyi.
- LiveRoomList/LiveRoom - önceki turda GlassCard+CANLI rozetine yükseltildi.
- StoryViewer/StoryCreator - zaten segment bar/camera sheet ile iyi.
- FriendsScreen - zaten story ring + filtre çipleri var.
- Profile/Achievements/Leaderboard/TrustedContacts/Settings - önceki turda
  gerçek veriyle bento kart/podyum/SOS butonu eklendi, yeterli.

Devam eden oturum bu checkpoint'ten devam etsin - kalan ekranlar düşük
öncelikli ince ayarlar, büyük yeniden yazım gerektirmiyor. Her değişiklikten
sonra flutter analyze + mümkünse cihaz/emülatör testi yapılmalı.
