import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../theme/app_theme.dart';
import 'navigation_service.dart';
import 'session_end_progress.dart';
import 'session_feedback_lifecycle.dart';
import 'session_ui_lock.dart';
import 'foreground_event_queue.dart';

/// Oturum sona erdiğinde Navigator yığınını tek ve yarışsız biçimde giriş
/// ekranına sıfırlar.
///
/// Normal çıkış, hesap silme ve socket kaynaklı oturum süresi dolması aynı anda
/// tetiklenebilir. Bu koordinatör bütün çağrıları tek Future altında birleştirir;
/// böylece iki LoginScreen üst üste açılmaz ve eski ekranlar yığında kalmaz.
class SessionNavigationCoordinator {
  SessionNavigationCoordinator._();

  static final SessionNavigationCoordinator instance =
      SessionNavigationCoordinator._();
  factory SessionNavigationCoordinator() => instance;

  Future<void>? _inFlight;
  int _generation = 0;

  Future<void> resetToLogin() {
    return _inFlight ??= _reset().whenComplete(() => _inFlight = null);
  }

  Future<void> _reset() async {
    final generation = ++_generation;
    final uiLockGeneration = SessionUiLock().lock();

    try {
      // Oturum kapanışı başladıktan sonra önceden kuyruğa alınmış arama/push
      // olayları LoginScreen üzerinde yeniden dialog veya navigation üretmesin.
      ForegroundEventQueue().clear();

      // Bir socket callback'i, dialog kapanışı veya setState döngüsü içinden
      // çağrılmış olabilir. Navigator ağacını güvenli bir event turunda değiştir.
      await Future<void>.delayed(Duration.zero);
      if (generation != _generation) return;

      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        // Uygulama ilk frame'i henüz çizmediyse bir frame daha bekle. Bu çağrı
        // yine tekilleştirilmiş olduğundan paralel route sıfırlaması oluşmaz.
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      if (generation != _generation) return;
      final readyNavigator = navigatorKey.currentState;
      if (readyNavigator == null) return;

      _dismissTransientUi(readyNavigator);
      if (generation != _generation) return;

      readyNavigator.pushAndRemoveUntil(
        AppPageRoute(
          builder: (_) => const LoginScreen(),
          settings: const RouteSettings(name: '/login'),
        ),
        (_) => false,
      );

      // Route değişiminin en az bir frame boyunca yerleşmesini bekle. Bu süre
      // boyunca eski ekranlardan dönen async sonuçlar UI üretemez.
      await Future<void>.delayed(const Duration(milliseconds: 16));
    } finally {
      SessionUiLock().unlock(uiLockGeneration);
    }
  }

  void _dismissTransientUi(NavigatorState navigator) {
    // Snackbar/MaterialBanner eski korumalı ekrana ait olabilir. Login route'u
    // kurulmadan önce temizlenmezse yeni ekranda görünmeye devam edebilir.
    SessionFeedbackLifecycle().clearForSessionEnd();

    // ScaffoldMessenger, Navigator'dan ayrı bir overlay tuttuğu için route
    // temizlemek tek başına yeterli değildir. Eski hesaba ait snackbar/banner
    // LoginScreen üzerinde görünmesin diye messenger katmanını da açıkça
    // boşaltıyoruz. Bu çağrılar gösterilecek bir mesaj yokken no-op'tur.
    final messenger = scaffoldMessengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.clearSnackBars();
    messenger?.hideCurrentMaterialBanner();

    // Dialog, modal bottom sheet ve popup menüler PopupRoute olarak; kalıcı
    // bottom sheet'ler ise PageRoute içindeki LocalHistoryEntry olarak tutulur.
    // `willHandlePopInternally` kontrolü ikisini de sayfayı kapatmadan söker.
    navigator.popUntil(
      (route) => route is PageRoute<dynamic> && !route.willHandlePopInternally,
    );

    // Progress dialog route ile birlikte kalkar; notifier'ı da sıfırlayarak
    // sonraki çıkışta eski aşama/zaman aşımı metninin görünmesini engelle.
    SessionEndProgressController().reset();
  }

  @visibleForTesting
  bool get isNavigating => _inFlight != null;

  @visibleForTesting
  int get generation => _generation;
}
