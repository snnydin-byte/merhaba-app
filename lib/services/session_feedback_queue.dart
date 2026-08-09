import 'dart:async';
import 'package:flutter/material.dart';

import 'navigation_service.dart';
import 'session_ui_lock.dart';

enum SessionFeedbackKind { snackBar, materialBanner }

enum SessionFeedbackPriority { low, normal, high, critical }

extension SessionFeedbackPriorityRank on SessionFeedbackPriority {
  int get rank => index;
}

String _feedbackText(Widget content) {
  if (content is Text) {
    return (content.data ?? content.textSpan?.toPlainText() ?? '')
        .toLowerCase();
  }
  return content.toStringShort().toLowerCase();
}

/// Açıkça `normal` bırakılan dinamik mesajları çalışma anında sınıflandırır.
/// Ekranlar yine kritik akışlarda açık priority verebilir; bu yardımcı özellikle
/// sunucudan gelen `e.message` gibi metinlerin sırada kaybolmasını önler.
@visibleForTesting
SessionFeedbackPriority inferSessionFeedbackPriority(
  Widget content,
  SessionFeedbackPriority requested,
) {
  if (requested != SessionFeedbackPriority.normal) return requested;

  final message = _feedbackText(content);
  const criticalTerms = <String>[
    'oturumun süresi doldu',
    'yeniden giriş yap',
    'hesap silindi',
    'hesabın silindi',
    'güvenlik nedeniyle',
    'auth_expired',
  ];
  const highTerms = <String>[
    'erişim',
    'yetki',
    'engellendi',
    'gruptan çıkar',
    'yayın sona',
    'oda sona',
    'bağlantı koptu',
    'sunucuya ulaşılamıyor',
    'başarısız',
    'kaydedilemedi',
    'yüklenemedi',
    'gönderilemedi',
    'açılamadı',
    'bulunamadı',
    'geçersiz',
    'zaman aşımı',
    'hata oluştu',
    'ters gitti',
  ];
  const lowTerms = <String>[
    'başarıyla',
    'kaydedildi',
    'güncellendi',
    'gönderildi',
    'eklendi',
    'kopyalandı',
    'tamamlandı',
    'oluşturuldu',
    'yüklendi',
    'temizlendi',
    'isteğin alındı',
    'şikayetin alındı',
    'bildirimin alındı',
  ];

  if (criticalTerms.any(message.contains)) {
    return SessionFeedbackPriority.critical;
  }
  if (highTerms.any(message.contains)) {
    return SessionFeedbackPriority.high;
  }
  if (lowTerms.any(message.contains)) {
    return SessionFeedbackPriority.low;
  }
  return SessionFeedbackPriority.normal;
}

class _SessionFeedbackRequest {
  const _SessionFeedbackRequest.snackBar({
    required this.key,
    required this.snackBar,
    required this.replaceCurrent,
    required this.priority,
  })  : kind = SessionFeedbackKind.snackBar,
        materialBanner = null;

  const _SessionFeedbackRequest.materialBanner({
    required this.key,
    required this.materialBanner,
    required this.replaceCurrent,
    required this.priority,
  })  : kind = SessionFeedbackKind.materialBanner,
        snackBar = null;

  final String key;
  final SessionFeedbackKind kind;
  final SnackBar? snackBar;
  final MaterialBanner? materialBanner;
  final bool replaceCurrent;
  final SessionFeedbackPriority priority;
}

/// Uygulama genelindeki snackbar ve MaterialBanner mesajlarını tek sırada
/// gösterir. Kaynak ekranın BuildContext'ine bağlı değildir; böylece aynı hata
/// farklı ekranlardan aynı anda gelse bile tek bir global geri bildirim üretilir.
class SessionFeedbackQueue {
  SessionFeedbackQueue._();
  static final SessionFeedbackQueue instance = SessionFeedbackQueue._();
  factory SessionFeedbackQueue() => instance;

  static const int _maxPending = 12;

  final List<_SessionFeedbackRequest> _pending = <_SessionFeedbackRequest>[];
  final Set<String> _queuedOrActiveKeys = <String>{};
  final Map<String, DateTime> _cooldowns = <String, DateTime>{};

  bool _processing = false;
  bool _frameRetryScheduled = false;
  int _generation = 0;
  _SessionFeedbackRequest? _activeSnackBar;
  SessionFeedbackPriority? _activeBannerPriority;
  String? _activeBannerKey;

  bool enqueueSnackBar(
    SnackBar snackBar, {
    required String key,
    Duration cooldown = const Duration(seconds: 2),
    bool replaceCurrent = false,
    SessionFeedbackPriority priority = SessionFeedbackPriority.normal,
  }) {
    if (!_claim(key, cooldown)) return false;
    _enqueue(_SessionFeedbackRequest.snackBar(
      key: key,
      snackBar: snackBar,
      replaceCurrent: replaceCurrent,
      priority: inferSessionFeedbackPriority(snackBar.content, priority),
    ));
    return true;
  }

  bool enqueueMaterialBanner(
    MaterialBanner banner, {
    required String key,
    Duration cooldown = const Duration(seconds: 3),
    bool replaceCurrent = false,
    SessionFeedbackPriority priority = SessionFeedbackPriority.normal,
  }) {
    if (!_claim(key, cooldown)) return false;
    _enqueue(_SessionFeedbackRequest.materialBanner(
      key: key,
      materialBanner: banner,
      replaceCurrent: replaceCurrent,
      priority: inferSessionFeedbackPriority(banner.content, priority),
    ));
    return true;
  }

