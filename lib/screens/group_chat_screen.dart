import 'package:flutter/material.dart';

import '../services/app_connection_state.dart';
import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../utils/forced_navigation.dart';
import '../widgets/connection_status_banner.dart';
import 'group_info_screen.dart';
import 'groups_screen.dart';
import '../utils/session_transient_ui.dart';

enum _SendState { sending, sent, failed }

class _GroupChatItem {
  final String clientId;
  String? serverId;
  String text;
  final String fromId;
  final DateTime createdAt;
  _SendState state;
  bool deleted;
  final String? replyToId;

  _GroupChatItem({
    required this.clientId,
    this.serverId,
    required this.text,
    required this.fromId,
    required this.createdAt,
    this.state = _SendState.sent,
    this.deleted = false,
    this.replyToId,
  });

  factory _GroupChatItem.fromMessage(GroupMessage m) => _GroupChatItem(
        clientId: m.id,
        serverId: m.id,
        text: m.text,
        fromId: m.fromId,
        createdAt: m.createdAt,
        deleted: m.deleted,
        replyToId: m.replyToId,
      );
}

/// Bir grup sohbeti ekranı (Batch B) - chat_screen.dart'ın basitleştirilmiş
/// hali: yalnızca düz metin + yanıtlama (replyToId - "Konu/yanıt zinciri"
/// maddesi), düzenleme/tepki/sabitleme/zengin mesaj türleri burada YOK
/// (bkz. groupMessageStore.js üstündeki kapsam notu).
class GroupChatScreen extends StatefulWidget {
  final Group group;
  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_GroupChatItem> _items = [];

  late Group _group = widget.group;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMoreHistory = false;
  String? _historyBefore;
  _GroupChatItem? _replyingTo;
  int _clientIdCounter = 0;

  String _myId = '';
  bool _accessRevoked = false;

  void _syncSessionUser() {
    final nextId = AuthService().sessionState.value.user?.id ?? '';
    if (_myId == nextId) return;
    if (mounted) {
      setState(() => _myId = nextId);
    } else {
      _myId = nextId;
    }
  }

  bool get _canSend => !_group.announcementOnly || _group.isAdmin(_myId);

  void _closeForLostAccess(String message) {
    if (!mounted || _accessRevoked) return;
    _accessRevoked = true;
    FocusManager.instance.primaryFocus?.unfocus();
    _controller.clear();
    _replyingTo = null;
    navigateAfterAccessLoss(
      context,
      destination: (_) => const GroupsScreen(),
      message: message,
    );
  }

  @override
  void initState() {
    super.initState();
    _myId = AuthService().sessionState.value.user?.id ?? '';
    AuthService().sessionState.addListener(_syncSessionUser);
    _scrollController.addListener(_handleHistoryScroll);
    _wireCallbacks();
    _loadHistory();
  }

  void _wireCallbacks() {
    MessagingService().onGroupMessageReceived = (message, fromDisplayName) {
      if (!mounted) return;
      if (message.groupId != _group.id) return;
      if (_items.any((i) => i.serverId == message.id)) return;
      setState(() => _items.add(_GroupChatItem.fromMessage(message)));
      _scrollToBottom();
    };
    MessagingService().onGroupMessageAck = (clientId, message) {
      if (!mounted) return;
      final item = _items.where((i) => i.clientId == clientId).firstOrNull;
      if (item == null) return;
      setState(() {
        item.state = _SendState.sent;
        item.serverId = message.id;
      });
    };
    MessagingService().onGroupMessageError = (clientId, message) {
      if (!mounted) return;
      if (clientId != null) {
        final item = _items.where((i) => i.clientId == clientId).firstOrNull;
        if (item != null) setState(() => item.state = _SendState.failed);
      }
      showSessionSnackBar(
        context,
        SnackBar(content: Text(message)),
        priority: SessionFeedbackPriority.normal,
      );
    };
    MessagingService().onGroupMessageDeleted = (message) {
      if (!mounted) return;
      if (message.groupId != _group.id) return;
      final item = _items.where((i) => i.serverId == message.id).firstOrNull;
      if (item == null) return;
      setState(() {
        item.deleted = true;
        item.text = '';
      });
    };
    MessagingService().onGroupUpdated = (group) {
      if (!mounted) return;
      if (group.id != _group.id) return;
      if (!group.members.contains(_myId)) {
        _closeForLostAccess('Bu gruba erişimin kaldırıldı.');
        return;
      }
      setState(() => _group = group);
    };
    MessagingService().onGroupDeleted = (groupId) {
      if (!mounted) return;
      if (groupId != _group.id) return;
      _closeForLostAccess('Bu grup silindi.');
    };
    MessagingService().onGroupRemovedYou = (groupId) {
      if (!mounted) return;
      if (groupId != _group.id) return;
      _closeForLostAccess('Bu gruptan çıkarıldın.');
    };
  }

