import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import 'video_chat_screen.dart';
import '../utils/session_transient_ui.dart';

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
        showSessionSnackBar(
          context,
          SnackBar(
            content: Text(value
                ? 'Sesli moda geçilemedi.'
                : 'Kamera açılamadı, sesli modda devam ediliyor.'),
          ),
          priority: SessionFeedbackPriority.high,
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
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 700;
              final previewHeight =
                  (constraints.maxHeight * (isCompact ? 0.36 : 0.43))
                      .clamp(236.0, 390.0)
                      .toDouble();

              if (_loading) {
                return Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 18),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              children: [
                                _buildPreview(height: previewHeight),
                                const SizedBox(height: 14),
                                if (!_permissionError) _buildVoiceOnlyToggle(),
                                if (!_rulesAcceptedBefore) ...[
                                  const SizedBox(height: 14),
                                  _buildRulesChecklist(),
                                ],
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStartButton(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.76),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: IconButton(
            tooltip: 'Geri',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kameranı kontrol et', style: AppText.heading),
              const SizedBox(height: 2),
              Text(
                'Eşleşmeden önce görünümünü ayarla',
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview({required double height}) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.surfaceBorder),
              boxShadow: neonGlow(
                AppColors.primary,
                opacity: 0.16,
                blurRadius: 30,
                spreadRadius: 0,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
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
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    const Icon(Icons.videocam_off_rounded,
                        color: Colors.white38, size: 48),

                  if (!_permissionError && _webrtc.hasCamera)
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color:
                                AppColors.textPrimary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          _camOn ? 'Kamera açık' : 'Kamera kapalı',
                          style: AppText.caption.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  // Mikrofon/kamera açma-kapama düğmeleri. Kamera hiç yoksa
                  // (sesli-yalnız mod) kamera düğmesi hiç gösterilmez - toggle
                  // edilecek bir track olmadığı için yanıltıcı olurdu.
                  if (!_permissionError)
                    Positioned(
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.74),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color:
                                AppColors.textPrimary.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _previewToggle(
                              label:
                                  _micOn ? 'Mikrofonu kapat' : 'Mikrofonu aç',
                              icon: _micOn
                                  ? Icons.mic_rounded
                                  : Icons.mic_off_rounded,
                              active: _micOn,
                              onTap: () {
                                setState(() => _micOn = !_micOn);
                                _webrtc.toggleMic(_micOn);
                              },
                            ),
                            if (_webrtc.hasCamera) ...[
                              const SizedBox(width: 10),
                              _previewToggle(
                                label:
                                    _camOn ? 'Kamerayı kapat' : 'Kamerayı aç',
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
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewToggle(
      {required String label,
      required IconData icon,
      required bool active,
      required VoidCallback onTap}) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppColors.textPrimary.withValues(alpha: 0.16)
                    : AppColors.danger.withValues(alpha: 0.9),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
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
          Icon(Icons.mic_rounded, color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sesli-yalnız mod (kamera kullanılmaz)',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Switch(
            value: _voiceOnlySwitch,
            activeThumbColor: AppColors.primary,
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
      gradient: AppGradients.warmSignal,
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
