import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'webrtc_service.dart' show signalingServerUrl;

import 'active_media_session_coordinator.dart';
import 'app_connection_state.dart';
import 'connection_error_classifier.dart';
import 'session_expiration_coordinator.dart';
import 'shared_socket_transport.dart';
import 'socket_event_payload.dart';

typedef OnRemoteStream = void Function(MediaStream stream);
typedef OnLocalStream = void Function(MediaStream stream);
typedef OnStatusChange = void Function(String status);

/// Bir arkadaşla yapılan sesli/görüntülü arama için uygulama boyunca KALICI,
/// tek bir servis (singleton - AuthService/MessagingService ile aynı desen).
///
/// webrtc_service.dart'taki WebRTCService ile ÇOK benzer bir WebRTC
/// çekirdeği kullanır (peer connection kurulumu, offer/answer/ICE), ama
/// bilerek ayrı bir sınıf: WebRTCService rastgele eşleştirme kuyruğuna
/// (find-match/skip) göre tasarlandı, bu servis ise BELİRLİ bir arkadaşı
/// (userId ile) arayıp davet/kabul akışı yürütüyor. İkisi de aynı sunucu
/// altyapısını (partners Map, 'matched'/'signal'/'partner-left' eventleri)
/// paylaşıyor - bkz. server.js'deki 'call-invite-response' handler'ı,
/// kabul edilince tıpkı rastgele eşleşme gibi 'matched' event'i yayınlıyor.
///
/// ÖNCEDEN sinyal SOKETİ yalnızca Arkadaşlar ekranı açıkken kuruluyordu, bu
/// yüzden gelen arama davetleri kullanıcı başka bir ekrandaysa (Sohbet, Ana
/// Sayfa, Profil...) hiç ulaşmıyordu. Artık soket, oturum açılır açılmaz BİR
/// KEZ kurulur (bkz. splash_screen.dart, login_screen.dart) ve çıkış
/// yapılana kadar açık kalır - gelen arama davetlerinin gösterilmesi de
/// (diyalog, CallScreen'e geçiş) artık belirli bir ekrana değil,
/// call_ui_controller.dart'a bağlı - bkz. orada.
///
/// Her görüşme kendi WebRTC oturumuna sahiptir ([endCallSession] ile
/// kapatılır, bkz. call_screen.dart) - yalnızca sinyal SOKETİ kalıcıdır,
/// tamamen kapatılması ([disconnectSocket]) yalnızca çıkış yapılırken olur.
///
/// "Aynı altyapı, kamera aç/kapa" prensibiyle: sesli ve görüntülü arama
/// TAMAMEN aynı bu servisi kullanır, tek fark initLocalMedia()'ya video
/// isteyip istemediğimizi söylememiz - sesli aramada kamera hiç açılmaz.
class CallService {
  CallService._internal();
  static final CallService instance = CallService._internal();
  factory CallService() => instance;

  io.Socket? _socket;
  bool _connecting = false;
  // inviteToCall() içinde soket bağlı değilse elle yeniden bağlanabilmek
  // için son kullanılan auth token'ı saklıyoruz (bkz. inviteToCall()).
  String? _lastAuthToken;
  // reconnect() BİLEREK eski soketi kesip yenisini kurar - bu durumda
  // onDisconnect callback'inin kullanıcıya "Bağlantı kesildi" alarmı
  // göstermesini istemiyoruz (bkz. reconnect() ve onDisconnect).
  bool _suppressNextDisconnectNotice = false;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _chatChannel;
  bool _chatChannelOpen = false;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  // _handleOffer() içinde eşzamanlı/art arda 'offer' sinyalleri gelirse
  // (ör. ağ gecikmesi yüzünden yeniden gönderim) createAnswer()'ın peer
  // connection "have-remote-offer"da değilken çağrılmasını (WebRTC
  // hatası: "cannot create an answer in a state other than
  // have-remote-offer or have-local-pranswer") engellemek için bir
  // yeniden-girebilirlik (reentrancy) kilidi - bkz. _handleOffer().
  bool _handlingOffer = false;
  // _handleAnswer() için AYNI GEREKÇEYLE bir kilit - bkz. _handleAnswer().
  bool _handlingAnswer = false;

  String? _partnerId;
  bool _isInitiator = false;
  bool _peerConnectionStarted = false;

