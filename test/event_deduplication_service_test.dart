import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/event_deduplication_service.dart';

void main() {
  final service = EventDeduplicationService();

  setUp(service.resetForTesting);
  tearDown(service.resetForTesting);

  test('same event key is accepted once within ttl', () {
    expect(service.claim('message:user-1'), isTrue);
    expect(service.claim('message:user-1'), isFalse);
    expect(service.claim('message:user-2'), isTrue);
  });

  test('forgotten event can be claimed again', () {
    expect(service.claim('call:invite-1'), isTrue);
    service.forget('call:invite-1');
    expect(service.claim('call:invite-1'), isTrue);
  });
}
