import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'auth_service.dart';
import 'push_notification_service.dart';
import 'webrtc_service.dart' show signalingServerUrl;

/// Kalıcı bir sohbet mesajı (sunucuda saklanır - bkz.
/// signaling_server/messageStore.js).
class PersistentMessage {
  final String id;
  final String fromId;
  final String toId;
  final String text;
  final DateTime createdAt;
  final String kind;
  final Map<String, dynamic>? meta;
  final String? replyToId;
  final DateTime? editedAt;
  final bool deleted;
  final bool pinned;
  // userId -> emoji. Bir kullanıcının bir mesaja aynı anda tek tepkisi olur.
  final Map<String, String> reactions;

  const PersistentMessage({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.text,
    required this.createdAt,
    this.kind = 'text',
    this.meta,
    this.replyToId,
    this.editedAt,
    this.deleted = false,
    this.pinned = false,
    this.reactions = const {},
  });

  factory PersistentMessage.fromJson(Map<String, dynamic> json) =>
      PersistentMessage(
        id: json['id'] as String,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        kind: json['kind'] as String? ?? 'text',
        meta: json['meta'] == null
            ? null
            : Map<String, dynamic>.from(json['meta'] as Map),
        replyToId: json['replyToId'] as String?,
        editedAt: json['editedAt'] == null
            ? null
            : DateTime.parse(json['editedAt'] as String),
        deleted: json['deleted'] as bool? ?? false,
        pinned: json['pinned'] as bool? ?? false,
        reactions: json['reactions'] == null
            ? const {}
            : Map<String, String>.from(json['reactions'] as Map),
      );
}

/// Kaybolan (ephemeral) bir mesaj - sunucuda hiç saklanmaz, yalnızca anlık
/// iletilir. Bu yüzden PersistentMessage'dan farklı olarak "toId" alanı
/// yok - zaten sadece bize gelen mesajlar bu tipte oluşuyor.
class DisappearingMessage {
  final String id;
  final String fromId;
  final String fromDisplayName;
  final String text;
  final DateTime createdAt;

  const DisappearingMessage({
    required this.id,
    required this.fromId,
    required this.fromDisplayName,
    required this.text,
    required this.createdAt,
  });
}

/// Uygulama boyunca KALICI, tek bir mesajlaşma soket bağlantısı (singleton -
/// AuthService/PushNotificationService ile aynı desen).
///
/// ÖNCEDEN bu bağlantı yalnızca Sohbet ekranı açıkken kuruluyor, ekran
/// kapanınca kesiliyordu - bu yüzden karşı taraf tam o sohbeti açık
/// tutmuyorsa mesaj anlık ulaşmıyordu, üstelik karşı tarafın BAŞKA bir
/// bağlantısı (ör. Arkadaşlar ekranı) açıksa sunucu onu yanlışlıkla
/// "çevrimiçi" sayıp push bildirimi de göndermiyordu - mesaj sessizce
/// kaybolmuş gibi görünüyordu. Artık bağlantı, oturum açılır açılmaz BİR
/// KEZ kurulur (bkz. splash_screen.dart, login_screen.dart) ve çıkış
/// yapılana kadar açık kalır - ekranlar yalnızca kendi UI callback'lerini
/// bu paylaşılan bağlantıya takıp çıkarır (bkz. connectIfNeeded(),
/// detachScreenCallbacks()).
///
/// "Kaybolan mesajlar" özelliği doğası gereği (bkz. server.js
/// disappearing-message-send) hâlâ yalnızca karşı taraf o an gerçekten
/// sohbet ekranında ([activeConversationFriendId] eşleşiyorsa) anlık
/// iletilir - bu BİLEREK böyle, kalıcı bir iz bırakmaması özelliğin amacı.
/// "Kalıcı sohbet" mesajları ise artık ekrandan bağımsız olarak sunucuda
/// saklanır VE ekran açık değilse yerel bir bildirimle haber verilir (bkz.
/// aşağıdaki 'persistent-message-received' dinleyicisi).
class MessagingService {
  MessagingService._internal();
  static final MessagingService instance = MessagingService._internal();
  factory MessagingService() => instance;

  io.Socket? _socket;
  bool _connecting = false;
  // reconnect() BİLEREK mevcut soketi kapatıp yenisini kurduğunda, o
  // kapatma da normal bir 'disconnect' event'i tetikler (sebebi 'io client
  // disconnect' olur) - bu PLANLI bir yeniden bağlanma, bir arıza değil.
  // Bu bayrak sayesinde o özel durumda kullanıcıya "Bağlantı kesildi..."
  // gibi alarm verici bir mesaj GÖSTERMİYORUZ, yalnızca logluyoruz - bkz.
  // reconnect() ve onDisconnect callback'i.
  bool _suppressNextDisconnectNotice = false;

