const fs = require('fs');
const assert = require('assert');

const auth = fs.readFileSync('lib/services/auth_service.dart', 'utf8');
const progress = fs.readFileSync('lib/services/session_end_progress.dart', 'utf8');

assert(auth.includes("_logoutDeadline = Duration(seconds: 12)"));
assert(auth.includes("_accountDeleteRequestDeadline = Duration(seconds: 15)"));
assert(auth.includes("_postDeleteCleanupDeadline = Duration(seconds: 10)"));
assert(auth.includes('await cleanup.timeout(_logoutDeadline)'));
assert(auth.includes('.timeout(_accountDeleteRequestDeadline)'));
assert(auth.includes('await _forceLocalSessionClear('));
assert(auth.includes("_sessionStorage.clear().timeout(const Duration(seconds: 2))"));
assert(auth.includes('Hesabın silindiği'));
assert(auth.includes('doğrulanamadığı için oturumun açık bırakıldı'));
assert(progress.includes('int _generation = 0'));
assert(progress.includes('int begin({'));
assert(progress.includes('if (generation != null && generation != _generation) return;'));
assert(auth.includes('final forcedGeneration = progress.begin('));
console.log('flutter-v75-session-end-deadline: successful');
