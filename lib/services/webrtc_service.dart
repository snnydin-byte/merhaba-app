import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// Ayarlar ekranındaki eşleşme tercihi anahtarları - burada tanımlıyoruz ki
// hem settings_screen.dart (yazan taraf) hem de bu servis (okuyan taraf)
// aynı sabitleri paylaşsın, anahtar isimleri iki yerde ayrı ayrı yazılıp
// birbirinden kayması riski olmasın.
const String matchGenderFilterPrefKey =
    'match_gender_filter'; // 'herkes' | 'erkek' | 'kadın'
const String matchMinAgePrefKey = 'match_min_age'; // int, yoksa yok
const String matchMaxAgePrefKey = 'match_max_age'; // int, yoksa yok
const String matchOnlyVerifiedPrefKey = 'match_only_verified'; // bool
// Batch C eşleştirme motoru genişletmeleri.
const String matchCountryFilterPrefKey = 'match_country_filter'; // String? ülke kodu
const String matchMaxDistanceKmPrefKey = 'match_max_distance_km'; // int, yoksa yok
const String matchTextOnlyPrefKey = 'match_text_only'; // bool
const String matchSpeedRoundPrefKey = 'match_speed_round'; // bool
// GECE_GELISTIRME madde 4 - ilgi alanı etiketiyle eşleştirme.
const String matchRequireCommonInterestPrefKey = 'match_require_common_interest'; // bool

/// Sunucunun adresi.
///
/// KALICI barındırma - Render'da (Frankfurt bölgesi) 7/24 çalışan bir Web
/// Service. Artık ne bilgisayarın açık olması, ne de bir tünel (cloudflared)
/// çalıştırman gerekiyor - sunucu Render'da bağımsız olarak çalışıyor,
/// verileri Firestore'a yedekliyor (bkz. signaling_server/firestoreSync.js).
///
/// Render'ın ücretsiz katmanında sunucu 15 dakika istek almazsa "uyur" -
/// bir sonraki istekte ~30-60 saniye gecikmeyle "uyanır" (bu normal, veri
/// kaybı OLMAZ çünkü kalıcı veri Firestore'da). Bu yüzden ilk bağlanma bazen
/// biraz uzun sürebilir.
const String signalingServerUrl = 'https://merhaba-signaling.onrender.com';

typedef OnRemoteStream = void Function(MediaStream stream);
typedef OnLocalStream = void Function(MediaStream stream);
typedef OnStatusChange = void Function(String status);

/// Yeni bir eşleşme bulunduğunda tetiklenir. [partnerHasAccount], karşı
/// tarafın gerçek bir hesabı olup olmadığını (misafir değil) bildirir -
/// "Arkadaş Ekle" butonunu yalnızca bu true iken göstermek için kullanılır.
/// [partnerDisplayName], karşı tarafın hesabı varsa adı - yoksa null
/// (misafirlerin adı olmaz). [partnerVerified], karşı tarafın hesabı en az
/// 7 günlük olup olmadığını (basit "onaylı hesap" rozeti) bildirir.
/// [partnerVoiceOnly], karşı tarafın "sesli-yalnız mod"da olup olmadığını
/// (kamerası hiç yok/kapalı) bildirir - true ise ekran, hiç gelmeyecek bir
/// video akışını beklemek yerine doğrudan sesli-mod göstergesini göstermeli.
/// [partnerTextOnly] (Batch C), karşı tarafın "sadece metin modu"nda olup
/// olmadığını bildirir - true ise hiçbir medya akışı (ne video ne ses)
/// beklenmemeli. [speedRoundSeconds] (Batch C), KENDİ "süreli hızlı
/// eşleştirme" tercihimiz seçiliyse bir geri sayım süresi (sn), aksi halde
/// null - karşı tarafın tercihiyle ilgisi yok, tamamen kişisel.
typedef OnMatchInfo = void Function(
    bool partnerHasAccount,
    String? partnerDisplayName,
    bool partnerVerified,
    bool partnerVoiceOnly,
    bool partnerTextOnly,
    int? speedRoundSeconds);

/// Karşı taraf bize bir arkadaşlık isteği gönderdiğinde tetiklenir.
typedef OnFriendRequestReceived = void Function(String fromDisplayName);

