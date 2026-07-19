import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';
import 'group_call_screen.dart';

/// Küçük grup rastgele görüşmesi (mesh, 3-4 kişi) için kamera önizlemesi +
/// grup büyüklüğü seçimi + rıza ekranı - pre_call_screen.dart'ın 1:1 eşiti.
/// Kamera/mikrofon edinme WebRTCService.initLocalMedia() ile YAPILIR (kod
/// tekrarı yok) ama WebRTCService.connectAndFindMatch() ASLA çağrılmaz -
/// bu örnek yalnızca medya akışını taşımak (GroupCallScreen'e devretmek) ve
/// mic/kamera aç-kapa/switchCamera gibi hazır yardımcıları kullanmak için
/// var, gerçek grup sinyalleşmesi GroupCallService'te.
class GroupCallPreScreen extends StatefulWidget {
  const GroupCallPreScreen({super.key});

  @override
  State<GroupCallPreScreen> createState() => _GroupCallPreScreenState();
}

class _GroupCallPreScreenState extends State<GroupCallPreScreen> {
  static const _rulesAcceptedPrefKey = 'community_rules_accepted';

  final WebRTCService _webrtc = WebRTCService();
  final RTCVideoRenderer _previewRenderer = RTCVideoRenderer();

  int _groupSize = 4;
  bool _micOn = true;
  bool _camOn = true;
  bool _loading = true;
  bool _permissionError = false;
  bool _permissionPermanentlyDenied = false;
  bool _rulesAcceptedBefore = false;
  bool _rulesCheckboxChecked = false;
  bool _starting = false;
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
      if (mounted) setState(() => _permissionError = true);
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
      setState(() => _loading = false);
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
    _handedOff = true;
    Navigator.of(context).pushReplacement(
      AppPageRoute(
        builder: (_) => GroupCallScreen(
          groupSize: _groupSize,
          webrtcForMedia: _webrtc,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _previewRenderer.dispose();
    if (!_handedOff) _webrtc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Grup Görüşmesi'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Expanded(child: _buildPreview()),
                      const SizedBox(height: 14),
                      if (!_permissionError) _buildSizePicker(),
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

  Widget _buildPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
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
            else if (_camOn)
              RTCVideoView(
                _previewRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              const Icon(Icons.videocam_off_rounded,
                  color: Colors.white38, size: 48),
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
                ),
              ),
          ],
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

  Widget _buildSizePicker() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded,
              color: AppColors.primaryLight, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Kaç kişilik grup?',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          _sizeChip(3),
          const SizedBox(width: 8),
          _sizeChip(4),
        ],
      ),
    );
  }

  Widget _sizeChip(int size) {
    final selected = _groupSize == size;
    return GestureDetector(
      onTap: () => setState(() => _groupSize = size),
      child: Container(
        width: 40,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '$size',
          style: TextStyle(
            color: Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildRulesChecklist() {
    const rules = [
      'Karşındaki kişilere saygılı davran, taciz veya nefret söylemi yasak.',
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
          : Text('$_groupSize Kişilik Gruba Katıl', style: AppText.button),
    );
  }
}
