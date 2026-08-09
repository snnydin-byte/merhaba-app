import 'package:flutter/foundation.dart';

import 'active_media_session_coordinator.dart';
import 'app_connection_state.dart';
import 'auth_service.dart';
import 'connection_retry_controller.dart';
import 'session_navigation_coordinator.dart';

/// Sunucunun bir socket JWT'sini açıkça geçersiz/süresi dolmuş olarak
/// reddetmesi halinde uygulama genelinde tek bir güvenli çıkış akışı yürütür.
///
/// Aynı anda mesajlaşma ve arama socketlerinden AUTH_EXPIRED gelebileceği için
/// işlem tekilleştirilir. Oturum önce güvenli depodan temizlenir; AuthService
/// notifier'ı üzerinden kalıcı socket/push koordinatörleri eski hesabı kapatır;
/// ardından bütün navigator geçmişi temizlenerek giriş ekranı gösterilir.
class SessionExpirationCoordinator {
  SessionExpirationCoordinator._();

  static final SessionExpirationCoordinator instance =
      SessionExpirationCoordinator._();
  factory SessionExpirationCoordinator() => instance;

  Future<void>? _inFlight;

  Future<void> handleExpiredSession() {
    return _inFlight ??= _handle().whenComplete(() => _inFlight = null);
  }

  Future<void> _handle() async {
    // Token ve navigator durumu temizlenmeden önce aktif kamera/mikrofon ve
    // LiveKit/WebRTC oturumlarını kapat. Böylece logout listener'ları ekranı
    // değiştirirken medya track'leri arka planda açık kalmaz.
    await ActiveMediaSessionCoordinator().closeAll();

    if (AuthService().isLoggedIn) {
      await AuthService().logout();
    }

    AppConnectionController().reset();
    ConnectionRetryController().resetBackoff(AppConnectionChannel.messaging);
    ConnectionRetryController().resetBackoff(AppConnectionChannel.call);
    ConnectionRetryController().resetBackoff(AppConnectionChannel.groupCall);
    ConnectionRetryController().resetBackoff(AppConnectionChannel.liveRoom);

    await SessionNavigationCoordinator().resetToLogin();
  }

  @visibleForTesting
  bool get isHandling => _inFlight != null;
}
