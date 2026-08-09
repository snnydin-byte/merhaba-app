import 'app_connection_state.dart';

class ClassifiedConnectionError {
  const ClassifiedConnectionError(
      {required this.kind, required this.message, required this.retryable});
  final ConnectionFailureKind kind;
  final String message;
  final bool retryable;
}

ClassifiedConnectionError classifyConnectionError(Object? error) {
  final raw = error is Map
      ? '${error['message'] ?? ''} ${error['code'] ?? ''} ${error['data'] ?? ''}'
      : (error?.toString() ?? '');
  final text = raw.toLowerCase();
  if (text.contains('auth_expired') ||
      text.contains('oturum geçersiz') ||
      text.contains('jwt expired') ||
      text.contains('unauthorized')) {
    return const ClassifiedConnectionError(
        kind: ConnectionFailureKind.sessionExpired,
        message: 'Oturumun süresi doldu. Lütfen yeniden giriş yap.',
        retryable: false);
  }
  if (text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('no address associated') ||
      text.contains('socketexception') ||
      text.contains('internet')) {
    return const ClassifiedConnectionError(
        kind: ConnectionFailureKind.offline,
        message: 'İnternet bağlantısı yok. Bağlantını kontrol et.',
        retryable: true);
  }
  if (text.contains('connection refused') ||
      text.contains('server') ||
      text.contains('timeout') ||
      text.contains('websocket error')) {
    return const ClassifiedConnectionError(
        kind: ConnectionFailureKind.serverUnavailable,
        message: 'Sunucuya şu anda ulaşılamıyor.',
        retryable: true);
  }
  return const ClassifiedConnectionError(
      kind: ConnectionFailureKind.temporary,
      message: 'Geçici bir bağlantı hatası oluştu.',
      retryable: true);
}
