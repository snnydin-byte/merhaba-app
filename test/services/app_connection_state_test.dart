import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/services/app_connection_state.dart';

void main() {
  setUp(() => AppConnectionController().reset());

  test('mesajlaşma ve arama durumları bağımsız güncellenir', () {
    final controller = AppConnectionController();
    controller.updateMessaging(SocketConnectionPhase.connected);
    controller.updateCall(
      SocketConnectionPhase.error,
      message: 'Arama bağlantısı kurulamadı.',
    );

    expect(controller.state.value.messaging.isConnected, isTrue);
    expect(controller.state.value.call.phase, SocketConnectionPhase.error);
    expect(controller.state.value.hasError, isTrue);
  });

  test('iki kanal da bağlı olduğunda tam bağlantı sağlanır', () {
    final controller = AppConnectionController();
    controller.updateMessaging(SocketConnectionPhase.connected);
    controller.updateCall(SocketConnectionPhase.connected);

    expect(controller.state.value.isFullyConnected, isTrue);
  });
}
