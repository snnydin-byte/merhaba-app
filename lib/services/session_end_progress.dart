import 'package:flutter/foundation.dart';

enum SessionEndOperation { logout, deleteAccount }

enum SessionEndPhase {
  idle,
  preparing,
  cleaningMedia,
  closingCalls,
  deletingAccount,
  clearingSession,
  completed,
  failed,
}

@immutable
class SessionEndProgress {
  const SessionEndProgress({
    this.operation = SessionEndOperation.logout,
    this.phase = SessionEndPhase.idle,
    this.message = '',
    this.timedOut = false,
  });

  final SessionEndOperation operation;
  final SessionEndPhase phase;
  final String message;
  final bool timedOut;

  bool get isRunning =>
      phase != SessionEndPhase.idle &&
      phase != SessionEndPhase.completed &&
      phase != SessionEndPhase.failed;
}

class SessionEndProgressController {
  SessionEndProgressController._();
  static final SessionEndProgressController _instance =
      SessionEndProgressController._();
  factory SessionEndProgressController() => _instance;

  final ValueNotifier<SessionEndProgress> state =
      ValueNotifier<SessionEndProgress>(const SessionEndProgress());

  int _generation = 0;

  int begin({
    required SessionEndOperation operation,
    required String message,
  }) {
    final generation = ++_generation;
    update(
      generation: generation,
      operation: operation,
      phase: SessionEndPhase.preparing,
      message: message,
    );
    return generation;
  }

  bool isCurrent(int generation) => generation == _generation;

  void update({
    int? generation,
    required SessionEndOperation operation,
    required SessionEndPhase phase,
    required String message,
    bool timedOut = false,
  }) {
    if (generation != null && generation != _generation) return;
    state.value = SessionEndProgress(
      operation: operation,
      phase: phase,
      message: message,
      timedOut: timedOut,
    );
  }

  void reset() {
    _generation++;
    state.value = const SessionEndProgress();
  }
}
