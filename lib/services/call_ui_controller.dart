import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/call_screen.dart';
import '../utils/session_transient_ui.dart';
import 'app_connection_state.dart';
import 'call_service.dart';
import 'foreground_event_queue.dart';
import 'event_deduplication_service.dart';
import 'navigation_service.dart';
import 'session_ui_lock.dart';

/// CallService'in (bkz. call_service.dart) arama daveti/başlangıcı
/// olaylarını uygulamanın HERHANGİ bir ekranından bağımsız şekilde
/// kullanıcıya gösterir (singleton).
///
/// ÖNCEDEN gelen arama diyaloğu ve CallScreen'e geçiş yalnızca Arkadaşlar
/// ekranı açıkken çalışıyordu (o ekranın kendi CallService örneğine ve
/// context'ine bağlıydı) - kullanıcı başka bir ekrandaysa (Sohbet, Ana
/// Sayfa, Profil...) arama daveti hiç ulaşmıyordu. Artık CallService
/// bağlantısı kalıcı olduğu için (bkz. orada), bu davranışı belirli bir
/// ekrana değil, [navigatorKey] üzerinden HERHANGİ bir ekranın üstüne
/// diyalog açabilen bu merkezi denetleyiciye taşıdık.
///
/// splash_screen.dart ve login_screen.dart'ta oturum kurulduğunda [wire]
/// bir kez çağrılır ve çıkışa kadar aktif kalır.
class CallUiController {
  CallUiController._internal();
  static final CallUiController instance = CallUiController._internal();
  factory CallUiController() => instance;

  bool _wired = false;
  bool _dialogShowing = false;
  bool _inCall = false;
  String? _outgoingTargetName;
  VoidCallback? _dialogPop;

  // ÖNCEDEN, karşı taraf bir aramaya hiç yanıt vermezse (ör. uygulaması
  // kapalı, telefonu erişemeyecek durumda, ya da sinyal soketinde sessiz bir
  // sorun varsa) "Aranıyor..." diyaloğu SONSUZA KADAR açık kalıyordu -
  // kullanıcının tek çıkışı elle "İptal"e basmaktı. Artık belirli bir süre
  // (bkz. _outgoingCallTimeout) sonunda otomatik olarak iptal ediyoruz.
  static const _outgoingCallTimeout = Duration(seconds: 45);
  Timer? _outgoingCallTimer;

  void _cancelOutgoingCallTimer() {
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = null;
  }

