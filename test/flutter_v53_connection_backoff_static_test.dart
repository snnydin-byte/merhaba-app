import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connection retry backoff and countdown remain wired', () {
    final controller = File('lib/services/connection_retry_controller.dart')
        .readAsStringSync();
    final banner =
        File('lib/widgets/connection_status_banner.dart').readAsStringSync();

    expect(controller, contains('Duration(seconds: 2)'));
    expect(controller, contains('Duration(seconds: 30)'));
    expect(controller, contains('nextAllowedAt'));
    expect(controller, contains('resetBackoff'));
    expect(controller, contains('Timer.periodic'));
    expect(banner, contains('SessionFeedbackActionButton'));
    expect(banner, contains(r"'$retrySeconds sn'"));
    expect(banner, contains('enabled: sessionExpired || retryAvailable'));
  });
}
