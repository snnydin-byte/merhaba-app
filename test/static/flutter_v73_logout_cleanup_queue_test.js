const fs = require('fs');
const assert = require('assert');

const queue = fs.readFileSync('lib/services/orphan_media_cleanup_queue.dart', 'utf8');
const auth = fs.readFileSync('lib/services/auth_service.dart', 'utf8');

assert(queue.includes('flushBeforeSessionEnd'), 'missing pre-logout flush');
assert(queue.includes('removeEntriesForUser'), 'missing account deletion queue cleanup');
assert(queue.includes('maxItems = 3'), 'pre-logout cleanup must be bounded');
assert(auth.includes('_flushOrphanMediaWithTimeout'), 'logout/delete must try bounded queue cleanup');
assert(auth.includes('OrphanMediaCleanupQueue()'), 'orphan queue integration missing');
assert(auth.includes('flushBeforeSessionEnd(userId: userId)'), 'bounded cleanup helper must call queue flush');
assert(auth.includes('await OrphanMediaCleanupQueue().removeEntriesForUser(userId)'), 'deleted account queue records must be purged');
assert(auth.includes('flushOrphanMedia: false'), 'account deletion must not duplicate pre-logout flush');
assert(auth.includes('operation: SessionEndOperation.deleteAccount'), 'account deletion cleanup must preserve operation type');
const logoutStart = auth.indexOf('Future<void> _logout');
const logoutBody = auth.slice(logoutStart, auth.indexOf('/// Yalnızca testlerde', logoutStart));
assert(logoutBody.indexOf('_flushOrphanMediaWithTimeout') < logoutBody.indexOf('_clearSession();'), 'cleanup must happen before token/session clear');

console.log('flutter-v73-logout-cleanup-queue: successful');