  /// CallService'in callback'lerini bu merkezi davranışa bağlar. Aynı
  /// callback'leri birden fazla kez bağlamamak için idempotent (splash VE
  /// login akışı aynı anda çağırabilir).
  void wire() {
    if (_wired) return;
    _wired = true;
    final service = CallService();

    service.onCallInviteReceived =
        (fromSocketId, fromDisplayName, callType, isRematch) {
      if (SessionUiLock().isLocked.value) {
        service.respondToCallInvite(false);
        return;
      }
      final dedupKey = 'call-invite:$fromSocketId';
      if (!EventDeduplicationService()
          .claim(dedupKey, ttl: const Duration(seconds: 45))) {
        return;
      }
      // ignore: avoid_print
      print(
          'CallUiController: davet geldi - $fromDisplayName ($callType, isRematch=$isRematch). '
          '_inCall=$_inCall _dialogShowing=$_dialogShowing currentAppContext=${currentAppContext == null ? "YOK" : "var"}');
      if (_inCall || _dialogShowing) {
        // Zaten bir görüşmedeyiz ya da başka bir diyalog açık - çakışan
        // diyaloglar açılmasın diye sessizce reddediyoruz.
        service.respondToCallInvite(false);
        return;
      }
      final queue = ForegroundEventQueue();
      if (!queue.isForeground.value || currentAppContext == null) {
        queue.enqueue(PendingForegroundEvent(
          key: 'incoming-call:$fromSocketId',
          expiresAt: DateTime.now().add(const Duration(seconds: 45)),
          isStillValid: () => service.isIncomingInvitePending(fromSocketId),
          action: () => _showIncomingCallDialog(
            fromDisplayName,
            callType,
            service,
            isRematch,
          ),
        ));
        return;
      }
      _showIncomingCallDialog(fromDisplayName, callType, service, isRematch);
    };

    service.onCallInviteSent = () {
      // Giden arama sunucuya ulaştı - "Aranıyor..." diyaloğu zaten açık.
    };

    service.onCallInviteDeclined = () {
      _cancelOutgoingCallTimer();
      _dialogPop?.call();
      _showSnack('${_outgoingTargetName ?? 'Kullanıcı'} aramayı reddetti.');
      _outgoingTargetName = null;
    };

    service.onCallInviteError = (message) {
      _cancelOutgoingCallTimer();
      _dialogPop?.call();
      _showSnack(message, retryable: true);
      _outgoingTargetName = null;
    };

    service.onCallInviteCancelled = () {
      _cancelOutgoingCallTimer();
      _dialogPop?.call();
    };

    service.onCallStarted = (callType) {
      _cancelOutgoingCallTimer();
      if (SessionUiLock().isLocked.value) {
        _dialogPop?.call();
        _inCall = false;
        return;
      }
      _dialogPop?.call();
      _inCall = true;
      final peerName = _outgoingTargetName ?? 'Kullanıcı';
      _outgoingTargetName = null;

      final navState = navigatorKey.currentState;
      if (navState == null) {
        _inCall = false;
        return;
      }
      navState
          .push(MaterialPageRoute(
            builder: (_) => CallScreen(
              callService: service,
              peerDisplayName: peerName,
              callType: callType,
            ),
          ))
          .then((_) => _inCall = false);
    };
  }

  /// Bir arkadaşı aramaya başlarken (bkz. friends_screen.dart) çağrılır -
  /// "Aranıyor..." diyaloğunu gösterir ve daveti gönderir.
  Future<void> startCall({
    required String friendId,
    required String friendDisplayName,
    required String callType,
  }) async {
    if (SessionUiLock().isLocked.value) return;
    _outgoingTargetName = friendDisplayName;
    CallService().inviteToCall(friendId: friendId, callType: callType);
    _cancelOutgoingCallTimer();
    _outgoingCallTimer = Timer(_outgoingCallTimeout, () {
      // Süre doldu, karşı taraf hâlâ yanıt vermedi - daveti sunucu
      // tarafında da iptal ediyoruz (karşı tarafın gelen arama diyaloğu
      // varsa o da kapanır, bkz. server.js 'call-invite-cancel') ve
      // kendi diyaloğumuzu kapatıp kullanıcıyı bilgilendiriyoruz.
      CallService().cancelOutgoingCall();
      _dialogPop?.call();
      _showSnack('${_outgoingTargetName ?? 'Kullanıcı'} yanıt vermedi.');
      _outgoingTargetName = null;
    });
    await _showOutgoingCallDialog(friendDisplayName, callType);
    _cancelOutgoingCallTimer();
  }

  /// "Tekrar eşleş" (GECE_GELISTIRME madde 2) - startCall()'ın rematch
  /// eşiti. video_chat_screen.dart, karşı taraf (hesaplıysa) ayrıldığında
  /// gösterdiği "Tekrar Eşleş" snackbar aksiyonundan çağırır. Aynı "Aranıyor
  /// ..." diyaloğu ve zaman aşımı mantığı kullanılıyor, tek fark
  /// CallService.inviteToCall() yerine requestRematch() çağrılması (hedef
  /// sunucu tarafında zaten biliniyor, bkz. orada).
  Future<void> requestRematch(String partnerDisplayName) async {
    if (SessionUiLock().isLocked.value) return;
    _outgoingTargetName = partnerDisplayName;
    CallService().requestRematch();
    _cancelOutgoingCallTimer();
    _outgoingCallTimer = Timer(_outgoingCallTimeout, () {
      CallService().cancelOutgoingCall();
      _dialogPop?.call();
      _showSnack('${_outgoingTargetName ?? 'Kullanıcı'} yanıt vermedi.');
      _outgoingTargetName = null;
    });
    await _showOutgoingCallDialog(partnerDisplayName, 'video');
    _cancelOutgoingCallTimer();
  }

