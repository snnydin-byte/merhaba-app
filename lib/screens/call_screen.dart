import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/call_service.dart';
import '../theme/app_theme.dart';

/// Bir arkadaşla yapılan sesli ya da görüntülü arama ekranı.
///
/// "Aynı altyapı, kamera aç/kapa" prensibiyle: bu ekran hem sesli hem
/// görüntülü arama için kullanılır, tek fark [callType] - 'audio' ise
/// kameraya hiç erişilmez, ortada bir avatar gösterilir; 'video' ise
/// video_chat_screen.dart'takine benzer bir kamera görünümü kullanılır.
///
/// Bu ekran, arama daveti zaten KABUL EDİLMİŞ ve sunucudan 'matched'
/// geldikten SONRA açılır (bkz. call_ui_controller.dart'taki
/// onCallStarted callback'i) - yani [callService] üzerinde partnerId/
/// isInitiator bilgisi zaten mevcuttur, burada yalnızca yerel medyayı açıp
/// peer connection'ın kurulmasını bekliyoruz.
class CallScreen extends StatefulWidget {
  final CallService callService;
  final String peerDisplayName;
  final String callType; // 'audio' | 'video'

  const CallScreen({
    super.key,
    required this.callService,
    required this.peerDisplayName,
    required this.callType,
  });

  bool get isVideo => callType == 'video';

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _micOn = true;
  bool _camOn = true;
  bool _connected = false;
  bool _permissionError = false;
  bool _permissionPermanentlyDenied = false;
  bool _switchingCamera = false;
  String _status = 'Bağlanılıyor...';

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    if (widget.isVideo) {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
    }

    widget.callService.onStatusChange = (status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        _connected = status == 'Bağlandı';
      });
    };

    widget.callService.onLocalStream = (stream) {
      // ÖNEMLİ: mounted kontrolü renderer'a dokunmadan ÖNCE yapılmalı -
      // izin/medya alma işlemi ekran kapandıktan sonra tamamlanırsa, o
      // sırada dispose edilmiş bir renderer'a dokunmuş oluruz.
      if (!mounted) return;
      if (widget.isVideo) _localRenderer.srcObject = stream;
      setState(() {});
    };

    widget.callService.onRemoteStream = (stream) {
      if (!mounted) return;
      if (widget.isVideo) _remoteRenderer.srcObject = stream;
      setState(() {});
    };

    widget.callService.onPartnerLeft = () {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _status = '${widget.peerDisplayName} aramadan ayrıldı.';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    };

    final granted = await _ensurePermissions();
    if (!granted) return;

    try {
      await widget.callService
          .initLocalMedia(video: widget.isVideo, onLocal: (_) {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = widget.isVideo
              ? 'Kamera/mikrofon açılamadı.'
              : 'Mikrofon açılamadı.';
          _permissionError = true;
        });
      }
    }
  }

  Future<bool> _ensurePermissions() async {
    final permissions = widget.isVideo
        ? [Permission.camera, Permission.microphone]
        : [Permission.microphone];
    final statuses = await permissions.request();
    final allGranted = statuses.values.every((s) => s.isGranted);

    if (allGranted) {
      if (mounted) {
        setState(() {
          _permissionError = false;
          _permissionPermanentlyDenied = false;
        });
      }
      return true;
    }

    final permanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    if (mounted) {
      setState(() {
        _permissionError = true;
        _permissionPermanentlyDenied = permanentlyDenied;
        _status = permanentlyDenied
            ? 'İzin reddedildi. Ayarlardan izin vermen gerekiyor.'
            : (widget.isVideo
                ? 'Kamera/mikrofon izni gerekli.'
                : 'Mikrofon izni gerekli.');
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
      setState(() => _status = 'Bağlanılıyor...');
      await widget.callService
          .initLocalMedia(video: widget.isVideo, onLocal: (_) {});
    } catch (e) {
      setState(() {
        _status = widget.isVideo
            ? 'Kamera/mikrofon açılamadı.'
            : 'Mikrofon açılamadı.';
        _permissionError = true;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_switchingCamera) return;
    setState(() => _switchingCamera = true);
    try {
      await widget.callService.switchCamera();
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  void _endCall() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (widget.isVideo) {
      _localRenderer.dispose();
      _remoteRenderer.dispose();
    }
    // CallService artık uygulama boyunca kalıcı (bkz. call_service.dart) -
    // yalnızca BU görüşmenin ses/görüntü bağlantısını kapatıyoruz, sinyal
    // soketine dokunmuyoruz (böylece gelecekteki arama davetlerini
    // dinlemeye devam eder).
    widget.callService.endCallSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
                child: widget.isVideo ? _buildVideoArea() : _buildAudioArea()),
            _buildControlBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioArea() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.35),
                  AppColors.secondary.withValues(alpha: 0.2),
                ],
              ),
            ),
            child: Center(
              child: Text(
                widget.peerDisplayName.isNotEmpty
                    ? widget.peerDisplayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.peerDisplayName,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _buildStatusRow(),
          if (_permissionError) ...[
            const SizedBox(height: 20),
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
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: AppColors.surface,
              ),
              clipBehavior: Clip.hardEdge,
              child: _connected
                  ? RTCVideoView(_remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _permissionError
                              ? const Icon(Icons.videocam_off_rounded,
                                  color: Colors.white38, size: 32)
                              : SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.primary),
                                ),
                          const SizedBox(height: 16),
                          Text(
                            widget.peerDisplayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          _buildStatusRow(),
                          if (_permissionError) ...[
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
                        ],
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
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
                  if (_camOn)
                    RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    const Icon(Icons.videocam_off_rounded,
                        color: Colors.white38, size: 24),
                  if (_camOn)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _switchCamera,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: _switchingCamera
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.cameraswitch_rounded,
                                  color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _connected
            ? const PulsingDot(color: Colors.greenAccent, size: 8)
            : const Icon(Icons.circle, color: Colors.grey, size: 8),
        const SizedBox(width: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _status,
            key: ValueKey(_status),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildControlBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(
            icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: _micOn,
            onTap: () {
              setState(() => _micOn = !_micOn);
              widget.callService.toggleMic(_micOn);
            },
          ),
          if (widget.isVideo)
            _controlButton(
              icon:
                  _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              active: _camOn,
              onTap: () {
                setState(() => _camOn = !_camOn);
                widget.callService.toggleCamera(_camOn);
              },
            ),
          GestureDetector(
            onTap: _endCall,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.danger),
              child: const Icon(Icons.call_end_rounded,
                  color: Colors.white, size: 26),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.08),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
