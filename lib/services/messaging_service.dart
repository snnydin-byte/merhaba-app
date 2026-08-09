import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'auth_service.dart';
import 'app_connection_state.dart';
import 'connection_error_classifier.dart';
import 'orphan_media_cleanup_queue.dart';
import 'session_expiration_coordinator.dart';
import 'push_notification_service.dart';
import 'socket_client_options.dart';
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
  final DateTime? readAt;

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
    this.readAt,
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
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
      );
}

/// Zamanlanmış (henüz gönderilmemiş) bir mesaj (#12 anket maddesi - bkz.
/// signaling_server/scheduledMessageStore.js). Gerçek bir PersistentMessage
/// DEĞİLDİR - sohbet geçmişinde hiç görünmez, yalnızca "Zamanlanmış
/// mesajlar" listesinde (bkz. chat_screen.dart) gösterilir. Sunucudaki
/// periyodik kontrol zamanı gelince bunu gerçek bir PersistentMessage'a
/// dönüştürür (bkz. onScheduleMessageFired).
class ScheduledMessage {
  final String id;
  final String fromId;
  final String toId;
  final String text;
  final String kind;
  final Map<String, dynamic>? meta;
  final DateTime sendAt;
  final DateTime createdAt;

  const ScheduledMessage({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.text,
    required this.sendAt,
    required this.createdAt,
    this.kind = 'text',
    this.meta,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) =>
      ScheduledMessage(
        id: json['id'] as String,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        text: json['text'] as String,
        kind: json['kind'] as String? ?? 'text',
        meta: json['meta'] == null
            ? null
            : Map<String, dynamic>.from(json['meta'] as Map),
        sendAt: DateTime.parse(json['sendAt'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Bir durum/hikaye paylaşımı (#71 anket maddesi) - bkz.
/// signaling_server/storyStore.js. 24 saat sonra sunucu tarafında
/// kendiliğinden "aktif olmayan" sayılır, GET /stories bir daha hiç
/// döndürmez (bkz. story_service kullanan ekranlar).
class Story {
  final String id;
  final String userId;
  final String authorDisplayName;
  final String? authorPhotoUrl;
  final String kind; // 'text' | 'photo'
  final String? text;
  final String? mediaUrl;
  final String? backgroundColor;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool viewed;
  final int viewCount;

  const Story({
    required this.id,
    required this.userId,
    required this.authorDisplayName,
    this.authorPhotoUrl,
    required this.kind,
    this.text,
    this.mediaUrl,
    this.backgroundColor,
    required this.createdAt,
    required this.expiresAt,
    this.viewed = false,
    this.viewCount = 0,
  });

  factory Story.fromJson(Map<String, dynamic> json) => Story(
        id: json['id'] as String,
        userId: json['userId'] as String,
        authorDisplayName: json['authorDisplayName'] as String? ?? 'Biri',
        authorPhotoUrl: json['authorPhotoUrl'] as String?,
        kind: json['kind'] as String? ?? 'text',
        text: json['text'] as String?,
        mediaUrl: json['mediaUrl'] as String?,
        backgroundColor: json['backgroundColor'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        viewed: json['viewed'] as bool? ?? false,
        viewCount: json['viewCount'] as int? ?? 0,
      );
}

/// Bir hikayeyi kimin/ne zaman izlediği - yalnızca hikaye sahibi çekebilir
/// (bkz. server.js GET /stories/:id/viewers).
class StoryViewer {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final DateTime viewedAt;

  const StoryViewer({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.viewedAt,
  });

  factory StoryViewer.fromJson(Map<String, dynamic> json) => StoryViewer(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String? ?? 'Biri',
        photoUrl: json['photoUrl'] as String?,
        viewedAt: DateTime.parse(json['viewedAt'] as String),
      );
}

/// Bir grup üyesinin adı/fotoğrafı - Group.memberProfiles içinde gelir.
/// Bir üye bizim kişisel arkadaşımız OLMAYABİLİR (ör. başka bir üyenin
/// eklediği kişi) - bu yüzden FriendsService'teki liste her zaman yeterli
/// olmuyor, sunucu grup nesnesiyle birlikte bu bilgiyi de gönderiyor (bkz.
/// server.js groupWithProfiles).
class GroupMemberProfile {
  final String id;
  final String displayName;
  final String? photoUrl;

  const GroupMemberProfile(
      {required this.id, required this.displayName, this.photoUrl});

  factory GroupMemberProfile.fromJson(Map<String, dynamic> json) =>
      GroupMemberProfile(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? 'Bilinmeyen',
        photoUrl: json['photoUrl'] as String?,
      );
}

/// Bir grup sohbeti (Batch B) - bkz. signaling_server/groupStore.js. Kapsam
/// BİLEREK dar: yeniden adlandırma/admin atama/duyuru-kanalı modu var,
/// grup fotoğrafı yükleme bu ilk sürümde YOK ([photoUrl] her zaman null).
class Group {
  final String id;
  final String name;
  final String? photoUrl;
  final String ownerId;
  final List<String> admins;
  final List<String> members;
  final List<GroupMemberProfile> memberProfiles;
  final bool announcementOnly;
  final DateTime createdAt;

  const Group({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.ownerId,
    required this.admins,
    required this.members,
    this.memberProfiles = const [],
    required this.announcementOnly,
    required this.createdAt,
  });

  bool isAdmin(String userId) => admins.contains(userId);
  bool isOwner(String userId) => ownerId == userId;
  bool isMember(String userId) => members.contains(userId);

  String displayNameFor(String userId) {
    for (final p in memberProfiles) {
      if (p.id == userId) return p.displayName;
    }
    return 'Biri';
  }

  String? photoUrlFor(String userId) {
    for (final p in memberProfiles) {
      if (p.id == userId) return p.photoUrl;
    }
    return null;
  }

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        photoUrl: json['photoUrl'] as String?,
        ownerId: json['ownerId'] as String,
        admins: List<String>.from(json['admins'] as List? ?? const []),
        members: List<String>.from(json['members'] as List? ?? const []),
        memberProfiles: json['memberProfiles'] == null
            ? const []
            : (json['memberProfiles'] as List)
                .map((e) => GroupMemberProfile.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList(),
        announcementOnly: json['announcementOnly'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Bir grup sohbeti mesajı - PersistentMessage'a benzer ama ikili
/// sohbetteki düzenleme/tepki/sabitleme burada YOK (bkz.
/// groupMessageStore.js üstündeki kapsam notu), yalnızca gönderme/silme/
/// yanıtlama (replyToId - basitleştirilmiş "thread").
class GroupMessage {
  final String id;
  final String groupId;
  final String fromId;
  final String text;
  final String kind;
  final Map<String, dynamic>? meta;
  final String? replyToId;
  final DateTime createdAt;
  final bool deleted;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.fromId,
    required this.text,
    required this.createdAt,
    this.kind = 'text',
    this.meta,
    this.replyToId,
    this.deleted = false,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) => GroupMessage(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        fromId: json['fromId'] as String,
        text: json['text'] as String,
        kind: json['kind'] as String? ?? 'text',
        meta: json['meta'] == null
            ? null
            : Map<String, dynamic>.from(json['meta'] as Map),
        replyToId: json['replyToId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        deleted: json['deleted'] as bool? ?? false,
      );
}

class GroupMessagePage {
  const GroupMessagePage({
    required this.messages,
    required this.hasMore,
    this.nextBefore,
  });

  final List<GroupMessage> messages;
  final bool hasMore;
  final String? nextBefore;
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
  // Okundu bilgisi (#24 anket maddesi) - karşı taraf bir/birden fazla
  // mesajımızı okuyunca (bkz. server.js 'conversation-read').
  void Function(List<String> messageIds, DateTime readAt)? onConversationRead;

  // "Yazıyor..." göstergesi (GECE_GELISTIRME madde 6) - fromId, YAZAN
  // kişinin userId'si (bkz. server.js typing-start/typing-stop). Hiçbir şey
  // SAKLANMIYOR, yalnızca anlık bir gösterge.
  void Function(String fromId)? onTypingStart;
  void Function(String fromId)? onTypingStop;

  /// Açık birebir sohbetin erişimi arkadaşlık kaldırma veya engelleme
  /// nedeniyle sonlandığında tetiklenir.
  void Function(String userId, String reason)? onFriendAccessRevoked;

  // Eşleşme (Dating) katmanı - Batch E. onDiscoverMatched, BİZ swipe
  // ATMADAN karşı taraf tetiklediğinde gelir (biz zaten önceden beğenmiştik,
  // karşı taraf da az önce bizi beğenip eşleşme oluştu) - kendi ATTIĞIMIZ
  // swipe'ın sonucu doğrudan DiscoverService.swipe()'ın dönüş değerinden
  // gelir, bu event'e ihtiyaç duymaz.
  void Function(String matchId, AppUser user, bool firstMessageIsYours)?
      onDiscoverMatched;
  void Function(String matchId)? onDiscoverMatchExpired;
  void Function(bool approved)? onSelfieVerificationReviewed;

  // Mesaj planlama (#12 anket maddesi) - bkz. yukarıdaki ScheduledMessage.
  void Function(String clientId, ScheduledMessage item)? onScheduleMessageAck;
  void Function(String? clientId, String? id, String message)?
      onScheduleMessageError;
  void Function(String id)? onScheduleMessageCancelled;
  // Zamanı gelip gerçek bir mesaja dönüştüğünde (sunucu periyodik kontrolü) -
  // [message] artık normal sohbet geçmişinde de var, bkz. server.js
  // processDueScheduledMessages().
  void Function(String id, PersistentMessage message)? onScheduleMessageFired;
  // Gönderim anına kadar arkadaşlık bozulmuşsa (ör. engellendiyse) - mesaj
  // hiç gönderilmez, kullanıcıya haber verilir.
  void Function(String id, String message)? onScheduleMessageFailed;

  // Durum/hikaye (#71 anket maddesi) - bkz. yukarıdaki Story/StoryViewer.
  void Function(String clientId, Story story)? onStoryCreateAck;
  void Function(String? clientId, String message)? onStoryError;
  // Bir arkadaş yeni bir hikaye paylaştığında ANLIK (bkz. server.js
  // 'story-new') - hikaye şeridini yeniden çekmeden güncelleyebilmek için.
  void Function(Story story, String fromDisplayName)? onNewStory;
  // Kendi hikayemizi biri izlediğinde - yalnızca hikaye sahibine gelir.
  void Function(String storyId, String viewerId, String viewerDisplayName,
      DateTime viewedAt)? onStoryViewed;
  void Function(String storyId)? onStoryDeleted;
  // Bir arkadaş kendi hikayesini sildiğinde ANLIK - o an açık olan hikaye
  // şeridinden/görüntüleyiciden kaldırılabilsin diye.
  void Function(String storyId)? onStoryRemoved;

  // Grup sohbeti (Batch B) - bkz. yukarıdaki Group/GroupMessage.
  void Function(String clientId, Group group)? onGroupCreateAck;
  void Function(String? clientId, String message)? onGroupError;
  // Biri bizi yeni bir gruba eklediğinde (ya da grubu oluşturduğunda) -
  // grup listesine yeni bir kart eklemek için.
  void Function(Group group, String fromDisplayName)? onGroupCreated;
  // Grup adı/admin listesi/üye listesi/duyuru modu değiştiğinde - GÜNCEL
  // grup nesnesinin TAMAMI gelir, çağıran taraf kendi listesinde eşleşen
  // id'yi bulup değiştirmeli.
  void Function(Group group)? onGroupUpdated;
  // Biz bir gruptan çıkarıldığımızda - grup listesinden kaldırılmalı.
  void Function(String groupId)? onGroupRemovedYou;
  void Function(String groupId)? onGroupDeleted;

  void Function(String clientId, GroupMessage message)? onGroupMessageAck;
  void Function(String? clientId, String message)? onGroupMessageError;
  void Function(GroupMessage message, String fromDisplayName)?
      onGroupMessageReceived;
  void Function(GroupMessage message)? onGroupMessageDeleted;

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
    AppConnectionController().updateMessaging(
      SocketConnectionPhase.connecting,
      message: 'Mesajlaşma sunucusuna bağlanılıyor…',
    );

    _socket = io.io(
      signalingServerUrl,
      buildSocketClientOptions(authToken: authToken),
    );

    _socket!.onConnect((_) {
      _connecting = false;
      AppConnectionController().updateMessaging(
        SocketConnectionPhase.connected,
      );
      onConnected?.call();
    });
    _socket!.onConnectError((err) {
      _connecting = false;
      final failure = classifyConnectionError(err);
      if (failure.kind == ConnectionFailureKind.sessionExpired) {
        unawaited(SessionExpirationCoordinator().handleExpiredSession());
      }
      AppConnectionController().updateMessaging(
        SocketConnectionPhase.error,
        message: failure.message,
        failureKind: failure.kind,
        retryable: failure.retryable,
      );
      onConnectError?.call(failure.message);
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
      AppConnectionController().updateMessaging(
        _suppressNextDisconnectNotice
            ? SocketConnectionPhase.reconnecting
            : SocketConnectionPhase.disconnected,
        message: _suppressNextDisconnectNotice
            ? 'Mesajlaşma bağlantısı yenileniyor…'
            : 'Mesajlaşma bağlantısı kesildi.',
      );
      if (_suppressNextDisconnectNotice) {
        // Bu, reconnect()'in KENDİ tetiklediği planlı bir kopma - kullanıcıya
        // yanlış alarm göstermiyoruz (bkz. sınıf üstündeki alan notu).
        _suppressNextDisconnectNotice = false;
        return;
      }
      onConnectError
          ?.call('Bağlantı kesildi ($reason), yeniden bağlanılıyor...');
    });

    // "Yazıyor..." göstergesi (GECE_GELISTIRME madde 6).
    _socket!.on('typing-start', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final fromId = map['fromId'] as String?;
        if (fromId != null) onTypingStart?.call(fromId);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (typing-start): $e');
      }
    });
    _socket!.on('typing-stop', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final fromId = map['fromId'] as String?;
        if (fromId != null) onTypingStop?.call(fromId);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (typing-stop): $e');
      }
    });

    // Eşleşme (Dating) katmanı - Batch E.
    _socket!.on('discover-matched', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final matchId = map['matchId'] as String?;
        final userJson = map['user'] as Map<String, dynamic>?;
        if (matchId == null || userJson == null) return;
        onDiscoverMatched?.call(
          matchId,
          AppUser.fromJson(userJson),
          map['firstMessageIsYours'] as bool? ?? false,
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (discover-matched): $e');
      }
    });
    _socket!.on('discover-match-expired', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final matchId = map['matchId'] as String?;
        if (matchId != null) onDiscoverMatchExpired?.call(matchId);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (discover-match-expired): $e');
      }
    });
    _socket!.on('selfie-verification-reviewed', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onSelfieVerificationReviewed?.call(map['approved'] as bool? ?? false);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (selfie-verification-reviewed): $e');
      }
    });

    _socket!.on('friend-access-revoked', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final userId = map['userId'] as String?;
        if (userId == null || userId.isEmpty) return;
        onFriendAccessRevoked?.call(
          userId,
          map['reason'] as String? ?? 'access-revoked',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (friend-access-revoked): $e');
      }
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

    _socket!.on('conversation-read', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final ids =
            (map['messageIds'] as List).map((e) => e as String).toList();
        onConversationRead?.call(ids, DateTime.parse(map['readAt'] as String));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (conversation-read): $e');
      }
    });

