import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

import '../services/auth_service.dart';
import '../services/live_room_service.dart';
import '../theme/app_theme.dart';

/// Canlı oda ekranı - host/co-host video ızgarası, izleyici sayacı, metin
/// sohbeti. Host olarak açılırken [title] verilir; izleyici olarak katılırken
/// [existingRoomId] verilir - ikisi karşılıklı dışlayıcı (bkz. constructor).
class LiveRoomScreen extends StatefulWidget {
  final String? title; // host modu
  final String? existingRoomId; // izleyici modu

  const LiveRoomScreen.host({super.key, this.title})
      : existingRoomId = null;

  const LiveRoomScreen.viewer({super.key, required String roomId})
      : existingRoomId = roomId,
        title = null;

  bool get isHost => existingRoomId == null;

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final LiveRoomService _service = LiveRoomService();
  final TextEditingController _chatController = TextEditingController();
  final List<LiveRoomChatMessage> _messages = [];

  String _status = 'Bağlanıyor...';
  int _viewerCount = 0;
  bool _ended = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _wireCallbacks();
    _start();
  }

  void _wireCallbacks() {
    _service.onStatusChange = (status) {
      if (!mounted) return;
      setState(() => _status = status);
    };
    _service.onUpdate = () {
      if (!mounted) return;
      setState(() {});
    };
    _service.onError = (message) {
      if (!mounted) return;
      setState(() => _error = message);
    };
    _service.onViewerCountChanged = (count) {
      if (!mounted) return;
      setState(() => _viewerCount = count);
    };
    _service.onChatMessage = (message) {
      if (!mounted) return;
      setState(() => _messages.add(message));
    };
    _service.onRoomEnded = () {
      if (!mounted) return;
      setState(() {
        _ended = true;
        _status = 'Yayın sona erdi.';
      });
    };
  }

  Future<void> _start() async {
    final token = AuthService().token;
    if (token == null) {
      setState(() => _error = 'Bu özellik için giriş yapmalısın.');
      return;
    }
    if (widget.isHost) {
      await _service.createRoom(authToken: token, title: widget.title);
    } else {
      await _service.joinAsViewer(authToken: token, roomId: widget.existingRoomId!);
    }
  }

  void _sendChat() {
    final text = _chatController.text;
    if (text.trim().isEmpty) return;
    _service.sendChatMessage(text);
    _chatController.clear();
  }

  @override
  void dispose() {
    _service.leaveRoom();
    _service.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.isHost ? 'Canlı Yayınım' : 'Canlı Yayın'),
        actions: [
          if (_viewerCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Row(
                  children: [
                    const Icon(Icons.visibility, size: 18, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text('$_viewerCount', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildVideoArea()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            _buildChatBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_ended) {
      return const Center(
        child: Text('Yayın sona erdi.', style: TextStyle(color: Colors.white70)),
      );
    }
    final remoteParticipants = _service.remoteParticipants.toList();
    if (widget.isHost) {
      // Host kendi kamerasını LiveKit'in yerel önizlemesiyle görür.
      final localVideoTrack = _service.room?.localParticipant?.videoTrackPublications
          .map((p) => p.track)
          .whereType<livekit.LocalVideoTrack>()
          .firstOrNull;
      if (localVideoTrack == null) {
        return Center(
          child: Text(_status, style: const TextStyle(color: Colors.white70)),
        );
      }
      return livekit.VideoTrackRenderer(localVideoTrack);
    }

    if (remoteParticipants.isEmpty) {
      return Center(
        child: Text(_status, style: const TextStyle(color: Colors.white70)),
      );
    }
    // Faz 1: yalnızca ilk host/co-host'un video akışını tam ekran göster -
    // çoklu co-host video ızgarası Faz 2'de.
    final firstParticipant = remoteParticipants.first;
    final videoTrack = firstParticipant.videoTrackPublications
        .map((p) => p.track)
        .whereType<livekit.VideoTrack>()
        .firstOrNull;
    if (videoTrack == null) {
      return Center(
        child: Text(_status, style: const TextStyle(color: Colors.white70)),
      );
    }
    return livekit.VideoTrackRenderer(videoTrack);
  }

  Widget _buildChatBar() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 120,
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      children: [
                        TextSpan(
                          text: '${message.displayName ?? '?'}: ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: message.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (!_ended)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: AppColors.primary),
                  onPressed: _sendChat,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
