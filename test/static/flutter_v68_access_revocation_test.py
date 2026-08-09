from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
chat = (ROOT / 'lib/screens/chat_screen.dart').read_text()
group = (ROOT / 'lib/screens/group_chat_screen.dart').read_text()
live = (ROOT / 'lib/screens/live_room_screen.dart').read_text()
msg = (ROOT / 'lib/services/messaging_service.dart').read_text()

assert 'onFriendAccessRevoked' in msg
assert "friend-access-revoked" in msg
assert '_handleFriendAccessRevoked' in chat
assert 'FriendsScreen' in chat
assert '_closeForLostAccess' in group
assert 'group.members.contains(_myId)' in group
assert 'GroupsScreen' in group
assert '_leaveForLostAccess' in live
assert 'LiveRoomListScreen' in live
print('flutter-v68-access-revocation: başarılı')
