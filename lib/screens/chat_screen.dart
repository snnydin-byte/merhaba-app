import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/stickers.dart';
import '../services/auth_service.dart';
import '../services/app_connection_state.dart';
import '../services/friends_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import '../utils/forced_navigation.dart';
import '../utils/async_operation_guard.dart';
import '../utils/message_safety.dart';
import 'friends_screen.dart';
import '../utils/session_transient_ui.dart';

// Ücretli Google Translation servisi yapılandırılmadan kullanıcıya kırık bir
// eylem göstermeyiz. API anahtarı Render'a eklendiğinde release derlemesi
// --dart-define=TRANSLATION_ENABLED=true ile açılabilir.
const bool _translationEnabled =
    bool.fromEnvironment('TRANSLATION_ENABLED', defaultValue: false);

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
  // 'text' | 'poll' | 'location' | 'sticker' | 'voice' | 'view_once_photo' -
  // bkz. signaling_server/messageStore.js ve buradaki _buildBubble().
  final String kind;
  Map<String, dynamic>? meta;
  DateTime? readAt;

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
    this.kind = 'text',
    this.meta,
    this.readAt,
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
        kind: m.kind,
        meta: m.meta,
        readAt: m.readAt,
      );

  void applyUpdate(PersistentMessage m) {
    text = m.text;
    editedAt = m.editedAt;
    deleted = m.deleted;
    pinned = m.pinned;
    reactions = m.reactions;
    meta = m.meta;
    readAt = m.readAt;
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
  bool _loadingOlderHistory = false;
  bool _hasMoreHistory = false;
  String? _historyBefore;
  _ChatItem? _replyingTo;

  // "Yazıyor..." göstergesi (GECE_GELISTIRME madde 6).
  bool _partnerTyping = false;
  Timer? _partnerTypingTimeout;
  // KENDİ yazma durumumuz - 'typing-start' art arda her tuş vuruşunda değil,
  // yazmaya BAŞLARKEN bir kez gönderilir (aşağıdaki _iAmTyping bayrağı bunu
  // takip eder); 2 saniyelik yazma durağanlığından sonra 'typing-stop' gider.
  bool _iAmTyping = false;
  Timer? _stopTypingDebounce;

  // Sesli mesaj kaydı (#48 anket maddesi).
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;
  Duration _recordingElapsed = Duration.zero;
  bool _uploadingAttachment = false;
  final AsyncOperationGuard _attachmentGuard = AsyncOperationGuard();
  final AsyncOperationGuard _sendGuard = AsyncOperationGuard();

  // Sesli mesaj oynatma - aynı anda tek bir mesaj çalınır, yenisine
  // basılınca öncekini durdurur (WhatsApp/Telegram'daki gibi).
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingVoiceMessageId;

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
  // Mesaj planlama (#12 anket maddesi) - bu sohbete ait, henüz gönderilmemiş
  // zamanlanmış mesajlar (bkz. _openScheduleComposer/_showScheduledSheet).
  final List<ScheduledMessage> _scheduledForThisChat = [];

  int _clientIdCounter = 0;
  String _myId = '';
  bool _accessRevoked = false;

  void _handleSessionChanged() {
    final nextId = AuthService().sessionState.value.user?.id ?? '';
    if (nextId == _myId) return;
    if (!mounted) {
      _myId = nextId;
      return;
    }
    setState(() {
      _myId = nextId;
      if (_isNoteToSelf) _mode = _ChatMode.persistent;
    });
  }

  void _handleConnectionChanged() {
    final status = AppConnectionController().state.value.messaging;
    if (!mounted) return;
    _cancelConnectTimeout();
    setState(() {
      _connecting = status.isBusy;
      _connectionError = status.phase == SocketConnectionPhase.error ||
              status.phase == SocketConnectionPhase.disconnected
          ? (status.message ?? 'Sunucuya bağlanılamadı.')
          : null;
    });
  }

  List<_ChatItem> get _currentItems =>
      _mode == _ChatMode.persistent ? _persistentItems : _disappearingItems;

  List<_ChatItem> get _pinnedItems =>
      _persistentItems.where((i) => i.pinned && !i.deleted).toList();

  @override
  void initState() {
    super.initState();
    _myId = AuthService().sessionState.value.user?.id ?? '';
    AuthService().sessionState.addListener(_handleSessionChanged);
    AppConnectionController().state.addListener(_handleConnectionChanged);
    _scrollController.addListener(_handleHistoryScroll);
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
      final status = AppConnectionController().state.value.messaging;
      if (status.isConnected) {
        setState(() {
          _connecting = false;
          _connectionError = null;
        });
      } else {
        setState(() {
          _connecting = status.isBusy;
          _connectionError = status.phase == SocketConnectionPhase.error ||
                  status.phase == SocketConnectionPhase.disconnected
              ? status.message
              : null;
        });
        _startConnectTimeout();
      }
    } else {
      setState(() {
        _connecting = false;
        _connectionError = 'Giriş yapmış olman gerekiyor.';
      });
    }

    await _loadHistory();
    await _loadScheduledMessages();
  }

  /// Bu sohbete ait, henüz gönderilmemiş zamanlanmış mesajları çeker (#12
  /// anket maddesi) - ekran her açıldığında bir öncekiler hâlâ görünsün diye.
  Future<void> _loadScheduledMessages() async {
    try {
      final all = await _messaging.fetchScheduledMessages();
      if (!mounted) return;
      setState(() {
        _scheduledForThisChat
          ..clear()
          ..addAll(all.where((s) => s.toId == widget.friend.id));
      });
    } catch (_) {
      // Sessizce yok say - liste boş kalır, kritik bir işlev değil.
    }
  }

  void _handleFriendAccessRevoked(String userId, String reason) {
    if (!mounted || _accessRevoked || userId != widget.friend.id) return;
    _accessRevoked = true;
    _attachmentGuard.cancelCurrent();
    _sendGuard.cancelCurrent();
    _cancelPendingComposerOperations();
    _messaging.activeConversationFriendId = null;
    final message = reason == 'blocked'
        ? 'Bu sohbet artık kullanılamıyor.'
        : 'Arkadaşlık sona erdiği için sohbet kapatıldı.';
    navigateAfterAccessLoss(
      context,
      destination: (_) => const FriendsScreen(),
      message: message,
    );
  }

  void _wireMessagingCallbacks() {
    // Socket taşıma durumu merkezi AppConnectionController üzerinden izlenir.
    _messaging.onFriendAccessRevoked = _handleFriendAccessRevoked;
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
        _persistentItems
            .add(_ChatItem.fromMessage(message, isMe: message.fromId == _myId));
      });
      _scrollToBottom();
      // Bu sohbet ekranı zaten açık olduğu için gelen mesaj anlık "okundu"
      // sayılır (#24 anket maddesi) - kendi gönderdiğimiz mesajlar için
      // (Kendime Not) bu gereksiz ama zararsız.
      if (!_isNoteToSelf) _messaging.markConversationRead(widget.friend.id);
    };

    _messaging.onConversationRead = (messageIds, readAt) {
      if (!mounted) return;
      setState(() {
        for (final item in _persistentItems) {
          if (item.serverId != null && messageIds.contains(item.serverId)) {
            item.readAt = readAt;
          }
        }
      });
    };

    // "Yazıyor..." göstergesi (GECE_GELISTIRME madde 6) - yalnızca BU
    // sohbetin karşı tarafından gelen sinyal işleniyor (fromId eşleşmeli).
    // typing-stop hiç gelmezse (ör. karşı taraf uygulamayı aniden kapattı)
    // 4 saniyelik bir zaman aşımıyla kendiliğinden kayboluyor - göstergenin
    // sonsuza kadar takılı kalmasını önlemek için.
    _messaging.onTypingStart = (fromId) {
      if (!mounted || fromId != widget.friend.id) return;
      setState(() => _partnerTyping = true);
      _partnerTypingTimeout?.cancel();
      _partnerTypingTimeout = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _partnerTyping = false);
      });
    };
    _messaging.onTypingStop = (fromId) {
      if (!mounted || fromId != widget.friend.id) return;
      _partnerTypingTimeout?.cancel();
      setState(() => _partnerTyping = false);
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
      showSessionSnackBar(
        context,
        SnackBar(content: Text(message)),
        priority: SessionFeedbackPriority.normal,
      );
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

    // Anket oyu / tek seferlik fotoğraf açma gibi meta güncellemeleri.
    _messaging.onMessageUpdated = (message) {
      if (!mounted) return;
      setState(() {
        _findByServerId(_persistentItems, message.id)?.applyUpdate(message);
      });
    };

    _messaging.onScheduleMessageAck = (clientId, item) {
      if (!mounted) return;
      if (item.toId != widget.friend.id) return;
      setState(() => _scheduledForThisChat.add(item));
    };

    _messaging.onScheduleMessageError = (clientId, id, message) {
      if (!mounted) return;
      showSessionSnackBar(
        context,
        SnackBar(content: Text(message)),
        priority: SessionFeedbackPriority.normal,
      );
    };

    _messaging.onScheduleMessageCancelled = (id) {
      if (!mounted) return;
      setState(() => _scheduledForThisChat.removeWhere((s) => s.id == id));
    };

    _messaging.onScheduleMessageFired = (id, message) {
      if (!mounted) return;
      setState(() => _scheduledForThisChat.removeWhere((s) => s.id == id));
      if (message.toId != widget.friend.id) return;
      if (_persistentItems.any((i) => i.serverId == message.id)) return;
      setState(() {
        _persistentItems.add(_ChatItem.fromMessage(message, isMe: true));
      });
      _scrollToBottom();
    };

    _messaging.onScheduleMessageFailed = (id, message) {
      if (!mounted) return;
      setState(() => _scheduledForThisChat.removeWhere((s) => s.id == id));
      showSessionSnackBar(
        context,
        SnackBar(content: Text(message)),
        priority: SessionFeedbackPriority.normal,
      );
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
      showSessionSnackBar(
        context,
        SnackBar(content: Text(message)),
        priority: SessionFeedbackPriority.normal,
      );
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
      final page =
          await _friendsService.fetchConversationPage(widget.friend.id);
      if (!mounted) return;
      setState(() {
        _persistentItems
          ..clear()
          ..addAll(page.messages
              .map((m) => _ChatItem.fromMessage(m, isMe: m.fromId == _myId)));
        _hasMoreHistory = page.hasMore;
        _historyBefore = page.nextBefore;
        _loadingHistory = false;
      });
      _scrollToBottom();
      if (!_isNoteToSelf) _messaging.markConversationRead(widget.friend.id);
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _handleHistoryScroll() {
    if (_mode != _ChatMode.persistent ||
        !_hasMoreHistory ||
        _loadingOlderHistory ||
        !_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.pixels <= 180) {
      unawaited(_loadOlderHistory());
    }
  }

  Future<void> _loadOlderHistory() async {
    final before = _historyBefore;
    if (before == null || !_hasMoreHistory || _loadingOlderHistory) return;
    _loadingOlderHistory = true;
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;
    try {
      final page = await _friendsService.fetchConversationPage(
        widget.friend.id,
        before: before,
      );
      if (!mounted) return;
      final existingIds = _persistentItems
          .map((item) => item.serverId)
          .whereType<String>()
          .toSet();
      final older = page.messages
          .where((message) => !existingIds.contains(message.id))
          .map((message) => _ChatItem.fromMessage(
                message,
                isMe: message.fromId == _myId,
              ))
          .toList();
      setState(() {
        _persistentItems.insertAll(0, older);
        _hasMoreHistory = page.hasMore;
        _historyBefore = page.nextBefore;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final newExtent = _scrollController.position.maxScrollExtent;
        final target = oldOffset + (newExtent - oldExtent);
        _scrollController.jumpTo(
          target
              .clamp(0.0, _scrollController.position.maxScrollExtent)
              .toDouble(),
        );
      });
    } catch (_) {
      // Eski sayfanın yüklenememesi mevcut konuşmayı bozmaz; tekrar yukarı
      // kaydırıldığında yeniden denenir.
    } finally {
      _loadingOlderHistory = false;
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

  /// "Yazıyor..." göstergesi (GECE_GELISTIRME madde 6) - kendine not/bot
  /// sohbetinde göstermenin bir anlamı yok (karşı taraf kendimiz/gerçek bir
  /// kişi değil), bkz. onTap yorumları.
  void _onComposerChanged(String text) {
    if (_isNoteToSelf || widget.friend.id == 'merhaba-bot') return;
    if (text.trim().isEmpty) {
      _stopTypingDebounce?.cancel();
      if (_iAmTyping) {
        _iAmTyping = false;
        _messaging.sendTypingStop(widget.friend.id);
      }
      return;
    }
    if (!_iAmTyping) {
      _iAmTyping = true;
      _messaging.sendTypingStart(widget.friend.id);
    }
    _stopTypingDebounce?.cancel();
    _stopTypingDebounce = Timer(const Duration(seconds: 2), () {
      _iAmTyping = false;
      _messaging.sendTypingStop(widget.friend.id);
    });
  }

  Future<bool?> _confirmSendAnyway(String title, String message) {
    return showSessionDialog<bool>(
      deduplicationKey: 'chat_screen.dialog.1',
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title, style: TextStyle(color: AppColors.textPrimary)),
        content:
            Text(message, style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yine de gönder'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_accessRevoked) return;
    final sendGeneration = _sendGuard.begin();
    if (sendGeneration < 0) return;
    final text = _controller.text.trim();
    if (text.isEmpty || _connecting || _connectionError != null) return;

    // Gönderim öncesi uyarılar (Batch F) - kendine not/bot sohbetinde
    // anlamsız (karşı taraf yok), yalnızca gerçek bir kişiyle konuşurken
    // gösteriliyor. Hiçbiri ENGELLEMİYOR, yalnızca bir kez "emin misin?"
    // soruyor - kullanıcı onaylarsa aynen gönderiliyor.
    if (!_isNoteToSelf && widget.friend.id != 'merhaba-bot') {
      if (containsPersonalInfo(text)) {
        final proceed = await _confirmSendAnyway(
          'Kişisel bilgi paylaşıyor olabilirsin',
          'Mesajın bir telefon numarası veya adres içeriyor gibi görünüyor. '
              'Yine de göndermek istiyor musun?',
        );
        if (proceed != true ||
            !_sendGuard.isActive(sendGeneration) ||
            _accessRevoked) {
          return;
        }
      } else if (containsOffensiveLanguage(text)) {
        final proceed = await _confirmSendAnyway(
          'Bir an dur',
          'Bu mesaj sert bir dil içeriyor gibi görünüyor. Yine de göndermek '
              'istiyor musun?',
        );
        if (proceed != true ||
            !_sendGuard.isActive(sendGeneration) ||
            _accessRevoked) {
          return;
        }
      }
    }
    if (!mounted || !_sendGuard.isActive(sendGeneration) || _accessRevoked) {
      return;
    }

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
    _stopTypingDebounce?.cancel();
    if (_iAmTyping) {
      _iAmTyping = false;
      _messaging.sendTypingStop(widget.friend.id);
    }

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

  /// Metin dışındaki tüm zengin mesaj türlerinin (anket/konum/sticker/sesli/
  /// tek seferlik fotoğraf) ortak gönderim yolu - yalnızca "Kalıcı Sohbet"
  /// modunda kullanılır (bkz. _buildInputBar - ek menüsü yalnızca o modda
  /// gösteriliyor), "Kaybolan Mesajlar" bilerek sade metinle sınırlı.
  void _sendRich(
      {required String kind,
      required Map<String, dynamic> meta,
      String caption = ''}) {
    if (_accessRevoked || !mounted) return;
    final clientId =
        'c${_clientIdCounter++}_${DateTime.now().microsecondsSinceEpoch}';
    final item = _ChatItem(
      clientId: clientId,
      text: caption,
      isMe: true,
      createdAt: DateTime.now(),
      state: _SendState.sending,
      kind: kind,
      meta: meta,
    );
    setState(() => _persistentItems.add(item));
    _scrollToBottom();
    _messaging.sendPersistentMessage(
      toId: widget.friend.id,
      text: caption,
      clientId: clientId,
      kind: kind,
      meta: meta,
    );
  }

  void _showAttachmentSheet() {
    showSessionModalBottomSheet<void>(
      deduplicationKey: 'chat_screen.sheet.1',
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AttachmentSheet(
        onPoll: () {
          Navigator.pop(sheetContext);
          _openPollComposer();
        },
        onLocation: () {
          Navigator.pop(sheetContext);
          _shareLocation();
        },
        onSticker: () {
          Navigator.pop(sheetContext);
          _openStickerPicker();
        },
        onPhoto: () {
          Navigator.pop(sheetContext);
          _sendViewOncePhoto();
        },
        onSchedule: () {
          Navigator.pop(sheetContext);
          _openScheduleComposer();
        },
      ),
    );
  }

  /// Mesaj planlama (#12 anket maddesi) - metin + tarih/saat seçtirip
  /// sunucuya bir zamanlama kaydı gönderir (gerçek mesaj o an OLUŞMAZ, bkz.
  /// MessagingService.scheduleMessage).
  Future<void> _openScheduleComposer() async {
    final textController = TextEditingController(text: _controller.text);
    DateTime? picked = await showSessionDialog<DateTime>(
      deduplicationKey: 'chat_screen.dialog.2',
      context: context,
      builder: (dialogContext) => _ScheduleComposerDialog(
        textController: textController,
      ),
    );
    final text = textController.text.trim();
    textController.dispose();
    if (picked == null || !mounted || text.isEmpty) return;

    final clientId =
        'sched${_clientIdCounter++}_${DateTime.now().microsecondsSinceEpoch}';
    _messaging.scheduleMessage(
      toId: widget.friend.id,
      text: text,
      clientId: clientId,
      sendAt: picked,
    );
    if (_controller.text.trim() == text) _controller.clear();
    showSessionSnackBar(
      context,
      SnackBar(
          content:
              Text('Mesaj ${_formatScheduleTime(picked)} için planlandı.')),
      priority: SessionFeedbackPriority.normal,
    );
  }

  String _formatScheduleTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'bugün $time';
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} $time';
  }

  /// Bu sohbete ait bekleyen zamanlanmış mesajların listesi - iptal etme
  /// imkanıyla birlikte.
  void _showScheduledSheet() {
    showSessionModalBottomSheet<void>(
      deduplicationKey: 'chat_screen.sheet.2',
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Zamanlanmış mesajlar',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (_scheduledForThisChat.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('Bekleyen zamanlanmış mesaj yok.',
                        style: TextStyle(color: AppColors.textMuted)),
                  )
                else
                  ..._scheduledForThisChat.map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.text,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(_formatScheduleTime(s.sendAt),
                                      style: TextStyle(
                                          color: AppColors.primaryLight,
                                          fontSize: 11)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded,
                                  color: AppColors.textMuted, size: 18),
                              onPressed: () {
                                _messaging.cancelScheduledMessage(s.id);
                                setSheetState(() => _scheduledForThisChat
                                    .removeWhere((e) => e.id == s.id));
                              },
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPollComposer() {
    showSessionDialog<void>(
      deduplicationKey: 'chat_screen.dialog.3',
      context: context,
      builder: (dialogContext) => _PollComposerDialog(
        onSubmit: (question, options) {
          Navigator.pop(dialogContext);
          _sendRich(
              kind: 'poll', meta: {'question': question, 'options': options});
        },
      ),
    );
  }

  void _openStickerPicker() {
    showSessionModalBottomSheet<void>(
      deduplicationKey: 'chat_screen.sheet.3',
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: kStickerCatalog
                .map((s) => GestureDetector(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _sendRich(kind: 'sticker', meta: {'stickerId': s.id});
                      },
                      child: Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child:
                            Text(s.emoji, style: const TextStyle(fontSize: 32)),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _shareLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showSnack('Konum izni verilmeden paylaşılamaz.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showSnack('Cihazının konum servisi kapalı.');
      return;
    }
    _showSnack('Konum alınıyor...');
    try {
      // LocationAccuracy.low - GPS/"Konum Doğruluğu" çözümleme diyaloğu
      // gerektirmeyen ağ-tabanlı konum kullanır (bazı cihazlarda .medium/.high
      // Play Services'in ayar çözümleme akışında asılı kalabiliyor) - basit
      // bir "konumumu paylaş" özelliği için zaten yeterli hassasiyette.
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 15));
      _sendRich(
          kind: 'location',
          meta: {'lat': position.latitude, 'lng': position.longitude});
    } catch (_) {
      _showSnack('Konum alınamadı, tekrar dene.');
    }
  }

  Future<void> _sendViewOncePhoto() async {
    if (_accessRevoked) return;
    final operationGeneration = _attachmentGuard.begin();
    if (operationGeneration < 0) return;
    final source = await showSessionModalBottomSheet<ImageSource>(
      deduplicationKey: 'chat_screen.sheet.4',
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
              leading: Icon(Icons.camera_alt_outlined,
                  color: AppColors.textSecondary),
              title: Text('Kameradan çek',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading:
                  Icon(Icons.photo_outlined, color: AppColors.textSecondary),
              title: Text('Galeriden seç',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null ||
        !_attachmentGuard.isActive(operationGeneration) ||
        _accessRevoked) {
      return;
    }

    final picker = ImagePicker();
    XFile? picked;
    try {
      picked = await picker.pickImage(
          source: source, maxWidth: 1280, imageQuality: 80);
    } catch (_) {
      _showSnack('Fotoğraf alınamadı, tekrar dene.');
      return;
    }
    if (picked == null ||
        !_attachmentGuard.isActive(operationGeneration) ||
        _accessRevoked) {
      return;
    }

    if (!mounted ||
        !_attachmentGuard.isActive(operationGeneration) ||
        _accessRevoked) {
      return;
    }
    setState(() => _uploadingAttachment = true);
    try {
      final result = await _messaging.uploadChatMedia(File(picked.path),
          mimeType: 'image/jpeg');
      if (!mounted ||
          !_attachmentGuard.isActive(operationGeneration) ||
          _accessRevoked) {
        await _discardUnsentUpload(result);
        return;
      }
      _sendRich(kind: 'view_once_photo', meta: {'url': result['url']});
    } catch (e) {
      if (mounted &&
          _attachmentGuard.isActive(operationGeneration) &&
          !_accessRevoked) {
        _showSnack(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && _attachmentGuard.isActive(operationGeneration)) {
        setState(() => _uploadingAttachment = false);
      }
    }
  }

  Future<void> _discardUnsentUpload(Map<String, dynamic>? result) async {
    final url = result?['url'];
    if (url is! String || url.isEmpty) return;
    await _messaging.discardUploadedChatMedia(url);
  }

  Future<void> _startVoiceRecording() async {
    if (_accessRevoked) return;
    if (!await _audioRecorder.hasPermission()) {
      _showSnack('Ses kaydı için mikrofon izni gerekiyor.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    _recordingStartedAt = DateTime.now();
    _recordingTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _recordingElapsed = DateTime.now().difference(_recordingStartedAt!);
      });
    });
    setState(() => _isRecordingVoice = true);
  }

  Future<void> _stopVoiceRecordingAndSend({required bool cancel}) async {
    final operationGeneration = _attachmentGuard.begin();
    if (operationGeneration < 0) return;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    final path = await _audioRecorder.stop();
    final duration = _recordingElapsed;
    if (!mounted || !_attachmentGuard.isActive(operationGeneration)) return;
    setState(() {
      _isRecordingVoice = false;
      _recordingElapsed = Duration.zero;
    });
    if (cancel || path == null) return;
    if (duration.inMilliseconds < 800) {
      _showSnack('Sesli mesaj çok kısa, tekrar dene.');
      return;
    }
    setState(() => _uploadingAttachment = true);
    try {
      final result =
          await _messaging.uploadChatMedia(File(path), mimeType: 'audio/mp4');
      if (!mounted ||
          !_attachmentGuard.isActive(operationGeneration) ||
          _accessRevoked) {
        await _discardUnsentUpload(result);
        return;
      }
      _sendRich(kind: 'voice', meta: {
        'url': result['url'],
        'durationMs': result['durationMs'] ?? duration.inMilliseconds,
      });
    } catch (e) {
      if (mounted &&
          _attachmentGuard.isActive(operationGeneration) &&
          !_accessRevoked) {
        _showSnack(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && _attachmentGuard.isActive(operationGeneration)) {
        setState(() => _uploadingAttachment = false);
      }
    }
  }

  Future<void> _toggleVoicePlayback(_ChatItem item) async {
    final url = item.meta?['url'] as String?;
    if (url == null) return;
    if (_playingVoiceMessageId == item.serverId) {
      await _audioPlayer.stop();
      setState(() => _playingVoiceMessageId = null);
      return;
    }
    await _audioPlayer.stop();
    setState(() => _playingVoiceMessageId = item.serverId);
    await _audioPlayer.play(UrlSource(url));
    _audioPlayer.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _playingVoiceMessageId = null);
    });
  }

  Future<void> _openViewOncePhoto(_ChatItem item) async {
    final viewed = item.meta?['viewed'] == true;
    if (!item.isMe && !viewed) {
      _messaging.openViewOncePhoto(item.serverId!);
    }
    final url = item.meta?['url'] as String?;
    if (url == null) {
      _showSnack(item.isMe
          ? 'Bu fotoğraf zaten görüntülendi.'
          : 'Fotoğraf artık görüntülenemiyor.');
      return;
    }
    if (!mounted) return;
    await showSessionDialog<void>(
      deduplicationKey: 'chat_screen.dialog.4',
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.pop(dialogContext),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    showSessionSnackBar(
      context,
      SnackBar(content: Text(message)),
      priority: SessionFeedbackPriority.normal,
    );
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final fallback =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  void _startEdit(_ChatItem item) {
    final controller = TextEditingController(text: item.text);
    showSessionDialog<void>(
      deduplicationKey: 'chat_screen.dialog.5',
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Mesajı düzenle',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: TextStyle(color: AppColors.textPrimary),
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
    showSessionDialog<void>(
      deduplicationKey: 'chat_screen.dialog.6',
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title:
            Text('Mesajı sil', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Bu mesaj herkesten (karşı tarafın ekranından da) silinecek.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (item.serverId != null) {
                _messaging.deleteMessage(item.serverId!);
              }
            },
            child: Text('Sil', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  /// Gerçek zamanlı mesaj çevirisi (GECE_GELISTIRME madde 5) - hedef dil
  /// olarak cihazın/uygulamanın o an gösterildiği dili kullanıyoruz ("bu
  /// mesajı BENİM anlayabileceğim dile çevir" mantığı). Sunucu
  /// TRANSLATE_API_KEY ile yapılandırılmadıysa AuthService.translateText()
  /// bir AuthException fırlatır (bkz. orada) - bu durumda kullanıcıya
  /// sunucunun döndürdüğü "çeviri şu an yapılandırılmamış" mesajı gösterilir.
  Future<void> _translateMessage(_ChatItem item) async {
    final targetLang = Localizations.localeOf(context).languageCode;
    showSessionDialog<void>(
      deduplicationKey: 'chat_screen.dialog.7',
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Text('Çevriliyor...',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
    try {
      final translated =
          await AuthService().translateText(item.text, targetLang);
      if (!mounted) return;
      Navigator.pop(context);
      showSessionDialog<void>(
        deduplicationKey: 'chat_screen.dialog.8',
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Çeviri', style: TextStyle(color: AppColors.textPrimary)),
          content: Text(translated,
              style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat')),
          ],
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showSessionSnackBar(
        context,
        SnackBar(content: Text(e.message)),
        priority: SessionFeedbackPriority.normal,
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      showSessionSnackBar(
        context,
        const SnackBar(content: Text('Çeviri yapılamadı, tekrar dene.')),
        priority: SessionFeedbackPriority.normal,
      );
    }
  }

  void _showMessageActions(_ChatItem item) {
    if (item.deleted || item.serverId == null) return;
    showSessionModalBottomSheet<void>(
      deduplicationKey: 'chat_screen.sheet.5',
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
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 26)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            Divider(color: AppColors.divider, height: 1),
            ListTile(
              leading: Icon(Icons.reply, color: AppColors.textSecondary),
              title: Text('Yanıtla',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyingTo = item);
              },
            ),
            if (_translationEnabled && item.kind == 'text')
              ListTile(
                leading: Icon(Icons.translate_rounded,
                    color: AppColors.textSecondary),
                title: Text('Çevir',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _translateMessage(item);
                },
              ),
            ListTile(
              leading: Icon(
                  item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: AppColors.textSecondary),
              title: Text(item.pinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                  style: TextStyle(color: AppColors.textPrimary)),
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
              if (item.kind == 'text')
                ListTile(
                  leading:
                      Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                  title: Text('Düzenle',
                      style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startEdit(item);
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text('Sil', style: TextStyle(color: AppColors.danger)),
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

  Future<void> _cancelPendingComposerOperations() async {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    if (_isRecordingVoice) {
      try {
        await _audioRecorder.cancel();
      } catch (_) {
        try {
          await _audioRecorder.stop();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _recordingElapsed = Duration.zero;
      _uploadingAttachment = false;
    });
  }

  @override
  void dispose() {
    AuthService().sessionState.removeListener(_handleSessionChanged);
    AppConnectionController().state.removeListener(_handleConnectionChanged);
    // MessagingService artık uygulama boyunca kalıcı (bkz. orada) - yalnızca
    // bu ekranın callback'lerini bırakıyoruz, ALTTAKI BAĞLANTIYA
    // dokunmuyoruz (böylece bu sohbetten çıkılsa bile başka bir yerden
    // gelecek arkadaşlık/mesaj/arama olayları çalışmaya devam eder).
    _messaging.detachScreenCallbacks();
    _cancelConnectTimeout();
    _partnerTypingTimeout?.cancel();
    _stopTypingDebounce?.cancel();
    if (_iAmTyping) _messaging.sendTypingStop(widget.friend.id);
    _controller.dispose();
    _scrollController.dispose();
    _attachmentGuard.close();
    _sendGuard.close();
    _recordingTicker?.cancel();
    if (_isRecordingVoice) {
      _audioRecorder.cancel();
    }
    _audioRecorder.dispose();
    _audioPlayer.dispose();
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
        toolbarHeight: 72,
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.22),
                  backgroundImage:
                      !_isNoteToSelf && widget.friend.photoUrl != null
                          ? NetworkImage(widget.friend.photoUrl!)
                          : null,
                  child: _isNoteToSelf
                      ? Icon(Icons.sticky_note_2_outlined,
                          color: AppColors.secondary, size: 19)
                      : widget.friend.photoUrl == null
                          ? Text(
                              widget.friend.displayName.isNotEmpty
                                  ? widget.friend.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.w800),
                            )
                          : null,
                ),
                if (!_isNoteToSelf && widget.friend.online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isNoteToSelf ? 'Kendime Not' : widget.friend.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subheading.copyWith(fontSize: 16),
                  ),
                  Text(
                    _partnerTyping
                        ? 'yazıyor...'
                        : _isNoteToSelf
                            ? 'yalnızca sen görebilirsin'
                            : widget.friend.online
                                ? 'çevrimiçi'
                                : 'sohbeti sürdür',
                    style: TextStyle(
                      color: _partnerTyping || widget.friend.online
                          ? AppColors.secondary
                          : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.background.withValues(alpha: 0.94),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_mode == _ChatMode.persistent && _scheduledForThisChat.isNotEmpty)
            IconButton(
              tooltip: 'Zamanlanmış mesajlar',
              onPressed: _showScheduledSheet,
              icon: Badge(
                label: Text('${_scheduledForThisChat.length}'),
                backgroundColor: AppColors.primary,
                child: Icon(Icons.schedule_send_rounded,
                    color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              if (!_isNoteToSelf)
                _buildModeToggle()
              else
                const SizedBox(height: 88),
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
          Icon(Icons.push_pin, color: AppColors.primaryLight, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _previewTextFor(pinned.last),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
          if (pinned.length > 1)
            Text('+${pinned.length - 1}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
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
        color: AppColors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _previewTextFor(replying),
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

  Widget _buildModeToggle() {
    // bkz. profile_screen.dart'taki aynı düzeltme - extendBodyBehindAppBar:
    // true yüzünden gövde şeffaf AppBar'ın arkasına kadar uzuyor. SafeArea
    // yalnızca durum çubuğunu hesaba katıyor, AppBar'ın kendi
    // (kToolbarHeight) yüksekliğini değil - bu yüzden Column'un İLK öğesi
    // olan bu mod anahtarı ("Kalıcı Sohbet"/"Kaybolan Mesajlar")
    // AppBar'ın dokunuş yakalayan bölgesiyle çakışıyordu.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 84, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceBorder),
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
          gradient: selected ? AppGradients.warmSignal : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textMuted,
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
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
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
            style: TextStyle(color: AppColors.textFaint, fontSize: 13),
          ),
        ),
      );
    }

    final showHistoryLoader = _mode == _ChatMode.persistent &&
        (_hasMoreHistory || _loadingOlderHistory);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: items.length + (showHistoryLoader ? 1 : 0),
      itemBuilder: (context, index) {
        if (showHistoryLoader && index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: _loadingOlderHistory
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
        return _buildBubble(items[itemIndex]);
      },
    );
  }

  _ChatItem? _findReplySource(String? replyToId) {
    if (replyToId == null) return null;
    return _findByServerId(_persistentItems, replyToId);
  }

  /// Yanıt önizlemesi / sabitlenmiş mesaj çubuğu gibi tek satırlık
  /// özetlerde kullanılan, türe göre okunabilir kısa metin (bkz. server.js
  /// notificationPreviewFor - aynı fikir, istemci tarafı).
  String _previewTextFor(_ChatItem item) {
    if (item.deleted) return 'Silinmiş mesaj';
    switch (item.kind) {
      case 'poll':
        return '📊 ${item.meta?['question'] as String? ?? 'Anket'}';
      case 'location':
        return '📍 Konum';
      case 'sticker':
        return '${stickerEmojiFor(item.meta?['stickerId'] as String? ?? '')} Sticker';
      case 'voice':
        return '🎤 Sesli mesaj';
      case 'view_once_photo':
        return '📷 Tek seferlik fotoğraf';
      default:
        return item.text;
    }
  }

  Widget _buildBubble(_ChatItem item) {
    final isPersistent = _mode == _ChatMode.persistent;
    final replySource = isPersistent ? _findReplySource(item.replyToId) : null;
    final isSticker = item.kind == 'sticker' && !item.deleted;

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
              padding: isSticker
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              // Kuyruklu (asimetrik köşe) balon - jenerik tek-tip yuvarlak
              // köşe yerine, konuşmacıya göre bir köşe daha keskin (gönderen
              // tarafın alt-dış köşesi), gerçek mesajlaşma uygulamalarındaki
              // "kuyruk" hissini taklit ediyor.
              decoration: isSticker
                  ? null
                  : BoxDecoration(
                      gradient: item.isMe ? AppGradients.warmSignal : null,
                      color: item.isMe ? null : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(item.isMe ? 16 : 4),
                        bottomRight: Radius.circular(item.isMe ? 4 : 16),
                      ),
                      border: item.isMe
                          ? null
                          : Border.all(color: AppColors.surfaceBorder),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.pinned && !isSticker)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Icon(Icons.push_pin,
                          size: 12,
                          color: item.isMe
                              ? Colors.white70
                              : AppColors.textSecondary),
                    ),
                  if (replySource != null && !isSticker)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                            left: BorderSide(
                                color: item.isMe
                                    ? Colors.white54
                                    : AppColors.textMuted,
                                width: 2)),
                      ),
                      child: Text(
                        _previewTextFor(replySource),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: item.isMe
                                ? Colors.white.withValues(alpha: 0.75)
                                : AppColors.textSecondary,
                            fontSize: 11),
                      ),
                    ),
                  _buildContentForKind(item),
                  if (item.editedAt != null &&
                      !item.deleted &&
                      item.kind == 'text')
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('düzenlendi',
                          style: TextStyle(
                              color: item.isMe
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : AppColors.textMuted,
                              fontSize: 10)),
                    ),
                ],
              ),
            ),
            if (item.reactions.isNotEmpty && !item.deleted)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.08),
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
                        : AppColors.textFaint,
                    fontSize: 10,
                  ),
                ),
              ),
            if (item.isMe &&
                item.state == _SendState.sent &&
                !item.deleted &&
                !_isNoteToSelf &&
                _mode == _ChatMode.persistent)
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 4),
                child: Icon(
                  item.readAt != null
                      ? Icons.done_all_rounded
                      : Icons.done_rounded,
                  size: 14,
                  color: item.readAt != null
                      ? AppColors.secondaryLight
                      : AppColors.textFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentForKind(_ChatItem item) {
    final onBubbleColor = item.isMe ? Colors.white : AppColors.textPrimary;
    if (item.deleted) {
      return Text(
        'Bu mesaj silindi',
        style: TextStyle(
            color: item.isMe ? Colors.white70 : AppColors.textSecondary,
            fontSize: 14,
            fontStyle: FontStyle.italic),
      );
    }
    switch (item.kind) {
      case 'poll':
        return _buildPollContent(item);
      case 'location':
        return _buildLocationContent(item);
      case 'sticker':
        return _buildStickerContent(item);
      case 'voice':
        return _buildVoiceContent(item);
      case 'view_once_photo':
        return _buildViewOncePhotoContent(item);
      default:
        return Text(item.text,
            style: TextStyle(color: onBubbleColor, fontSize: 14));
    }
  }

  Widget _buildPollContent(_ChatItem item) {
    final meta = item.meta ?? const {};
    final question = meta['question'] as String? ?? '';
    final options = (meta['options'] as List?)
            ?.cast<dynamic>()
            .map((e) => e.toString())
            .toList() ??
        const <String>[];
    final votesRaw = meta['votes'];
    final votes = votesRaw is Map
        ? Map<String, dynamic>.from(votesRaw)
        : <String, dynamic>{};
    final total = votes.length;
    final myVote = votes[_myId] is int ? votes[_myId] as int : null;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 16,
                  color: item.isMe ? Colors.white70 : AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(question,
                    style: TextStyle(
                        color: item.isMe ? Colors.white : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _pollOption(item, i, options[i], votes, total, myVote),
            ),
          Text('$total oy',
              style: TextStyle(
                  color: item.isMe
                      ? Colors.white.withValues(alpha: 0.5)
                      : AppColors.textMuted,
                  fontSize: 10)),
        ],
      ),
    );
  }

  Widget _pollOption(_ChatItem item, int index, String label,
      Map<String, dynamic> votes, int total, int? myVote) {
    final count = votes.values.where((v) => v == index).length;
    final pct = total == 0 ? 0.0 : count / total;
    final selected = myVote == index;
    return GestureDetector(
      onTap: item.serverId == null
          ? null
          : () => _messaging.votePoll(
              messageId: item.serverId!, optionIndex: index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Container(
                height: 34,
                color: AppColors.textPrimary.withValues(alpha: 0.08)),
            FractionallySizedBox(
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(
                height: 34,
                color: (selected ? AppColors.secondary : AppColors.primaryLight)
                    .withValues(alpha: 0.45),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.check_circle,
                            size: 14,
                            color: item.isMe
                                ? Colors.white
                                : AppColors.textPrimary),
                      ),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color:
                              item.isMe ? Colors.white : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    Text('${(pct * 100).round()}%',
                        style: TextStyle(
                            color: item.isMe
                                ? Colors.white70
                                : AppColors.textSecondary,
                            fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationContent(_ChatItem item) {
    final meta = item.meta ?? const {};
    final lat = (meta['lat'] as num?)?.toDouble();
    final lng = (meta['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      return Text('📍 Konum',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14));
    }
    return GestureDetector(
      onTap: () => _openInMaps(lat, lng),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.secondary.withValues(alpha: 0.28),
              AppColors.primary.withValues(alpha: 0.28),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.15),
                  shape: BoxShape.circle),
              child: Icon(Icons.location_on_rounded,
                  color: AppColors.textPrimary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Konum paylaşıldı',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                  const SizedBox(height: 2),
                  Text('${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 10)),
                  const SizedBox(height: 4),
                  Text('Haritada aç →',
                      style: TextStyle(
                          color: AppColors.secondaryLight,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerContent(_ChatItem item) {
    final stickerId = item.meta?['stickerId'] as String? ?? '';
    return Text(stickerEmojiFor(stickerId),
        style: const TextStyle(fontSize: 62));
  }

  Widget _buildVoiceContent(_ChatItem item) {
    final meta = item.meta ?? const {};
    final durationMs = (meta['durationMs'] as num?)?.toInt() ?? 0;
    final seconds = (durationMs / 1000).round();
    final isPlaying =
        item.serverId != null && _playingVoiceMessageId == item.serverId;
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          GestureDetector(
            onTap:
                item.serverId == null ? null : () => _toggleVoicePlayback(item),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: item.isMe
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppColors.textPrimary.withValues(alpha: 0.12),
              child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: item.isMe ? Colors.white : AppColors.textPrimary,
                  size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 20,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(
                      16,
                      (i) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: 5 + (i % 5) * 3.0,
                          decoration: BoxDecoration(
                            color: (item.isMe
                                    ? Colors.white
                                    : AppColors.textPrimary)
                                .withValues(alpha: isPlaying ? 0.9 : 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('$seconds sn',
                    style: TextStyle(
                        color: item.isMe
                            ? Colors.white.withValues(alpha: 0.6)
                            : AppColors.textSecondary,
                        fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewOncePhotoContent(_ChatItem item) {
    final viewed = item.meta?['viewed'] == true;
    if (!item.isMe && !viewed) {
      return GestureDetector(
        onTap: () => _openViewOncePhoto(item),
        child: Container(
          width: 150,
          height: 150,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.35),
                AppColors.secondary.withValues(alpha: 0.35),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_rounded,
                  color: AppColors.textPrimary, size: 26),
              const SizedBox(height: 6),
              Text('Görmek için dokun',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Tek seferlik',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            ],
          ),
        ),
      );
    }
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: (item.isMe ? Colors.white : AppColors.textPrimary)
            .withValues(alpha: 0.06),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.isMe && !viewed
                ? Icons.lock_clock_outlined
                : Icons.check_circle_outline,
            color: item.isMe ? Colors.white38 : AppColors.textFaint,
            size: 26,
          ),
          const SizedBox(height: 6),
          Text(
            item.isMe && !viewed ? 'Gönderildi · tek seferlik' : 'Görüntülendi',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: item.isMe ? Colors.white38 : AppColors.textFaint,
                fontSize: 10),
          ),
        ],
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
    final canAttach = _mode == _ChatMode.persistent && !_uploadingAttachment;

    if (_isRecordingVoice) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            children: [
              const _PulsingDot(),
              const SizedBox(width: 10),
              Text(
                _formatDuration(_recordingElapsed),
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _stopVoiceRecordingAndSend(cancel: true),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child:
                      Icon(Icons.close_rounded, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _stopVoiceRecordingAndSend(cancel: false),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppGradients.warmSignal,
                    boxShadow: neonGlow(
                      AppColors.primary,
                      opacity: 0.26,
                      blurRadius: 15,
                      spreadRadius: 0,
                    ),
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final showMicInstead = canAttach && _controller.text.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          if (canAttach)
            GestureDetector(
              onTap: _uploadingAttachment ? null : _showAttachmentSheet,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: _uploadingAttachment
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primaryLight),
                      )
                    : Icon(Icons.add_rounded, color: AppColors.textSecondary),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              onChanged: (text) {
                setState(() {});
                _onComposerChanged(text);
              },
              decoration: InputDecoration(
                hintText: _isNoteToSelf
                    ? 'Kendine bir not yaz...'
                    : _mode == _ChatMode.persistent
                        ? 'Mesaj yaz...'
                        : 'Kaybolan mesaj yaz...',
                hintStyle: TextStyle(color: AppColors.textFaint),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: AppColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: AppColors.surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      BorderSide(color: AppColors.secondary, width: 1.2),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: showMicInstead ? _startVoiceRecording : _send,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppGradients.warmSignal,
                boxShadow: neonGlow(
                  AppColors.primary,
                  opacity: 0.26,
                  blurRadius: 15,
                  spreadRadius: 0,
                ),
              ),
              child: Icon(
                showMicInstead ? Icons.mic_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Sesli mesaj kaydı sırasında gösterilen, yavaşça yanıp sönen kırmızı
/// nokta - kayıt durumunu net bir görsel geri bildirimle gösterir.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
      child: CircleAvatar(radius: 6, backgroundColor: AppColors.danger),
    );
  }
}

/// Sohbette "+" butonuna basınca açılan ek menüsü - Telegram/WhatsApp'ın
/// ikon+etiket ızgara deseninden esinlenildi, uygulamanın mevcut düz liste
/// menülerinden bilerek farklı/daha canlı tasarlandı.
class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onPoll;
  final VoidCallback onLocation;
  final VoidCallback onSticker;
  final VoidCallback onPhoto;
  final VoidCallback onSchedule;

  const _AttachmentSheet({
    required this.onPoll,
    required this.onLocation,
    required this.onSticker,
    required this.onPhoto,
    required this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.textFaint,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runSpacing: 16,
              children: [
                _attachTile(
                    icon: Icons.bar_chart_rounded,
                    label: 'Anket',
                    color: AppColors.primary,
                    onTap: onPoll),
                _attachTile(
                    icon: Icons.location_on_rounded,
                    label: 'Konum',
                    color: AppColors.secondary,
                    onTap: onLocation),
                _attachTile(
                    icon: Icons.emoji_emotions_rounded,
                    label: 'Sticker',
                    color: AppColors.warning,
                    onTap: onSticker),
                _attachTile(
                    icon: Icons.camera_alt_rounded,
                    label: 'Fotoğraf',
                    color: AppColors.danger,
                    onTap: onPhoto),
                _attachTile(
                    icon: Icons.schedule_send_rounded,
                    label: 'Zamanla',
                    color: AppColors.secondaryLight,
                    onTap: onSchedule),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachTile(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return SizedBox(
      width: 68,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Anket oluşturma diyaloğu - 2-8 arası dinamik seçenek alanı.
class _PollComposerDialog extends StatefulWidget {
  final void Function(String question, List<String> options) onSubmit;
  const _PollComposerDialog({required this.onSubmit});

  @override
  State<_PollComposerDialog> createState() => _PollComposerDialogState();
}

class _PollComposerDialogState extends State<_PollComposerDialog> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 8) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() => _optionControllers.removeAt(index).dispose());
  }

  void _submit() {
    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (question.isEmpty || options.length < 2) return;
    widget.onSubmit(question, options);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      title:
          Text('Anket oluştur', style: TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _questionController,
                autofocus: true,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(hintText: 'Soru...'),
                maxLength: 200,
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < _optionControllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _optionControllers[i],
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration:
                              InputDecoration(hintText: 'Seçenek ${i + 1}'),
                          maxLength: 80,
                          buildCounter: (_,
                                  {required currentLength,
                                  required isFocused,
                                  maxLength}) =>
                              null,
                        ),
                      ),
                      if (_optionControllers.length > 2)
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline,
                              color: AppColors.textFaint, size: 20),
                          onPressed: () => _removeOption(i),
                        ),
                    ],
                  ),
                ),
              if (_optionControllers.length < 8)
                TextButton.icon(
                  onPressed: _addOption,
                  icon:
                      Icon(Icons.add, color: AppColors.primaryLight, size: 18),
                  label: Text('Seçenek ekle',
                      style: TextStyle(color: AppColors.primaryLight)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Oluştur'),
        ),
      ],
    );
  }
}

/// Mesaj planlama (#12 anket maddesi) diyaloğu - metin + tarih/saat seçimi.
/// Onaylanınca seçilen [DateTime]'ı (yerel saat) Navigator.pop ile döner,
/// gerçek zamanlama isteğini çağıran taraf (_openScheduleComposer) gönderir.
class _ScheduleComposerDialog extends StatefulWidget {
  final TextEditingController textController;
  const _ScheduleComposerDialog({required this.textController});

  @override
  State<_ScheduleComposerDialog> createState() =>
      _ScheduleComposerDialogState();
}

class _ScheduleComposerDialogState extends State<_ScheduleComposerDialog> {
  DateTime? _picked;

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
    );
    if (time == null || !mounted) return;
    setState(() {
      _picked =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String _formatPicked(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _submit() {
    if (widget.textController.text.trim().isEmpty || _picked == null) return;
    if (_picked!.isBefore(DateTime.now().add(const Duration(seconds: 55)))) {
      showSessionSnackBar(
        context,
        const SnackBar(
            content: Text('Gönderim zamanı en az 1 dakika sonrası olmalı.')),
        priority: SessionFeedbackPriority.normal,
      );
      return;
    }
    Navigator.pop(context, _picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      title: Text('Mesajı zamanla',
          style: TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.textController,
              autofocus: true,
              maxLines: 4,
              minLines: 1,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Mesajını yaz...'),
              maxLength: 2000,
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDateTime,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        color: AppColors.primaryLight, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _picked == null
                          ? 'Tarih ve saat seç'
                          : _formatPicked(_picked!),
                      style: TextStyle(
                          color: _picked == null
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Planla'),
        ),
      ],
    );
  }
}
