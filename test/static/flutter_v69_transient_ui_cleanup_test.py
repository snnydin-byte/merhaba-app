from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
helper = (ROOT / 'lib/utils/forced_navigation.dart').read_text()
chat = (ROOT / 'lib/screens/chat_screen.dart').read_text()
group = (ROOT / 'lib/screens/group_chat_screen.dart').read_text()
live = (ROOT / 'lib/screens/live_room_screen.dart').read_text()

assert 'FocusManager.instance.primaryFocus?.unfocus()' in helper
assert 'hideCurrentSnackBar()' in helper
assert 'rootNavigator: true' in helper
assert 'route is PageRoute<dynamic>' in helper
assert 'navigateAfterAccessLoss' in chat
assert 'navigateAfterAccessLoss' in group
assert 'navigateAfterAccessLoss' in live
assert "destination: (_) => const FriendsScreen()" in chat
assert "destination: (_) => const GroupsScreen()" in group
assert "destination: (_) => const LiveRoomListScreen()" in live
print('flutter-v69-transient-ui-cleanup: başarılı')
