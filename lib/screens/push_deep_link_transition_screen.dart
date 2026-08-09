import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/foreground_event_queue.dart';
import '../services/network_availability_monitor.dart';
import '../services/push_deep_link_resolver.dart';
import '../services/push_notification_platform.dart';
import '../theme/app_theme.dart';

class PushDeepLinkTransitionScreen extends StatefulWidget {
  const PushDeepLinkTransitionScreen({
    super.key,
    required this.payload,
    required this.resolver,
    required this.destinationBuilder,
    this.networkMonitor,
    this.sessionListenable,
    this.foregroundListenable,
  });

  final PushNotificationPayload payload;
  final PushDeepLinkResolver resolver;
  final Widget Function(PushDeepLinkTarget target) destinationBuilder;
  final NetworkAvailabilityMonitor? networkMonitor;
  final ValueListenable<AuthSessionState>? sessionListenable;
  final ValueListenable<bool>? foregroundListenable;

  @override
  State<PushDeepLinkTransitionScreen> createState() =>
      _PushDeepLinkTransitionScreenState();
}

class _PushDeepLinkTransitionScreenState
    extends State<PushDeepLinkTransitionScreen> {
  bool _loading = true;
  static const int _maxRetryAttempts = 3;

  bool _retrying = false;
  int _resolveGeneration = 0;
  int _retryAttempts = 0;
  int _retryCooldownSeconds = 0;
  Timer? _retryCooldownTimer;
  StreamSubscription<bool>? _networkSubscription;
  late final NetworkAvailabilityMonitor _networkMonitor;
  late final ValueListenable<AuthSessionState> _sessionListenable;
  late final ValueListenable<bool> _foregroundListenable;
  late final String? _initialUserId;
  late final String? _initialToken;
  bool _networkAvailable = true;
  bool _retryResetAfterRecovery = false;
  bool _automaticRecoveryRetryUsed = false;
  bool _navigationAbandoned = false;
  bool _destinationNavigationStarted = false;
  PushDeepLinkTarget? _target;
  String? _message;

  @override
  void initState() {
    super.initState();
    _networkMonitor =
        widget.networkMonitor ?? ConnectivityNetworkAvailabilityMonitor();
    _sessionListenable = widget.sessionListenable ?? AuthService().sessionState;
    _foregroundListenable =
        widget.foregroundListenable ?? ForegroundEventQueue().isForeground;
    _initialUserId = _sessionListenable.value.user?.id;
    _initialToken = _sessionListenable.value.token;
    _sessionListenable.addListener(_onNavigationGuardChanged);
    _foregroundListenable.addListener(_onNavigationGuardChanged);
    _networkSubscription =
        _networkMonitor.availabilityChanges.listen(_onNetworkAvailability);
    unawaited(_loadInitialNetworkState());
    unawaited(_resolve());
  }

  bool get _sessionStillValid {
    final state = _sessionListenable.value;
    return state.isAuthenticated &&
        state.user?.id == _initialUserId &&
        state.token == _initialToken;
  }

  bool get _appIsForeground => _foregroundListenable.value;

  void _onNavigationGuardChanged() {
    if (!mounted || _destinationNavigationStarted || _navigationAbandoned) {
      return;
    }
    if (!_sessionStillValid) {
      _invalidateResolvedNavigation(
        const PushFriendsFallbackTarget(
          PushDeepLinkFailureReason.sessionExpired,
        ),
      );
      return;
    }
    if (!_appIsForeground && !_loading) {
      _invalidateResolvedNavigation(
        const PushFriendsFallbackTarget(
          PushDeepLinkFailureReason.appBackgrounded,
        ),
      );
    }
  }

  void _invalidateResolvedNavigation(PushDeepLinkFailureTarget target) {
    _resolveGeneration++;
    _retryCooldownTimer?.cancel();
    setState(() {
      _loading = false;
      _retrying = false;
      _retryCooldownSeconds = 0;
      _target = target;
      _message = _messageFor(target.reason);
    });
  }

  bool _sameDestination(PushDeepLinkTarget first, PushDeepLinkTarget second) {
    return switch ((first, second)) {
      (
        PushFriendChatTarget(:final friend),
        PushFriendChatTarget(friend: final friend2)
      ) =>
        friend.id == friend2.id,
      (
        PushGroupChatTarget(:final group),
        PushGroupChatTarget(group: final group2)
      ) =>
        group.id == group2.id,
      (
        PushLiveRoomTarget(:final roomId),
        PushLiveRoomTarget(roomId: final roomId2)
      ) =>
        roomId == roomId2,
      _ => first.runtimeType == second.runtimeType,
    };
  }

  Future<void> _loadInitialNetworkState() async {
    final available = await _networkMonitor.isAvailable();
    if (!mounted) return;
    setState(() => _networkAvailable = available);
  }

  void _onNetworkAvailability(bool available) {
    if (!mounted) return;
    final recovered = !_networkAvailable && available;
    setState(() {
      _networkAvailable = available;
      if (!available) {
        _automaticRecoveryRetryUsed = false;
      }
      if (recovered && _isNetworkFailure) {
        _retryAttempts = 0;
        _retryResetAfterRecovery = true;
        _retryCooldownTimer?.cancel();
        _retryCooldownSeconds = 0;
        _message =
            'İnternet bağlantısı geri geldi. İçerik otomatik olarak yeniden doğrulanıyor.';
      }
    });
    if (recovered && _isNetworkFailure) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_runAutomaticRecoveryRetry());
      });
    }
  }

  Future<void> _runAutomaticRecoveryRetry() async {
    if (!mounted ||
        !_networkAvailable ||
        !_isNetworkFailure ||
        _automaticRecoveryRetryUsed ||
        _loading ||
        _retrying) {
      return;
    }
    _automaticRecoveryRetryUsed = true;
    await _resolve(automaticRecovery: true);
  }

  Future<void> _resolve({
    bool retry = false,
    bool automaticRecovery = false,
  }) async {
    if (_retrying ||
        ((retry || automaticRecovery) && _loading) ||
        (retry && !_canRetryNow)) {
      return;
    }
    if (retry) {
      _retryAttempts++;
    }
    if (retry || automaticRecovery) {
      _retryResetAfterRecovery = false;
    }
    _retryCooldownTimer?.cancel();
    _retryCooldownSeconds = 0;
    final generation = ++_resolveGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _retrying = retry || automaticRecovery;
        _message = null;
      });
    }

    final target = await widget.resolver.resolve(widget.payload);
    if (!mounted ||
        generation != _resolveGeneration ||
        _navigationAbandoned ||
        _destinationNavigationStarted) {
      return;
    }

    if (target is PushDeepLinkFailureTarget) {
      setState(() {
        _loading = false;
        _retrying = false;
        _target = target;
        _message = _messageFor(target.reason);
      });
      if (target.reason == PushDeepLinkFailureReason.network &&
          _retryAttempts < _maxRetryAttempts) {
        _startRetryCooldown();
      }
      return;
    }

    setState(() {
      _loading = false;
      _retrying = false;
      _target = target;
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted ||
        generation != _resolveGeneration ||
        _navigationAbandoned ||
        _destinationNavigationStarted) {
      return;
    }
    if (!_sessionStillValid) {
      _invalidateResolvedNavigation(
        const PushFriendsFallbackTarget(
          PushDeepLinkFailureReason.sessionExpired,
        ),
      );
      return;
    }
    if (!_appIsForeground) {
      _invalidateResolvedNavigation(
        const PushFriendsFallbackTarget(
          PushDeepLinkFailureReason.appBackgrounded,
        ),
      );
      return;
    }

    // İlk çözümleme ile gerçek Navigator geçişi arasındaki kısa sürede
    // arkadaşlık/grup üyeliği değişmiş olabilir. Hedefi son kez sunucudan
    // doğrula; farklı veya başarısız bir sonuç geldiyse eski hedefi açma.
    final revalidatedTarget = await widget.resolver.resolve(widget.payload);
    if (!mounted ||
        generation != _resolveGeneration ||
        _navigationAbandoned ||
        _destinationNavigationStarted) {
      return;
    }
    if (revalidatedTarget is PushDeepLinkFailureTarget) {
      _invalidateResolvedNavigation(revalidatedTarget);
      return;
    }
    if (!_sameDestination(target, revalidatedTarget) ||
        !_sessionStillValid ||
        !_appIsForeground) {
      _invalidateResolvedNavigation(
        const PushFriendsFallbackTarget(
          PushDeepLinkFailureReason.permissionLost,
        ),
      );
      return;
    }

    _destinationNavigationStarted = true;
    await Navigator.of(context).pushReplacement(
      AppPageRoute(
        builder: (_) => widget.destinationBuilder(revalidatedTarget),
      ),
    );
  }

  bool get _isNetworkFailure =>
      _target is PushDeepLinkFailureTarget &&
      (_target as PushDeepLinkFailureTarget).reason ==
          PushDeepLinkFailureReason.network;

  bool get _retryLimitReached => _retryAttempts >= _maxRetryAttempts;

  bool get _isLifecycleFailure =>
      _target is PushDeepLinkFailureTarget &&
      (_target as PushDeepLinkFailureTarget).reason ==
          PushDeepLinkFailureReason.appBackgrounded;

  bool get _canRetry =>
      ((_isNetworkFailure && !_retryLimitReached && _networkAvailable) ||
          (_isLifecycleFailure && _appIsForeground && _sessionStillValid));

  bool get _canRetryNow =>
      _canRetry && !_retrying && _retryCooldownSeconds == 0;

  void _startRetryCooldown() {
    _retryCooldownTimer?.cancel();
    final seconds = switch (_retryAttempts) {
      0 => 2,
      1 => 4,
      _ => 8,
    };
    if (!mounted) return;
    setState(() => _retryCooldownSeconds = seconds);
    _retryCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retryCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _retryCooldownSeconds = 0);
      } else {
        setState(() => _retryCooldownSeconds--);
      }
    });
  }

  Future<void> _retry() => _resolve(retry: true);

  String _messageFor(PushDeepLinkFailureReason reason) => switch (reason) {
        PushDeepLinkFailureReason.notFound =>
          'Bu içerik artık bulunamıyor veya kaldırılmış olabilir.',
        PushDeepLinkFailureReason.permissionLost =>
          'Bu içeriğe erişim yetkin artık bulunmuyor.',
        PushDeepLinkFailureReason.invalidPayload =>
          'Bildirim bağlantısı eksik veya geçersiz.',
        PushDeepLinkFailureReason.network => _retryLimitReached
            ? 'İçerik üç denemeden sonra doğrulanamadı. Bağlantını kontrol edip daha sonra yeniden açabilirsin.'
            : 'İçerik doğrulanamadı. Bağlantını kontrol edip tekrar deneyebilirsin.',
        PushDeepLinkFailureReason.appBackgrounded =>
          'Uygulama arka plana geçtiği için geçiş durduruldu. Ön plandayken yeniden deneyebilirsin.',
        PushDeepLinkFailureReason.sessionExpired =>
          'Oturum değişti veya kapandı. Bildirim bağlantısı güvenlik nedeniyle açılmadı.',
      };

  void _abandonPendingNavigation() {
    if (_navigationAbandoned) return;
    _navigationAbandoned = true;
    _resolveGeneration++;
    _retryCooldownTimer?.cancel();
    _retryCooldownSeconds = 0;
  }

  void _handleSystemBack(bool didPop, Object? result) {
    if (didPop) _abandonPendingNavigation();
  }

  @override
  void dispose() {
    _abandonPendingNavigation();
    _retryCooldownTimer?.cancel();
    unawaited(_networkSubscription?.cancel());
    _sessionListenable.removeListener(_onNavigationGuardChanged);
    _foregroundListenable.removeListener(_onNavigationGuardChanged);
    super.dispose();
  }

  Future<void> _continueToFallback() async {
    final target = _target;
    if (target == null ||
        !mounted ||
        _destinationNavigationStarted ||
        (target is PushDeepLinkFailureTarget &&
            target.reason == PushDeepLinkFailureReason.sessionExpired)) {
      return;
    }
    _abandonPendingNavigation();
    _destinationNavigationStarted = true;
    await Navigator.of(context).pushReplacement(
      AppPageRoute(builder: (_) => widget.destinationBuilder(target)),
    );
  }

  Future<void> _closeTransition() async {
    if (!mounted || _destinationNavigationStarted) return;
    _abandonPendingNavigation();
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _handleSystemBack,
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_loading) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 18),
                          Text(
                            'İçerik hazırlanıyor…',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Erişim ve üyelik bilgileri doğrulanıyor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ] else ...[
                          Icon(
                            Icons.link_off_rounded,
                            size: 42,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Bağlantı açılamadı',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _message ?? 'İçerik şu anda kullanılamıyor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 20),
                          if (_isNetworkFailure && !_networkAvailable) ...[
                            Text(
                              'İnternet bağlantısı bekleniyor…',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else if (_canRetry) ...[
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _canRetryNow ? _retry : null,
                                icon: _retrying
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded),
                                label: Text(
                                  _retrying
                                      ? 'Yeniden deneniyor…'
                                      : _retryResetAfterRecovery
                                          ? 'Bağlantı geri geldi — otomatik deneniyor'
                                          : _retryCooldownSeconds > 0
                                              ? '$_retryCooldownSeconds sn sonra dene'
                                              : 'Tekrar dene',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else if (_isNetworkFailure &&
                              _retryLimitReached) ...[
                            Text(
                              'Maksimum deneme sayısına ulaşıldı.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (!(_target is PushDeepLinkFailureTarget &&
                              (_target as PushDeepLinkFailureTarget).reason ==
                                  PushDeepLinkFailureReason
                                      .sessionExpired)) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed:
                                    _retrying ? null : _continueToFallback,
                                child: const Text('Güvenli ekrana git'),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          TextButton(
                            onPressed: _closeTransition,
                            child: const Text('Kapat'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