  @override
  void dispose() {
    AuthService().sessionState.removeListener(_syncSessionUser);
    MessagingService().onGroupMessageReceived = null;
    MessagingService().onGroupMessageAck = null;
    MessagingService().onGroupMessageError = null;
    MessagingService().onGroupMessageDeleted = null;
    MessagingService().onGroupUpdated = null;
    MessagingService().onGroupDeleted = null;
    MessagingService().onGroupRemovedYou = null;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final page = await MessagingService().fetchGroupMessagePage(_group.id);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.messages.map(_GroupChatItem.fromMessage));
        _hasMoreHistory = page.hasMore;
        _historyBefore = page.nextBefore;
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleHistoryScroll() {
    if (!_hasMoreHistory || _loadingOlder || !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.pixels <= 180) {
      _loadOlderHistory();
    }
  }

  Future<void> _loadOlderHistory() async {
    final before = _historyBefore;
    if (before == null || !_hasMoreHistory || _loadingOlder) return;
    _loadingOlder = true;
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    try {
      final page = await MessagingService().fetchGroupMessagePage(
        _group.id,
        before: before,
      );
      if (!mounted) return;
      final known =
          _items.map((item) => item.serverId).whereType<String>().toSet();
      final older = page.messages
          .where((message) => !known.contains(message.id))
          .map(_GroupChatItem.fromMessage)
          .toList();
      setState(() {
        _items.insertAll(0, older);
        _hasMoreHistory = page.hasMore;
        _historyBefore = page.nextBefore;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final newExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(
          (oldOffset + newExtent - oldExtent)
              .clamp(0.0, _scrollController.position.maxScrollExtent)
              .toDouble(),
        );
      });
    } catch (_) {
      // Mevcut listeyi koru; kullanıcı tekrar yukarı kaydırınca yeniden dene.
    } finally {
      _loadingOlder = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    if (_accessRevoked || !mounted) return;
    final text = _controller.text.trim();
    if (text.isEmpty || !_canSend) return;
    final clientId =
        'gm${_clientIdCounter++}_${DateTime.now().microsecondsSinceEpoch}';
    final replyToId = _replyingTo?.serverId;
    final item = _GroupChatItem(
      clientId: clientId,
      text: text,
      fromId: _myId,
      createdAt: DateTime.now(),
      state: _SendState.sending,
      replyToId: replyToId,
    );
    setState(() {
      _items.add(item);
      _controller.clear();
      _replyingTo = null;
    });
    _scrollToBottom();
    MessagingService().sendGroupMessage(
      groupId: _group.id,
      text: text,
      clientId: clientId,
      replyToId: replyToId,
    );
  }

  void _showMessageActions(_GroupChatItem item) {
    if (item.deleted) return;
    final canDelete = item.fromId == _myId || _group.isAdmin(_myId);
    showSessionModalBottomSheet<void>(
      deduplicationKey: 'group_chat_screen.sheet.1',
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(Icons.reply_rounded, color: AppColors.textSecondary),
              title: Text('Yanıtla',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyingTo = item);
              },
            ),
            if (canDelete)
              ListTile(
                leading:
                    Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                title: Text('Sil', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (item.serverId != null) {
                    MessagingService().deleteGroupMessage(
                        groupId: _group.id, messageId: item.serverId!);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  String _replyPreviewText(String? replyToId) {
    if (replyToId == null) return '';
    final target = _items.where((i) => i.serverId == replyToId).firstOrNull;
    if (target == null) return '';
    return target.deleted ? 'Silinmiş mesaj' : target.text;
  }

  // Canva mockup'ındaki gibi her göndericiye sabit/deterministik bir renk -
  // grup sohbetinde kimin yazdığını isme bakmadan da ayırt etmeyi kolaylaştırır
  // (aynı kullanıcı her zaman aynı rengi alır, id hash'inden türetilir).
  static const _senderPalette = [
    Color(0xFFC77DFF),
    Color(0xFF00E5FF),
    Color(0xFF00FF88),
    Color(0xFFFF6FB5),
    Color(0xFFFFB74D),
    Color(0xFF6FF3FF),
  ];

  Color _senderColor(String userId) {
    return _senderPalette[userId.hashCode.abs() % _senderPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            await Navigator.of(context).push<void>(
              AppPageRoute(builder: (_) => GroupInfoScreen(group: _group)),
            );
            if (!mounted) return;
            // GroupInfoScreen açıkken MessagingService'in paylaşılan
            // callback alanlarını kendi üzerine yazmıştı (bkz. sınıf
            // üstündeki not) - geri dönünce bu ekranın kendi
            // dinleyicilerini yeniden takıyoruz, en güncel grup halini de
            // sunucudan tazeliyoruz.
            _wireCallbacks();
            try {
              final groups = await MessagingService().fetchGroups();
              final match = groups.where((g) => g.id == _group.id).firstOrNull;
              if (match != null && mounted) setState(() => _group = match);
            } catch (_) {
              // sessizce yok say - elimizdeki son bilinen hal kalır.
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_group.name, style: AppText.subheading),
              Text('${_group.members.length} üye',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: kToolbarHeight + 8),
              const ConnectionStatusBanner(
                channel: AppConnectionChannel.messaging,
                compact: true,
                margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
              ),
              if (_group.announcementOnly)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_outlined,
                          color: AppColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _canSend
                              ? 'Duyuru kanalı - yalnızca yöneticiler mesaj gönderebilir.'
                              : 'Bu bir duyuru kanalı, yalnızca yöneticiler mesaj gönderebilir.',
                          style:
                              TextStyle(color: AppColors.warning, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _buildList()),
              if (_replyingTo != null) _buildReplyPreview(),
              if (_canSend) _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_items.isEmpty) {
      return Center(
        child: Text('Henüz mesaj yok. İlk mesajı sen gönder.',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }
    final showHistoryLoader = _hasMoreHistory || _loadingOlder;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _items.length + (showHistoryLoader ? 1 : 0),
      itemBuilder: (context, index) {
        if (showHistoryLoader && index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: _loadingOlder
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Daha eski mesajlar için yukarı kaydır'),
            ),
          );
        }
        final itemIndex = index - (showHistoryLoader ? 1 : 0);
        final item = _items[itemIndex];
        final isMe = item.fromId == _myId;
        return GestureDetector(
          onLongPress: () => _showMessageActions(item),
          child: Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.primary
                    : AppColors.textPrimary.withValues(alpha: 0.08),
                // 1:1 sohbetle (chat_screen.dart) tutarlı kuyruklu balon.
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(_group.displayNameFor(item.fromId),
                          style: TextStyle(
                              color: _senderColor(item.fromId),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  if (item.replyToId != null && !item.deleted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _replyPreviewText(item.replyToId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                  Text(
                    item.deleted ? 'Bu mesaj silindi' : item.text,
                    style: TextStyle(
                        color: item.deleted
                            ? (isMe ? Colors.white38 : AppColors.textFaint)
                            : (isMe ? Colors.white : AppColors.textPrimary),
                        fontStyle:
                            item.deleted ? FontStyle.italic : FontStyle.normal,
                        fontSize: 14),
                  ),
                  if (item.state == _SendState.failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.error_outline,
                          color: AppColors.danger, size: 14),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _replyingTo!.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _replyingTo = null),
            child: Icon(Icons.close, color: AppColors.textMuted, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Mesaj yaz...',
                hintStyle: TextStyle(color: AppColors.textFaint),
                filled: true,
                fillColor: AppColors.textPrimary.withValues(alpha: 0.06),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary,
              child:
                  const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