/// Gönderdiğimiz ya da bize gelen bir arkadaşlık isteğinin sonucu
/// belli olduğunda tetiklenir (kabul/red).
typedef OnFriendRequestResult = void Function(
    bool accepted, String? displayName);

class WebRTCService {
  /// Ayarlar ekranında SharedPreferences'a kaydedilmiş eşleşme tercihlerini
  /// okuyup connectAndFindMatch()'in beklediği formatta döner. Hiçbir tercih
  /// kaydedilmemişse (ilk kurulum, ya da kullanıcı hiç değiştirmediyse) boş
  /// bir map döner - bu da sunucu tarafında "filtresiz eşleştirme" anlamına
  /// gelir.
  static Future<Map<String, dynamic>> loadMatchPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{};
    final gender = prefs.getString(matchGenderFilterPrefKey);
    if (gender != null && gender != 'herkes') result['genderFilter'] = gender;
    final minAge = prefs.getInt(matchMinAgePrefKey);
    if (minAge != null) result['minAge'] = minAge;
    final maxAge = prefs.getInt(matchMaxAgePrefKey);
    if (maxAge != null) result['maxAge'] = maxAge;
    final onlyVerified = prefs.getBool(matchOnlyVerifiedPrefKey);
    if (onlyVerified == true) result['onlyVerified'] = true;
    final country = prefs.getString(matchCountryFilterPrefKey);
    if (country != null && country.isNotEmpty) result['countryFilter'] = country;
    final textOnly = prefs.getBool(matchTextOnlyPrefKey);
    if (textOnly == true) result['textOnly'] = true;
    final speedRound = prefs.getBool(matchSpeedRoundPrefKey);
    if (speedRound == true) result['speedRound'] = true;
    final requireCommonInterest = prefs.getBool(matchRequireCommonInterestPrefKey);
    if (requireCommonInterest == true) result['requireCommonInterest'] = true;

