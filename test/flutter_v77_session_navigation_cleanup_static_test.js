const fs = require('fs');
const assert = require('assert');

const coordinator = fs.readFileSync('lib/services/session_navigation_coordinator.dart', 'utf8');
const navigation = fs.readFileSync('lib/services/navigation_service.dart', 'utf8');
const main = fs.readFileSync('lib/main.dart', 'utf8');

assert(coordinator.includes('_dismissTransientUi(readyNavigator)'));
assert(coordinator.includes('hideCurrentSnackBar()'));
assert(coordinator.includes('clearSnackBars()'));
assert(coordinator.includes('hideCurrentMaterialBanner()'));
assert(coordinator.includes('route.willHandlePopInternally'));
assert(coordinator.includes('SessionEndProgressController().reset()'));
assert(navigation.includes('scaffoldMessengerKey'));
assert(main.includes('scaffoldMessengerKey: scaffoldMessengerKey'));
console.log('flutter-v77-session-navigation-cleanup: başarılı');