  /// O an ekranda açık olan sohbetin karşı taraf id'si (bkz.
  /// chat_screen.dart). Gelen bir kalıcı mesaj bu kişiden DEĞİLSE, ilgili
  /// sohbet ekranı açık olmadığı anlamına gelir ve kullanıcı yerel bir
  /// bildirimle haberdar edilir.
  String? activeConversationFriendId;

  bool get isConnected => _socket?.connected ?? false;

  void Function()? onConnected;
  void Function(String reason)? onConnectError;

  void Function(PersistentMessage message)? onPersistentMessageReceived;
  void Function(String clientId, PersistentMessage message)?
      onPersistentMessageAck;
  void Function(String clientId, String message)? onPersistentMessageError;

  // Mesaj düzenlendiğinde/silindiğinde/tepki alındığında/sabitlendiğinde
  // sunucu bu güncellenmiş mesajı HER İKİ tarafa da yayınlar (bkz. server.js
  // broadcastMessageUpdate) - kendi gönderdiğimiz bir işlemin sonucu da
  // dahil, böylece tek bir kod yolu tüm ekranları senkron tutar.
  void Function(PersistentMessage message)? onMessageEdited;
  void Function(PersistentMessage message)? onMessageDeleted;
  void Function(PersistentMessage message)? onMessageReacted;
  void Function(PersistentMessage message)? onMessagePinned;
  // Anket oyu / tek seferlik fotoğraf açma gibi 'meta' alanını değiştiren
  // ama ayrı bir olay adı gerektirmeyen genel güncellemeler (bkz. server.js
  // 'message-updated' yayını).
  void Function(PersistentMessage message)? onMessageUpdated;

  void Function(DisappearingMessage message)? onDisappearingMessageReceived;
  void Function(String clientId, String id, DateTime createdAt)?
      onDisappearingMessageAck;
  void Function(String clientId, String message)? onDisappearingMessageError;

  /// Kalıcı bağlantıyı kurar - zaten bağlıysa ya da bağlanma sürecindeyse
  /// hiçbir şey yapmaz (birden fazla ekran/akış aynı anda çağırabilir, ör.
  /// splash_screen.dart VE login_screen.dart).
  void connectIfNeeded(String authToken) {
    if (_socket != null && (_socket!.connected || _connecting)) return;
    // Önceki bir bağlanma denemesi başarısız olup kalıcı olarak koptuysa
    // (ne bağlı ne de bağlanma sürecinde) burada eski socket'i bırakmadan
    // yenisini kurmuş oluruz - önce onu düzgünce kapatıyoruz.
    _socket?.disconnect();
    _socket?.dispose();
    _connecting = true;

    _socket = io.io(
      signalingServerUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': authToken})
          .build(),
    );

    _socket!.onConnect((_) {
      _connecting = false;
      onConnected?.call();
    });
    _socket!.onConnectError((err) {
      _connecting = false;
      onConnectError?.call(err.toString());
    });
    _socket!.onDisconnect((reason) {
      // socket.io kendi başına yeniden bağlanmayı DENER (varsayılan
      // davranış) - ama mobil işletim sistemleri (özellikle Android) arka
      // planda bu yeniden bağlanmayı engelleyebiliyor, bu yüzden ekranlara
      // haber veriyoruz ki kullanıcı "bağlı" sanıp mesaj göndermeye
      // çalışmasın. Uygulama öne döndüğünde main.dart'taki yaşam döngüsü
      // gözlemcisi, YALNIZCA gerçekten uzun süre arka planda kalındıysa
      // (bkz. orada) bir reconnect() tetikliyor.
      //
      // 'reason' socket.io'nun kendi verdiği sebep string'i ('transport
      // close', 'ping timeout', 'io client disconnect', ...) - sunucudaki
      // (server.js) eşleniğiyle karşılaştırılabilir, gerçek nedeni (ağ mı,
      // sunucu mu, bizim kendi reconnect() çağrımız mı) ayırt etmek için
      // logluyoruz.
      // ignore: avoid_print
      print('MessagingService bağlantı koptu, sebep: $reason');
      if (_suppressNextDisconnectNotice) {
        // Bu, reconnect()'in KENDİ tetiklediği planlı bir kopma - kullanıcıya
        // yanlış alarm göstermiyoruz (bkz. sınıf üstündeki alan notu).
        _suppressNextDisconnectNotice = false;
        return;
      }
      onConnectError?.call('Bağlantı kesildi ($reason), yeniden bağlanılıyor...');
    });

    _socket!.on('persistent-message-received', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final message = PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map));
        onPersistentMessageReceived?.call(message);

