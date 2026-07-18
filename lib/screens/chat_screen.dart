import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friends_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';

enum _ChatMode { persistent, disappearing }

/// Bir tek "iyimser" (optimistic) mesaj öğesi - gönderilirken hemen listeye
/// eklenir, sunucudan onay/hata gelince durumu güncellenir.
enum _SendState { sending, sent, failed }

/// Hızlı tepki çubuğunda gösterilen sabit emoji seti (Telegram/WhatsApp'ın
/// "en çok kullanılanlar" kısayolu gibi - tam bir emoji klavyesi yerine).
const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

class _ChatItem {
  final String clientId;
  // Sunucudaki gerçek mesaj id'si - optimistic gönderimde başta bilinmez,
  // ack/receive geldiğinde doldurulur. Düzenle/sil/tepki/pin işlemleri
  // MUTLAKA bu id'yi kullanır (clientId sunucu için anlamsız).
  String? serverId;
  String text;
  final bool isMe;
  final DateTime createdAt;
  _SendState state;
  DateTime? editedAt;
  bool deleted;
  bool pinned;
  Map<String, String> reactions;
  String? replyToId;

  _ChatItem({
    required this.clientId,
    this.serverId,
    required this.text,
    required this.isMe,
    required this.createdAt,
    this.state = _SendState.sent,
    this.editedAt,
    this.deleted = false,
    this.pinned = false,
    this.reactions = const {},
    this.replyToId,
  });

  factory _ChatItem.fromMessage(PersistentMessage m, {required bool isMe}) =>
      _ChatItem(
        clientId: m.id,
        serverId: m.id,
        text: m.text,
        isMe: isMe,
        createdAt: m.createdAt,
        editedAt: m.editedAt,
        deleted: m.deleted,
        pinned: m.pinned,
        reactions: m.reactions,
        replyToId: m.replyToId,
      );

  void applyUpdate(PersistentMessage m) {
    text = m.text;
    editedAt = m.editedAt;
    deleted = m.deleted;
    pinned = m.pinned;
    reactions = m.reactions;
  }
}

/// Bir arkadaşla mesajlaşma ekranı. Üstteki iki seçenekten biri seçilir:
/// - "Kalıcı Sohbet": sunucuda saklanır, ekrana her girişte geçmiş yeniden
///   yüklenir, karşı taraf o an bağlı olmasa bile mesaj kaydedilir ve daha
///   sonra görür.
/// - "Kaybolan Mesajlar": hiçbir yerde saklanmaz, yalnızca karşı taraf da
///   o an bu ekrandaysa anlık iletilir; ekrandan çıkınca bu sohbetin izi
///   kalmaz (uygulama hafızasında bile).
///
/// NOT: [friend].id kendi kullanıcı id'ne eşitse ("Kendime Not" girişi, bkz.
/// friends_screen.dart) bu ekran "Kalıcı Sohbet" moduna sabitlenir ve tek
/// kişilik bir not defteri gibi çalışır - sunucu tarafında (server.js
/// persistent-message-send) kendine mesaj göndermeye özel olarak izin
/// verilir.
class ChatScreen extends StatefulWidget {
  final AppUser friend;
  const ChatScreen({super.key, required this.friend});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessagingService _messaging = MessagingService();
  final FriendsService _friendsService = FriendsService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _ChatMode _mode = _ChatMode.persistent;
  bool _connecting = true;
  String? _connectionError;
  bool _loadingHistory = true;
  _ChatItem? _replyingTo;

  bool get _isNoteToSelf => widget.friend.id == _myId;

  static const _connectTimeoutDuration = Duration(seconds: 12);
  Timer? _connectTimeoutTimer;