  void _enqueue(_SessionFeedbackRequest request) {
    final messenger = scaffoldMessengerKey.currentState;

    if (request.priority == SessionFeedbackPriority.critical) {
      _dropPendingWhere(
          (queued) => queued.priority.rank < SessionFeedbackPriority.high.rank);
    }

    final activeSnackBar = _activeSnackBar;
    if (activeSnackBar != null &&
        request.priority.rank > activeSnackBar.priority.rank &&
        request.priority.rank >= SessionFeedbackPriority.high.rank) {
      messenger?.hideCurrentSnackBar();
    }

    final activeBannerPriority = _activeBannerPriority;
    if (activeBannerPriority != null &&
        request.priority.rank > activeBannerPriority.rank &&
        request.priority.rank >= SessionFeedbackPriority.high.rank) {
      messenger?.hideCurrentMaterialBanner();
    }

    while (_pending.length >= _maxPending) {
      final lowIndex = _pending.lastIndexWhere(
        (queued) => queued.priority == SessionFeedbackPriority.low,
      );
      final normalIndex = _pending.lastIndexWhere(
        (queued) => queued.priority == SessionFeedbackPriority.normal,
      );
      final dropIndex = lowIndex >= 0
          ? lowIndex
          : normalIndex >= 0
              ? normalIndex
              : _pending.length - 1;
      _removePendingAt(dropIndex);
    }

    final insertionIndex = _pending.indexWhere(
      (queued) => queued.priority.rank < request.priority.rank,
    );
    if (insertionIndex < 0) {
      _pending.add(request);
    } else {
      _pending.insert(insertionIndex, request);
    }
    _scheduleProcessing();
  }

  void _dropPendingWhere(bool Function(_SessionFeedbackRequest) predicate) {
    for (var index = _pending.length - 1; index >= 0; index--) {
      if (predicate(_pending[index])) _removePendingAt(index);
    }
  }

  void _removePendingAt(int index) {
    final removed = _pending.removeAt(index);
    _queuedOrActiveKeys.remove(removed.key);
  }

  bool _claim(String key, Duration cooldown) {
    if (!SessionUiLock().allowsTransientUi) return false;

    final now = DateTime.now();
    if (_cooldowns.length > 128) {
      _cooldowns.removeWhere((_, blockedUntil) => !now.isBefore(blockedUntil));
    }

    final blockedUntil = _cooldowns[key];
    if (blockedUntil != null && now.isBefore(blockedUntil)) return false;
    if (!_queuedOrActiveKeys.add(key)) return false;

    _cooldowns[key] = now.add(cooldown);
    return true;
  }

  void _scheduleProcessing() {
    if (_processing) return;
    unawaited(_process());
  }

  Future<void> _process() async {
    if (_processing) return;
    _processing = true;
    final generation = _generation;

    try {
      while (_pending.isNotEmpty && generation == _generation) {
        if (!SessionUiLock().allowsTransientUi) {
          clear();
          return;
        }

        final messenger = scaffoldMessengerKey.currentState;
        if (messenger == null) {
          _scheduleFrameRetry();
          return;
        }

        final request = _pending.removeAt(0);
        if (request.kind == SessionFeedbackKind.snackBar) {
          _activeSnackBar = request;
          try {
            if (request.replaceCurrent) messenger.hideCurrentSnackBar();
            final controller = messenger.showSnackBar(request.snackBar!);
            await controller.closed;
          } finally {
            if (identical(_activeSnackBar, request)) _activeSnackBar = null;
            _queuedOrActiveKeys.remove(request.key);
          }
        } else {
          _activeBannerPriority = request.priority;
          _activeBannerKey = request.key;
          if (request.replaceCurrent) messenger.hideCurrentMaterialBanner();
          final controller = messenger.showMaterialBanner(
            request.materialBanner!,
          );
          // Banner kullanıcı aksiyonuna kadar açık kalabilir. Snackbar kuyruğunu
          // bloke etmemesi için kapanışı arka planda izlenir.
          unawaited(controller.closed.whenComplete(() {
            _queuedOrActiveKeys.remove(request.key);
            if (_activeBannerKey == request.key) {
              _activeBannerPriority = null;
              _activeBannerKey = null;
            }
          }));
        }
      }
    } finally {
      _processing = false;
      if (_pending.isNotEmpty &&
          generation == _generation &&
          scaffoldMessengerKey.currentState != null) {
        _scheduleProcessing();
      }
    }
  }

  void _scheduleFrameRetry() {
    if (_frameRetryScheduled) return;
    _frameRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameRetryScheduled = false;
      if (_pending.isNotEmpty) _scheduleProcessing();
    });
  }

  /// Oturum kapanışı/test sıfırlaması sırasında aktif ve bekleyen geri
  /// bildirimleri birlikte temizler.
  void clear() {
    _generation++;
    _pending.clear();
    _queuedOrActiveKeys.clear();
    _cooldowns.clear();
    _frameRetryScheduled = false;
    _activeSnackBar = null;
    _activeBannerPriority = null;
    _activeBannerKey = null;

    final messenger = scaffoldMessengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..clearSnackBars()
      ..hideCurrentMaterialBanner();
  }

  @visibleForTesting
  int get pendingCount => _pending.length;

  @visibleForTesting
  bool get isProcessing => _processing;
}