  // Şu an aktif bir görüşme oturumu var mı. getUserMedia() izin diyaloğu
  // kullanıcı yanıt verene kadar uzun sürebilir; bu sırada CallScreen
  // kapanıp endCallSession() çağrılırsa, izin sonunda gelince artık var
  // olmayan bir görüşme için kamera/mikrofonu açık bırakmamak (kaynak
  // sızıntısı, arkada yanan kamera ışığı) için bu bayrağı kontrol ediyoruz.
  // ÖNCEDEN bu bayrak kalıcıydı (_disposed) çünkü servis tek kullanımlıktı -
  // artık uygulama boyunca TEK bir CallService örneği tekrar tekrar
  // kullanıldığı için (bkz. sınıf üstündeki not) her görüşme oturumunda
  // sıfırlanıp yeniden kuruluyor.
  bool _sessionActive = false;
  bool _backgroundSuspended = false;
  bool _resumeMic = false;
  bool _resumeCamera = false;

  /// Şu an aktif (bağlanmış ya da kurulmakta olan) bir görüşme var mı - bkz.
  /// main.dart'taki yaşam döngüsü gözlemcisi: bir görüşme sürerken
  /// uygulamayı arka plana alıp geri dönmek sinyal soketini KOŞULSUZ
  /// tazelerse (reconnect()), görüşmenin kendisi de kesintiye uğrar - bu
  /// yüzden aktif bir görüşme varken reconnect() çağrılmıyor.
  bool get isInActiveCall => _sessionActive;

  // 'matched' event'i art arda (ör. bir görüşme daha başlamadan hemen yeni
  // bir davet kabul edilirse) birden fazla kez gelebilir - bkz.
  // webrtc_service.dart'taki _matchGeneration'ın aynısı. _sessionActive TEK
  // BAŞINA bunu ayırt edemiyor çünkü aynı oturum içinde true kalmaya devam
  // ediyor; bu sayaç her 'matched' event'inde artırılır ve
  // _createPeerConnection()/_createOffer() kendi await'lerinden SONRA hâlâ
  // güncel olduklarını buradan doğrular.
  int _callGeneration = 0;

  bool get isConnected => _socket?.connected ?? false;

  OnRemoteStream? onRemoteStream;
  OnLocalStream? onLocalStream;
  OnStatusChange? onStatusChange;
  void Function()? onPartnerLeft;
  void Function(String message)? onChatMessage;

  // Arama daveti akışı - call_ui_controller.dart tarafından oturum
  // açıldığında bir kez bağlanır (bkz. orada), tıpkı bu servisin sinyal
  // soketinin bir kez kurulması gibi.
  void Function(String fromSocketId, String fromDisplayName, String callType,
      bool isRematch)? onCallInviteReceived;
  void Function()? onCallInviteSent;
  void Function(String message)? onCallInviteError;
  void Function()? onCallInviteDeclined;
  void Function()? onCallInviteCancelled;

  /// Davet kabul edilip 'matched' geldiğinde tetiklenir - henüz peer
  /// connection kurulmamış olabilir (yerel medya hazır değilse), bkz.
  /// _tryBeginPeerConnection().
  void Function(String callType)? onCallStarted;

  String? _pendingIncomingFromSocketId;
  DateTime? _pendingIncomingExpiresAt;

