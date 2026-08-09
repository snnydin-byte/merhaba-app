import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'active_media_session_coordinator.dart';
import 'match_preferences_repository.dart';
import 'socket_client_options.dart';
import 'socket_event_payload.dart';

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
const String signalingServerUrl = String.fromEnvironment(
  'SIGNALING_SERVER_URL',
  defaultValue: 'https://merhaba-signaling.onrender.com',
);

typedef OnRemoteStream = void Function(MediaStream stream);
typedef OnLocalStream = void Function(MediaStream stream);
typedef OnStatusChange = void Function(String status);

/// Yeni bir eşleşme bulunduğunda tetiklenir. [partnerHasAccount], karşı
/// tarafın geçerli bir hesabı olup olmadığını bildirir -
/// "Arkadaş Ekle" butonunu yalnızca bu true iken göstermek için kullanılır.
/// [partnerDisplayName], karşı tarafın hesabı varsa adı - yoksa null
/// (eski eksik kayıtlarda ad olmayabilir). [partnerVerified], karşı tarafın hesabı en az
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
  io.Socket? _socket;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _partnerId;
  bool _disposed = false;
  bool _handlingOffer = false;
  bool _handlingAnswer = false;
  int _matchGeneration = 0;

  OnRemoteStream? onRemoteStream;
  OnLocalStream? onLocalStream;
  OnStatusChange? onStatusChange;
  OnMatchInfo? onMatchInfo;
  OnFriendRequestReceived? onFriendRequestReceived;
  OnFriendRequestResult? onFriendRequestResult;
  void Function()? onPartnerLeft;
  void Function(String message)? onChatMessage;
  void Function(String emoji)? onReaction;
  void Function(String message)? onFriendRequestError;
  void Function(String reportId)? onReportSent;
  void Function(String message)? onReportError;
  void Function(String message)? onAccountRestricted;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };
  Future<void>? _iceServersFuture;

  bool _backgroundSuspended = false;
  bool _resumeMic = false;
  bool _resumeCamera = false;

  /// Ayarlar ekranında SharedPreferences'a kaydedilmiş eşleşme tercihlerini
  /// okuyup connectAndFindMatch()'in beklediği formatta döner. Hiçbir tercih
  /// kaydedilmemişse (ilk kurulum, ya da kullanıcı hiç değiştirmediyse) boş
  /// bir map döner - bu da sunucu tarafında "filtresiz eşleştirme" anlamına
  /// gelir.
  static Future<Map<String, dynamic>> loadMatchPreferences() async {
    final preferences = await MatchPreferencesRepository().load();
    final result = preferences.toServerMap();

    // Konum yalnızca eşleşme başlatılırken okunur; kalıcı profile yazılmaz.
    final maxDistanceKm = preferences.maxDistanceKm;
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
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.low),
          ).timeout(const Duration(seconds: 10));
          result['maxDistanceKm'] = maxDistanceKm;
          result['myLat'] = position.latitude;
          result['myLng'] = position.longitude;
        }
      } catch (_) {
        // Konum alınamazsa diğer tercihlerle eşleşmeye devam edilir.
      }
    }
    return result;
  }

  /// Sunucunun /turn-credentials ucundan güncel ICE sunucu listesini çeker.
  /// Sunucuda TURN yapılandırılmamışsa, sunucu zaten yalnızca STUN listesi
  /// döner. İstek herhangi bir sebeple başarısız olursa (sunucuya
  /// ulaşılamıyor, zaman aşımı vb.) varsayılan STUN listesiyle sessizce
  /// devam ediyoruz - bu, TURN'ün "iyileştirme" olduğu, olmazsa olmaz
  /// olmadığı anlamına gelir.
  Future<void> _refreshIceServers(String authToken) async {
    try {
      final response = await http.get(
        Uri.parse('$signalingServerUrl/turn-credentials'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(const Duration(seconds: 20));
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
    _disposed = false;
    ActiveMediaSessionCoordinator().register(
      this,
      dispose,
      suspend: suspendMediaForBackground,
      resume: resumeMediaAfterBackground,
    );
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

  /// [authToken] zorunludur. Sunucu v108 itibarıyla yalnızca giriş yapmış
  /// ve doğum tarihiyle 18+ doğrulamasını tamamlamış hesapların random-match
  /// socket bağlantısını kabul eder.
  ///
  /// [matchPreferences] Ayarlar ekranından gelen eşleşme tercihleri
  /// (`genderFilter`, `minAge`, `maxAge`, `onlyVerified`) - verilmezse
  /// sunucu varsayılan (filtresiz) eşleştirme yapar.
  void connectAndFindMatch(
      {String? authToken, Map<String, dynamic>? matchPreferences}) {
    if (authToken == null || authToken.isEmpty) {
      onStatusChange?.call(
        'Rastgele eşleşme için giriş yapmış ve 18+ doğrulamasını tamamlamış olmalısın.',
      );
      return;
    }
    _disposed = false;
    ActiveMediaSessionCoordinator().register(
      this,
      dispose,
      suspend: suspendMediaForBackground,
      resume: resumeMediaAfterBackground,
    );
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
    _iceServersFuture = _refreshIceServers(authToken);
    _socket = io.io(
      signalingServerUrl,
      buildSocketClientOptions(authToken: authToken),
    );

    _socket!.onConnect((_) {
      final partnerId = _partnerId;
      if (partnerId != null) {
        onStatusChange?.call('Bağlantı geri yükleniyor...');
        _socket!.emit('match-resume', {'partnerId': partnerId});
      } else {
        onStatusChange?.call('Bağlandı, eşleşme aranıyor...');
        _socket!.emit('find-match', _matchPreferences);
      }
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

        final map = socketEventMap(data);
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
        final outer = socketEventMap(data);
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
        final map = socketEventMap(data);
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
        final map = socketEventMap(data);
        onChatMessage?.call(map['text'] as String? ?? '');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (chat-message): $e');
      }
    });

    // Karşı taraf bize arkadaşlık isteği gönderdi.
    _socket!.on('friend-request-received', (data) {
      try {
        final map = socketEventMap(data);
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
        final map = socketEventMap(data);
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
    // oturum geçersiz, zaten arkadaşsınız).
    _socket!.on('friend-request-error', (data) {
      try {
        final map = socketEventMap(data);
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
        final map = socketEventMap(data);
        onReportSent?.call(map['id'] as String? ?? '');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (report-user-sent): $e');
      }
    });

    // Şikayet gönderilemedi (ör. o an bir eşleşme yok).
    _socket!.on('report-user-error', (data) {
      try {
        final map = socketEventMap(data);
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
        final map = socketEventMap(data);
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
      if (pc.signalingState !=
              RTCSignalingState.RTCSignalingStateHaveRemoteOffer &&
          pc.signalingState !=
              RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer) {
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

  Future<void> suspendMediaForBackground() async {
    if (_backgroundSuspended) return;
    final audio = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    final video = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    _resumeMic = audio.any((track) => track.enabled);
    _resumeCamera = video.any((track) => track.enabled);
    for (final track in audio) {
      track.enabled = false;
    }
    for (final track in video) {
      track.enabled = false;
    }
    _backgroundSuspended = true;
  }

  Future<void> resumeMediaAfterBackground() async {
    if (!_backgroundSuspended || _disposed) return;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = _resumeMic;
    }
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = _resumeCamera;
    }
    _backgroundSuspended = false;
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

  Future<bool> leaveMatch(
      {Duration timeout = const Duration(seconds: 3)}) async {
    final socket = _socket;
    if (socket == null || !socket.connected) return false;
    final completer = Completer<bool>();
    socket.emitWithAck(
      'leave-match',
      const <String, dynamic>{},
      ack: (data) {
        if (completer.isCompleted) return;
        final map = socketEventMap(data);
        completer.complete(map['ok'] == true);
      },
    );
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return false;
    }
  }

  void toggleMic(bool enabled) {
    _resumeMic = enabled;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = enabled;
    });
  }

  void toggleCamera(bool enabled) {
    _resumeCamera = enabled;
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
    _backgroundSuspended = false;
    ActiveMediaSessionCoordinator().unregister(this);
    _disposed = true;
    _cleanupPeerConnection();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _socket?.disconnect();
    _socket?.dispose();
  }
}
