import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/models/app_user.dart';
import 'package:merhaba_app/services/messaging_service.dart';
import 'package:merhaba_app/services/push_deep_link_resolver.dart';
import 'package:merhaba_app/services/push_notification_platform.dart';

class _FakeDataSource implements PushDeepLinkDataSource {
  _FakeDataSource({this.friends = const [], this.groups = const []});
  final List<AppUser> friends;
  final List<Group> groups;

  @override
  Future<List<AppUser>> fetchFriends() async => friends;

  @override
  Future<List<Group>> fetchGroups() async => groups;
}

PushNotificationPayload _payload(Map<String, String> data) =>
    PushNotificationPayload(data: data);

void main() {
  test('message bildirimi doğrudan arkadaş sohbetini çözer', () async {
    const friend = AppUser(
      id: 'friend-1',
      email: 'friend@example.com',
      displayName: 'Arkadaş',
    );
    final resolver = PushDeepLinkResolver(
      dataSource: _FakeDataSource(friends: const [friend]),
    );

    final target = await resolver.resolve(
      _payload({'type': 'message', 'fromId': 'friend-1'}),
    );

    expect(target, isA<PushFriendChatTarget>());
    expect((target as PushFriendChatTarget).friend.id, 'friend-1');
  });

  test('üyesi olunan grup doğrudan grup sohbetini çözer', () async {
    final group = Group.fromJson({
      'id': 'group-1',
      'name': 'Grup',
      'ownerId': 'me',
      'members': ['me'],
      'admins': ['me'],
      'announcementOnly': false,
      'createdAt': '2026-08-03T00:00:00.000Z',
    });
    final resolver = PushDeepLinkResolver(
      dataSource: _FakeDataSource(groups: [group]),
    );

    final target = await resolver.resolve(
      _payload({'type': 'group-message', 'groupId': 'group-1'}),
    );

    expect(target, isA<PushGroupChatTarget>());
  });

  test('oda kimliği bulunan canlı oda doğrudan çözümlenir', () async {
    final resolver = PushDeepLinkResolver(dataSource: _FakeDataSource());
    final target = await resolver.resolve(
      _payload({'type': 'live-room', 'roomId': 'room-1'}),
    );
    expect(target, isA<PushLiveRoomTarget>());
  });

  test('erişilemeyen varlık güvenli liste ekranına düşer', () async {
    final resolver = PushDeepLinkResolver(dataSource: _FakeDataSource());
    final target = await resolver.resolve(
      _payload({'type': 'group-message', 'groupId': 'missing'}),
    );
    expect(target, isA<PushGroupsFallbackTarget>());
  });
}
