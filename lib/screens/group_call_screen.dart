import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

import '../services/auth_service.dart';
import '../services/group_call_service.dart';
import '../theme/app_theme.dart';

/// Grup Eşleşme (3-8 kişi) ekranı - video_chat_screen.dart'ın grup eşiti.
/// ESKİ mesh sürümünden FARKLI: kamera/mikrofon artık burada LiveKit
/// tarafından yönetiliyor (bkz. group_call_service.dart) - [initialMicOn]/
/// [initialCamOn] yalnızca GroupCallPreScreen'deki önizleme tercihini
/// taşıyor, gerçek medya akışı bu ekranda LiveKit ile YENİDEN kurulur.
class GroupCallScreen extends StatefulWidget {
  final int groupSize;
  final bool initialMicOn;
  final bool initialCamOn;

  const GroupCallScreen({
    super.key,
    required this.groupSize,
    this.initialMicOn = true,
    this.initialCamOn = true,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final GroupCallService _groupCall = GroupCallService();

  String _status = 'Grup aranıyor...';
  bool _micOn = true;
  bool _camOn = true;
  bool _reporting = false;

  @override
  void initState() {
    super.initState();
    _micOn = widget.initialMicOn;
    _camOn = widget.initialCamOn;
    _setup();
  }

  void _setup() {
    _groupCall.onStatusChange = (status) {
      if (!mounted) return;
      setState(() => _status = status);
    };
    _groupCall.onUpdate = () {
      if (!mounted) return;
      setState(() {});
    };
    _groupCall.onError = (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

    _groupCall.connectAndFind(size: widget.groupSize, authToken: AuthService().token);
  }

  void _skipToNextGroup() {
    setState(() => _status = 'Yeni grup aranıyor...');
    _groupCall.findNewGroup(widget.groupSize);
  }

  void _leave() {
    _groupCall.leaveRoom();
    Navigator.of(context).pop();
  }

  void _toggleMic() {
    setState(() => _micOn = !_micOn);
    _groupCall.room?.localParticipant?.setMicrophoneEnabled(_micOn);
  }

  void _toggleCam() {
    setState(() => _camOn = !_camOn);
    _groupCall.room?.localParticipant?.setCameraEnabled(_camOn);
  }

  void _switchCamera() {
    final track = _groupCall.room?.localParticipant?.videoTrackPublications
        .map((p) => p.track)
        .whereType<livekit.LocalVideoTrack>()
        .firstOrNull;
    if (track == null) return;
    final options = track.currentOptions;
    if (options is! livekit.CameraCaptureOptions) return;
    track.setCameraPosition(
      options.cameraPosition == livekit.CameraPosition.front
          ? livekit.CameraPosition.back
          : livekit.CameraPosition.front,
    );
  }

  void _showReportSheet() {
    final participants = _groupCall.remoteParticipants.toList();
    if (participants.isEmpty) return;
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
            ...participants.map(
              (p) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                  child: Text(
                    p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(p.name.isNotEmpty ? p.name : 'Kullanıcı',
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showReportReasonDialog(p.identity);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportReasonDialog(String targetUserId) {
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
                      _groupCall.reportUser(targetUserId, r.$1);
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
              '${_groupCall.targetSize ?? widget.groupSize} Kişilik Grup · $_status',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: (_reporting || _groupCall.remoteParticipants.isEmpty) ? null : _showReportSheet,
            icon: const Icon(Icons.flag_outlined, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final localVideoTrack = _groupCall.room?.localParticipant?.videoTrackPublications
        .map((p) => p.track)
        .whereType<livekit.LocalVideoTrack>()
        .firstOrNull;

    final tiles = <Widget>[
      _localVideoTile(localVideoTrack),
      for (final participant in _groupCall.remoteParticipants) _remoteVideoTile(participant),
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

  Widget _localVideoTile(livekit.LocalVideoTrack? track) {
    return _tileFrame(
      label: 'Sen',
      video: (_camOn && track != null) ? livekit.VideoTrackRenderer(track, mirrorMode: livekit.VideoViewMirrorMode.mirror) : null,
    );
  }

  Widget _remoteVideoTile(livekit.RemoteParticipant participant) {
    final videoTrack = participant.videoTrackPublications
        .map((p) => p.track)
        .whereType<livekit.VideoTrack>()
        .firstOrNull;
    return _tileFrame(
      label: participant.name.isNotEmpty ? participant.name : 'Kullanıcı',
      video: videoTrack != null ? livekit.VideoTrackRenderer(videoTrack) : null,
    );
  }

  Widget _tileFrame({required String label, Widget? video}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        color: AppColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video != null)
              video
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
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
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
            onTap: _toggleMic,
          ),
          const SizedBox(width: 16),
          _controlButton(
            icon: _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            active: _camOn,
            onTap: _toggleCam,
          ),
          const SizedBox(width: 16),
          _controlButton(
            icon: Icons.cameraswitch_rounded,
            active: true,
            onTap: _switchCamera,
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
