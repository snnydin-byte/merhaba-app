import '../models/app_user.dart';
import 'friends_service.dart';
import 'messaging_service.dart';
import 'push_notification_platform.dart';

sealed class PushDeepLinkTarget {
  const PushDeepLinkTarget();
}

class PushFriendChatTarget extends PushDeepLinkTarget {
  final AppUser friend;
  const PushFriendChatTarget(this.friend);
}

class PushGroupChatTarget extends PushDeepLinkTarget {
  final Group group;
  const PushGroupChatTarget(this.group);
}

class PushLiveRoomTarget extends PushDeepLinkTarget {
  final String roomId;
  const PushLiveRoomTarget(this.roomId);
}

enum PushDeepLinkFailureReason {
  notFound,
  permissionLost,
  invalidPayload,
  network,
  appBackgrounded,
  sessionExpired,
}

abstract class PushDeepLinkFailureTarget extends PushDeepLinkTarget {
  final PushDeepLinkFailureReason reason;
  const PushDeepLinkFailureTarget(this.reason);
}

class PushFriendsFallbackTarget extends PushDeepLinkFailureTarget {
  const PushFriendsFallbackTarget([
    super.reason = PushDeepLinkFailureReason.notFound,
  ]);
}

class PushGroupsFallbackTarget extends PushDeepLinkFailureTarget {
  const PushGroupsFallbackTarget([
    super.reason = PushDeepLinkFailureReason.permissionLost,
  ]);
}

class PushLiveRoomsFallbackTarget extends PushDeepLinkFailureTarget {
  const PushLiveRoomsFallbackTarget([
    super.reason = PushDeepLinkFailureReason.notFound,
  ]);
}

abstract interface class PushDeepLinkDataSource {
  Future<List<AppUser>> fetchFriends();
  Future<List<Group>> fetchGroups();
}

class DefaultPushDeepLinkDataSource implements PushDeepLinkDataSource {
  final FriendsService friendsService;
  final MessagingService messagingService;

  DefaultPushDeepLinkDataSource({
    FriendsService? friendsService,
    MessagingService? messagingService,
  })  : friendsService = friendsService ?? FriendsService(),
        messagingService = messagingService ?? MessagingService();

  @override
  Future<List<AppUser>> fetchFriends() => friendsService.fetchFriends();

  @override
  Future<List<Group>> fetchGroups() => messagingService.fetchGroups();
}

class PushDeepLinkResolver {
  PushDeepLinkResolver({PushDeepLinkDataSource? dataSource})
      : _dataSource = dataSource ?? DefaultPushDeepLinkDataSource();

  final PushDeepLinkDataSource _dataSource;

  static String? _safeId(Object? value, {int maxLength = 160}) {
    final id = value?.toString().trim();
    if (id == null || id.isEmpty || id.length > maxLength) return null;
    return id;
  }

  Future<PushDeepLinkTarget> resolve(PushNotificationPayload payload) async {
    final type = payload.data['type']?.trim();

    switch (type) {
      case 'message':
      case 'call-invite':
        return _resolveFriend(payload);
      case 'group-message':
        return _resolveGroup(payload);
      case 'live-room':
      case 'live-room-invite':
        final roomId = _safeId(payload.data['roomId']);
        return roomId == null
            ? const PushLiveRoomsFallbackTarget(
                PushDeepLinkFailureReason.invalidPayload,
              )
            : PushLiveRoomTarget(roomId);
      default:
        return const PushFriendsFallbackTarget();
    }
  }

  Future<PushDeepLinkTarget> _resolveFriend(
      PushNotificationPayload payload) async {
    final friendId = _safeId(
      payload.data['fromId'] ??
          payload.data['friendId'] ??
          payload.data['userId'],
    );
    if (friendId == null) {
      return const PushFriendsFallbackTarget(
        PushDeepLinkFailureReason.invalidPayload,
      );
    }

    try {
      final friends = await _dataSource.fetchFriends();
      for (final friend in friends) {
        if (friend.id == friendId) return PushFriendChatTarget(friend);
      }
    } catch (_) {
      return const PushFriendsFallbackTarget(
        PushDeepLinkFailureReason.network,
      );
    }
    return const PushFriendsFallbackTarget(
      PushDeepLinkFailureReason.permissionLost,
    );
  }

  Future<PushDeepLinkTarget> _resolveGroup(
      PushNotificationPayload payload) async {
    final groupId = _safeId(payload.data['groupId']);
    if (groupId == null) {
      return const PushGroupsFallbackTarget(
        PushDeepLinkFailureReason.invalidPayload,
      );
    }

    try {
      final groups = await _dataSource.fetchGroups();
      for (final group in groups) {
        if (group.id == groupId) return PushGroupChatTarget(group);
      }
    } catch (_) {
      return const PushGroupsFallbackTarget(
        PushDeepLinkFailureReason.network,
      );
    }
    return const PushGroupsFallbackTarget(
      PushDeepLinkFailureReason.permissionLost,
    );
  }
}
