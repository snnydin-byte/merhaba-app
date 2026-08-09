import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canlı oda socket yeniden bağlanınca oturumu geri yükler', () {
    final source =
        File('lib/services/live_room_service.dart').readAsStringSync();

    expect(source, contains("_socket!.emit('live-room-resume'"));
    expect(source, contains("_socket!.on('live-room-resumed'"));
    expect(source, contains("map['code'] == 'LIVE_ROOM_ACCESS_LOST'"));
  });
}
