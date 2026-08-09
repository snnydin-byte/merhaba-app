const assert = require('assert');
const fs = require('fs');

const source = fs.readFileSync(
  'lib/screens/push_deep_link_transition_screen.dart',
  'utf8',
);

assert(source.includes('bool _navigationAbandoned = false;'));
assert(source.includes('bool _destinationNavigationStarted = false;'));
assert(source.includes('generation != _resolveGeneration'));
assert(source.includes('_navigationAbandoned ||'));
assert(source.includes('_destinationNavigationStarted'));
assert(source.includes('void _abandonPendingNavigation()'));
assert(source.includes('_resolveGeneration++;'));
assert(source.includes('Future<bool> _handleSystemBack()'));
assert(source.includes('onWillPop: _handleSystemBack'));
assert(source.includes('onPressed: _closeTransition'));
assert(source.includes('_abandonPendingNavigation();\n    _destinationNavigationStarted = true;'));

console.log('flutter-v66-deep-link-lifecycle: başarılı');
