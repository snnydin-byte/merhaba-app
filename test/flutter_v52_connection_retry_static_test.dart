import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connection retry surfaces remain wired', () {
    final banner =
        File('lib/widgets/connection_status_banner.dart').readAsStringSync();
    final coordinator =
        File('lib/services/socket_session_coordinator.dart').readAsStringSync();
    final group =
        File('lib/services/group_call_service.dart').readAsStringSync();
    final live = File('lib/services/live_room_service.dart').readAsStringSync();

    expect(banner, contains('SessionFeedbackActionButton'));
    expect(banner, contains('SessionFeedbackActions.forConnectionStatus'));
    expect(banner, contains('ConnectionRetryController'));
    expect(coordinator, contains('AppConnectionChannel.messaging'));
    expect(coordinator, contains('AppConnectionChannel.call'));
    expect(group, contains('AppConnectionChannel.groupCall'));
    expect(live, contains('AppConnectionChannel.liveRoom'));
  });
}
