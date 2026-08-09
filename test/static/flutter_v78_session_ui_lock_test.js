const fs = require('fs');

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

const lock = read('lib/services/session_ui_lock.dart');
const nav = read('lib/services/session_navigation_coordinator.dart');
const queue = read('lib/services/foreground_event_queue.dart');
const callUi = read('lib/services/call_ui_controller.dart');
const pushRouter = read('lib/services/push_interaction_router.dart');
const pushNav = read('lib/services/push_navigation_coordinator.dart');

const checks = [
  [lock.includes('class SessionUiLock'), 'SessionUiLock sınıfı yok'],
  [lock.includes('ValueNotifier<bool> isLocked'), 'reaktif kilit durumu yok'],
  [lock.includes('int lock()'), 'generation tabanlı lock yok'],
  [lock.includes('void unlock(int generation)'), 'generation korumalı unlock yok'],
  [nav.includes('SessionUiLock().lock()'), 'login reset kilidi başlatmıyor'],
  [nav.includes('SessionUiLock().unlock(uiLockGeneration)'), 'login reset kilidi açmıyor'],
  [nav.includes('ForegroundEventQueue().clear()'), 'bekleyen UI kuyruğu temizlenmiyor'],
  [queue.includes('SessionUiLock().isLocked.value'), 'foreground kuyruğu kilidi uygulamıyor'],
  [callUi.includes('service.respondToCallInvite(false)'), 'kilit sırasında gelen arama reddedilmiyor'],
  [callUi.includes('if (SessionUiLock().isLocked.value) return;'), 'arama UI üretimi kilitlenmiyor'],
  [pushRouter.includes('SessionUiLock().isLocked.value'), 'push router kilidi uygulamıyor'],
  [pushNav.includes('SessionUiLock().isLocked.value'), 'push navigation kilidi uygulamıyor'],
];

for (const [ok, message] of checks) {
  if (!ok) throw new Error(message);
}

console.log('flutter-v78-session-ui-lock: başarılı');
