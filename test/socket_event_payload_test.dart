import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/socket_event_payload.dart';

void main() {
  test('direct map payload is accepted', () {
    expect(socketEventMap({'partnerId': 'p1'}), {'partnerId': 'p1'});
  });

  test('socket.io singleton argument lists are unwrapped', () {
    expect(
        socketEventMap([
          {'partnerId': 'p1'}
        ]),
        {'partnerId': 'p1'});
    expect(
        socketEventMap([
          [
            {'roomId': 'r1'}
          ]
        ]),
        {'roomId': 'r1'});
  });

  test('socket.io multi-argument lists yield their object payload', () {
    expect(
      socketEventMap([
        {'partnerId': 'p1'},
        null,
      ]),
      {'partnerId': 'p1'},
    );
    expect(
      socketEventMap([
        'matched',
        [
          {'partnerId': 'p2'},
          false,
        ],
      ]),
      {'partnerId': 'p2'},
    );
  });

  test('invalid payloads fail explicitly', () {
    expect(() => socketEventMap(<dynamic>[]), throwsFormatException);
    expect(() => socketEventMap('invalid'), throwsFormatException);
  });
}
