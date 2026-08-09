const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

const state = read('lib/services/app_connection_state.dart');
for (const token of ['groupCall', 'liveRoom', 'updateGroupCall', 'updateLiveRoom', 'statusFor']) {
  if (!state.includes(token)) throw new Error(`connection state missing ${token}`);
}

const expectations = [
  ['lib/screens/call_screen.dart', 'AppConnectionChannel.call'],
  ['lib/screens/group_chat_screen.dart', 'AppConnectionChannel.messaging'],
  ['lib/screens/group_call_screen.dart', 'AppConnectionChannel.groupCall'],
  ['lib/screens/live_room_screen.dart', 'AppConnectionChannel.liveRoom'],
];
for (const [file, token] of expectations) {
  const source = read(file);
  if (!source.includes('ConnectionStatusBanner')) throw new Error(`${file} missing banner`);
  if (!source.includes(token)) throw new Error(`${file} missing ${token}`);
}

const groupService = read('lib/services/group_call_service.dart');
const liveService = read('lib/services/live_room_service.dart');
for (const [name, source, updater] of [
  ['group', groupService, 'updateGroupCall'],
  ['live', liveService, 'updateLiveRoom'],
]) {
  for (const phase of ['connecting', 'connected', 'reconnecting', 'error', 'disconnected']) {
    if (!source.includes(`SocketConnectionPhase.${phase}`)) {
      throw new Error(`${name} service missing ${phase}`);
    }
  }
  if (!source.includes(updater)) throw new Error(`${name} updater missing`);
}

console.log('flutter-v51-connection-surfaces: successful');
