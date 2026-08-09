const fs = require('fs');
const assert = require('assert');

const coordinator = fs.readFileSync('lib/services/session_navigation_coordinator.dart', 'utf8');
const expiration = fs.readFileSync('lib/services/session_expiration_coordinator.dart', 'utf8');
const profile = fs.readFileSync('lib/screens/profile_screen.dart', 'utf8');
const settings = fs.readFileSync('lib/screens/settings_screen.dart', 'utf8');

assert(coordinator.includes('class SessionNavigationCoordinator'));
assert(coordinator.includes('Future<void>? _inFlight'));
assert(coordinator.includes('pushAndRemoveUntil'));
assert(coordinator.includes("settings: const RouteSettings(name: '/login')"));
assert(expiration.includes('SessionNavigationCoordinator().resetToLogin()'));
assert(profile.includes('SessionNavigationCoordinator().resetToLogin()'));
assert(settings.includes('SessionNavigationCoordinator().resetToLogin()'));
assert(!profile.includes('pushAndRemoveUntil(\n        AppPageRoute(builder: (_) => const LoginScreen())'));
assert(!settings.includes('pushAndRemoveUntil(\n        MaterialPageRoute(builder: (_) => const LoginScreen())'));
console.log('flutter-v76-session-navigation: başarılı');
