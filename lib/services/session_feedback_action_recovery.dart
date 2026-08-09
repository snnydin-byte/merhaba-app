import 'app_connection_state.dart';
import 'session_feedback_actions.dart';

/// Başarılı socket bağlantıları ilgili feedback aksiyonunun tükenmiş/backoff
/// durumunu otomatik sıfırlar.
class SessionFeedbackActionRecovery {
  SessionFeedbackActionRecovery._() {
    AppConnectionController().state.addListener(_handleConnectionState);
  }

  static final SessionFeedbackActionRecovery instance =
      SessionFeedbackActionRecovery._();
  factory SessionFeedbackActionRecovery() => instance;

  AppConnectionState _previous = const AppConnectionState();

  void _handleConnectionState() {
    final current = AppConnectionController().state.value;
    for (final channel in AppConnectionChannel.values) {
      final wasConnected = _previous.statusFor(channel).isConnected;
      final isConnected = current.statusFor(channel).isConnected;
      if (!wasConnected && isConnected) {
        SessionFeedbackActionRunner().resetKey('connection:${channel.name}');
      }
    }
    if (!_previous.isFullyConnected && current.isFullyConnected) {
      SessionFeedbackActionRunner().resetKey('connection:persistent');
    }
    _previous = current;
  }

  void ensureInitialized() {}

  void resetForTesting() {
    _previous = const AppConnectionState();
  }
}
