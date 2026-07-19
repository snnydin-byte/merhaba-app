# Merhaba — Gerçek Görüntülü Sohbet Uygulaması (WebRTC)

Uygulama gerçek kamera/mikrofon kullanıyor ve **kalıcı olarak barındırılan**
bir sinyalleşme sunucusu (Render, 7/24 çalışıyor) üzerinden gerçek karşı
tarafla WebRTC bağlantısı kuruyor. İki ayrı parça var:

1. `lib/` (proje kökü) → Flutter mobil uygulaması
2. `signaling_server/` → Node.js sinyalleşme sunucusu (Render'da canlı,
   `https://merhaba-signaling.onrender.com` adresinde)

---

## 1) Kurulum (geliştirme ortamı)

Sunucuyu kendi bilgisayarında ayrıca çalıştırmana **gerek yok** — uygulama
doğrudan canlı sunucuya bağlanacak şekilde yapılandırılmış
(`lib/services/webrtc_service.dart` içindeki `signalingServerUrl` sabiti).
Yerel IP adresi bulmana, `10.0.2.2` ayarlamana ya da telefon/bilgisayarın
aynı Wi-Fi'de olmasına gerek yok — bu artık geçerli değil, uygulama
internete bağlı her cihazdan çalışır.

```
flutter pub get
flutter run
```

Kamera/mikrofon izinleri (Android `AndroidManifest.xml`, iOS `Info.plist`)
zaten projeye eklenmiş durumda, elle bir şey eklemen gerekmiyor.

### Sunucu tarafında değişiklik yaptıysan

Yalnızca `signaling_server/` içindeki bir dosyayı (ör. `server.js`)
değiştirdiysen, bunun canlıya yansıması için o klasörden push'lamalısın:

```
cd signaling_server
git add -A
git commit -m "..."
git push
```

Render, bu push'u algılayıp otomatik olarak yeniden deploy eder (Render
dashboard'unda "Live" durumunu bekle). Flutter tarafında (ekranlar, servisler
vb.) yaptığın değişiklikler için push/deploy gerekmez — sadece `flutter run`
yeterli, değişiklik doğrudan derlenen uygulamada olur.

## Test etmek için: İKİ cihaza/hesaba ihtiyacın var

Görüntülü sohbeti ya da arkadaş aramasını test edebilmen için uygulamayı
**aynı anda iki cihazda** (iki telefon, ya da bir telefon + bir emülatör)
farklı hesaplarla açman gerekir. Tek cihazla "Sohbete Başla" dediğinde,
eşleşecek ikinci biri olmadığı için sürekli "eşleşme aranıyor" ekranında
bekler.

## Neler var?

```
(proje kökü)/
├── lib/
│   ├── main.dart
│   ├── theme/
│   │   └── app_theme.dart           → Ortak tasarım sistemi (renkler, bileşenler)
│   ├── services/
│   │   ├── webrtc_service.dart      → Rastgele eşleşme WebRTC bağlantı yönetimi
│   │   ├── call_service.dart        → Arkadaş araması (sesli/görüntülü)
│   │   └── messaging_service.dart   → Mesajlaşma
│   └── screens/
│       └── ...
├── android/ , ios/                  → Platform projeleri
├── pubspec.yaml
└── analysis_options.yaml

signaling_server/
├── server.js                        → Eşleştirme, sinyal mesajları, arkadaşlık/mesajlaşma API'si
├── firestoreSync.js                 → Kalıcı veri yedekleme (Firestore)
└── package.json
```

## Sınırlamalar / bilinmesi gerekenler

- **STUN + TURN birlikte kullanılıyor** — sunucu `/turn-credentials`
  üzerinden dinamik TURN kimlik bilgisi sağlıyor (bkz.
  `signaling_server/server.js`, `turnCredential.json`); TURN alınamazsa
  yalnızca STUN'a düşülüyor. Bu sayede farklı ağlardaki (biri Wi-Fi biri
  mobil veri) cihazlar arasında da bağlantı büyük ölçüde güvenilir kuruluyor.
- Bildirme (report) butonu gerçek — sunucuya kaydediliyor (bkz.
  `signaling_server/reportStore.js`); ayrıca bir moderatör paneli/otomatik
  aksiyon sistemi yok, şikayetler şu an yalnızca kayıt altına alınıyor.

## Push Bildirimleri (Firebase Cloud Messaging) Kurulumu

Uygulama kapalıyken/arka plandayken gelen mesajlar için push bildirimi
Firebase Cloud Messaging (FCM) üzerinden çalışıyor. Firebase yapılandırılmadan
uygulama ve sunucu normal çalışmaya devam eder — sadece push bildirimleri
gelmez (bkz. `isFirebaseConfigured` / `firebase-service-account.json`
kontrolleri).

### İstemci tarafı (Flutter)

`lib/firebase_options.dart` dosyasındaki `DefaultFirebaseOptions.android`
değerleri Firebase konsolundan indirilen `google-services.json` içeriğiyle
dolduruldu (proje: merhaba-93ddb). Yeni bir Firebase projesine geçilirse bu
dosya güncellenmeli.

