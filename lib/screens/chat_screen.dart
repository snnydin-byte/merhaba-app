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

class _ChatItem {
  final String clientId;
  final String text;
  final bool isMe;
  final DateTime createdAt;
  _SendState state;

  _ChatItem({
    required this.clientId,
    required this.text,
    required this.isMe,
    required this.createdAt,
    this.state = _SendState.sent,
  });
}

/// Bir arkadaşla mesajlaşma ekranı. Üstteki iki seçenekten biri seçilir:
/// - "Kalıcı Sohbet": sunucuda saklanır, ekrana her girişte geçmiş yeniden
///   yüklenir, karşı taraf o an bağlı olmasa bile mesaj kaydedilir ve daha
///   sonra görür.
/// - "Kaybolan Mesajlar": hiçbir yerde saklanmaz, yalnızca karşı taraf da
///   o an bu ekrandaysa anlık iletilir; ekrandan çıkınca bu sohbetin izi
///   kalmaz (uygulama hafızasında bile).
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

  // ÖNCEDEN mesajlaşma soketi bir sebeple (ör. sunucu tarafında sessiz bir
  // sorun, ağ kesintisi 'connect'/'connect_error' hiç tetiklenmeden) asılı
  // kalırsa, kullanıcı bu ekranda mesaj gönderemeden SONSUZA KADAR bekliyordu
  // - hiçbir görsel geri bildirim ya da elle tekrar deneme yolu yoktu. Artık
  // bağlanma belirli bir süreyi (bkz. _connectTimeoutDuration) aşarsa banner
  // içinde bir uyarı + "Tekrar Dene" butonu gösteriyoruz.
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

  @override
  void initState() {
    super.initState();
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
      setState(() {
        _persistentItems.add(_ChatItem(
          clientId: message.id,
          text: message.text,
          isMe: false,
          createdAt: message.createdAt,
        ));
      });
      _scrollToBottom();
    };

    _messaging.onPersistentMessageAck = (clientId, message) {
      if (!mounted) return;
      setState(() {
        _findItem(_persistentItems, clientId)?.state = _SendState.sent;
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
  /// (Dart core'daki firstOrNull ile isim çakışmasına girmemek için elle
  /// yazıyoruz.)
  _ChatItem? _findItem(List<_ChatItem> items, String clientId) {
    for (final item in items) {
      if (item.clientId == clientId) return item;
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
          ..addAll(history.map((m) => _ChatItem(
                clientId: m.id,
                text: m.text,
                isMe: m.fromId == _myId,
                createdAt: m.createdAt,
              )));
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
    final item = _ChatItem(
      clientId: clientId,
      text: text,
      isMe: true,
      createdAt: DateTime.now(),
      state: _SendState.sending,
    );

    setState(() {
      _currentItems.add(item);
      _controller.clear();
    });
    _scrollToBottom();

    if (_mode == _ChatMode.persistent) {
      _messaging.sendPersistentMessage(
          toId: widget.friend.id, text: text, clientId: clientId);
    } else {
      _messaging.sendDisappearingMessage(
          toId: widget.friend.id, text: text, clientId: clientId);
    }
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
        title: Text(widget.friend.displayName),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildModeToggle(),
              if (_connectionError != null) _buildConnectionBanner(),
              Expanded(child: _buildMessageList()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
            _mode == _ChatMode.persistent
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

  Widget _buildBubble(_ChatItem item) {
    return Align(
      alignment: item.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            item.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: item.isMe ? AppColors.primary : Colors.white12,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(item.text,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
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
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: _mode == _ChatMode.persistent
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