  void _showSnack(String message, {bool retryable = false}) {
    if (SessionUiLock().isLocked.value) return;
    final context = currentAppContext;
    if (context == null) return;
    showSessionSnackBar(
      context,
      retryable
          ? SessionFeedbackActions.connectionSnackBar(
              message: message,
              channel: AppConnectionChannel.call,
            )
          : SnackBar(content: Text(message)),
      deduplicationKey: 'call-ui:$message',
      priority: retryable
          ? SessionFeedbackPriority.high
          : SessionFeedbackPriority.normal,
    );
  }

  Future<void> _showOutgoingCallDialog(
      String friendName, String callType) async {
    if (SessionUiLock().isLocked.value) return;
    final context = currentAppContext;
    if (context == null) return;
    _dialogShowing = true;
    await showDialog<void>(
      context: context,
      // Geri tuşu/gesture ile sessizce kapatılırsa sunucudaki daveti hiç
      // iptal etmemiş oluruz - arayan taraf (biz) "İptal" demeden dialog
      // kaybolursa, karşı taraf hâlâ bizi arıyor sanıp bekler. PopScope
      // bunu engelliyor, yalnızca "İptal" butonu kapatabilir.
      barrierDismissible: false,
      builder: (dialogContext) {
        _dialogPop = () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        };
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A1035),
            title: Text(
              callType == 'video' ? 'Görüntülü arama' : 'Sesli arama',
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              '$friendName aranıyor...',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _cancelOutgoingCallTimer();
                  CallService().cancelOutgoingCall();
                  Navigator.pop(dialogContext);
                },
                child: const Text('İptal',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        );
      },
    );
    _dialogShowing = false;
    _dialogPop = null;
  }

  Future<void> _showIncomingCallDialog(String fromDisplayName, String callType,
      CallService service, bool isRematch) async {
    if (SessionUiLock().isLocked.value) {
      service.respondToCallInvite(false);
      return;
    }
    final context = currentAppContext;
    if (context == null) {
      // Gösterecek bir ekran yok (uygulama henüz hiç açılmadı) - sessizce
      // reddet, push bildirimi zaten ayrıca kullanıcıyı bilgilendirir.
      service.respondToCallInvite(false);
      return;
    }
    _dialogShowing = true;
    await showDialog<void>(
      context: context,
      // Aynı gerekçe: geri tuşuyla sessizce kapatılırsa arayan taraf
      // cevapsız kalır, sonsuza dek "aranıyor..." görür. Yalnızca
      // "Kabul Et"/"Reddet" butonları kapatabilsin.
      barrierDismissible: false,
      builder: (dialogContext) {
        _dialogPop = () {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        };
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A1035),
            title: Text(
              isRematch
                  ? 'Tekrar Eşleş'
                  : (callType == 'video' ? 'Görüntülü arama' : 'Sesli arama'),
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              isRematch
                  ? '$fromDisplayName seninle tekrar görüşmek istiyor.'
                  : '$fromDisplayName seni arıyor.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  service.respondToCallInvite(false);
                  Navigator.pop(dialogContext);
                },
                child: const Text('Reddet'),
              ),
              TextButton(
                onPressed: () {
                  service.respondToCallInvite(true);
                  Navigator.pop(dialogContext);
                },
                child: const Text('Kabul Et',
                    style: TextStyle(color: Color(0xFF00BFA5))),
              ),
            ],
          ),
        );
      },
    );
    _dialogShowing = false;
    _dialogPop = null;
  }
}