    // Yakınlık bazlı eşleştirme (Batch C) - konum sunucuya HER SEFERİNDE
    // canlı olarak gönderilir (bkz. server.js passesProximityFilter), asla
    // profile kaydedilmez. Konum alınamazsa (izin yok/GPS kapalı/zaman
    // aşımı) maxDistanceKm'i SESSİZCE atlıyoruz - sunucu myLat/myLng
    // olmadan zaten bu filtreyi uygulayamıyor, kullanıcıyı burada bir
    // hatayla durdurmanın (bu metot bir BuildContext'e sahip değil) bir
    // faydası yok, filtresiz eşleştirmeye devam etmesi daha iyi.
    final maxDistanceKm = prefs.getInt(matchMaxDistanceKmPrefKey);
    if (maxDistanceKm != null) {
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        final hasPermission = permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever;
        if (hasPermission && await Geolocator.isLocationServiceEnabled()) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          ).timeout(const Duration(seconds: 10));
          result['maxDistanceKm'] = maxDistanceKm;
          result['myLat'] = position.latitude;
          result['myLng'] = position.longitude;
        }
      } catch (_) {
        // Konum alınamadı - maxDistanceKm hiç eklenmedi, filtresiz devam.
      }
    }
    return result;
  }

  io.Socket? _socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _partnerId;

  // _handleOffer() içinde eşzamanlı/art arda 'offer' sinyalleri gelirse
  // createAnswer()'ın peer connection "have-remote-offer"da değilken
  // çağrılmasını (WEBRTC_CREATE_ANSWER_ERROR: "cannot create an answer in
  // a state other than have-remote-offer or have-local-pranswer" - canlı
  // olarak gözlemlenen çökme) engellemek için bir yeniden-girebilirlik
  // (reentrancy) kilidi - bkz. _handleOffer().
  bool _handlingOffer = false;

  // _handleAnswer() için AYNI GEREKÇEYLE bir kilit - canlı testte gözlemlenen
  // WEBRTC_SET_REMOTE_DESCRIPTION_ERROR ("Called in wrong state: stable")
  // çökmesi bunun eksikliğinden kaynaklanıyordu, bkz. _handleAnswer().
  bool _handlingAnswer = false;

  // 'matched' event'i, kullanıcı art arda hızlı eşleştirilirse (ör. iki
  // taraf da neredeyse aynı anda "sıradaki kişi"ye basıp hemen yeniden
  // eşleştirildiğinde) kısa aralıklarla birden fazla kez gelebilir. Her
  // gelişte bu sayaç artırılır - bir 'matched' işleyicisi kendi await'leri
  // sırasında (ör. _createPeerConnection() TURN bilgisini beklerken) DAHA
  // YENİ bir 'matched' event'i tarafından geçersiz kılınırsa, kendi
  // sayacının artık güncel olmadığını görüp durur - aksi halde iki farklı
  // eşleşmenin sinyalleri (offer/answer) karışıp WebRTC'nin "Called in
  // wrong state" hatasını fırlatmasına yol açıyordu.
  int _matchGeneration = 0;

  // getUserMedia() izin diyaloğu kullanıcı yanıt verene kadar uzun sürebilir.
  // Bu sırada ekran kapanıp dispose() çağrılırsa, izin sonunda gelince artık
  // var olmayan bir ekran için kamera/mikrofon akışını açık bırakmamak
  // (kaynak sızıntısı) için bu bayrağı kontrol ediyoruz.
  bool _disposed = false;

  OnRemoteStream? onRemoteStream;
  OnLocalStream? onLocalStream;
  OnStatusChange? onStatusChange;
  void Function(String text)? onChatMessage;
  void Function(String emoji)? onReaction;
  void Function()? onPartnerLeft;
  OnMatchInfo? onMatchInfo;
  OnFriendRequestReceived? onFriendRequestReceived;
  OnFriendRequestResult? onFriendRequestResult;
  void Function(String message)? onFriendRequestError;
  void Function(String reportId)? onReportSent;
  void Function(String message)? onReportError;
  void Function(String message)? onAccountRestricted;

  // Varsayılan (yalnızca STUN) liste - sunucudan TURN bilgisi alınamazsa
  // (ör. sunucuda TURN yapılandırılmamışsa ya da /turn-credentials isteği
  // zaman aşımına uğrarsa) bu listeyle devam ediyoruz, böylece aynı Wi-Fi
  // gibi STUN'un yeterli olduğu durumlarda hiçbir şey bozulmuyor.
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  // connectAndFindMatch() çağrıldığında arka planda başlatılır - eşleşme
  // bulunup peer connection kurulana kadar genelde tamamlanmış olur, bu
  // yüzden gerçek bağlantı kurulumunu geciktirmez. Sunucudan güncel TURN
  // sunucu bilgisini (varsa) çeker - bkz. _refreshIceServers().
  Future<void>? _iceServersFuture;

  /// Sunucunun /turn-credentials ucundan güncel ICE sunucu listesini çeker.
  /// Sunucuda TURN yapılandırılmamışsa, sunucu zaten yalnızca STUN listesi
  /// döner. İstek herhangi bir sebeple başarısız olursa (sunucuya
  /// ulaşılamıyor, zaman aşımı vb.) varsayılan STUN listesiyle sessizce
  /// devam ediyoruz - bu, TURN'ün "iyileştirme" olduğu, olmazsa olmaz
  /// olmadığı anlamına gelir.
  Future<void> _refreshIceServers() async {
    try {
      final response = await http
          .get(Uri.parse('$signalingServerUrl/turn-credentials'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final servers = data['iceServers'] as List<dynamic>?;
      if (servers == null || servers.isEmpty) return;
      _iceServers = {
        'iceServers':
            servers.map((s) => Map<String, dynamic>.from(s as Map)).toList(),
      };
    } catch (e) {
      // ignore: avoid_print
      print('TURN bilgisi alınamadı, yalnızca STUN ile devam ediliyor: $e');
    }
  }

  /// Şu an açık olan yerel kamera/mikrofon akışı - varsa. PreCallScreen'de
  /// zaten initLocalMedia() ile başlatılmış bir akışı VideoChatScreen'e
  /// (izinleri/kamerayı tekrar istemeden) devretmek için kullanılır.
  MediaStream? get localStream => _localStream;

  /// PreCallScreen'de kullanıcı mikrofonu/kamerayı kapatmış olabilir -
  /// VideoChatScreen bu akışı devraldığında düğme durumlarını (açık/kapalı
  /// ikonu) gerçek track durumuyla eşleştirmek için kullanılır.
  bool get isMicEnabled {
    final tracks = _localStream?.getAudioTracks();
    if (tracks == null || tracks.isEmpty) return true;
    return tracks.first.enabled;
  }

  bool get isCamEnabled {
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return true;
    return tracks.first.enabled;
  }

  // "Sesli-yalnız mod" - true ise yerel akışta hiç video track'i yok
  // (kamera hiç açılmadı), isCamEnabled'daki "track yoksa true dön"
  // davranışıyla KARIŞTIRILMAMALI: isCamEnabled "kamera açık mı" sorusuna,
  // hasCamera ise "kamera hiç var mı" sorusuna cevap verir. initLocalMedia()
  // audioOnly:true ile çağrıldığında ayarlanır - bkz. orada.
  bool _voiceOnly = false;

  /// Şu an yerel akışta bir video track'i olup olmadığını bildirir -
  /// PreCallScreen/VideoChatScreen bunu kamera düğmesini/önizlemesini hiç
  /// göstermemek için kullanır (kullanıcı "sesli-yalnız mod"u seçtiyse
  /// kamera hiç açılmamıştır, kapalıyken açık bir düğme göstermek yanıltıcı
  /// olurdu).
  bool get hasCamera => (_localStream?.getVideoTracks().length ?? 0) > 0;

  /// [audioOnly] true verilirse kamera HİÇ istenmez (yalnızca mikrofon
  /// akışı alınır) - "sesli-yalnız mod" için. Bu, mevcut toggleCamera()'nın
  /// aksine (track'i sadece enabled=false yapıp açık bırakır) kamerayı
  /// fiilen hiç açmaz/serbest bırakır - hem gizlilik hem de karşı tarafa
  /// boşuna siyah bir video karesi göndermemek için daha doğrusu budur.
  /// Bu metot, önceden açılmış bir yerel akış varken de (ör. kullanıcı
  /// PreCallScreen'de "sesli-yalnız mod"u açıp sonra tekrar kapatırsa)
  /// güvenle tekrar çağrılabilir - yeni akış BAŞARIYLA alındıktan SONRA
  /// eskisi kapatılır, böylece getUserMedia() başarısız olursa (ör. izin
  /// sorunu) önceki çalışan akış kaybolmaz.
  Future<void> initLocalMedia(
      {required OnLocalStream onLocal, bool audioOnly = false}) async {
    onLocalStream = onLocal;
    final mediaConstraints = {
      'audio': true,
      'video': audioOnly
          ? false
          : {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
            },
    };
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (_disposed) {
      // Ekran bu izin bekleme sırasında kapandı - akışı hemen durdurup
      // bırakıyoruz, hiçbir callback'i tetiklemiyoruz.
      stream.getTracks().forEach((track) => track.stop());
      stream.dispose();
      return;
    }
    final oldStream = _localStream;
    _localStream = stream;
    _voiceOnly = audioOnly;
    oldStream?.getTracks().forEach((track) => track.stop());
    oldStream?.dispose();
    onLocal(stream);
  }

  // Ayarlar ekranında seçilen eşleşme tercihleri (cinsiyet/yaş/onaylı hesap
  // filtreleri) - connectAndFindMatch()'e verilir, hem ilk bağlantıda hem de
  // skipToNext() ile kuyruğa her yeniden eklenişte sunucuya gönderilir ki
  // filtre tüm oturum boyunca geçerli kalsın.
  Map<String, dynamic>? _matchPreferences;

  /// [authToken] verilirse (giriş yapmış kullanıcı), sunucuya bağlanırken
  /// kimlik doğrulaması için gönderilir - böylece sunucu bu socket'in
  /// arkasında gerçek bir hesap olduğunu bilir ve arkadaşlık isteklerine
  /// izin verir. Misafir kullanıcılar için null geçilebilir; video sohbetin
  /// temel özellikleri hesap gerektirmez.
  ///
  /// [matchPreferences] Ayarlar ekranından gelen eşleşme tercihleri
  /// (`genderFilter`, `minAge`, `maxAge`, `onlyVerified`) - verilmezse
  /// sunucu varsayılan (filtresiz) eşleştirme yapar.
  void connectAndFindMatch(
      {String? authToken, Map<String, dynamic>? matchPreferences}) {
    // ÖNCEDEN burada, önceki bir _socket varsa (ör. pre_call_screen.dart'ta
    // izin reddedilip kullanıcı izni sonradan verip _retry() akışını
    // tekrar tetiklediğinde - bu servis aynı ekranda ikinci kez
    // çağrılabiliyor) hiç kapatılmadan üzerine YENİ bir soket atanıyordu -
    // eski soket sunucuya bağlı/kuyrukta kalmaya devam edip kaynak
    // sızıntısına ve sunucu tarafında hayalet bir kuyruk kaydına yol
    // açabiliyordu. messaging_service.dart/call_service.dart'taki
    // connectIfNeeded() ile aynı desen: yeni soket kurmadan önce eskisini
    // düzgünce kapatıyoruz.
    _socket?.disconnect();
    _socket?.dispose();
    // "Sesli-yalnız mod" seçiliyse (bkz. hasCamera/initLocalMedia notu) bunu
    // eşleşme tercihlerine ekliyoruz ki sunucu, karşı tarafa
    // "partnerVoiceOnly" bilgisini iletebilsin (bkz. server.js tryMatch()) -
    // böylece karşı tarafın ekranı hiç gelmeyecek bir video akışını
    // beklemek yerine doğrudan sesli-mod göstergesini gösterir.
    final prefs = Map<String, dynamic>.from(matchPreferences ?? {});
    if (_voiceOnly) prefs['voiceOnly'] = true;
    _matchPreferences = prefs.isEmpty ? null : prefs;
    onStatusChange?.call('Sunucuya bağlanılıyor...');
    // Soket bağlantısıyla PARALEL olarak TURN bilgisini almaya başlıyoruz -
    // eşleşme genelde bundan daha uzun sürdüğü için _createPeerConnection()
    // çağrıldığında bu iş çoktan bitmiş olur.
    _iceServersFuture = _refreshIceServers();
    final optionBuilder = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew();
    if (authToken != null) {
      optionBuilder.setAuth({'token': authToken});
    }
    _socket = io.io(signalingServerUrl, optionBuilder.build());

    _socket!.onConnect((_) {
      onStatusChange?.call('Bağlandı, eşleşme aranıyor...');
      _socket!.emit('find-match', _matchPreferences);
    });

    _socket!.onConnectError((err) {
      onStatusChange?.call('Bağlantı hatası: sunucuya ulaşılamıyor.');
    });

    _socket!.on('matched', (data) async {
      final myGeneration = ++_matchGeneration;
      try {
        // Önceki eşleşmeden kalma bir peer connection varsa önce onu
        // temizliyoruz - iki taraf da neredeyse aynı anda yeniden
        // eşleştirilirse art arda 'matched' event'i gelebiliyor, eski
        // bağlantı hâlâ "teklif gönderdim, yanıt bekliyorum" durumundayken
        // yeni bağlantının sinyalleri ona karışmasın diye (bkz. sınıf
        // üstündeki _matchGeneration notu).
        _cleanupPeerConnection();

        final map = Map<String, dynamic>.from(data as Map);
        final partnerId = map['partnerId'] as String?;
        final isInitiator = map['isInitiator'] as bool? ?? false;
        _partnerId = partnerId;
        onStatusChange?.call('Eşleşme bulundu, bağlanılıyor...');
        onMatchInfo?.call(
          map['partnerHasAccount'] as bool? ?? false,
          map['partnerDisplayName'] as String?,
          map['partnerVerified'] as bool? ?? false,
          map['partnerVoiceOnly'] as bool? ?? false,
          map['partnerTextOnly'] as bool? ?? false,
          map['speedRoundSeconds'] as int?,
        );
        await _createPeerConnection(expectedGeneration: myGeneration);

        // Yukarıdaki await sırasında ekran kapanmış (bkz.
        // _createPeerConnection() içindeki _disposed kontrolü) YA DA daha
        // yeni bir 'matched' event'i gelip bizi geçersiz kılmış olabilir -
        // bu durumlarda burada durup artık geçersiz olan bu eşleşme için
        // teklif oluşturmuyoruz. isInitiator'ı yerel değişkenden okuyoruz
        // (instance alanından değil) ki aradaki bir 'matched' event'i onu
        // değiştirmiş olsa bile BU eşleşmenin doğru kararını versin.
        if (myGeneration != _matchGeneration || _peerConnection == null) return;
        if (isInitiator) {
          await _createOffer(expectedGeneration: myGeneration);
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('HATA (matched): $e\n$st');
        onStatusChange?.call('Hata (eşleşme): $e');
      }
    });

    _socket!.on('signal', (data) async {
      try {
        final outer = Map<String, dynamic>.from(data as Map);
        final fromId = outer['fromId'] as String?;
        final payload = Map<String, dynamic>.from(outer['data'] as Map);
        if (fromId != _partnerId) return;

        final type = payload['type'];
        if (type == 'offer') {
          await _handleOffer(payload);
        } else if (type == 'answer') {
          await _handleAnswer(payload);
        } else if (type == 'candidate') {
          await _handleCandidate(payload);
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('HATA (signal): $e\n$st');
        onStatusChange?.call('Hata (sinyal): $e');
      }
    });

    // Görüşme içi hızlı tepkiler (GECE_GELISTIRME madde 3).
    _socket!.on('call-reaction', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final emoji = map['emoji'] as String?;
        if (emoji != null) onReaction?.call(emoji);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (call-reaction): $e');
      }
    });

    _socket!.on('partner-left', (_) {
      onStatusChange?.call('Karşı taraf ayrıldı.');
      onPartnerLeft?.call();
      _cleanupPeerConnection();
    });

    _socket!.on('chat-message', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onChatMessage?.call(map['text'] as String? ?? '');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (chat-message): $e');
      }
    });

    // Karşı taraf bize arkadaşlık isteği gönderdi.
    _socket!.on('friend-request-received', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onFriendRequestReceived
            ?.call(map['fromDisplayName'] as String? ?? 'Biri');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (friend-request-received): $e');
      }
    });

    // Gönderdiğimiz ya da bize gelen isteğin sonucu belli oldu.
    _socket!.on('friend-request-result', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onFriendRequestResult?.call(
          map['accepted'] as bool? ?? false,
          map['displayName'] as String?,
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (friend-request-result): $e');
      }
    });

    // Arkadaşlık isteği gönderilemedi (ör. giriş yapılmamış, karşı taraf
    // misafir, zaten arkadaşsınız).
    _socket!.on('friend-request-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onFriendRequestError?.call(
            map['message'] as String? ?? 'Arkadaşlık isteği gönderilemedi.');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (friend-request-error): $e');
      }
    });

    // Şikayet başarıyla kaydedildi.
    _socket!.on('report-user-sent', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onReportSent?.call(map['id'] as String? ?? '');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (report-user-sent): $e');
      }
    });

    // Şikayet gönderilemedi (ör. o an bir eşleşme yok).
    _socket!.on('report-user-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onReportError
            ?.call(map['message'] as String? ?? 'Şikayet gönderilemedi.');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (report-user-error): $e');
      }
    });

    // Hesabımız, birden fazla şikayet nedeniyle rastgele eşleştirmeden
    // kısıtlandı (sunucu bunu ya find-match/skip anında ya da karşı taraf
    // bizi şikayet edip eşiği aştığımızda mevcut görüşmeyi de sonlandırarak
    // gönderir).
    _socket!.on('account-restricted', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onAccountRestricted?.call(
          map['message'] as String? ?? 'Hesabın incelemeye alındı.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (account-restricted): $e');
      }
    });

    _socket!.connect();
  }

  /// Şu an eşleşilen kişiye arkadaşlık isteği gönderir. Sunucu, karşı
  /// tarafın hesabı olup olmadığını ve zaten arkadaş olunup olunmadığını
  /// kontrol eder - burada ek bir doğrulama yapmıyoruz.
  void sendFriendRequest() {
    _socket?.emit('friend-request');
  }

  /// Gelen bir arkadaşlık isteğine cevap verir (kabul/red).
  void respondToFriendRequest(bool accepted) {
    _socket?.emit('friend-request-response', {'accepted': accepted});
  }

  Future<void> _createPeerConnection({int? expectedGeneration}) async {
    // TURN bilgisi henüz gelmediyse burada bekliyoruz (en fazla
    // _refreshIceServers() içindeki zaman aşımı kadar) - ama ekran bu
    // sırada kapanmış olabilir, bu yüzden bekledikten sonra tekrar
    // _disposed kontrolü yapıyoruz.
    if (_iceServersFuture != null) {
      await _iceServersFuture;
    }
    if (_disposed) return;
    // Bu bekleme sırasında DAHA YENİ bir 'matched' event'i gelip bizi
    // geçersiz kılmış olabilir (bkz. _matchGeneration notu) - bu durumda
    // artık geçersiz olan bu bağlantıyı kurmaya devam etmiyoruz, aksi
    // halde biraz aşağıda oluşturacağımız peer connection, YENİ eşleşmenin
    // az önce kurduğu geçerli bağlantının üzerine yazabilir.
    if (expectedGeneration != null && expectedGeneration != _matchGeneration) {
      return;
    }

    final pc = await createPeerConnection(_iceServers);
    if (_disposed ||
        (expectedGeneration != null &&
            expectedGeneration != _matchGeneration)) {
      // Peer connection kurulurken ekran kapandı YA DA bu eşleşme artık
      // geçersiz - hemen kapatıp hiçbir yere atamıyoruz, kaynak sızıntısı
      // olmasın ve geçerli (daha yeni) bağlantının üzerine yazılmasın.
      pc.close();
      return;
    }
    _peerConnection = pc;

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
        onStatusChange?.call('Bağlandı');
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_partnerId == null) return;
      _socket?.emit('signal', {
        'targetId': _partnerId,
        'data': {
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };
  }

  Future<void> _createOffer({int? expectedGeneration}) async {
    final pc = _peerConnection;
    if (pc == null) return;
    final targetId = _partnerId;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    // Yukarıdaki await'ler sırasında bu eşleşme daha yeni bir 'matched'
    // event'i tarafından geçersiz kılınmış olabilir (bkz. _matchGeneration
    // notu) - bu durumda artık kapatılmış/değiştirilmiş olabilecek bir
    // bağlantı için sinyal göndermiyoruz, _peerConnection'ı tekrar
    // force-unwrap etmek yerine yakaladığımız yerel `pc` referansı üzerinde
    // çalışıyoruz ki araya giren bir değişiklik yanlış bağlantıyı
    // etkilemesin.
    if (expectedGeneration != null && expectedGeneration != _matchGeneration) {
      return;
    }
    _socket?.emit('signal', {
      'targetId': targetId,
      'data': {'type': 'offer', 'sdp': offer.sdp},
    });
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    final pc = _peerConnection;
    if (pc == null) return;
    // bkz. sınıf üstündeki _handlingOffer notu - zaten bir offer
    // işleniyorsa (ör. ağ gecikmesi yüzünden yeniden gönderim) yenisini
    // sessizce yok sayıyoruz.
    if (_handlingOffer) return;
    _handlingOffer = true;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(payload['sdp'] as String, 'offer'),
      );
      // setRemoteDescription sırasında (await) peer connection başka bir
      // event tarafından kapatılmış/durumu değişmiş olabilir -
      // createAnswer() yalnızca have-remote-offer ya da have-local-pranswer
      // durumundayken geçerlidir - aksi halde tam da canlı test sırasında
      // gözlemlenen WEBRTC_CREATE_ANSWER_ERROR çökmesi oluşuyordu.
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveRemoteOffer &&
          pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer) {
        return;
      }
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _socket?.emit('signal', {
        'targetId': _partnerId,
        'data': {'type': 'answer', 'sdp': answer.sdp},
      });
    } finally {
      _handlingOffer = false;
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    final pc = _peerConnection;
    // setRemoteDescription(answer) yalnızca peer connection "kendi teklifimizi
    // gönderdik, yanıt bekliyoruz" (have-local-offer) durumundayken
    // geçerlidir. Ağ gecikmesi/yeniden gönderim yüzünden AYNI yanıt iki kez
    // gelirse (ya da bağlantı skip/yeni eşleşme nedeniyle zaten değiştiyse)
    // burada sessizce yok sayıyoruz - aksi halde WebRTC "Called in wrong
    // state: stable" hatası fırlatıyor ve görüşme "BAĞLANIYOR" durumunda
    // takılı kalıyordu.
    if (pc == null ||
        pc.signalingState !=
            RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      return;
    }
    // CANLI TESTTE GÖZLEMLENEN GERÇEK ÇÖKME: yukarıdaki kontrol tek başına
    // yeterli değildi - _handleOffer()'a eklediğim kilitle AYNI sınıftan bir
    // yarış durumu (race condition) burada da vardı. İki 'answer' sinyali
    // (ör. ağ üzerinden çok yakın aralıkla art arda) neredeyse aynı anda
    // işlenmeye başlarsa: HER İKİSİ de yukarıdaki senkron kontrolü geçebilir
    // (ikisi de kontrol anında hâlâ "have-local-offer" görür, çünkü ilk
    // çağrının setRemoteDescription()'ı native tarafta henüz TAMAMLANMAMIŞ
    // olabilir) - sonra ilki native tarafta işlenip durumu "stable"a
    // geçirince, ikincisinin native çağrısı ARTIK GEÇERSİZ bir durumda
    // ("Called in wrong state: stable") çalışıp hata fırlatıyordu. Kilit,
    // aynı anda yalnızca TEK bir setRemoteDescription çağrısının
    // çalışmasını garanti ediyor - ikinci çağrı kilidi görüp hemen çıkıyor.
    if (_handlingAnswer) return;
    _handlingAnswer = true;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(payload['sdp'] as String, 'answer'),
      );
    } finally {
      _handlingAnswer = false;
    }
  }

  Future<void> _handleCandidate(Map<String, dynamic> payload) async {
    final pc = _peerConnection;
    if (pc == null) return;
    if (payload['candidate'] == null) return;
    await pc.addCandidate(
      RTCIceCandidate(
        payload['candidate'] as String,
        payload['sdpMid'] as String?,
        payload['sdpMLineIndex'] as int?,
      ),
    );
  }

  void skipToNext() {
    _cleanupPeerConnection();
    // Eski eşleşmenin kimliğini de temizliyoruz - aksi halde skip'ten hemen
    // sonra eski partnerden gecikmeli gelen bir sinyal (ör. geç kalmış bir
    // ICE candidate), _partnerId hâlâ eski değeri taşıdığı için "geçerli"
    // sanılıp artık null olan _peerConnection üzerinde çalıştırılmaya
    // çalışılıp çökmeye neden olabiliyordu.
    _partnerId = null;
    onStatusChange?.call('Yeni eşleşme aranıyor...');
    _socket?.emit('skip');
  }

  /// Şu an eşleşilen kişiyi bildirir/şikayet eder. [reason] sunucunun kabul
  /// ettiği sabit nedenlerden biri olmalı ('uygunsuz-goruntu', 'taciz',
  /// 'spam', 'sahte-hesap', 'diger') - geçersiz/boş bir değer sunucu
  /// tarafında otomatik olarak 'diger'e düşürülür. [note] isteğe bağlı,
  /// serbest metin bir açıklama.
  void reportUser(String reason, {String? note}) {
    _socket?.emit('report-user', {'reason': reason, 'note': note});
  }

  void sendChatMessage(String text) {
    _socket?.emit('chat-message', {'text': text});
  }

  /// Görüşme içi hızlı tepki gönderir (GECE_GELISTIRME madde 3) - [emoji]
  /// sunucudaki QUICK_REACTIONS kataloğunda olmalı, aksi halde sunucu
  /// sessizce yok sayar (bkz. video_chat_screen.dart quickReactions).
  void sendReaction(String emoji) {
    _socket?.emit('call-reaction', {'emoji': emoji});
  }

  void toggleMic(bool enabled) {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = enabled;
    });
  }

  void toggleCamera(bool enabled) {
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = enabled;
    });
  }

  /// Ön/arka kamera arasında geçiş yapar. WebRTC bağlantısı zaten kurulmuşsa
  /// (peer'a video gönderiliyorsa) karşı taraf da otomatik olarak yeni
  /// kamera görüntüsünü görmeye başlar - track değişmez, sadece kaynağı değişir.
  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks == null || videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
  }

  void _cleanupPeerConnection() {
    _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
    // Yeni bir eşleşme/bağlantı başlıyor - eski bağlantıya ait bir offer/
    // answer işleme kilidi varsa (ör. temizlik tam bir _handleOffer()/
    // _handleAnswer() ortasında tetiklendiyse) yeni bağlantının sinyallerini
    // sonsuza kadar engellememesi için sıfırlıyoruz.
    _handlingOffer = false;
    _handlingAnswer = false;
  }

  void dispose() {
    _disposed = true;
    _cleanupPeerConnection();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
