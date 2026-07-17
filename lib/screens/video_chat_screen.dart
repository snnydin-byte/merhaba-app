import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/icebreakers.dart';
import '../services/auth_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';

/// "Arkadaş Ekle" butonunun/durumunun o anki eşleşme için hangi aşamada
/// olduğunu tutar. Her yeni eşleşmede [none]'a sıfırlanır.
enum _FriendStatus { none, sending, sent, added }

/// Bu ekran artık GERÇEK kamera/mikrofon akışı kullanır ve bir sinyalleşme
/// sunucusu (bkz. signaling_server/) üzerinden karşı tarafla WebRTC
/// bağlantısı kurar. Sunucu çalışmıyorsa veya adres doğru ayarlanmadıysa
/// "eşleşme aranıyor" ekranında takılı kalır - bkz. KURULUM.md.
class VideoChatScreen extends StatefulWidget {
  /// PreCallScreen'de kamera/mikrofon izinleri zaten alınıp önizleme akışı
  /// başlatılmışsa, aynı WebRTCService örneği buraya geçirilir - böylece
  /// izin isteği ve getUserMedia() burada TEKRAR yapılmaz (kullanıcı zaten
  /// önizlemede kamerasını/mikrofonunu görüp onayladı). null geçilirse
  /// (ör. eski bir yerden doğrudan çağrılırsa) ekran kendi izin/kamera
  /// akışını baştan başlatır - eski davranışla geriye dönük uyumlu.
  final WebRTCService? preloadedWebrtc;

  const VideoChatScreen({super.key, this.preloadedWebrtc});

  @override
  State<VideoChatScreen> createState() => _VideoChatScreenState();
}

class _VideoChatScreenState extends State<VideoChatScreen> {
  late final WebRTCService _webrtc = widget.preloadedWebrtc ?? WebRTCService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _micOn = true;
  bool _camOn = true;
  bool _chatOpen = false;
  bool _connected = false;
  bool _permissionError = false;
  bool _permissionPermanentlyDenied = false;
  String _status = 'Kameraya erişiliyor...';

  // ÖNCEDEN eşleşme/sinyal sunucusu bir sebeple (ör. sunucu tarafında
  // beklenmedik bir durum, ağ sorunu, ya da canlı olarak gözlemlenen WebRTC
  // createAnswer hatası gibi bir çökme) yanıt vermeyi bırakırsa, kullanıcı
  // "BAĞLANIYOR" yazısında SONSUZA KADAR takılı kalıyordu - tek çıkış yolu
  // ekranı tamamen kapatıp yeniden açmaktı. Artık arama/bağlanma belirli bir
  // süreyi (bkz. _matchTimeoutDuration) aşarsa kullanıcıya "Tekrar Dene"
  // butonu gösteriyoruz.
  static const _matchTimeoutDuration = Duration(seconds: 20);
  Timer? _matchTimeoutTimer;
  bool _searchTimedOut = false;

  void _startMatchTimeout() {
    _matchTimeoutTimer?.cancel();
    _searchTimedOut = false;
    _matchTimeoutTimer = Timer(_matchTimeoutDuration, () {
      if (!mounted) return;
      if (_connected) return;
      setState(() {
        _searchTimedOut = true;
        _status = 'Bağlantı kurulamadı, tekrar dene.';
      });
    });
  }

  void _cancelMatchTimeout() {
    _matchTimeoutTimer?.cancel();
    _matchTimeoutTimer = null;
  }

  bool _partnerHasAccount = false;
  String? _partnerDisplayName;
  bool _partnerVerified = false;
  // _partnerDisplayName misafir eşleşmelerde null olur (misafirin adı
  // yok) - bu yüzden "eşleşmiş miyim" bilgisini AYRI bir bayrakla
  // tutuyoruz, yoksa misafirle eşleşince isim alanı yanlışlıkla boş
  // (eşleşme yokmuş gibi) görünür.
  bool _hasPartner = false;
  _FriendStatus _friendStatus = _FriendStatus.none;
  bool _reportSending = false;