Android tarafında `POST_NOTIFICATIONS` izni ve bildirim kanalı meta-verisi
`AndroidManifest.xml`'e zaten eklendi.

### Sunucu tarafı (Node.js)

Sunucunun push gönderebilmesi için Firebase konsolu → **Proje Ayarları →
Service accounts** → "Generate new private key" ile bir servis hesabı JSON'u
indirilip `signaling_server/firebase-service-account.json` olarak
yerleştirilmeli (bu dosya `.gitignore`'da — asla versiyon kontrolüne
eklenmemeli, `users.json` gibi).

> Not: `firebase-admin` v14+ modüler API kullanıyor
> (`require('firebase-admin/app')` / `require('firebase-admin/messaging')`) -
> eski `admin.credential.cert(...)` / `admin.messaging()` deseni bu sürümde
> çalışmıyor, `pushNotificationService.js` doğru (yeni) API'yi kullanıyor.

### Nasıl çalışıyor

- Bir kullanıcı giriş yaptığında veya oturumu geri yüklendiğinde cihazın FCM
  token'ı `POST /push-token` ile sunucuya kaydedilir.
- Çıkış yapıldığında `DELETE /push-token` ile token kaydı silinir.
- Bir arkadaş kalıcı mesaj gönderdiğinde, alıcı o an çevrimdışıysa
  (hiçbir açık bağlantısı yoksa) sunucu otomatik olarak push bildirimi
  gönderir.
- Uygulama ön plandayken gelen bildirimler `flutter_local_notifications` ile
  sistem bildirimi olarak gösterilir.
- Artık geçersiz olan token'lar Firebase'in hata yanıtlarından tespit edilip
  otomatik temizlenir.

## Google ile Hızlı Kayıt Kurulumu

"Google ile devam et" düğmesi kodda hazır ama iki değer YALNIZCA Firebase
konsolundan alınıp elle girilmeden çalışmaz — ayarlanana kadar düğme
istemcide hiç GÖSTERİLMEZ, sunucu tarafı da 503 döner (çökme yok, bkz.
`isGoogleSignInConfigured` / `GOOGLE_WEB_CLIENT_ID`).

### 1) Android imza parmak izini (SHA-1) Firebase'e ekle

Debug imzasının SHA-1/SHA-256 değeri (bu makinedeki `debug.keystore`'dan
üretildi):

```
SHA-1:   AD:9D:B5:69:86:7B:E7:05:D4:B6:04:0D:BB:75:8A:0C:3F:B8:B5:5F
SHA-256: DF:52:4B:4F:AC:FB:E6:50:E9:DA:FA:C0:37:99:2F:BC:B5:C8:DC:8C:03:D1:A4:66:06:86:DD:CB:94:D2:83:40
```

Firebase konsolu (console.firebase.google.com) → `merhaba-93ddb` projesi →
⚙ **Project settings** → **General** sekmesi → **Your apps** altında
`com.merhaba.app` Android uygulaması → **Add fingerprint** → yukarıdaki
SHA-1'i yapıştır (SHA-256 alanı varsa onu da ekle).

> Bu, yalnızca DEBUG derlemeleri (emülatör/geliştirme cihazı) için yeterli.
> Play Store'a gerçek bir sürüm yayınlarken RELEASE imzasının SHA-1'i de
> aynı şekilde eklenmeli, yoksa yayınlanan sürümde Google girişi çalışmaz.

### 2) Google sağlayıcısını aç ve Web Client ID'yi al

Firebase konsolu → sol menü **Authentication** → **Sign-in method** sekmesi
→ **Add new provider** → **Google** → Etkinleştir → bir destek e-postası
seç (kendi e-postan yeterli) → Kaydet.

Bu adım otomatik olarak bir "Web client (auto created by Google Service)"
OAuth istemcisi oluşturur. Aynı sayfada **Google** sağlayıcısına tıklayıp
"Web SDK configuration" kısmını açarsan **Web client ID** değerini
görürsün (`237640279761-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com`
formatında).

### 3) Bu değeri iki yere gir

- **İstemci**: `lib/services/auth_service.dart` içindeki
  `_googleWebClientId` sabitini bu değerle değiştir.
- **Sunucu**: Render dashboard → `merhaba-signaling` servisi →
  **Environment** sekmesi → **Add Environment Variable** →
  Key: `GOOGLE_WEB_CLIENT_ID`, Value: aynı değer → Save (otomatik yeniden
  deploy tetikler).

Bu değer GİZLİ değil (apiKey gibi herkese açık bir tanımlayıcı) — istemci
kodunda görünmesi normal, `.gitignore`'a eklenmesi gerekmiyor.

## Kalıcı Barındırma (Firestore Yedekleme)

