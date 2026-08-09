import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/chat_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/group_chat_screen.dart';
import '../screens/groups_screen.dart';
import '../screens/live_room_list_screen.dart';
import '../screens/live_room_screen.dart';
import '../screens/push_deep_link_transition_screen.dart';
import '../theme/app_theme.dart';
import 'event_deduplication_service.dart';
import 'foreground_event_queue.dart';
import 'navigation_service.dart';
import 'push_deep_link_resolver.dart';
import 'push_notification_platform.dart';
import 'push_navigation_coordinator.dart';
import 'session_ui_lock.dart';

class PushInteractionRouter {
  PushInteractionRouter._internal();
  static final PushInteractionRouter instance =
      PushInteractionRouter._internal();
  factory PushInteractionRouter() => instance;

  PushDeepLinkResolver _resolver = PushDeepLinkResolver();

  void setResolverForTesting(PushDeepLinkResolver resolver) {
    _resolver = resolver;
  }

  void resetForTesting() {
    _resolver = PushDeepLinkResolver();
    PushNavigationCoordinator().resetForTesting();
  }

  String eventKey(PushNotificationPayload payload) {
    final type = payload.data['type']?.trim() ?? 'notification';
    final entity = payload.data['eventId'] ??
        payload.data['inviteId'] ??
        payload.data['roomId'] ??
        payload.data['groupId'] ??
        payload.data['fromId'] ??
        payload.id ??
        '${payload.title ?? ''}:${payload.body ?? ''}';
    return '$type:$entity';
  }

  Future<void> handle(PushNotificationPayload payload) async {
    if (SessionUiLock().isLocked.value) return;
    final key = eventKey(payload);
    if (!EventDeduplicationService().claim(key)) return;

    final queue = ForegroundEventQueue();
    queue.enqueue(PendingForegroundEvent(
      key: 'push-open:$key',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      action: () => _navigate(payload),
    ));
  }

  String _targetKey(PushNotificationPayload payload) {
    final type = payload.data['type']?.trim() ?? 'notification';
    final entity = switch (type) {
      'message' || 'call-invite' => payload.data['fromId'] ??
          payload.data['friendId'] ??
          payload.data['userId'],
      'group-message' => payload.data['groupId'],
      'live-room' || 'live-room-invite' => payload.data['roomId'],
      _ => payload.id ?? eventKey(payload),
    };
    return '$type:${entity?.trim() ?? eventKey(payload)}';
  }

  Widget _destinationFor(PushDeepLinkTarget target) => switch (target) {
        PushFriendChatTarget(:final friend) => ChatScreen(friend: friend),
        PushGroupChatTarget(:final group) => GroupChatScreen(group: group),
        PushLiveRoomTarget(:final roomId) =>
          LiveRoomScreen.viewer(roomId: roomId),
        PushGroupsFallbackTarget() => const GroupsScreen(),
        PushLiveRoomsFallbackTarget() => const LiveRoomListScreen(),
        PushFriendsFallbackTarget() => const FriendsScreen(),
        PushDeepLinkFailureTarget() => const FriendsScreen(),
      };

  Future<void> _navigate(PushNotificationPayload payload) async {
    if (SessionUiLock().isLocked.value) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      // Navigator henüz kurulmadıysa olay kısa süreli kuyruğa geri girer.
      ForegroundEventQueue().enqueue(PendingForegroundEvent(
        key: 'push-open-retry:${eventKey(payload)}',
        expiresAt: DateTime.now().add(const Duration(seconds: 20)),
        action: () => _navigate(payload),
      ));
      return;
    }

    final targetKey = _targetKey(payload);
    await PushNavigationCoordinator().runOnce(targetKey, () async {
      await navigator.push(
        AppPageRoute(
          builder: (_) => PushDeepLinkTransitionScreen(
            payload: payload,
            resolver: _resolver,
            destinationBuilder: _destinationFor,
          ),
        ),
      );
    });
  }
}