  final TextEditingController _msgController = TextEditingController();
  final List<_ChatMsg> _messages = [];

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _webrtc.onStatusChange = (status) {
      if (!mounted) return;
      final justConnected = status == 'Bağlandı';
      if (justConnected) _cancelMatchTimeout();
      setState(() {
        _status = status;
        _connected = justConnected;
      });
    };

    _webrtc.onLocalStream = (stream) {
      // ÖNEMLİ: mounted kontrolü renderer'a dokunmadan ÖNCE yapılmalı.
      // Ekran kapandığında (dispose) _localRenderer de dispose ediliyor;
      // getUserMedia() gibi async bir işlem ekran kapandıktan SONRA
      // tamamlanıp bu callback'i tetiklerse, dispose edilmiş bir renderer'a
      // .srcObject atamak hataya yol açabilir. Bu, önceden "stabil
      // çalışmıyor" şikayetlerine yol açan hatalardan biriydi.
      if (!mounted) return;
      _localRenderer.srcObject = stream;
      setState(() {});
    };

    _webrtc.onRemoteStream = (stream) {
      if (!mounted) return;
      _remoteRenderer.srcObject = stream;
      setState(() {});
    };

    _webrtc.onChatMessage = (text) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatMsg(text, false)));
    };

    _webrtc.onPartnerLeft = () {
      if (!mounted) return;
      // Karşı taraf ayrıldığında ekranda öylece kalmak yerine otomatik
      // olarak yeni bir eşleşme aranmaya başlanır - tıpkı "sıradaki kişi"
      // butonuna basılmış gibi.
      setState(() {
        _connected = false;
        _messages.clear();
        _remoteRenderer.srcObject = null;
        _status = 'Karşı taraf ayrıldı, yeni biri aranıyor...';
        _partnerHasAccount = false;
        _partnerDisplayName = null;
        _partnerVerified = false;
        _hasPartner = false;
        _friendStatus = _FriendStatus.none;
      });
      _startMatchTimeout();
      _webrtc.skipToNext();
    };

    // Yeni bir eşleşme bulunduğunda karşı tarafın hesabı olup olmadığını,
    // (varsa) adını ve "onaylı hesap" rozetini öğreniyoruz - eşleşme
    // ekranında kiminle eşleştiğini göstermek ve "Arkadaş Ekle" butonunu
    // buna göre göstermek için. Her yeni eşleşmede önceki arkadaşlık isteği
    // durumunu da sıfırlıyoruz.
    _webrtc.onMatchInfo =
        (partnerHasAccount, partnerDisplayName, partnerVerified) {
      if (!mounted) return;
      setState(() {
        _partnerHasAccount = partnerHasAccount;
        _partnerDisplayName = partnerDisplayName;
        _partnerVerified = partnerVerified;
        _hasPartner = true;
        _friendStatus = _FriendStatus.none;
      });
    };

    // Şikayetimiz sunucuya kaydedildi.
    _webrtc.onReportSent = (reportId) {
      if (!mounted) return;
      setState(() => _reportSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şikayetin alındı, teşekkür ederiz.')),
      );
    };

    // Şikayet gönderilemedi (ör. eşleşme yok).
    _webrtc.onReportError = (message) {
      if (!mounted) return;
      setState(() => _reportSending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    };

    // Hesabımız birden fazla şikayet nedeniyle rastgele eşleştirmeden
    // kısıtlandı - kullanıcıyı bilgilendirip ana ekrana geri gönderiyoruz,
    // ekranda kalıp boşuna eşleşme aramasın.
    _webrtc.onAccountRestricted = (message) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Hesabın kısıtlandı',
              style: TextStyle(color: Colors.white)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    };

    // Karşı taraf bize arkadaşlık isteği gönderdi - kabul/red diyaloğu göster.
    _webrtc.onFriendRequestReceived = (fromDisplayName) {
      if (!mounted) return;
      _showFriendRequestDialog(fromDisplayName);
    };

    // Gönderdiğimiz ya da bize gelen bir isteğin sonucu belli oldu.
    _webrtc.onFriendRequestResult = (accepted, displayName) {
      if (!mounted) return;
      setState(() {
        _friendStatus = accepted ? _FriendStatus.added : _FriendStatus.none;
      });
      final name = displayName ?? 'Kullanıcı';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted ? '$name artık arkadaşın!' : '$name isteği reddetti.',
          ),
        ),
      );
    };

    // Arkadaşlık isteği gönderilemedi (giriş yapılmamış, misafir, vb.).
    _webrtc.onFriendRequestError = (message) {
      if (!mounted) return;
      setState(() => _friendStatus = _FriendStatus.none);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    };

    if (widget.preloadedWebrtc != null && _webrtc.localStream != null) {
      // PreCallScreen'de izinler zaten alındı ve kamera/mikrofon zaten
      // açık - burada tekrar istemiyoruz, doğrudan mevcut akışı önizleme
      // rendererına bağlayıp eşleşme aramaya geçiyoruz. Düğme durumlarını
      // (mic/cam açık-kapalı ikonu) da PreCallScreen'de bırakılan gerçek
      // track durumuyla eşitliyoruz.
      _localRenderer.srcObject = _webrtc.localStream;
      _micOn = _webrtc.isMicEnabled;
      _camOn = _webrtc.isCamEnabled;
      setState(() {});
      final matchPrefs = await WebRTCService.loadMatchPreferences();
      if (!mounted) return;
      _startMatchTimeout();
      _webrtc.connectAndFindMatch(
          authToken: AuthService().token, matchPreferences: matchPrefs);
      return;
    }

    final granted = await _ensurePermissions();
    if (!granted) return;

    try {
      await _webrtc.initLocalMedia(onLocal: (_) {});
      final matchPrefs = await WebRTCService.loadMatchPreferences();
      if (!mounted) return;
      _startMatchTimeout();
      _webrtc.connectAndFindMatch(
          authToken: AuthService().token, matchPreferences: matchPrefs);
    } catch (e) {
      setState(() {
        _status = 'Kamera/mikrofon açılamadı.';
        _permissionError = true;
      });
    }
  }

  void _showFriendRequestDialog(String fromDisplayName) {
    showDialog<void>(
      context: context,
      // Kullanıcı diyaloğu dışarı dokunarak ya da geri tuşuyla kapatırsa
      // sunucudaki bekleyen isteği YANITLAMADAN kapanır - istek gönderen
      // taraf sonsuza dek cevap bekler. Bu yüzden yalnızca butonlarla
      // kapatılabilsin istiyoruz (bkz. PopScope aşağıda - geri tuşu/
      // gesture'ı da engelliyor).
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Arkadaşlık isteği',
              style: TextStyle(color: Colors.white)),
          content: Text(
            '$fromDisplayName seni arkadaş olarak eklemek istiyor.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _webrtc.respondToFriendRequest(false);
              },
              child: const Text('Reddet'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _webrtc.respondToFriendRequest(true);
                setState(() => _friendStatus = _FriendStatus.added);
              },
              child: const Text('Kabul Et',
                  style: TextStyle(color: AppColors.secondary)),
            ),
          ],
        ),
      ),
    );
  }

  void _sendFriendRequest() {
    if (_friendStatus != _FriendStatus.none) return;
    _webrtc.sendFriendRequest();
    // Asıl sonuç (kabul/red/hata) socket üzerinden onFriendRequestResult ya
    // da onFriendRequestError ile gelecek - burada sadece butonun tekrar
    // basılmasını engellemek için "gönderildi" durumuna geçiyoruz.
    setState(() => _friendStatus = _FriendStatus.sent);
  }

  /// Şikayet nedeni seçim diyaloğu - sunucunun kabul ettiği sabit nedenler
  /// (bkz. signaling_server/reportStore.js VALID_REASONS) Türkçe etiketlerle
  /// gösterilir. Seçim yapılınca doğrudan gönderilir, ekstra not istemez
  /// (basitlik için) - gerekirse ileride bir not alanı eklenebilir.
  void _showReportDialog() {
    const reasons = [
      ('uygunsuz-goruntu', 'Uygunsuz görüntü/içerik'),
      ('taciz', 'Taciz veya kötüye kullanım'),
      ('kucuk-yasta', 'Reşit olmayan biri gibi görünüyor'),
      ('spam', 'Spam / reklam'),
      ('sahte-hesap', 'Sahte hesap'),
      ('diger', 'Diğer'),
    ];
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Kullanıcıyı bildir',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: reasons
              .map(
                (r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.$2,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(context);
                    _submitReport(r.$1);
                  },
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
  }

  void _submitReport(String reason) {
    setState(() => _reportSending = true);
    _webrtc.reportUser(reason);
  }

  /// Kamera/mikrofon izinlerini kontrol eder, gerekiyorsa kullanıcıdan ister.
  /// Önceden izin reddedildiğinde uygulama sonsuza kadar "eşleşme aranıyor"
  /// ekranında takılı kalıyordu; artık kullanıcıya ne olduğunu söylüyoruz ve
  /// kalıcı olarak reddedilmişse doğrudan uygulama ayarlarına yönlendiriyoruz.
  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final camGranted = statuses[Permission.camera]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

    if (camGranted && micGranted) {
      if (mounted) {
        setState(() {
          _permissionError = false;
          _permissionPermanentlyDenied = false;
        });
      }
      return true;
    }

    final permanentlyDenied =
        (statuses[Permission.camera]?.isPermanentlyDenied ?? false) ||
            (statuses[Permission.microphone]?.isPermanentlyDenied ?? false);

    if (mounted) {
      setState(() {
        _permissionError = true;
        _permissionPermanentlyDenied = permanentlyDenied;
        _status = permanentlyDenied
            ? 'Kamera/mikrofon izni reddedildi. Ayarlardan izin vermen gerekiyor.'
            : 'Kamera/mikrofon izni gerekli.';
      });
    }
    return false;
  }

  Future<void> _retry() async {
    if (_permissionPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    final granted = await _ensurePermissions();
    if (!granted) return;
    try {
      setState(() => _status = 'Kameraya erişiliyor...');
      await _webrtc.initLocalMedia(onLocal: (_) {});
      final matchPrefs = await WebRTCService.loadMatchPreferences();
      if (!mounted) return;
      _startMatchTimeout();
      _webrtc.connectAndFindMatch(
          authToken: AuthService().token, matchPreferences: matchPrefs);
    } catch (e) {
      setState(() {
        _status = 'Kamera/mikrofon açılamadı.';
        _permissionError = true;
      });
    }
  }

  /// "BAĞLANIYOR" durumunda süresi dolup "Tekrar Dene" butonu gösterildiğinde
  /// çağrılır. Kamera/mikrofon zaten açık olduğu için (yalnızca sinyal/eşleşme
  /// tarafı takılı kaldı) izinleri tekrar istemiyoruz - webrtc_service.dart'ın
  /// connectAndFindMatch()'i artık önceki soketi düzgünce kapatıp yenisini
  /// kurduğu için (bkz. oradaki düzeltme) aynı WebRTCService örneği üzerinde
  /// güvenle tekrar çağrılabilir.
  Future<void> _retryAfterTimeout() async {
    setState(() {
      _searchTimedOut = false;
      _connected = false;
      _status = 'Yeniden bağlanılıyor...';
    });
    final matchPrefs = await WebRTCService.loadMatchPreferences();
    if (!mounted) return;
    _startMatchTimeout();
    _webrtc.connectAndFindMatch(
        authToken: AuthService().token, matchPreferences: matchPrefs);
  }

  void _sendMessage() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMsg(text, true));
      _msgController.clear();
    });
    _webrtc.sendChatMessage(text);
  }

  /// Sohbeti nasıl başlatacağını bilemeyenler için birkaç rastgele "buz
  /// kırıcı" soru gösterir (bkz. lib/data/icebreakers.dart). Seçilen soru
  /// doğrudan gönderilmez - mesaj kutusuna yazılır, kullanıcı isterse
  /// düzenleyip öyle gönderir.
  void _showIcebreakerSheet() {
    final shuffled = List<String>.of(icebreakerPrompts)..shuffle(Random());
    final picks = shuffled.take(4).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Buz Kırıcı Sorular',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            ...picks.map(
              (p) => ListTile(
                leading: const Icon(Icons.chat_bubble_outline,
                    color: AppColors.primaryLight, size: 18),
                title: Text(p,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _msgController.text = p);
                  if (!_chatOpen) setState(() => _chatOpen = true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _nextPerson() {
    setState(() {
      _connected = false;
      _messages.clear();
      _remoteRenderer.srcObject = null;
      _status = 'Yeni eşleşme aranıyor...';
      _partnerHasAccount = false;
      _partnerDisplayName = null;
      _partnerVerified = false;
      _hasPartner = false;
      _friendStatus = _FriendStatus.none;
    });
    _startMatchTimeout();
    _webrtc.skipToNext();
  }

  void _endCall() {
    _webrtc.dispose();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  bool _switchingCamera = false;
  bool _showLocalAsMain = false;

  Future<void> _switchCamera() async {
    if (_switchingCamera) return;
    setState(() => _switchingCamera = true);
    try {
      await _webrtc.switchCamera();
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  @override
  void dispose() {
    _cancelMatchTimeout();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _msgController.dispose();
    _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ÜST BAR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _connected
                            ? const PulsingDot(color: Colors.redAccent, size: 8)
                            : const SizedBox(
                                width: 10,
                                height: 10,
                                child: Icon(Icons.circle,
                                    color: Colors.grey, size: 10),
                              ),
                        const SizedBox(width: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _connected ? 'CANLI' : 'BAĞLANIYOR',
                            key: ValueKey(_connected),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hasPartner)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _partnerDisplayName ?? 'Misafir',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.75),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (_partnerVerified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified_rounded,
                                        color: AppColors.secondary, size: 14),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        _buildFriendButton(),
                        IconButton(
                          onPressed: _hasPartner && !_reportSending
                              ? _showReportDialog
                              : null,
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                shape: BoxShape.circle),
                            child: _reportSending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.flag_outlined,
                                    color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ORTA ALAN: büyük ekran + küçük ekran (dokununca yer değiştirir)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // BÜYÜK EKRAN: _showLocalAsMain'e göre kendi görüntün ya da karşı tarafın görüntüsü
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(
                            () => _showLocalAsMain = !_showLocalAsMain),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: AppColors.surface,
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: _showLocalAsMain
                              ? (_camOn
                                  ? RTCVideoView(
                                      _localRenderer,
                                      mirror: true,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover,
                                    )
                                  : const Center(
                                      child: Icon(Icons.videocam_off_rounded,
                                          color: Colors.white38, size: 40),
                                    ))
                              : (_connected
                                  ? RTCVideoView(_remoteRenderer,
                                      objectFit: RTCVideoViewObjectFit
                                          .RTCVideoViewObjectFitCover)
                                  : Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          (_permissionError || _searchTimedOut)
                                              ? const Icon(
                                                  Icons.videocam_off_rounded,
                                                  color: Colors.white38,
                                                  size: 32)
                                              : const SizedBox(
                                                  width: 32,
                                                  height: 32,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2.5,
                                                          color: AppColors
                                                              .primary),
                                                ),
                                          const SizedBox(height: 16),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 24),
                                            child: Text(
                                              _status,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.7),
                                                  fontSize: 14),
                                            ),
                                          ),
                                          if (_permissionError) ...[
                                            const SizedBox(height: 16),
                                            OutlinedButton(
                                              onPressed: _retry,
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: const BorderSide(
                                                    color: Colors.white38),
                                              ),
                                              child: Text(
                                                _permissionPermanentlyDenied
                                                    ? 'Ayarlara Git'
                                                    : 'Tekrar Dene',
                                              ),
                                            ),
                                          ] else if (_searchTimedOut) ...[
                                            const SizedBox(height: 16),
                                            OutlinedButton(
                                              onPressed: _retryAfterTimeout,
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: const BorderSide(
                                                    color: Colors.white38),
                                              ),
                                              child: const Text('Tekrar Dene'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    )),
                        ),
                      ),
                    ),

                    // KÜÇÜK EKRAN (sağ üstte): büyükte gösterilmeyen taraf. Dokununca yer değiştirir,
                    // sadece sağ-alt köşedeki kamera-değiştir ikonuna dokununca kamera değişir.
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: () => setState(
                            () => _showLocalAsMain = !_showLocalAsMain),
                        child: Container(
                          width: 84,
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: AppColors.surfaceElevated,
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_showLocalAsMain)
                                (_connected
                                    ? RTCVideoView(_remoteRenderer,
                                        objectFit: RTCVideoViewObjectFit
                                            .RTCVideoViewObjectFitCover)
                                    : const Icon(Icons.person,
                                        color: Colors.white38, size: 28))
                              else if (_camOn)
                                RTCVideoView(
                                  _localRenderer,
                                  mirror: true,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                )
                              else
                                const Icon(Icons.videocam_off_rounded,
                                    color: Colors.white38, size: 24),

                              // Kamera değiştirme ikonu - sadece kendi görüntün küçük ekrandayken gösterilir
                              if (!_showLocalAsMain && _camOn)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: _switchCamera,
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.55),
                                        shape: BoxShape.circle,
                                      ),
                                      child: _switchingCamera
                                          ? const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white),
                                            )
                                          : const Icon(
                                              Icons.cameraswitch_rounded,
                                              color: Colors.white,
                                              size: 14),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // SOHBET PANELİ
            if (_chatOpen) _buildChatPanel(),

            // ALT KONTROL ÇUBUĞU
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlButton(
                    icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    active: _micOn,
                    onTap: () {
                      setState(() => _micOn = !_micOn);
                      _webrtc.toggleMic(_micOn);
                    },
                  ),
                  _controlButton(
                    icon: Icons.chat_bubble_rounded,
                    active: _chatOpen,
                    onTap: () => setState(() => _chatOpen = !_chatOpen),
                  ),
                  GestureDetector(
                    onTap: _nextPerson,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppGradients.liveAccent,
                      ),
                      child: const Icon(Icons.skip_next_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                  _controlButton(
                    icon: _camOn
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    active: _camOn,
                    onTap: () {
                      setState(() => _camOn = !_camOn);
                      _webrtc.toggleCamera(_camOn);
                    },
                  ),
                  _controlButton(
                    icon: Icons.call_end_rounded,
                    active: false,
                    isDanger: true,
                    onTap: _endCall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Üst bardaki "Arkadaş Ekle" butonu. Yalnızca giriş yapılmışsa VE karşı
  /// tarafın da bir hesabı varsa görünür - misafirler arkadaş
  /// ekleyemez/eklenemez, sunucu da bunu zaten reddeder ama butonu hiç
  /// göstermemek daha temiz bir kullanıcı deneyimi sağlıyor.
  Widget _buildFriendButton() {
    if (!AuthService().isLoggedIn || !_partnerHasAccount) {
      return const SizedBox.shrink();
    }

    switch (_friendStatus) {
      case _FriendStatus.none:
        return IconButton(
          onPressed: _sendFriendRequest,
          tooltip: 'Arkadaş Ekle',
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle),
            child: const Icon(Icons.person_add_alt_1_rounded,
                color: Colors.white, size: 18),
          ),
        );
      case _FriendStatus.sending:
      case _FriendStatus.sent:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle),
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        );
      case _FriendStatus.added:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.2),
              shape: BoxShape.circle),
          child: const Icon(Icons.how_to_reg_rounded,
              color: AppColors.secondary, size: 18),
        );
    }
  }

  Widget _buildChatPanel() {
    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sohbet',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _showIcebreakerSheet,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.lightbulb_outline,
                            color: Colors.white54, size: 18),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _chatOpen = false),
                      child: const Icon(Icons.close,
                          color: Colors.white54, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment:
                      msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: msg.isMe ? AppColors.primary : Colors.white12,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(msg.text,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Mesaj yaz...',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _sendMessage,
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primary,
                    child:
                        Icon(Icons.send_rounded, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDanger
              ? Colors.redAccent
              : (active
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ChatMsg {
  final String text;
  final bool isMe;
  _ChatMsg(this.text, this.isMe);
}