        if (activeConversationFriendId != message.fromId) {
          // İlgili sohbet ekranı şu an açık değil - kullanıcı sunucu
          // tarafında "çevrimiçi" sayıldığı için (bu soket bağlı olduğu
          // için) push bildirimi gelmeyecek, bu yüzden burada yerel bir
          // bildirimle haberdar ediyoruz.
          final senderName = map['fromDisplayName'] as String? ?? 'Biri';
          final preview = message.text.length > 100
              ? '${message.text.substring(0, 100)}...'
              : message.text;
          PushNotificationService()
              .showLocalMessageNotification(title: senderName, body: preview);
        }
      } catch (e) {
        // ignore: avoid_print
        print('HATA (persistent-message-received): $e');
      }
    });

    _socket!.on('persistent-message-ack', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final message = PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map));
        onPersistentMessageAck?.call(map['clientId'] as String, message);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (persistent-message-ack): $e');
      }
    });

    _socket!.on('persistent-message-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onPersistentMessageError?.call(
          map['clientId'] as String? ?? '',
          map['message'] as String? ?? 'Mesaj gönderilemedi.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (persistent-message-error): $e');
      }
    });

    _socket!.on('message-edited', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onMessageEdited?.call(PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map)));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (message-edited): $e');
      }
    });

    _socket!.on('message-deleted', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onMessageDeleted?.call(PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map)));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (message-deleted): $e');
      }
    });

    _socket!.on('message-reacted', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onMessageReacted?.call(PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map)));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (message-reacted): $e');
      }
    });

    _socket!.on('message-pinned', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onMessagePinned?.call(PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map)));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (message-pinned): $e');
      }
    });

    _socket!.on('message-updated', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onMessageUpdated?.call(PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map)));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (message-updated): $e');
      }
    });

    _socket!.on('disappearing-message-received', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onDisappearingMessageReceived?.call(DisappearingMessage(
          id: map['id'] as String,
          fromId: map['fromId'] as String,
          fromDisplayName: map['fromDisplayName'] as String? ?? 'Biri',
          text: map['text'] as String,
          createdAt: DateTime.parse(map['createdAt'] as String),
        ));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (disappearing-message-received): $e');
      }
    });

    _socket!.on('disappearing-message-ack', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onDisappearingMessageAck?.call(
          map['clientId'] as String,
          map['id'] as String,
          DateTime.parse(map['createdAt'] as String),
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (disappearing-message-ack): $e');
      }
    });

    _socket!.on('disappearing-message-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onDisappearingMessageError?.call(
          map['clientId'] as String? ?? '',
          map['message'] as String? ?? 'Mesaj iletilemedi.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (disappearing-message-error): $e');
      }
    });

    _socket!.connect();
  }

  /// Mevcut bağlantı gerçekten çalışıyor mu bilinmiyorsa (ör. uygulama arka
  /// plandan öne döndüğünde, bkz. main.dart'taki yaşam döngüsü gözlemcisi)
  /// koşulsuz olarak tazeler - eskisini (varsa "hayalet" bile olsa) kapatıp
  /// yepyeni bir bağlantı kurar. connectIfNeeded()'den farklı olarak
  /// _socket!.connected şu an true görünüyor olsa bile çalışır, çünkü
  /// mobil işletim sistemleri arka plandaki bir soketi kendi bilgisi
  /// dışında koparabiliyor - istemci tarafı bunu her zaman hemen fark
  /// edemiyor.
  void reconnect(String authToken) {
    // Bu, main.dart'taki yaşam döngüsü gözlemcisinin BİLEREK tetiklediği bir
    // kesme - kullanıcıya "Bağlantı kesildi" alarmı gösterilmemeli, çünkü
    // hemen ardından yeni bağlantı kuruluyor zaten. Bkz. onDisconnect
    // callback'indeki _suppressNextDisconnectNotice kontrolü.
    _suppressNextDisconnectNotice = true;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connecting = false;
    connectIfNeeded(authToken);
  }

  void sendPersistentMessage(
      {required String toId,
      required String text,
      required String clientId,
      String? replyToId,
      String kind = 'text',
      Map<String, dynamic>? meta}) {
    _socket?.emit('persistent-message-send', {
      'toId': toId,
      'text': text,
      'clientId': clientId,
      if (replyToId != null) 'replyToId': replyToId,
      'kind': kind,
      if (meta != null) 'meta': meta,
    });
  }

  /// Anket oyu (#39 anket maddesi) - aynı seçeneğe tekrar oy vermek oyu
  /// geri çeker (bkz. server.js voteOnPoll toggle mantığı).
  void votePoll({required String messageId, required int optionIndex}) {
    _socket?.emit('message-poll-vote',
        {'messageId': messageId, 'optionIndex': optionIndex});
  }

  /// Tek seferlik fotoğrafı açar (#59 anket maddesi) - yalnızca alıcı,
  /// yalnızca bir kez çağırmalı (bkz. server.js openViewOncePhoto).
  void openViewOncePhoto(String messageId) {
    _socket?.emit('message-view-once-open', {'messageId': messageId});
  }

  /// Sohbet içi medya (sesli mesaj / tek seferlik fotoğraf) dosyasını
  /// sunucuya yükler (bkz. server.js POST /chat/media, chatMediaStorage.js).
  /// Dönen URL, ardından 'kind'e göre sendPersistentMessage'a meta olarak
  /// geçilir - mesajın kendisi burada OLUŞTURULMAZ.
  ///
  /// [mimeType] AÇIKÇA verilmeli (ör. 'image/jpeg', 'audio/mp4') - dosya
  /// yolundan otomatik MIME tahmini (image_picker/record'un ürettiği
  /// dosyalarda uzantı her zaman güvenilir olmadığı için) sunucudaki
  /// multer fileFilter'ın "Desteklenmeyen dosya türü" diye reddetmesine
  /// yol açabiliyordu - bu yüzden çağıran taraf türü kesin olarak bilir.
  Future<Map<String, dynamic>> uploadChatMedia(File file, {required String mimeType}) async {
    final token = AuthService().token;
    if (token == null) {
      throw Exception('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final request =
        http.MultipartRequest('POST', Uri.parse('$signalingServerUrl/chat/media'))
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(await http.MultipartFile.fromPath(
            'file',
            file.path,
            contentType: MediaType.parse(mimeType),
          ));

    final http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      response = await http.Response.fromStream(streamed);
    } catch (_) {
      throw Exception('Sunucuya ulaşılamıyor. Tekrar dene.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(data['error'] as String? ?? 'Dosya yüklenemedi.');
    }
    return data;
  }

  void editMessage({required String messageId, required String text}) {
    _socket?.emit('message-edit', {'messageId': messageId, 'text': text});
  }

  void deleteMessage(String messageId) {
    _socket?.emit('message-delete', {'messageId': messageId});
  }

  void reactToMessage({required String messageId, required String emoji}) {
    _socket?.emit('message-react', {'messageId': messageId, 'emoji': emoji});
  }

  void pinMessage(String messageId) {
    _socket?.emit('message-pin', {'messageId': messageId});
  }

  void unpinMessage(String messageId) {
    _socket?.emit('message-unpin', {'messageId': messageId});
  }

  /// "Kendine Not" (#42) - kendi id'ne mesaj gönderir, sunucu tarafında
  /// arkadaşlık kontrolü bilerek atlanır (bkz. server.js persistent-message-send).
  void sendNoteToSelf(
      {required String myId, required String text, required String clientId}) {
    sendPersistentMessage(toId: myId, text: text, clientId: clientId);
  }

  void sendDisappearingMessage(
      {required String toId, required String text, required String clientId}) {
    _socket?.emit('disappearing-message-send',
        {'toId': toId, 'text': text, 'clientId': clientId});
  }

  /// Sohbet ekranı kapanırken çağrılır - YALNIZCA bu ekranın kendi
  /// callback'lerini bırakır, altta kalıcı olan bağlantıya dokunmaz. Gerçek
  /// bağlantı kopuşu yalnızca çıkış yapılırken disconnectSocket() ile olur.
  void detachScreenCallbacks() {
    onConnected = null;
    onConnectError = null;
    onPersistentMessageReceived = null;
    onPersistentMessageAck = null;
    onPersistentMessageError = null;
    onMessageEdited = null;
    onMessageDeleted = null;
    onMessageReacted = null;
    onMessagePinned = null;
    onMessageUpdated = null;
    onDisappearingMessageReceived = null;
    onDisappearingMessageAck = null;
    onDisappearingMessageError = null;
    activeConversationFriendId = null;
  }

  /// Yalnızca çıkış yapılırken (bkz. profile_screen.dart _logout()) çağrılır
  /// - kalıcı bağlantıyı tamamen kapatır.
  void disconnectSocket() {
    detachScreenCallbacks();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connecting = false;
  }
}