Sunucu dosya tabanlı (`users.json`, `messages.json`, `reports.json`,
`turnCredential.json`) çalışıyor — Render gibi ücretsiz platformlarda yerel
disk kalıcı olmadığı için (her deploy/yeniden başlatmada sıfırlanabilir),
her değişiklik birkaç saniye içinde aynı Firebase projesindeki bir
**Firestore veritabanına** da yedekleniyor. Sunucu başlarken
(`bootstrapFirestoreSync.js`), yerel dosyalar boşsa Firestore'daki son
yedeği otomatik geri yükler — bu sayede Render'ın deploy/yeniden başlatma
döngüsünde veri kaybı olmaz.

`firebase-service-account.json` (push bildirimleri için zaten yerleştirilmiş
olan) Firestore'a erişim için de kullanılıyor, ekstra bir yapılandırma
gerekmiyor.

## Play Store Yayın Hazırlığı

Uygulama artık geliştirme/demo aşamasında değil — aşağıdaki adımlar gerçek
bir Play Store yayını için tamamlanmış/gerekli olanlar:

### Tamamlanmış olanlar

- `applicationId` → `com.merhaba.app` (Play Console'a kalıcı bağlı, bir
  daha değiştirilemez).
- `android:usesCleartextTraffic` ve yerel/test amaçlı
  `network_security_config.xml` referansı kaldırıldı — tüm trafik zaten
  HTTPS/WSS (Render + Firebase).
- Sürüm numarası artık `pubspec.yaml`'dan otomatik okunuyor
  (`package_info_plus`), elle senkronize edilen bir metin değil.

### Senin yapman gereken (yalnızca sende, tek seferlik)

**1. Release imzalama anahtarı (keystore) oluştur.** Şu an release build
hâlâ geçici debug anahtarıyla imzalanıyor (`key.properties` yoksa buna geri
düşüyor) — Play Console bunu production için kabul etmez. Kendi
bilgisayarında (JDK kurulu olmalı, Android Studio ile birlikte gelir):

```
keytool -genkey -v -keystore merhaba-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias merhaba
```

Sorulan şifreleri **not al, kimseyle paylaşma** — bu anahtarı kaybedersen
uygulamayı BİR DAHA güncelleyemezsin (Play Store'un "app signing" özelliği
devredeyse Google yedek tutar, ama upload key'in yine de bu olur).

`.jks` dosyasını `android/` klasörüne koy, sonra yanına
`android/key.properties` dosyasını oluştur:

```
storePassword=<keystore şifren>
keyPassword=<key şifren>
keyAlias=merhaba
storeFile=merhaba-release.jks
```

Bu dosya `.gitignore`'a eklenmiş olmalı — **asla** versiyon kontrolüne
ekleme. `android/app/build.gradle.kts` bu dosya varsa otomatik olarak
release build'i onunla imzalar.

**2. Gizlilik politikası.** Play Console, yayından önce bir gizlilik
politikası URL'si zorunlu kılıyor (rastgele görüntülü sohbet gibi
kullanıcı verisi işleyen uygulamalarda özellikle sıkı denetleniyor).
Ayarlar ekranındaki "Gizlilik Politikası" ve "Topluluk Kuralları" satırları
şu an dokunulduğunda hiçbir şey açmıyor — gerçek bir sayfa/URL hazırlanıp
bu ekranlara bağlanmalı.

**3. Hesap silme.** Google Play artık kullanıcı verisi toplayan uygulamalarda
uygulama İÇİNDEN hesap silme özelliğini zorunlu tutuyor — bu zaten var
(Ayarlar → "Hesabı Sil"), ekstra bir şey gerekmiyor.

**4. Data Safety formu.** Play Console'da hangi verilerin toplandığını
(e-posta, profil bilgisi, konum yok, vb.) beyan eden formu doldurman
gerekecek — bu form Play Console'da doldurulur, kodda bir karşılığı yok.

**5. İçerik derecelendirmesi / yaş sınırı.** Rastgele görüntülü sohbet
uygulamaları Google'ın "Kullanıcı Etkileşimli İçerik" kategorisinde en sıkı
denetlenen gruplardan biri — uygulama içinde zaten 18 yaş kuralı ve
şikayet/engelleme mekanizması var, ama Play Console'daki içerik
derecelendirme anketini buna göre doldurman gerekecek.

## Sorun giderme

- **"Eşleşme aranıyor" ekranında takılı kalıyorsa:** Render sunucusu
  "uyuyor" olabilir (ücretsiz katman 15 dk hareketsizlikten sonra uyur) —
  ilk istekte 30-60 saniye gecikme normal.
- **Kamera açılmıyorsa:** İzin diyaloğu reddedilmiş olabilir, Ayarlar'dan
  izni elle vermek gerekebilir (uygulama içinde "Ayarlara Git" butonu var).
- **Karşı taraf görünmüyor ama "bağlandı" yazıyorsa:** TURN kimlik bilgisi
  alınamamış olabilir (`/turn-credentials` isteği başarısız) — Render
  loglarında kontrol edilebilir.
