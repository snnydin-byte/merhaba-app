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

  const LiveRoomScreen.host({super.key, this.title}) : existingRoomId = null;

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
  List<LiveRoomViewer> _viewers = [];
  void Function(void Function())? _viewerSheetSetState;
  bool _friendRequestSent = false;

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
    _service.onViewerList = (viewers) {
      if (!mounted) return;
      setState(() => _viewers = viewers);
      _viewerSheetSetState?.call(() {});
    };
    _service.onModeratorChanged = (userId, isMod) {
      if (!mounted) return;
      // Kendi rolüm değiştiyse AppBar'daki moderasyon butonu görünürlüğü
      // canModerate'e göre anında güncellensin.
      setState(() {});
      _viewerSheetSetState?.call(() {});
    };
    _service.onMuteChanged = (userId, muted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                muted ? 'Yayıncı susturuldu.' : 'Yayıncının sesi açıldı.')),
      );
    };
    _service.onKicked = () {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Yayından atıldın',
              style: TextStyle(color: Colors.white)),
          content: const Text('Host seni bu canlı yayından çıkardı.',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).maybePop();
              },
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    };
    _service.onFriendRequestReceived = (fromUserId, fromDisplayName) {
      if (!mounted) return;
      _showFriendRequestDialog(fromDisplayName);
    };
    _service.onFriendRequestResult = (accepted, displayName) {
      if (!mounted) return;
      setState(() => _friendRequestSent = false);
      final name = displayName ?? 'Kullanıcı';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(accepted
                ? '$name artık arkadaşın!'
                : '$name isteği reddetti.')),
      );
    };
    _service.onFriendRequestError = (message) {
      if (!mounted) return;
      setState(() => _friendRequestSent = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    };
    _service.onReportSent = (id) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirimin alındı, incelenecek.')),
      );
    };
    _service.onReportError = (message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
      await _service.joinAsViewer(
          authToken: token, roomId: widget.existingRoomId!);
    }
  }

  void _sendChat() {
    final text = _chatController.text;
    if (text.trim().isEmpty) return;
    _service.sendChatMessage(text);
    _chatController.clear();
  }

  void _sendFriendRequestToHost() {
    if (_friendRequestSent || _service.hostUserId == null) return;
    _service.sendFriendRequest(_service.hostUserId!);
    setState(() => _friendRequestSent = true);
  }

  // 1'e1 görüşmedeki arkadaşlık isteği diyaloğuyla (video_chat_screen.dart)
  // AYNI görsel dil - PopScope ile geri tuşu engelleniyor ki istek
  // yanıtlanmadan diyalog kapanmasın (karşı taraf sonsuza dek beklemesin).
  void _showFriendRequestDialog(String fromDisplayName) {
    showDialog<void>(
      context: context,
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
                _service.respondToFriendRequest(false);
              },
              child: const Text('Reddet'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _service.respondToFriendRequest(true);
              },
              child: Text('Kabul Et',
                  style: TextStyle(color: AppColors.secondary)),
            ),
          ],
        ),
      ),
    );
  }

  // reportStore.js VALID_REASONS ile aynı sabit nedenler, video_chat_screen
  // .dart'taki _showReportDialog ile BİREBİR aynı liste/görsel dil.
  void _showReportDialog(String targetUserId) {
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
              .map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.$2,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _service.reportUser(targetUserId, reason: r.$1);
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

  void _confirmKick(LiveRoomViewer viewer) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('İzleyiciyi at',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('${viewer.displayName} bu yayından atılacak.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _service.kickUser(viewer.userId);
            },
            child: Text('At', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  // İzleyici listesi paneli - group_info_screen.dart'taki üye listesi
  // (GlassCard + PopupMenuButton) ile AYNI görsel dil. StatefulBuilder,
  // liste geldiğinde (onViewerList) sheet'i canlı güncelleyebilmek için.
  void _openViewerList() {
    _service.requestViewerList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            _viewerSheetSetState = setModalState;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('İzleyiciler (${_viewers.length})',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 12),
                    if (_viewers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Henüz izleyici yok.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(sheetContext).size.height * 0.5),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _viewers.length,
                          itemBuilder: (_, index) =>
                              _buildViewerRow(_viewers[index]),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => _viewerSheetSetState = null);
  }

  Widget _buildViewerRow(LiveRoomViewer viewer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary.withValues(alpha: 0.25),
              backgroundImage: viewer.photoUrl != null
                  ? NetworkImage(viewer.photoUrl!)
                  : null,
              child: viewer.photoUrl == null
                  ? Text(viewer.displayName.isNotEmpty
                      ? viewer.displayName[0].toUpperCase()
                      : '?')
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      viewer.displayName,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    ),
                  ),
                  if (viewer.isModerator)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('Moderatör',
                          style: TextStyle(
                              color: AppColors.secondaryLight, fontSize: 10)),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppColors.textFaint, size: 18),
              color: AppColors.surfaceElevated,
              onSelected: (value) {
                switch (value) {
                  case 'toggle-moderator':
                    if (viewer.isModerator) {
                      _service.removeModerator(viewer.userId);
                    } else {
                      _service.addModerator(viewer.userId);
                    }
                    break;
                  case 'kick':
                    _confirmKick(viewer);
                    break;
                  case 'friend-request':
                    _service.sendFriendRequest(viewer.userId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Arkadaşlık isteği gönderildi.')),
                    );
                    break;
                  case 'report':
                    _showReportDialog(viewer.userId);
                    break;
                }
              },
              itemBuilder: (context) => [
                // Moderatör atama/kaldırma yalnızca host'a açık - co-host'lar
                // ve moderatörler bunu yapamaz (bkz. server.js live-room-add-
                // moderator, isHost kontrolü).
                if (widget.isHost)
                  PopupMenuItem(
                    value: 'toggle-moderator',
                    child: Text(
                      viewer.isModerator
                          ? 'Moderatörlükten al'
                          : 'Moderatör yap',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                PopupMenuItem(
                    value: 'kick',
                    child:
                        Text('At', style: TextStyle(color: AppColors.danger))),
                PopupMenuItem(
                    value: 'friend-request',
                    child: Text('Arkadaş ekle',
                        style: TextStyle(color: AppColors.textPrimary))),
                PopupMenuItem(
                    value: 'report',
                    child: Text('Bildir',
                        style: TextStyle(color: AppColors.textPrimary))),
              ],
            ),
          ],
        ),
      ),
    );
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
      backgroundColor: AppColors.backgroundDeep,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDeep,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.isHost ? 'Canlı yayınım' : 'Canlı yayın',
                style: AppText.subheading.copyWith(fontSize: 17)),
            Text(
              _ended ? 'yayın sona erdi' : 'toplulukla canlı bağlantı',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (_viewerCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: PillBadge(
                  label: '$_viewerCount',
                  color: AppColors.secondary,
                  icon: Icons.visibility_rounded,
                ),
              ),
            ),
          // İzleyici listesi/moderasyon paneli - yalnızca host/co-host/
          // moderatöre görünür (bkz. LiveRoomService.canModerate).
          if (_service.canModerate)
            IconButton(
              tooltip: 'İzleyiciler',
              icon: const Icon(Icons.groups_outlined, color: Colors.white),
              onPressed: _openViewerList,
            ),
          // Yayına izleyici olarak katılan biri host'a arkadaşlık isteği
          // gönderebilsin - video_chat_screen.dart'taki 1'e1 "Arkadaş Ekle"
          // butonuyla AYNI görsel dil.
          if (!widget.isHost && AuthService().isLoggedIn && !_friendRequestSent)
            IconButton(
              tooltip: 'Arkadaş Ekle',
              onPressed: _sendFriendRequestToHost,
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle),
                child: const Icon(Icons.person_add_alt_1_rounded,
                    size: 18, color: Colors.white),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildVideoStage()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            _buildChatBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoStage() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: neonGlow(
          AppColors.primary,
          opacity: 0.14,
          blurRadius: 24,
          spreadRadius: 0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Stack(
          children: [
            Positioned.fill(child: _buildVideoArea()),
            Positioned(
              top: 14,
              left: 14,
              child: PillBadge(
                label: _ended ? 'BİTTİ' : 'CANLI',
                color: _ended ? AppColors.textMuted : AppColors.danger,
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDeep.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forum_outlined,
                        color: AppColors.secondary, size: 15),
                    const SizedBox(width: 6),
                    Text('${_messages.length}',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_ended) {
      return const Center(
        child:
            Text('Yayın sona erdi.', style: TextStyle(color: Colors.white70)),
      );
    }
    final remoteParticipants = _service.remoteParticipants.toList();
    if (widget.isHost) {
      // Host kendi kamerasını LiveKit'in yerel önizlemesiyle görür.
      final localVideoTrack = _service
          .room?.localParticipant?.videoTrackPublications
          .map((p) => p.track)
          .whereType<livekit.LocalVideoTrack>()
          .firstOrNull;
      if (localVideoTrack == null) {
        return Center(
          child: Text(_status, style: const TextStyle(color: Colors.white70)),
        );
      }
      return livekit.VideoTrackRenderer(
        localVideoTrack,
        fit: livekit.VideoViewFit.cover,
      );
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
    return livekit.VideoTrackRenderer(
      videoTrack,
      fit: livekit.VideoViewFit.cover,
    );
  }

  Widget _buildChatBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 132,
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      children: [
                        TextSpan(
                          text: '${message.displayName ?? '?'}: ',
                          style: TextStyle(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w800),
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
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Mesaj yaz...',
                      hintStyle: TextStyle(color: AppColors.textFaint),
                      filled: true,
                      fillColor: AppColors.background.withValues(alpha: 0.72),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
                GestureDetector(
                  onTap: _sendChat,
                  child: Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppGradients.warmSignal,
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 19),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