    _socket!.on('schedule-message-ack', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final item = ScheduledMessage.fromJson(
            Map<String, dynamic>.from(map['item'] as Map));
        onScheduleMessageAck?.call(map['clientId'] as String, item);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (schedule-message-ack): $e');
      }
    });

    _socket!.on('schedule-message-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onScheduleMessageError?.call(
          map['clientId'] as String?,
          map['id'] as String?,
          map['message'] as String? ?? 'Mesaj planlanamadı.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (schedule-message-error): $e');
      }
    });

    _socket!.on('schedule-message-cancelled', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onScheduleMessageCancelled?.call(map['id'] as String);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (schedule-message-cancelled): $e');
      }
    });

    _socket!.on('schedule-message-fired', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final message = PersistentMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map));
        onScheduleMessageFired?.call(map['id'] as String, message);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (schedule-message-fired): $e');
      }
    });

    _socket!.on('schedule-message-failed', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onScheduleMessageFailed?.call(
          map['id'] as String,
          map['message'] as String? ?? 'Planlanan mesaj gönderilemedi.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (schedule-message-failed): $e');
      }
    });

    _socket!.on('story-create-ack', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final story =
            Story.fromJson(Map<String, dynamic>.from(map['story'] as Map));
        onStoryCreateAck?.call(map['clientId'] as String, story);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (story-create-ack): $e');
      }
    });

    _socket!.on('story-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onStoryError?.call(
          map['clientId'] as String?,
          map['message'] as String? ?? 'Hikaye paylaşılamadı.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (story-error): $e');
      }
    });

    _socket!.on('story-new', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final story =
            Story.fromJson(Map<String, dynamic>.from(map['story'] as Map));
        onNewStory?.call(story, map['fromDisplayName'] as String? ?? 'Biri');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (story-new): $e');
      }
    });

    _socket!.on('story-viewed', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onStoryViewed?.call(
          map['storyId'] as String,
          map['viewerId'] as String,
          map['viewerDisplayName'] as String? ?? 'Biri',
          DateTime.parse(map['viewedAt'] as String),
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (story-viewed): $e');
      }
    });

    _socket!.on('story-deleted', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onStoryDeleted?.call(map['storyId'] as String);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (story-deleted): $e');
      }
    });

    _socket!.on('story-removed', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onStoryRemoved?.call(map['storyId'] as String);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (story-removed): $e');
      }
    });

    _socket!.on('group-create-ack', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final group =
            Group.fromJson(Map<String, dynamic>.from(map['group'] as Map));
        onGroupCreateAck?.call(map['clientId'] as String, group);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-create-ack): $e');
      }
    });

    _socket!.on('group-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onGroupError?.call(
          map['clientId'] as String?,
          map['message'] as String? ?? 'Grup işlemi başarısız.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-error): $e');
      }
    });

    _socket!.on('group-created', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final group =
            Group.fromJson(Map<String, dynamic>.from(map['group'] as Map));
        onGroupCreated?.call(
            group, map['fromDisplayName'] as String? ?? 'Biri');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-created): $e');
      }
    });

    _socket!.on('group-updated', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onGroupUpdated?.call(
            Group.fromJson(Map<String, dynamic>.from(map['group'] as Map)));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-updated): $e');
      }
    });

    _socket!.on('group-removed-you', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onGroupRemovedYou?.call(map['groupId'] as String);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-removed-you): $e');
      }
    });

    _socket!.on('group-deleted', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onGroupDeleted?.call(map['groupId'] as String);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-deleted): $e');
      }
    });

    _socket!.on('group-message-ack', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final message = GroupMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map));
        onGroupMessageAck?.call(map['clientId'] as String, message);
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-message-ack): $e');
      }
    });

    _socket!.on('group-message-error', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onGroupMessageError?.call(
          map['clientId'] as String?,
          map['message'] as String? ?? 'Mesaj gönderilemedi.',
        );
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-message-error): $e');
      }
    });

    _socket!.on('group-message-received', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final message = GroupMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map));
        onGroupMessageReceived?.call(
            message, map['fromDisplayName'] as String? ?? 'Biri');
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-message-received): $e');
      }
    });

    _socket!.on('group-message-deleted', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        onGroupMessageDeleted?.call(GroupMessage.fromJson(
            Map<String, dynamic>.from(map['message'] as Map)));
      } catch (e) {
        // ignore: avoid_print
        print('HATA (group-message-deleted): $e');
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
    AppConnectionController().updateMessaging(
      SocketConnectionPhase.reconnecting,
      message: 'Mesajlaşma bağlantısı yenileniyor…',
    );
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connecting = false;
    connectIfNeeded(authToken);
  }

  /// "Yazıyor..." göstergesi (GECE_GELISTIRME madde 6) - chat_screen.dart
  /// bunu TextField onChanged'inde (debounce'lu) çağırır.
  void sendTypingStart(String toId) {
    _socket?.emit('typing-start', {'toId': toId});
  }

  void sendTypingStop(String toId) {
    _socket?.emit('typing-stop', {'toId': toId});
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

  /// Bir sohbeti "okundu" olarak işaretler (#24 anket maddesi) - chat_screen
  /// açıldığında ve/ya o sohbet açıkken yeni bir mesaj geldiğinde çağrılır.
  void markConversationRead(String friendId) {
    _socket?.emit('conversation-mark-read', {'friendId': friendId});
  }

  /// Bir mesajı ileri bir tarihe planlar (#12 anket maddesi) - [sendAt] en az
  /// 1 dakika, en fazla 30 gün sonrası olmalı (bkz. server.js
  /// SCHEDULE_MIN_LEAD_MS/SCHEDULE_MAX_LEAD_MS, sunucu tarafında da
  /// doğrulanıyor). Sonuç onScheduleMessageAck/onScheduleMessageError ile
  /// gelir.
  void scheduleMessage(
      {required String toId,
      required String text,
      required String clientId,
      required DateTime sendAt,
      String kind = 'text',
      Map<String, dynamic>? meta}) {
    _socket?.emit('schedule-message-create', {
      'toId': toId,
      'text': text,
      'clientId': clientId,
      'kind': kind,
      if (meta != null) 'meta': meta,
      'sendAt': sendAt.toUtc().toIso8601String(),
    });
  }

  /// Henüz gönderilmemiş bir zamanlanmış mesajı iptal eder.
  void cancelScheduledMessage(String id) {
    _socket?.emit('schedule-message-cancel', {'id': id});
  }

  /// O an bekleyen (henüz gönderilmemiş/iptal edilmemiş) TÜM zamanlanmış
  /// mesajları döner - "Zamanlanmış mesajlar" listesi ekranı için (bkz.
  /// server.js GET /messages/scheduled).
  Future<List<ScheduledMessage>> fetchScheduledMessages() async {
    final token = AuthService().token;
    if (token == null) return [];

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$signalingServerUrl/messages/scheduled'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw Exception('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    if (response.statusCode != 200) {
      throw Exception('Zamanlanmış mesajlar alınamadı.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['scheduled'] as List<dynamic>? ?? []);
    return list
        .map((e) => ScheduledMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Yeni bir durum/hikaye paylaşır (#71 anket maddesi) - [kind] 'text' ise
  /// [text] zorunlu, 'photo' ise [mediaUrl] zorunlu (fotoğraf önce
  /// uploadChatMedia ile yüklenip dönen URL buraya geçilir). Sonuç
  /// onStoryCreateAck/onStoryError ile gelir.
  void createStory(
      {required String kind,
      required String clientId,
      String? text,
      String? mediaUrl,
      String? backgroundColor,
      bool closeFriendsOnly = false}) {
    _socket?.emit('story-create', {
      'clientId': clientId,
      'kind': kind,
      if (text != null) 'text': text,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      'closeFriendsOnly': closeFriendsOnly,
    });
  }

  /// Bir hikayeyi "görüldü" işaretler - sahibi kendi hikayesi için
  /// çağırırsa sunucu sessizce yok sayar (bkz. storyStore.markViewed).
  void viewStory(String storyId) {
    _socket?.emit('story-view', {'storyId': storyId});
  }

  /// Yalnızca kendi hikayeni silebilirsin.
  void deleteStory(String storyId) {
    _socket?.emit('story-delete', {'storyId': storyId});
  }

  /// Arkadaşların (+ kendi) süresi dolmamış TÜM hikayelerini döner (bkz.
  /// server.js GET /stories).
  Future<List<Story>> fetchStories() async {
    final token = AuthService().token;
    if (token == null) return [];
    final http.Response response;
    try {
      response = await http.get(Uri.parse('$signalingServerUrl/stories'),
          headers: {
            'Authorization': 'Bearer $token'
          }).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw Exception('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    if (response.statusCode != 200) throw Exception('Hikayeler alınamadı.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['stories'] as List<dynamic>? ?? []);
    return list.map((e) => Story.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Bir hikayeyi kimlerin izlediği - yalnızca sahibiyken çağrılabilir (bkz.
  /// server.js GET /stories/:id/viewers, aksi halde 403 döner).
  Future<List<StoryViewer>> fetchStoryViewers(String storyId) async {
    final token = AuthService().token;
    if (token == null) return [];
    final http.Response response;
    try {
      response = await http.get(
          Uri.parse('$signalingServerUrl/stories/$storyId/viewers'),
          headers: {
            'Authorization': 'Bearer $token'
          }).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw Exception('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    if (response.statusCode != 200) throw Exception('İzleyenler alınamadı.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['viewers'] as List<dynamic>? ?? []);
    return list
        .map((e) => StoryViewer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Yeni bir grup sohbeti oluşturur (Batch B) - [memberIds] yalnızca
  /// oluşturanın ARKADAŞLARI olabilir, sunucu arkadaş olmayanları sessizce
  /// eler (bkz. server.js 'group-create'). Sonuç onGroupCreateAck/
  /// onGroupError ile gelir.
  void createGroup(
      {required String name,
      required List<String> memberIds,
      required String clientId}) {
    _socket?.emit('group-create', {
      'name': name,
      'memberIds': memberIds,
      'clientId': clientId,
    });
  }

  void sendGroupMessage(
      {required String groupId,
      required String text,
      required String clientId,
      String? replyToId,
      String kind = 'text',
      Map<String, dynamic>? meta}) {
    _socket?.emit('group-message-send', {
      'groupId': groupId,
      'text': text,
      'clientId': clientId,
      if (replyToId != null) 'replyToId': replyToId,
      'kind': kind,
      if (meta != null) 'meta': meta,
    });
  }

  /// Gönderen kendi mesajını, bir admin grupta HERHANGİ bir mesajı silebilir.
  void deleteGroupMessage(
      {required String groupId, required String messageId}) {
    _socket?.emit(
        'group-message-delete', {'groupId': groupId, 'messageId': messageId});
  }

  /// Yalnızca mevcut bir admin yeni üye ekleyebilir, eklenecek kişiler
  /// EKLEYENİN arkadaşı olmalı (bkz. server.js 'group-member-add').
  void addGroupMembers(
      {required String groupId, required List<String> memberIds}) {
    _socket?.emit(
        'group-member-add', {'groupId': groupId, 'memberIds': memberIds});
  }

  /// [memberId] == kendi id'n ise gruptan ayrılma, aksi halde (admin
  /// olman gerekir) o kişiyi çıkarma.
  void removeGroupMember({required String groupId, required String memberId}) {
    _socket?.emit(
        'group-member-remove', {'groupId': groupId, 'memberId': memberId});
  }

  /// Yalnızca grup sahibi başka üyeleri admin yapabilir/admin'likten alabilir.
  void setGroupAdmin(
      {required String groupId,
      required String memberId,
      required bool isAdmin}) {
    _socket?.emit('group-set-admin',
        {'groupId': groupId, 'memberId': memberId, 'isAdmin': isAdmin});
  }

  void renameGroup({required String groupId, required String name}) {
    _socket?.emit('group-rename', {'groupId': groupId, 'name': name});
  }

  /// true ise grup tek yönlü duyuru kanalına döner - yalnızca adminler
  /// mesaj gönderebilir.
  void setGroupAnnouncementOnly(
      {required String groupId, required bool value}) {
    _socket?.emit(
        'group-set-announcement-only', {'groupId': groupId, 'value': value});
  }

  /// Yalnızca grup sahibi silebilir.
  void deleteGroup(String groupId) {
    _socket?.emit('group-delete', {'groupId': groupId});
  }

  /// Üyesi olduğumuz TÜM grupları döner (bkz. server.js GET /groups).
  Future<List<Group>> fetchGroups() async {
    final token = AuthService().token;
    if (token == null) return [];
    final http.Response response;
    try {
      response = await http.get(Uri.parse('$signalingServerUrl/groups'),
          headers: {
            'Authorization': 'Bearer $token'
          }).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw Exception('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    if (response.statusCode != 200) throw Exception('Gruplar alınamadı.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['groups'] as List<dynamic>? ?? []);
    return list.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Bir grubun mesaj geçmişini döner (bkz. server.js GET /groups/:id/messages).
  Future<GroupMessagePage> fetchGroupMessagePage(
    String groupId, {
    String? before,
    int limit = 100,
  }) async {
    final token = AuthService().token;
    if (token == null) {
      return const GroupMessagePage(messages: [], hasMore: false);
    }
    final uri =
        Uri.parse('$signalingServerUrl/groups/$groupId/messages').replace(
      queryParameters: {
        'limit': limit.clamp(1, 200).toString(),
        if (before != null && before.isNotEmpty) 'before': before,
      },
    );
    final http.Response response;
    try {
      response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw Exception('Sunucuya ulaşılamıyor. Tekrar dene.');
    }
    if (response.statusCode != 200) throw Exception('Grup geçmişi alınamadı.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['messages'] as List<dynamic>? ?? []);
    return GroupMessagePage(
      messages: list
          .map((e) => GroupMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: data['hasMore'] as bool? ?? false,
      nextBefore: data['nextBefore'] as String?,
    );
  }

  Future<List<GroupMessage>> fetchGroupMessages(String groupId) async =>
      (await fetchGroupMessagePage(groupId)).messages;

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
  Future<Map<String, dynamic>> uploadChatMedia(File file,
      {required String mimeType}) async {
    final token = AuthService().token;
    if (token == null) {
      throw Exception('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    final request = http.MultipartRequest(
        'POST', Uri.parse('$signalingServerUrl/chat/media'))
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(mimeType),
      ));

    final http.Response response;
    try {
      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
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

  /// Mesaja dönüştürülemeyen geçici sohbet medyasını sunucudan ve
  /// Cloudinary'den temizler. Yalnızca yüklemeyi yapan kullanıcı silebilir.
  Future<bool> discardUploadedChatMedia(
    String url, {
    bool enqueueOnFailure = true,
  }) async {
    final normalized = url.trim();
    final token = AuthService().token;
    if (normalized.isEmpty) return true;
    if (token == null) {
      if (enqueueOnFailure) {
        await OrphanMediaCleanupQueue().enqueue(normalized);
      }
      return false;
    }

    final request = http.Request(
      'DELETE',
      Uri.parse('$signalingServerUrl/chat/media'),
    )
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'url': normalized});

    try {
      final streamed =
          await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200 || response.statusCode == 404) return true;
    } catch (_) {
      // Aşağıdaki kalıcı kuyruk ağ geri geldiğinde yeniden deneyecek.
    }
    if (enqueueOnFailure) {
      await OrphanMediaCleanupQueue().enqueue(normalized);
    }
    return false;
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
    onConversationRead = null;
    onTypingStart = null;
    onTypingStop = null;
    onFriendAccessRevoked = null;
    onDiscoverMatched = null;
    onDiscoverMatchExpired = null;
    onSelfieVerificationReviewed = null;
    onScheduleMessageAck = null;
    onScheduleMessageError = null;
    onScheduleMessageCancelled = null;
    onScheduleMessageFired = null;
    onScheduleMessageFailed = null;
    onStoryCreateAck = null;
    onStoryError = null;
    onNewStory = null;
    onStoryViewed = null;
    onStoryDeleted = null;
    onStoryRemoved = null;
    onGroupCreateAck = null;
    onGroupError = null;
    onGroupCreated = null;
    onGroupUpdated = null;
    onGroupRemovedYou = null;
    onGroupDeleted = null;
    onGroupMessageAck = null;
    onGroupMessageError = null;
    onGroupMessageReceived = null;
    onGroupMessageDeleted = null;
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
    AppConnectionController().updateMessaging(
      SocketConnectionPhase.disconnected,
    );
  }
}
