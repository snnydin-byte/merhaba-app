import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/auth_service.dart';
import '../services/group_call_service.dart';
import '../services/webrtc_service.dart';
import '../theme/app_theme.dart';

/// Küçük grup rastgele görüşmesi (mesh, 3-4 kişi) ekranı - video_chat_screen
/// .dart'ın grup eşiti. [webrtcForMedia], GroupCallPreScreen'de ZATEN
/// başlatılmış kamera/mikrofon akışının sahibi - bu ekran onu devralır
/// (izin/getUserMedia burada TEKRAR istenmez), mic/kamera aç-kapa/kamera
/// değiştirme için onun hazır yöntemlerini kullanır. Gerçek grup
/// sinyalleşmesi (oda kurulumu, mesh peer connection'lar) TAMAMEN
/// GroupCallService'te - bu ekran yalnızca onu UI'a bağlar.
class GroupCallScreen extends StatefulWidget {
  final int groupSize;
  final WebRTCService webrtcForMedia;

  const GroupCallScreen({
    super.key,
    required this.groupSize,
    required this.webrtcForMedia,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final GroupCallService _groupCall = GroupCallService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};

  String _status = 'Grup aranıyor...';
  bool _micOn = true;
  bool _camOn = true;
  bool _reporting = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _localRenderer.initialize();
    _localRenderer.srcObject = widget.webrtcForMedia.localStream;
    _micOn = widget.webrtcForMedia.isMicEnabled;
    _camOn = widget.webrtcForMedia.isCamEnabled;

    _groupCall.onStatusChange = (status) {
      if (!mounted) return;
      setState(() => _status = status);
    };
    _groupCall.onUpdate = _syncRenderers;
    _groupCall.onPeerLeft = (socketId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bir katılımcı görüşmeden ayrıldı.')),
      );
    };
    _groupCall.onCallEnded = () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Görüşme sona erdi - yalnız kaldın.')),
      );
      Navigator.of(context).pop();
    };
    _groupCall.onAccountRestricted = (message) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Hesap kısıtlandı', style: TextStyle(color: Colors.white)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).pop();
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    };
    _groupCall.onReportSent = (_) {
      if (!mounted) return;
      setState(() => _reporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şikayetin alındı, teşekkürler.')),
      );
    };
    _groupCall.onReportError = (message) {
      if (!mounted) return;
      setState(() => _reporting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    };

    _groupCall.connectAndFind(
      size: widget.groupSize,
      localStream: widget.webrtcForMedia.localStream!,
      authToken: AuthService().token,
    );
  }

  Future<void> _syncRenderers() async {
    final currentIds = _groupCall.peers.map((p) => p.socketId).toSet();

    // Artık odada olmayan katılımcıların renderer'larını serbest bırak.
    final staleIds = _remoteRenderers.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in staleIds) {
      await _remoteRenderers.remove(id)?.dispose();
    }

    // Yeni katılımcılar için renderer oluştur.
    for (final peer in _groupCall.peers) {
      if (!_remoteRenderers.containsKey(peer.socketId)) {
        final renderer = RTCVideoRenderer();
        await renderer.initialize();
        _remoteRenderers[peer.socketId] = renderer;
      }
      _remoteRenderers[peer.socketId]!.srcObject = peer.remoteStream;
    }

    if (mounted) setState(() {});
  }

  void _skipToNextGroup() {
    setState(() => _status = 'Yeni grup aranıyor...');
    _groupCall.findNewGroup(widget.groupSize);
  }

  void _leave() {
    _groupCall.leaveRoom();
    Navigator.of(context).pop();
  }

  void _showReportSheet() {
    final peers = _groupCall.peers;
    if (peers.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kimi bildirmek istiyorsun?',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            ...peers.map(
              (p) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                  backgroundImage: p.photoUrl != null ? NetworkImage(p.photoUrl!) : null,
                  child: p.photoUrl == null
                      ? Text((p.displayName?.isNotEmpty ?? false) ? p.displayName![0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white))
                      : null,
                ),
                title: Text(p.displayName ?? 'Misafir', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showReportReasonDialog(p.socketId);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportReasonDialog(String targetSocketId) {
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
        title: const Text('Kullanıcıyı bildir', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: reasons
              .map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.$2, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _reporting = true);
                      _groupCall.reportUser(targetSocketId, r.$1);
                    },
                  ))
              .toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _groupCall.dispose();
    _localRenderer.dispose();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    // Kamera/mikrofon akışının GERÇEK sahibi bu (bkz. sınıf üstü not) -
    // GroupCallService.dispose() bunu durdurmuyor, burada durduruyoruz.
    widget.webrtcForMedia.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _groupCall.leaveRoom();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildStatusBar(),
              Expanded(child: _buildGrid()),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              _groupCall.leaveRoom();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          ),
          Expanded(
            child: Text(
              '${widget.groupSize} Kişilik Grup · $_status',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: (_reporting || _groupCall.peers.isEmpty) ? null : _showReportSheet,
            icon: const Icon(Icons.flag_outlined, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final tiles = <Widget>[
      _videoTile(
        renderer: _localRenderer,
        label: 'Sen',
        mirror: true,
        muted: true,
        showVideo: _camOn,
      ),
      for (final peer in _groupCall.peers)
        _videoTile(
          renderer: _remoteRenderers[peer.socketId],
          label: peer.displayName ?? 'Misafir',
          verified: peer.verified,
          showVideo: _remoteRenderers[peer.socketId]?.srcObject != null,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.75,
        children: tiles,
      ),
    );
  }

  Widget _videoTile({
    RTCVideoRenderer? renderer,
    required String label,
    bool mirror = false,
    bool muted = false,
    bool verified = false,
    required bool showVideo,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        color: AppColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showVideo && renderer != null)
              RTCVideoView(
                renderer,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              const Center(
                child: Icon(Icons.person_rounded, color: Colors.white24, size: 48),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified_rounded, color: AppColors.primaryLight, size: 13),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _controlButton(
            icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: _micOn,
            onTap: () {
              setState(() => _micOn = !_micOn);
              widget.webrtcForMedia.toggleMic(_micOn);
            },
          ),
          const SizedBox(width: 16),
          _controlButton(
            icon: _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            active: _camOn,
            onTap: () {
              setState(() => _camOn = !_camOn);
              widget.webrtcForMedia.toggleCamera(_camOn);
            },
          ),
          const SizedBox(width: 16),
          _controlButton(
            icon: Icons.cameraswitch_rounded,
            active: true,
            onTap: () => widget.webrtcForMedia.switchCamera(),
          ),
          const SizedBox(width: 16),
          _controlButton(
            icon: Icons.skip_next_rounded,
            active: true,
            onTap: _skipToNextGroup,
          ),
          const SizedBox(width: 16),
          _controlButton(
            icon: Icons.call_end_rounded,
            active: false,
            danger: true,
            onTap: _leave,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required bool active,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: danger
              ? Colors.redAccent
              : (active ? Colors.white.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.85)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