  bool isIncomingInvitePending(String fromSocketId) {
    final expiresAt = _pendingIncomingExpiresAt;
    return _pendingIncomingFromSocketId == fromSocketId &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt);
  }

  void _clearPendingIncomingInvite() {
    _pendingIncomingFromSocketId = null;
    _pendingIncomingExpiresAt = null;
  }

  // Varsayılan (yalnızca STUN) liste - webrtc_service.dart'taki
  // WebRTCService ile aynı mantık, bkz. oradaki açıklama. connectIfNeeded()
  // çağrıldığında _refreshIceServers() ile güncellenmeye çalışılır.
  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  Future<void>? _iceServersFuture;

  /// bkz. webrtc_service.dart'taki WebRTCService._refreshIceServers() -
  /// birebir aynı davranış, TURN yapılandırılmamışsa ya da istek
  /// başarısız olursa sessizce STUN'a düşer.
  Future<void> _refreshIceServers() async {
    final authToken = _lastAuthToken;
    if (authToken == null || authToken.isEmpty) return;
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

  /// Uygulama boyunca kalıcı sinyal bağlantısını kurar ve arama daveti
  /// alışverişi için gerekli event'leri dinlemeye başlar - zaten bağlıysa
  /// ya da bağlanma sürecindeyse hiçbir şey yapmaz (bkz. sınıf üstündeki
  /// not). WebRTCService.connectAndFindMatch()'ten farklı olarak burada
  /// ASLA otomatik 'find-match' göndermiyoruz - bu servis yalnızca belirli
  /// bir arkadaşı arama/aranma içindir.
  void connectIfNeeded(String authToken) {
    _lastAuthToken = authToken;
    if (_socket != null && (_socket!.connected || _connecting)) return;
    if (_socket != null) {
      _connecting = true;
      AppConnectionController().updateCall(
        SocketConnectionPhase.connecting,
        message: 'Arama sunucusuna bağlanılıyor…',
      );
      SharedSocketTransport().connect(authToken);
      return;
    }
    // Önceki bir bağlanma denemesi başarısız olup kalıcı olarak koptuysa
    // (ne bağlı ne de bağlanma sürecinde) burada eski socket'i bırakmadan
    // yenisini kurmuş oluruz - önce onu düzgünce kapatıyoruz.
    _connecting = true;
    AppConnectionController().updateCall(
      SocketConnectionPhase.connecting,
      message: 'Arama sunucusuna bağlanılıyor…',
    );

    // Soket bağlantısıyla paralel olarak TURN bilgisini almaya başlıyoruz -
    // bkz. webrtc_service.dart'taki aynı mantık.
    _iceServersFuture = _refreshIceServers();
    _socket = SharedSocketTransport().socketFor(authToken);

    _socket!.onConnect((_) {
      _connecting = false;
      AppConnectionController().updateCall(
        SocketConnectionPhase.connected,
      );
      final partnerId = _partnerId;
      if (_sessionActive && partnerId != null) {
        onStatusChange?.call('Görüşme bağlantısı geri yükleniyor…');
        _socket!.emit('match-resume', {'partnerId': partnerId});
      } else {
        onStatusChange?.call('Bağlandı.');
      }
    });
    _socket!.onConnectError((err) {
      _connecting = false;
      final failure = classifyConnectionError(err);
      if (failure.kind == ConnectionFailureKind.sessionExpired) {
        unawaited(SessionExpirationCoordinator().handleExpiredSession());
      }
      AppConnectionController().updateCall(
        SocketConnectionPhase.error,
        message: failure.message,
        failureKind: failure.kind,
        retryable: failure.retryable,
      );
      onStatusChange?.call(failure.message);
    });
    _socket!.onDisconnect((reason) {
      // ignore: avoid_print
      print('CallService bağlantı koptu, sebep: $reason');
      AppConnectionController().updateCall(
        _suppressNextDisconnectNotice ||
                SharedSocketTransport().isPlannedReconnect
            ? SocketConnectionPhase.reconnecting
            : SocketConnectionPhase.disconnected,
        message: _suppressNextDisconnectNotice ||
                SharedSocketTransport().isPlannedReconnect
            ? 'Arama bağlantısı yenileniyor…'
            : 'Arama bağlantısı kesildi.',
      );
      if (_suppressNextDisconnectNotice ||
          SharedSocketTransport().isPlannedReconnect) {
        _suppressNextDisconnectNotice = false;
        return;
      }
      // bkz. messaging_service.dart'taki aynı mantık - mobil işletim
      // sistemleri arka plandaki bir soketi kendi bilgisi dışında
      // koparabiliyor, uygulama öne döndüğünde main.dart'taki yaşam döngüsü
      // gözlemcisi zaten (gerekiyorsa) bir reconnect() tetikliyor.
      onStatusChange
          ?.call('Bağlantı kesildi ($reason), yeniden bağlanılıyor...');
    });

    _socket!.on('matched', (data) {
      final myGeneration = ++_callGeneration;
      try {
        // Önceki bir görüşmeden kalma bir peer connection varsa önce onu
        // temizliyoruz - webrtc_service.dart'taki aynı düzeltmeyle aynı
        // gerekçe (bkz. orada), art arda hızlı 'matched' event'leri
        // gelirse eski bağlantının sinyalleri yeniye karışmasın diye.
        _cleanupPeerConnection();
        _peerConnectionStarted = false;

        final map = socketEventMap(data);
        _clearPendingIncomingInvite();
        _sessionActive = true;
        ActiveMediaSessionCoordinator().register(
          this,
          endCallSession,
          suspend: suspendMediaForBackground,
          resume: resumeMediaAfterBackground,
        );
        _partnerId = map['partnerId'] as String?;
        _isInitiator = map['isInitiator'] as bool? ?? false;
        final callType = map['callType'] as String? ?? 'video';
        onCallStarted?.call(callType);
        _tryBeginPeerConnection(expectedGeneration: myGeneration);
      } catch (e, st) {
        // ignore: avoid_print
        print('HATA (matched): $e\n$st');
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
      }
    });

    _socket!.on('partner-left', (_) {
      onPartnerLeft?.call();
      _cleanupPeerConnection();
    });

    _socket!.on('call-invite-received', (data) {
      try {
        final map = socketEventMap(data);
        // ignore: avoid_print
        print(
            'CallService: call-invite-received alındı -> $map (onCallInviteReceived ${onCallInviteReceived == null ? "BAĞLI DEĞİL" : "bağlı"})');
        final fromSocketId = map['fromSocketId'] as String;
        _pendingIncomingFromSocketId = fromSocketId;
        _pendingIncomingExpiresAt =
            DateTime.now().add(const Duration(seconds: 45));
        onCallInviteReceived?.call(
          fromSocketId,
          map['fromDisplayName'] as String? ?? 'Biri',
          map['callType'] as String? ?? 'video',
          map['isRematch'] as bool? ?? false,
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (call-invite-received): $e');
      }
    });

    _socket!.on('call-invite-sent', (_) => onCallInviteSent?.call());
    _socket!.on('call-invite-declined', (_) {
      _clearPendingIncomingInvite();
      onCallInviteDeclined?.call();
    });
    _socket!.on('call-invite-cancelled', (_) {
      _clearPendingIncomingInvite();
      onCallInviteCancelled?.call();
    });

    _socket!.on('call-invite-error', (data) {
      try {
        final map = socketEventMap(data);
        _clearPendingIncomingInvite();
        onCallInviteError
            ?.call(map['message'] as String? ?? 'Arama başlatılamadı.');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (call-invite-error): $e');
      }
    });

    SharedSocketTransport().connect(authToken);
  }

  /// Mevcut bağlantı gerçekten çalışıyor mu bilinmiyorsa (ör. uygulama arka
  /// plandan öne döndüğünde, bkz. main.dart'taki yaşam döngüsü gözlemcisi)
  /// koşulsuz olarak tazeler - bkz. messaging_service.dart'taki aynı
  /// metotun açıklaması.
  void reconnect(String authToken) {
    _suppressNextDisconnectNotice = true;
    AppConnectionController().updateCall(
      SocketConnectionPhase.reconnecting,
      message: 'Arama bağlantısı yenileniyor…',
    );
    _connecting = true;
    final reconnectStarted = SharedSocketTransport().reconnect(authToken);
    if (!reconnectStarted) {
      _suppressNextDisconnectNotice = false;
      _connecting = !(_socket?.connected ?? false);
    }
  }

  void inviteToCall({required String friendId, required String callType}) {
    // ÖNCEDEN burada soket null ise ya da bağlı değilse `_socket?.emit(...)`
    // SESSİZCE hiçbir şey yapmıyordu - kullanıcı "Aranıyor..." diyaloğunu
    // görmeye devam ediyor (dialog, emit'in gerçekten gidip gitmediğine
    // bakmadan açılıyor - bkz. call_ui_controller.dart startCall()), ama
    // sunucuya HİÇBİR ŞEY ulaşmıyordu. Bu, "aranıyor yazıyor ama karşı
    // tarafa hiçbir şey gitmiyor" şikayetinin asıl nedeni olabilir - ör.
    // sunucu bir deploy sırasında yeniden başladığında (Render'ın her
    // deploy'da yaptığı gibi) eski soket bağlantısı kopuyor; istemci
    // normalde otomatik yeniden bağlanır ama tam o anda arama denenirse
    // soket henüz "connected" olmayabilir. Artık bu durumu tespit edip
    // kullanıcıya görünür bir hata veriyoruz VE hemen bir yeniden bağlanma
    // deniyoruz.
    final connected = _socket?.connected ?? false;
    // ignore: avoid_print
    print('CallService: inviteToCall -> toId=$friendId callType=$callType '
        '(socket=${_socket == null ? "YOK" : "var"}, connected=$connected, connecting=$_connecting)');
    if (_socket == null || (!connected && !_connecting)) {
      // ignore: avoid_print
      print(
          'CallService: inviteToCall SESSİZCE BAŞARISIZ OLACAKTI - soket bağlı değil, davet gönderilmedi. Yeniden bağlanılıyor.');
      onCallInviteError?.call('Sunucu bağlantısı kopmuş, tekrar dene.');
      final token = _lastAuthToken;
      if (token != null) reconnect(token);
      return;
    }
    _socket?.emit('call-invite', {'toId': friendId, 'callType': callType});
  }

  /// "Tekrar eşleş" (GECE_GELISTIRME madde 2) - inviteToCall()'ın SADELEŞMİŞ
  /// hâli: hedef sunucu tarafında BELİRLENİYOR (son rastgele eşleştiğimiz
  /// hesaplı kişi, bkz. server.js lastPartnerByUser) - burada bir friendId
  /// GEÇMİYORUZ. Kabul/red aynı call-invite-received/response akışından
  /// geçiyor (bkz. CallUiController.requestRematch() - isRematch bayrağıyla
  /// farklı bir metin gösteriyor, akışın kendisi BİREBİR aynı).
  void requestRematch() {
    final connected = _socket?.connected ?? false;
    if (_socket == null || (!connected && !_connecting)) {
      onCallInviteError?.call('Sunucu bağlantısı kopmuş, tekrar dene.');
      final token = _lastAuthToken;
      if (token != null) reconnect(token);
      return;
    }
    _socket?.emit('rematch-invite');
  }

  void respondToCallInvite(bool accepted) {
    _clearPendingIncomingInvite();
    _socket?.emit('call-invite-response', {'accepted': accepted});
  }

  void cancelOutgoingCall() {
    _socket?.emit('call-invite-cancel');
  }

  /// Yerel kamera/mikrofon akışını açar. [video] false ise (sesli arama)
  /// kameraya HİÇ erişilmez - yalnızca mikrofon istenir.
  Future<void> initLocalMedia(
      {required bool video, required OnLocalStream onLocal}) async {
    onLocalStream = onLocal;
    final mediaConstraints = {
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
            }
          : false,
    };
    final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (!_sessionActive) {
      // Görüşme bu izin bekleme sırasında sonlandı (ör. kullanıcı
      // "aranıyor..." diyaloğunu iptal etti ya da geri gitti) - akışı hemen
      // durdurup bırakıyoruz, peer connection kurmuyoruz.
      stream.getTracks().forEach((track) => track.stop());
      stream.dispose();
      return;
    }
    _localStream = stream;
    onLocal(stream);
    // Burada belirli bir 'matched' event'ine bağlı olmadığımız için (bu
    // metot medya izni akışından tetikleniyor) sabit bir nesil geçirmiyoruz
    // - o an geçerli olan HANGİ eşleşme varsa onunla devam edilir; asıl
    // güvence _tryBeginPeerConnection()/_createPeerConnection() içindeki
    // _sessionActive kontrolleri.
    _tryBeginPeerConnection(expectedGeneration: _callGeneration);
  }

  /// Peer connection'ı yalnızca hem eşleşme bilgisi (partnerId/isInitiator)
  /// hem de yerel medya hazır olduğunda kurar. Bu iki koşul iki farklı
  /// sırada gerçekleşebilir (ör. arayan tarafta 'matched' önce gelir, medya
  /// izin diyaloğu sonra tamamlanır; ya da tersi) - hangisi son tamamlanırsa
  /// o tetikler. [expectedGeneration], art arda hızlı 'matched' event'leri
  /// gelirse eski bir çağrının yeni bir görüşmenin üzerine yazmasını
  /// engeller (bkz. sınıf üstündeki _callGeneration notu).
  void _tryBeginPeerConnection({int? expectedGeneration}) {
    if (!_sessionActive) return;
    if (_peerConnectionStarted) return;
    if (_partnerId == null || _localStream == null) return;
    _peerConnectionStarted = true;
    _beginPeerConnection(expectedGeneration: expectedGeneration);
  }

  Future<void> _beginPeerConnection({int? expectedGeneration}) async {
    await _createPeerConnection(expectedGeneration: expectedGeneration);
    // Görüşme, yukarıdaki await sırasında sonlandırılmış OLABİLİR (bkz.
    // _createPeerConnection() içindeki _sessionActive kontrolü) YA DA daha
    // yeni bir 'matched' event'i gelip bizi geçersiz kılmış olabilir - bu
    // durumda _peerConnection hiç atanmamış/başka bir görüşmeye ait olur,
    // teklif oluşturmaya çalışmıyoruz.
    if (expectedGeneration != null && expectedGeneration != _callGeneration) {
      return;
    }
    if (_isInitiator && _peerConnection != null) {
      await _createChatChannel(_peerConnection!);
      if (expectedGeneration != null && expectedGeneration != _callGeneration) {
        return;
      }
      await _createOffer(expectedGeneration: expectedGeneration);
    }
  }

  Future<void> _createPeerConnection({int? expectedGeneration}) async {
    if (_iceServersFuture != null) {
      await _iceServersFuture;
    }
    if (!_sessionActive) return;
    if (expectedGeneration != null && expectedGeneration != _callGeneration) {
      return;
    }

    final pc = await createPeerConnection(_iceServers);
    if (!_sessionActive ||
        (expectedGeneration != null && expectedGeneration != _callGeneration)) {
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

    // Mesajlar, çağrı için zaten kurulmuş olan WebRTC bağlantısının veri
    // kanalından gider. Böylece arama içi yazışma için ayrı sunucu, veritabanı
    // ya da kalıcı sohbet altyapısı gerekmez.
    _peerConnection!.onDataChannel = _configureChatChannel;

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

  Future<void> _createChatChannel(RTCPeerConnection peerConnection) async {
    try {
      final channel = await peerConnection.createDataChannel(
        'call-chat',
        RTCDataChannelInit(),
      );
      _configureChatChannel(channel);
    } catch (e) {
      // Mesajlaşma kurulamazsa görüntülü/sesli görüşmeyi engellemeyiz.
      // ignore: avoid_print
      print('Arama içi mesaj kanalı açılamadı: $e');
    }
  }

  void _configureChatChannel(RTCDataChannel channel) {
    _chatChannel = channel;
    _chatChannelOpen = channel.state == RTCDataChannelState.RTCDataChannelOpen;

    channel.onDataChannelState = (state) {
      if (!identical(_chatChannel, channel)) return;
      _chatChannelOpen = state == RTCDataChannelState.RTCDataChannelOpen;
    };
    channel.onMessage = (message) {
      if (message.isBinary || message.text.trim().isEmpty) return;
      onChatMessage?.call(message.text);
    };
  }

  /// Sadece aktif görüşmedeki iki cihaz arasında iletilen geçici mesajı yollar.
  /// Arama bağlantısı henüz hazır değilse [false] döner; arama akışı etkilenmez.
  Future<bool> sendChatMessage(String text) async {
    final message = text.trim();
    final channel = _chatChannel;
    if (message.isEmpty || channel == null || !_chatChannelOpen) return false;

    try {
      await channel.send(RTCDataChannelMessage(message));
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('Arama içi mesaj gönderilemedi: $e');
      return false;
    }
  }

  Future<void> _createOffer({int? expectedGeneration}) async {
    final pc = _peerConnection;
    if (pc == null) return;
    final targetId = _partnerId;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    // bkz. webrtc_service.dart'taki aynı düzeltme - yukarıdaki await'ler
    // sırasında bu görüşme daha yeni bir 'matched' event'i tarafından
    // geçersiz kılınmış olabilir, bu durumda artık geçersiz olan bağlantı
    // için sinyal göndermiyoruz.
    if (expectedGeneration != null && expectedGeneration != _callGeneration) {
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
    // bkz. sınıf üstündeki _handlingOffer notu - art arda/örtüşen 'offer'
    // sinyalleri aynı anda işlenmeye çalışılırsa createAnswer() peer
    // connection'ın beklenmedik bir durumunda çağrılıp WebRTC hatası
    // fırlatabiliyordu. Zaten bir offer işleniyorsa yenisini sessizce yok
    // sayıyoruz.
    if (_handlingOffer) return;
    _handlingOffer = true;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(payload['sdp'] as String, 'offer'),
      );
      // setRemoteDescription sırasında (await) peer connection başka bir
      // event tarafından kapatılmış/durumu değişmiş olabilir -
      // createAnswer() yalnızca have-remote-offer ya da have-local-pranswer
      // durumundayken geçerlidir (bkz. WEBRTC_CREATE_ANSWER_ERROR).
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
    // gelirse burada sessizce yok sayıyoruz - aksi halde WebRTC "Called in
    // wrong state: stable" hatası fırlatıp görüşmeyi donuk bırakıyordu (bkz.
    // webrtc_service.dart'taki aynı düzeltme).
    if (pc == null ||
        pc.signalingState !=
            RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      return;
    }
    // bkz. webrtc_service.dart'taki aynı düzeltme - yukarıdaki kontrol tek
    // başına yeterli değil, iki 'answer' sinyali neredeyse aynı anda
    // işlenmeye başlarsa ikisi de kontrolü geçip native tarafta yarış
    // durumuna (race condition) girebiliyordu. Kilit, aynı anda yalnızca
    // TEK bir setRemoteDescription çağrısının çalışmasını garanti ediyor.
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
    if (!_backgroundSuspended || !_sessionActive) return;
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

  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks == null || videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
  }

  void _cleanupPeerConnection() {
    final chatChannel = _chatChannel;
    _chatChannel = null;
    _chatChannelOpen = false;
    if (chatChannel != null) {
      chatChannel.onDataChannelState = null;
      chatChannel.onMessage = null;
      unawaited(chatChannel.close());
    }
    _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
    // bkz. webrtc_service.dart'taki aynı düzeltme - yeni bir görüşme
    // başlarken eski bağlantıya ait bir offer/answer işleme kilidi kalmasın.
    _handlingOffer = false;
    _handlingAnswer = false;
  }

  /// Bir görüşme bittiğinde (bkz. call_screen.dart dispose()) çağrılır -
  /// YALNIZCA o görüşmenin ses/görüntü bağlantısını ve yerel medyasını
  /// kapatır, sinyal SOKETİNE dokunmaz (artık uygulama boyunca kalıcı, bkz.
  /// sınıf üstündeki not) - böylece gelecekteki arama davetlerini dinlemeye
  /// devam eder. Sonraki bir görüşme için tüm oturuma özel durumu sıfırlar.
  ///
  /// CallScreen'in _setup()'ta bu servise taktığı onRemoteStream/
  /// onLocalStream/onStatusChange/onPartnerLeft callback'lerini de burada
  /// bırakıyoruz - servis artık kalıcı bir singleton olduğu için bunları
  /// bırakmazsak, kapanmış (disposed) bir CallScreen State'i bir sonraki
  /// görüşmeye kadar bellekte tutmuş oluruz (bkz. onCallInviteReceived/
  /// onCallStarted gibi arama-daveti callback'leri call_ui_controller.dart
  /// tarafından bağlanıyor, BUNLARA dokunmuyoruz - onlar görüşmeler arası
  /// kalıcı olmalı).
  void endCallSession() {
    _backgroundSuspended = false;
    ActiveMediaSessionCoordinator().unregister(this);
    // ÖNEMLİ DÜZELTME: bu servisin sinyal soketi kalıcı olduğu için (bkz.
    // sınıf üstündeki not) görüşme bitince socket HİÇ kapanmıyordu - bu
    // yüzden sunucu tarafında "bu ikisi hâlâ görüşmede" kaydı (partners
    // Map'i) hiç temizlenmiyordu ve bir sonraki TÜM arama denemeleri
    // yanlışlıkla "meşgul" diye reddediliyordu (canlı testte gözlemlenen
    // bug). Artık görüşme bittiğinde sunucuya açıkça haber veriyoruz -
    // bkz. server.js'teki 'call-end' handler'ı.
    _socket?.emit('call-end');
    _sessionActive = false;
    _cleanupPeerConnection();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;
    _partnerId = null;
    _isInitiator = false;
    _peerConnectionStarted = false;
    onRemoteStream = null;
    onLocalStream = null;
    onStatusChange = null;
    onPartnerLeft = null;
    onChatMessage = null;
  }

  /// Yalnızca çıkış yapılırken (bkz. profile_screen.dart _logout()) çağrılır
  /// - kalıcı sinyal bağlantısını tamamen kapatır.
  void disconnectSocket() {
    endCallSession();
    SharedSocketTransport().disconnect();
    _socket = null;
    _connecting = false;
    AppConnectionController().updateCall(
      SocketConnectionPhase.disconnected,
    );
  }
}
