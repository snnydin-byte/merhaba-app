import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;

import '../services/app_connection_state.dart';
import '../services/auth_service.dart';
import '../services/group_call_service.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_status_banner.dart';
import '../utils/session_transient_ui.dart';

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
  bool _chatOpen = false;
  bool _sendingMessage = false;
  int _unreadMessageCount = 0;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<GroupCallChatMessage> _messages = [];

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
    _groupCall.onChatMessage = (message) {
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        if (!_chatOpen) _unreadMessageCount++;
      });
      _scrollChatToLatest();
    };
    _groupCall.onError = (message) {
      if (!mounted) return;
      showSessionSnackBar(
        context,
        SnackBar(content: Text(message)),
        priority: SessionFeedbackPriority.normal,
      );
    };
    _groupCall.onCallEnded = () {
      if (!mounted) return;
      showSessionSnackBar(
        context,
        const SnackBar(content: Text('Görüşme sona erdi - yalnız kaldın.')),
        priority: SessionFeedbackPriority.normal,
      );
      Navigator.of(context).pop();
    };
    _groupCall.onAccountRestricted = (message) {
      if (!mounted) return;
      showSessionDialog<void>(
        deduplicationKey: 'group_call_screen.dialog.1',
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Hesap kısıtlandı',
              style: TextStyle(color: Colors.white)),
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
      showSessionSnackBar(
        context,
        const SnackBar(content: Text('Şikayetin alındı, teşekkürler.')),
        priority: SessionFeedbackPriority.normal,
      );
    };
    _groupCall.onReportError = (message) {
      if (!mounted) return;
      setState(() => _reporting = false);
      showSessionSnackBar(
        context,
        SnackBar(content: Text(message)),
        priority: SessionFeedbackPriority.normal,
      );
    };

    _groupCall.connectAndFind(
        size: widget.groupSize, authToken: AuthService().token);
  }

  void _skipToNextGroup() {
    setState(() {
      _status = 'Yeni grup aranıyor...';
      _messages.clear();
      _unreadMessageCount = 0;
      _chatOpen = false;
    });
    _groupCall.findNewGroup(widget.groupSize);
  }

  void _leave() {
    _groupCall.leaveRoom();
    Navigator.of(context).pop();
  }

  void _toggleMic() {
    setState(() => _micOn = !_micOn);
    _groupCall.setMicrophoneEnabled(_micOn);
  }

  void _toggleCam() {
    setState(() => _camOn = !_camOn);
    _groupCall.setCameraEnabled(_camOn);
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

  void _toggleChat() {
    final openingChat = !_chatOpen;
    setState(() {
      _chatOpen = openingChat;
      if (_chatOpen) _unreadMessageCount = 0;
    });
    if (openingChat) _scrollChatToLatest();
  }

  void _scrollChatToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatOpen || !_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sendingMessage) return;

    setState(() => _sendingMessage = true);
    final sent = await _groupCall.sendChatMessage(text);
    if (!mounted) return;

    if (!sent) {
      setState(() => _sendingMessage = false);
      showSessionSnackBar(
        context,
        const SnackBar(
          content: Text(
              'Grup mesajı hazırlanıyor, birkaç saniye sonra tekrar dene.'),
        ),
        priority: SessionFeedbackPriority.normal,
      );
      return;
    }

    setState(() {
      _messages.add(
        GroupCallChatMessage(
          text: text,
          senderName: _groupCall.localParticipantName,
          isMe: true,
        ),
      );
      _messageController.clear();
      _sendingMessage = false;
    });
    _scrollChatToLatest();
  }

  void _showReportSheet() {
    final participants = _groupCall.remoteParticipants.toList();
    if (participants.isEmpty) return;
    showSessionModalBottomSheet<void>(
      deduplicationKey: 'group_call_screen.sheet.1',
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kimi bildirmek istiyorsun?',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
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
    showSessionDialog<void>(
      deduplicationKey: 'group_call_screen.dialog.2',
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Kullanıcıyı bildir',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: reasons
              .map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.$2,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _reporting = true);
                      _groupCall.reportUser(targetUserId, r.$1);
                    },
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _chatScrollController.dispose();
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
              const ConnectionStatusBanner(
                channel: AppConnectionChannel.groupCall,
                compact: true,
                margin: EdgeInsets.fromLTRB(12, 0, 12, 6),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _chatOpen
                      ? KeyedSubtree(
                          key: const ValueKey('group-chat'),
                          child: _buildChatView(),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('group-video-grid'),
                          child: _buildGrid(),
                        ),
                ),
              ),
              if (_groupCall.room != null && !_chatOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _buildConversationButton(),
                ),
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
            onPressed: (_reporting || _groupCall.remoteParticipants.isEmpty)
                ? null
                : _showReportSheet,
            icon: const Icon(Icons.flag_outlined, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final localVideoTrack = _groupCall
        .room?.localParticipant?.videoTrackPublications
        .map((p) => p.track)
        .whereType<livekit.LocalVideoTrack>()
        .firstOrNull;

    final tiles = <Widget>[
      _localVideoTile(localVideoTrack),
      for (final participant in _groupCall.remoteParticipants)
        _remoteVideoTile(participant),
    ];

    if (tiles.length == 1) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: tiles.first,
      );
    }

    final crossAxisCount = tiles.length <= 2
        ? 1
        : tiles.length <= 4
            ? 2
            : 3;
    final childAspectRatio = tiles.length <= 2
        ? 1.36
        : tiles.length <= 4
            ? 0.76
            : 0.70;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        itemCount: tiles.length,
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: childAspectRatio,
        ),
        itemBuilder: (_, index) => tiles[index],
      ),
    );
  }

  Widget _localVideoTile(livekit.LocalVideoTrack? track) {
    return _tileFrame(
      label: 'Sen',
      video: (_camOn && track != null)
          ? livekit.VideoTrackRenderer(
              track,
              fit: livekit.VideoViewFit.cover,
              mirrorMode: livekit.VideoViewMirrorMode.mirror,
            )
          : null,
    );
  }

  Widget _remoteVideoTile(livekit.RemoteParticipant participant) {
    final videoTrack = participant.videoTrackPublications
        .map((p) => p.track)
        .whereType<livekit.VideoTrack>()
        .firstOrNull;
    return _tileFrame(
      label: participant.name.isNotEmpty ? participant.name : 'Kullanıcı',
      video: videoTrack != null
          ? livekit.VideoTrackRenderer(
              videoTrack,
              fit: livekit.VideoViewFit.cover,
            )
          : null,
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
                child:
                    Icon(Icons.person_rounded, color: Colors.white24, size: 48),
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
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationButton() {
    final hasUnreadMessages = _unreadMessageCount > 0;
    final unreadLabel =
        _unreadMessageCount > 9 ? '9+' : _unreadMessageCount.toString();

    return Semantics(
      button: true,
      label: hasUnreadMessages
          ? 'Grup sohbeti, $_unreadMessageCount okunmamış mesaj'
          : 'Grup sohbeti',
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: hasUnreadMessages
                ? AppColors.danger.withValues(alpha: 0.18)
                : AppColors.surfaceElevated.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: hasUnreadMessages
                  ? AppColors.danger.withValues(alpha: 0.9)
                  : AppColors.secondary.withValues(alpha: 0.52),
            ),
            boxShadow: neonGlow(
              hasUnreadMessages ? AppColors.danger : AppColors.secondary,
              opacity: hasUnreadMessages ? 0.26 : 0.12,
              blurRadius: 22,
              spreadRadius: 0,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: _toggleChat,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.forum_rounded,
                    color: hasUnreadMessages
                        ? AppColors.danger
                        : AppColors.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasUnreadMessages ? 'Yeni mesaj' : 'Grup sohbeti',
                    style: AppText.button.copyWith(fontSize: 15),
                  ),
                  if (hasUnreadMessages) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        unreadLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: SizedBox.expand(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                    child: Row(
                      children: [
                        Icon(Icons.forum_rounded,
                            color: AppColors.secondary, size: 17),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Grup sohbeti',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Grup sohbetini kapat',
                          onPressed: _toggleChat,
                          icon: const Icon(Icons.close,
                              color: Colors.white54, size: 19),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _messages.isEmpty
                        ? Center(
                            child: Text(
                              'Gruptaki herkese buradan mesaj yazabilirsin.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.48),
                                fontSize: 12,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _chatScrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: double.infinity,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: message.isMe
                                        ? AppColors.primary
                                            .withValues(alpha: 0.22)
                                        : Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message.senderName,
                                        style: TextStyle(
                                          color: message.isMe
                                              ? AppColors.primary
                                              : AppColors.secondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        message.text,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
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
                            controller: _messageController,
                            enabled: !_sendingMessage,
                            textInputAction: TextInputAction.send,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Gruba mesaj yaz...',
                              hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4)),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.06),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Gruba mesaj gönder',
                          onPressed: _sendingMessage ? null : _sendMessage,
                          icon: _sendingMessage
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(Icons.send_rounded,
                                  color: AppColors.secondary),
                        ),
                      ],
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
              : (active
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.redAccent.withValues(alpha: 0.85)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
