import 'session_feedback_action_recovery.dart';
import 'session_feedback_actions.dart';
import 'session_feedback_network_recovery.dart';
import 'session_feedback_queue.dart';

/// Feedback altyapısının uygulama ve oturum yaşam döngüsü girişlerini tek
/// noktada toplar.
class SessionFeedbackLifecycle {
  SessionFeedbackLifecycle._();

  static final SessionFeedbackLifecycle instance = SessionFeedbackLifecycle._();
  factory SessionFeedbackLifecycle() => instance;

  Future<void>? _initialization;

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    SessionFeedbackActionRecovery().ensureInitialized();
    await SessionFeedbackNetworkRecovery().ensureInitialized();
  }

  void clearForSessionEnd() {
    SessionFeedbackActionRunner().cancelAll();
    SessionFeedbackQueue().clear();
  }

  void clearForTesting() {
    SessionFeedbackActionRunner().cancelAll();
    SessionFeedbackQueue().clear();
    SessionFeedbackActionRecovery().resetForTesting();
  }
}
