const fs = require('fs');
const assert = require('assert');

const router = fs.readFileSync('lib/services/push_interaction_router.dart', 'utf8');
const transition = fs.readFileSync('lib/screens/push_deep_link_transition_screen.dart', 'utf8');
const resolver = fs.readFileSync('lib/services/push_deep_link_resolver.dart', 'utf8');
const coordinator = fs.readFileSync('lib/services/push_navigation_coordinator.dart', 'utf8');

assert(router.includes('PushDeepLinkTransitionScreen'));
assert(router.includes('PushNavigationCoordinator().runOnce'));
assert(transition.includes('İçerik hazırlanıyor'));
assert(transition.includes('Bağlantı açılamadı'));
assert(resolver.includes('PushDeepLinkFailureReason.permissionLost'));
assert(resolver.includes('PushDeepLinkFailureReason.network'));
assert(coordinator.includes('_activeTargets'));
assert(coordinator.includes('_inFlight'));

console.log('flutter-v61-push-transition: başarılı');