  void _startConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(_connectTimeoutDuration, () {
      if (!mounted) return;
      if (!_connecting) return;
      setState(() {
        _connectionError = 'Bağlantı kuruluyor, bu normalden uzun sürüyor.';
      });
    });
  }

  void _cancelConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
  }

  void _retryConnection() {
    final token = AuthService().token;
    if (token == null) return;
    setState(() {
      _connecting = true;
      _connectionError = null;
    });
    _startConnectTimeout();
    _messaging.reconnect(token);
  }

  final List<_ChatItem> _persistentItems = [];
  final List<_ChatItem> _disappearingItems = [];

  int _clientIdCounter = 0;
  String get _myId => AuthService().currentUser?.id ?? '';

  List<_ChatItem> get _currentItems =>
      _mode == _ChatMode.persistent ? _persistentItems : _disappearingItems;

  List<_ChatItem> get _pinnedItems =>
      _persistentItems.where((i) => i.pinned && !i.deleted).toList();

  @override
  void initState() {
    super.initState();
    if (_isNoteToSelf) _mode = _ChatMode.persistent;
    _setup();
  }

  Future<void> _setup() async {
    _wireMessagingCallbacks();

    final token = AuthService().token;
    if (token != null) {
      _messaging.activeConversationFriendId = widget.friend.id;
      _messaging.connectIfNeeded(token);
      // MessagingService artık uygulama boyunca kalıcı (bkz. orada) - bu
      // ekran açıldığında bağlantı büyük olasılıkla ZATEN kurulu olacak,
      // bu durumda 'connect' olayı bir daha ateşlenmeyeceği için durumu
      // burada elle senkronize ediyoruz.
      if (_messaging.isConnected) {
        setState(() {
          _connecting = false;
          _connectionError = null;
        });
      } else {
        _startConnectTimeout();
      }
    } else {
      setState(() {
        _connecting = false;
        _connectionError = 'Giriş yapmış olman gerekiyor.';
      });
    }

    await _loadHistory();
  }

  void _wireMessagingCallbacks() {
    _messaging.onConnected = () {
      if (!mounted) return;
      _cancelConnectTimeout();
      setState(() {
        _connecting = false;
        _connectionError = null;
      });
    };

    _messaging.onConnectError = (reason) {
      if (!mounted) return;
      _cancelConnectTimeout();
      setState(() {
        _connecting = false;
        _connectionError = 'Sunucuya bağlanılamadı.';
      });
    };

    _messaging.onPersistentMessageReceived = (message) {
      if (!mounted) return;
      if (message.fromId != widget.friend.id) return;
      // "Kendime Not"ta (ve genel olarak çok-cihazlı senkronda) aynı mesaj
      // hem bu socket'in kendi ack'i hem de emitToUser yayını üzerinden İKİ
      // KEZ gelebilir (bkz. server.js emitToUser - gönderen kendi socket'ini
      // hariç tutmuyor). Zaten listede olan bir server id'yi tekrar EKLEMEK
      // yerine sessizce yok sayıyoruz.
      if (_persistentItems.any((i) => i.serverId == message.id)) return;
      setState(() {
        _persistentItems.add(_ChatItem.fromMessage(message,
            isMe: message.fromId == _myId));
      });
      _scrollToBottom();
    };

    _messaging.onPersistentMessageAck = (clientId, message) {
      if (!mounted) return;
      setState(() {
        final item = _findItem(_persistentItems, clientId);
        if (item != null) {
          item.state = _SendState.sent;
          item.serverId = message.id;
        }
      });
    };

    _messaging.onPersistentMessageError = (clientId, message) {
      if (!mounted) return;
      setState(() {
        _findItem(_persistentItems, clientId)?.state = _SendState.failed;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    };

    _messaging.onMessageEdited = (message) {
      if (!mounted) return;
      setState(() {
        _findByServerId(_persistentItems, message.id)?.applyUpdate(message);
      });
    };

    _messaging.onMessageDeleted = (message) {
      if (!mounted) return;
      setState(() {
        _findByServerId(_persistentItems, message.id)?.applyUpdate(message);
      });
    };

    _messaging.onMessageReacted = (message) {
      if (!mounted) return;
      setState(() {
        _findByServerId(_persistentItems, message.id)?.applyUpdate(message);
      });
    };

    _messaging.onMessagePinned = (message) {
      if (!mounted) return;
      setState(() {
        _findByServerId(_persistentItems, message.id)?.applyUpdate(message);
      });
    };

    _messaging.onDisappearingMessageReceived = (message) {
      if (!mounted) return;
      if (message.fromId != widget.friend.id) return;
      setState(() {
        _disappearingItems.add(_ChatItem(
          clientId: message.id,
          text: message.text,
          isMe: false,
          createdAt: message.createdAt,
        ));
      });
      _scrollToBottom();
    };

    _messaging.onDisappearingMessageAck = (clientId, id, createdAt) {
      if (!mounted) return;
      setState(() {
        _findItem(_disappearingItems, clientId)?.state = _SendState.sent;
      });
    };

    _messaging.onDisappearingMessageError = (clientId, message) {
      if (!mounted) return;
      setState(() {
        _findItem(_disappearingItems, clientId)?.state = _SendState.failed;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    };
  }

  /// clientId'ye göre listede eşleşen öğeyi bulur, yoksa null döner.
  _ChatItem? _findItem(List<_ChatItem> items, String clientId) {
    for (final item in items) {
      if (item.clientId == clientId) return item;
    }
    return null;
  }

  _ChatItem? _findByServerId(List<_ChatItem> items, String serverId) {
    for (final item in items) {
      if (item.serverId == serverId) return item;
    }
    return null;
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final history = await _friendsService.fetchConversation(widget.friend.id);
      if (!mounted) return;
      setState(() {
        _persistentItems
          ..clear()
          ..addAll(history.map(
              (m) => _ChatItem.fromMessage(m, isMe: m.fromId == _myId)));
        _loadingHistory = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
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
    final text = _controller.text.trim();
    if (text.isEmpty || _connecting || _connectionError != null) return;

    final clientId =
        'c${_clientIdCounter++}_${DateTime.now().microsecondsSinceEpoch}';
    final replyToId = _replyingTo?.serverId;
    final item = _ChatItem(
      clientId: clientId,
      text: text,
      isMe: true,
      createdAt: DateTime.now(),
      state: _SendState.sending,
      replyToId: replyToId,
    );

    setState(() {
      _currentItems.add(item);
      _controller.clear();
      _replyingTo = null;
    });
    _scrollToBottom();

    if (_mode == _ChatMode.persistent) {
      _messaging.sendPersistentMessage(
          toId: widget.friend.id,
          text: text,
          clientId: clientId,
          replyToId: replyToId);
    } else {
      _messaging.sendDisappearingMessage(
          toId: widget.friend.id, text: text, clientId: clientId);
    }
  }

  void _startEdit(_ChatItem item) {
    final controller = TextEditingController(text: item.text);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Mesajı düzenle', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Mesajını düzenle...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              final newText = controller.text.trim();
              Navigator.pop(dialogContext);
              if (newText.isEmpty || item.serverId == null) return;
              _messaging.editMessage(messageId: item.serverId!, text: newText);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(_ChatItem item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Mesajı sil', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Bu mesaj herkesten (karşı tarafın ekranından da) silinecek.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (item.serverId != null) _messaging.deleteMessage(item.serverId!);
            },
            child: const Text('Sil', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _showMessageActions(_ChatItem item) {
    if (item.deleted || item.serverId == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(
                spacing: 6,
                children: _quickReactions
                    .map((emoji) => GestureDetector(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _messaging.reactToMessage(
                                messageId: item.serverId!, emoji: emoji);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(emoji, style: const TextStyle(fontSize: 26)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.white70),
              title: const Text('Yanıtla', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyingTo = item);
              },
            ),
            ListTile(
              leading: Icon(
                  item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: Colors.white70),
              title: Text(item.pinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                  style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                if (item.pinned) {
                  _messaging.unpinMessage(item.serverId!);
                } else {
                  _messaging.pinMessage(item.serverId!);
                }
              },
            ),
            if (item.isMe) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                title: const Text('Düzenle', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startEdit(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: const Text('Sil', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(item);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // MessagingService artık uygulama boyunca kalıcı (bkz. orada) - yalnızca
    // bu ekranın callback'lerini bırakıyoruz, ALTTAKI BAĞLANTIYA
    // dokunmuyoruz (böylece bu sohbetten çıkılsa bile başka bir yerden
    // gelecek arkadaşlık/mesaj/arama olayları çalışmaya devam eder).
    _messaging.detachScreenCallbacks();
    _cancelConnectTimeout();
    _controller.dispose();
    _scrollController.dispose();
    // Kaybolan mesajlar zaten hiç sunucuya kaydedilmiyordu; ekrandan
    // çıkınca hafızadaki listeyi de bırakıyoruz ki gerçekten "kaybolsun".
    _disappearingItems.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_isNoteToSelf ? 'Kendime Not' : widget.friend.displayName),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (!_isNoteToSelf) _buildModeToggle() else const SizedBox(height: kToolbarHeight + 16),
              if (_connectionError != null) _buildConnectionBanner(),
              if (_mode == _ChatMode.persistent && _pinnedItems.isNotEmpty)
                _buildPinnedBar(),
              Expanded(child: _buildMessageList()),
              if (_replyingTo != null) _buildReplyPreview(),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedBar() {
    final pinned = _pinnedItems;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.push_pin, color: AppColors.primaryLight, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pinned.last.deleted ? 'Silinmiş mesaj' : pinned.last.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          if (pinned.length > 1)
            Text('+${pinned.length - 1}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    final replying = _replyingTo!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
            left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              replying.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _replyingTo = null),
            child: const Icon(Icons.close, color: Colors.white54, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    // bkz. profile_screen.dart'taki aynı düzeltme - extendBodyBehindAppBar:
    // true yüzünden gövde şeffaf AppBar'ın arkasına kadar uzuyor. SafeArea
    // yalnızca durum çubuğunu hesaba katıyor, AppBar'ın kendi
    // (kToolbarHeight) yüksekliğini değil - bu yüzden Column'un İLK öğesi
    // olan bu mod anahtarı ("Kalıcı Sohbet"/"Kaybolan Mesajlar")
    // AppBar'ın dokunuş yakalayan bölgesiyle çakışıyordu.
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12 + kToolbarHeight, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(child: _modeTab('Kalıcı Sohbet', _ChatMode.persistent)),
            Expanded(
                child: _modeTab('Kaybolan Mesajlar', _ChatMode.disappearing)),
          ],
        ),
      ),
    );
  }

  Widget _modeTab(String label, _ChatMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _connectionError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _retryConnection,
            child: const Text(
              'Tekrar Dene',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_mode == _ChatMode.persistent && _loadingHistory) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final items = _currentItems;

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _isNoteToSelf
                ? 'Kendine ilk notunu bırak.'
                : _mode == _ChatMode.persistent
                    ? 'Henüz mesajlaşmadınız. İlk mesajı sen gönder.'
                    : 'Kaybolan mesajlar yalnızca ikiniz de bu ekrandayken iletilir '
                        've hiçbir yerde saklanmaz.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildBubble(items[index]),
    );
  }

  _ChatItem? _findReplySource(String? replyToId) {
    if (replyToId == null) return null;
    return _findByServerId(_persistentItems, replyToId);
  }

  Widget _buildBubble(_ChatItem item) {
    final isPersistent = _mode == _ChatMode.persistent;
    final replySource = isPersistent ? _findReplySource(item.replyToId) : null;

    return GestureDetector(
      onLongPress: isPersistent ? () => _showMessageActions(item) : null,
      child: Align(
        alignment: item.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              item.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              decoration: BoxDecoration(
                color: item.isMe ? AppColors.primary : Colors.white12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.pinned)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Icon(Icons.push_pin,
                          size: 12, color: Colors.white70),
                    ),
                  if (replySource != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                            left: BorderSide(color: Colors.white54, width: 2)),
                      ),
                      child: Text(
                        replySource.deleted
                            ? 'Silinmiş mesaj'
                            : replySource.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11),
                      ),
                    ),
                  Text(
                    item.deleted ? 'Bu mesaj silindi' : item.text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontStyle:
                          item.deleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  if (item.editedAt != null && !item.deleted)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('düzenlendi',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10)),
                    ),
                ],
              ),
            ),
            if (item.reactions.isNotEmpty && !item.deleted)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _reactionSummary(item.reactions),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (item.isMe && item.state != _SendState.sent)
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 4),
                child: Text(
                  item.state == _SendState.sending
                      ? 'gönderiliyor...'
                      : 'gönderilemedi',
                  style: TextStyle(
                    color: item.state == _SendState.failed
                        ? Colors.redAccent
                        : Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Aynı emojiyi birden fazla kişi kullandıysa tekilleştirip yanına sayı
  /// ekler (ör. "👍 2").
  String _reactionSummary(Map<String, String> reactions) {
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} ${e.value}' : e.key)
        .join('  ');
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: _isNoteToSelf
                    ? 'Kendine bir not yaz...'
                    : _mode == _ChatMode.persistent
                        ? 'Mesaj yaz...'
                        : 'Kaybolan mesaj yaz...',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
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
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
