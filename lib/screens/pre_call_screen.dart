import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import 'video_chat_screen.dart';

/// Rastgele eşleşme aramaya başlamadan ÖNCE gösterilen önizleme + rıza
/// ekranı. Kullanıcı kamerasının/mikrofonunun nasıl göründüğünü kontrol
/// edebilir, açma/kapama yapabilir ve (ilk seferinde) Topluluk Kurallarını
/// onaylar. Burada başlatılan kamera/mikrofon akışı VideoChatScreen'e
/// (WebRTCService örneği üzerinden) devredilir - izin isteği ve
/// getUserMedia() bu yüzden İKİ KEZ değil, yalnızca burada bir kez yapılır.
class PreCallScreen extends StatefulWidget {
  const PreCallScreen({super.key});

  @override
  State<PreCallScreen> createState() => _PreCallScreenState();
}

class _PreCallScreenState extends State<PreCallScreen> {
  static const _rulesAcceptedPrefKey = 'community_rules_accepted';

  final WebRTCService _webrtc = WebRTCService();
  final RTCVideoRenderer _previewRenderer = RTCVideoRenderer();

  bool _micOn = true;
  bool _camOn = true;
  // Kullanıcı "Sesli-yalnız mod" anahtarını açtıysa true - bu durumda kamera
  // HİÇ kullanılmaz (bkz. _toggleVoiceOnly()). VideoChatScreen'e devredilen
  // WebRTCService, bu tercihi eşleşme aranırken otomatik olarak karşı tarafa
  // bildirir (bkz. webrtc_service.dart connectAndFindMatch() notu).
  bool _voiceOnlySwitch = false;
  bool _loading = true;
  bool _permissionError = false;
  bool _permissionPermanentlyDenied = false;
  bool _rulesAcceptedBefore = false;
  bool _rulesCheckboxChecked = false;
  bool _starting = false;
  // PreCallScreen'den ayrılırken (ör. geri tuşu) _webrtc/kamera akışının
  // ikinci kez dispose edilmesini önlemek için - VideoChatScreen'e
  // devredildiyse burada artık bize ait değildir.
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _previewRenderer.initialize();

    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() =>
          _rulesAcceptedBefore = prefs.getBool(_rulesAcceptedPrefKey) ?? false);
    }

    final granted = await _ensurePermissions();
    if (!granted) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      await _webrtc.initLocalMedia(
        onLocal: (stream) {
          if (!mounted || _handedOff) return;
          _previewRenderer.srcObject = stream;
          setState(() {});
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _permissionError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Kullanıcı önizlemedeki "Sesli-yalnız mod" anahtarını değiştirdiğinde
  /// çağrılır. WebRTCService.initLocalMedia() yeni akışı BAŞARIYLA aldıktan
  /// sonra eskisini kapattığı için (bkz. oradaki not) burada güvenle tekrar
  /// çağrılabilir - anahtarı kapatıp kamerayı geri isterken bir sorun
  /// çıkarsa (ör. izin o sırada geri alınmışsa) önceki çalışan (sesli)
  /// akış kaybolmaz, yalnızca anahtar eski durumuna döner.
  Future<void> _toggleVoiceOnly(bool value) async {
    setState(() {
      _voiceOnlySwitch = value;
      _loading = true;
    });
    try {
      await _webrtc.initLocalMedia(
        audioOnly: value,
        onLocal: (stream) {
          if (!mounted || _handedOff) return;
          _previewRenderer.srcObject = stream;
          setState(() {});
        },
      );
      if (mounted) {
        setState(() {
          _camOn = _webrtc.isCamEnabled;
          _micOn = _webrtc.isMicEnabled;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _voiceOnlySwitch = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value
                ? 'Sesli moda geçilemedi.'
                : 'Kamera açılamadı, sesli modda devam ediliyor.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
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
      });
    }
    return false;
  }

  Future<void> _retry() async {
    if (_permissionPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    setState(() => _loading = true);
    final granted = await _ensurePermissions();
    if (!granted) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      await _webrtc.initLocalMedia(
        onLocal: (stream) {
          if (!mounted || _handedOff) return;
          _previewRenderer.srcObject = stream;
          setState(() {});
        },
      );
    } catch (_) {
      if (mounted) setState(() => _permissionError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canStart {
    if (_permissionError || _webrtc.localStream == null) return false;
    return _rulesAcceptedBefore || _rulesCheckboxChecked;
  }

  Future<void> _start() async {
    if (!_canStart || _starting) return;
    setState(() => _starting = true);

    if (!_rulesAcceptedBefore) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rulesAcceptedPrefKey, true);
    }

    if (!mounted) return;
    _handedOff = true; // artık kamera akışının sahibi VideoChatScreen
    Navigator.of(context).pushReplacement(
      AppPageRoute(builder: (_) => VideoChatScreen(preloadedWebrtc: _webrtc)),
    );
  }

  @override
  void dispose() {
    _previewRenderer.dispose();
    // Kullanıcı Başla'ya basmadan ekrandan ayrıldıysa (geri tuşu vb.)
    // kamera/mikrofonu açık bırakmamak için burada temizliyoruz. Devredildiyse
    // (_handedOff) VideoChatScreen kendi dispose()'unda bunu zaten yapacak.
    if (!_handedOff) {
      _webrtc.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Hazır mısın?'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Expanded(child: _buildPreview()),
                      const SizedBox(height: 14),
                      if (!_permissionError) _buildVoiceOnlyToggle(),
                      const SizedBox(height: 14),
                      if (!_rulesAcceptedBefore) _buildRulesChecklist(),
                      const SizedBox(height: 16),
                      _buildStartButton(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // Dairesel ("porthole") önizleme - Canva mockup'ındaki gibi, dikdörtgen
  // tam-ekran önizleme yerine. Grup görüşmesi hazırlık ekranından (kare/
  // yuvarlak-köşeli, gelecek 2x2 grid'i çağrıştıran) KASITLI farklı - 1:1
  // görüşme daha "samimi/yakın" hissettiren bir çerçeveyle ayrışıyor.
  Widget _buildPreview() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipOval(
          child: Container(
        color: AppColors.surface,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_permissionError)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded,
                        color: Colors.white38, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      _permissionPermanentlyDenied
                          ? 'Kamera/mikrofon izni reddedildi. Ayarlardan izin vermen gerekiyor.'
                          : 'Devam etmek için kamera ve mikrofon iznine ihtiyacımız var.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _retry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      child: Text(_permissionPermanentlyDenied
                          ? 'Ayarlara Git'
                          : 'Tekrar Dene'),
                    ),
                  ],
                ),
              )
            else if (!_webrtc.hasCamera)
              // Sesli-yalnız mod aktif - hiç kamera akışı yok, bunu
              // "kamera kapalı" ile karıştırmamak için ayrı bir gösterge.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic_rounded,
                      color: Colors.white38, size: 48),
                  const SizedBox(height: 10),
                  Text(
                    'Sesli-yalnız mod',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13),
                  ),
                ],
              )
            else if (_camOn)
              RTCVideoView(
                _previewRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              const Icon(Icons.videocam_off_rounded,
                  color: Colors.white38, size: 48),

            // Mikrofon/kamera açma-kapama düğmeleri. Kamera hiç yoksa
            // (sesli-yalnız mod) kamera düğmesi hiç gösterilmez - toggle
            // edilecek bir track olmadığı için yanıltıcı olurdu.
            if (!_permissionError)
              Positioned(
                bottom: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _previewToggle(
                      icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      active: _micOn,
                      onTap: () {
                        setState(() => _micOn = !_micOn);
                        _webrtc.toggleMic(_micOn);
                      },
                    ),
                    if (_webrtc.hasCamera) ...[
                      const SizedBox(width: 14),
                      _previewToggle(
                        icon: _camOn
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        active: _camOn,
                        onTap: () {
                          setState(() => _camOn = !_camOn);
                          _webrtc.toggleCamera(_camOn);
                        },
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
          ),
        ),
      ),
    );
  }

  Widget _previewToggle(
      {required IconData icon,
      required bool active,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.redAccent.withValues(alpha: 0.85),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  /// "Sesli-yalnız mod" anahtarı - açıksa kamera hiç kullanılmadan, yalnızca
  /// ses ile eşleşme aranır (bkz. _toggleVoiceOnly()). Rastgele eşleşen
  /// karşı tarafın ekranında bu tercih otomatik olarak görünür (bkz.
  /// webrtc_service.dart/server.js "partnerVoiceOnly" notları) - bu yüzden
  /// burada ekstra bir açıklama gerekmiyor, karşı taraf zaten uyarılıyor.
  Widget _buildVoiceOnlyToggle() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.mic_rounded,
              color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sesli-yalnız mod (kamera kullanılmaz)',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Switch(
            value: _voiceOnlySwitch,
            activeColor: AppColors.primary,
            onChanged: _loading ? null : _toggleVoiceOnly,
          ),
        ],
      ),
    );
  }

  Widget _buildRulesChecklist() {
    const rules = [
      'Karşındaki kişiye saygılı davran, taciz veya nefret söylemi yasak.',
      'Uygunsuz/müstehcen görüntü paylaşmak hesabının kısıtlanmasına yol açar.',
      '18 yaşından küçüklerin kullanımı yasaktır.',
      'Rahatsız edici bir kullanıcıyla karşılaşırsan "Bildir" özelliğini kullan.',
    ];
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Topluluk Kuralları',
            style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...rules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '•  $r',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: _rulesCheckboxChecked,
                activeColor: AppColors.primary,
                onChanged: (v) =>
                    setState(() => _rulesCheckboxChecked = v ?? false),
              ),
              const Expanded(
                child: Text(
                  'Kuralları okudum, kabul ediyorum.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return GradientButton(
      height: 54,
      onPressed: _canStart && !_starting ? _start : null,
      child: _starting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : const Text('Sohbete Başla', style: AppText.button),
    );
  }
}
