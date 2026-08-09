import 'package:flutter/material.dart';

import '../services/session_feedback_actions.dart';
import '../services/session_feedback_queue.dart';
export '../services/session_feedback_actions.dart'
    show
        SessionFeedbackAction,
        SessionFeedbackActionButton,
        SessionFeedbackActionRunner,
        SessionFeedbackActions,
        SessionFeedbackSnackAction;
export '../services/session_feedback_queue.dart' show SessionFeedbackPriority;
import '../services/session_ui_lock.dart';

final Set<String> _activeTransientUiKeys = <String>{};
String _widgetMessageFingerprint(Widget widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? 'text';
  }
  return widget.toStringShort();
}

String _snackBarKey(SnackBar snackBar, String? explicitKey) {
  if (explicitKey != null && explicitKey.trim().isNotEmpty) {
    return 'snackbar:${explicitKey.trim()}';
  }
  final action = snackBar.action?.label ?? '';
  return 'snackbar:${_widgetMessageFingerprint(snackBar.content)}:$action';
}

String _materialBannerKey(MaterialBanner banner, String? explicitKey) {
  if (explicitKey != null && explicitKey.trim().isNotEmpty) {
    return 'banner:${explicitKey.trim()}';
  }
  final actions =
      banner.actions.map((action) => action.toStringShort()).join(',');
  return 'banner:${_widgetMessageFingerprint(banner.content)}:$actions';
}

bool _claimTransientUiKey(String? key) {
  if (key == null || key.isEmpty) return true;
  return _activeTransientUiKeys.add(key);
}

void _releaseTransientUiKey(String? key) {
  if (key == null || key.isEmpty) return;
  _activeTransientUiKeys.remove(key);
}

/// Test ve oturum sıfırlama akışları için aktif modal anahtarlarını temizler.
void resetSessionTransientUiDeduplication() {
  _activeTransientUiKeys.clear();
  SessionFeedbackActionRunner().cancelAll();
  SessionFeedbackQueue().clear();
}

/// Oturum kapanışı başladıktan sonra eski ekranlardan yeni geçici UI
/// üretilmesini engelleyen merkezi yardımcılar.
///
/// Bu katman yalnızca güvenlik kilidi açıkken çağrıyı no-op yapar; normal
/// kullanımda Flutter'ın standart dialog/sheet/snackbar davranışını korur.
Future<T?> showSessionDialog<T>({
  String? deduplicationKey,
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  if (!context.mounted ||
      !SessionUiLock().allowsTransientUi ||
      !_claimTransientUiKey(deduplicationKey)) {
    return Future<T?>.value(null);
  }
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    requestFocus: requestFocus,
    animationStyle: animationStyle,
  ).whenComplete(() => _releaseTransientUiKey(deduplicationKey));
}

Future<T?> showSessionModalBottomSheet<T>({
  String? deduplicationKey,
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  if (!context.mounted ||
      !SessionUiLock().allowsTransientUi ||
      !_claimTransientUiKey(deduplicationKey)) {
    return Future<T?>.value(null);
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: sheetAnimationStyle,
    requestFocus: requestFocus,
  ).whenComplete(() => _releaseTransientUiKey(deduplicationKey));
}

void showSessionSnackBar(
  BuildContext context,
  SnackBar snackBar, {
  String? deduplicationKey,
  Duration cooldown = const Duration(seconds: 2),
  bool replaceCurrent = false,
  SessionFeedbackPriority priority = SessionFeedbackPriority.normal,
}) {
  if (!context.mounted || !SessionUiLock().allowsTransientUi) return;
  showGlobalSessionSnackBar(
    snackBar,
    deduplicationKey: deduplicationKey,
    cooldown: cooldown,
    replaceCurrent: replaceCurrent,
    priority: priority,
  );
}

/// BuildContext taşımayan servis ve koordinatörlerin kullanabileceği global
/// snackbar girişi. Gerçek gösterim merkezi feedback kuyruğunda yapılır.
bool showGlobalSessionSnackBar(
  SnackBar snackBar, {
  String? deduplicationKey,
  Duration cooldown = const Duration(seconds: 2),
  bool replaceCurrent = false,
  SessionFeedbackPriority priority = SessionFeedbackPriority.normal,
}) {
  final key = _snackBarKey(snackBar, deduplicationKey);
  return SessionFeedbackQueue().enqueueSnackBar(
    snackBar,
    key: key,
    cooldown: cooldown,
    replaceCurrent: replaceCurrent,
    priority: priority,
  );
}

void showSessionMaterialBanner(
  BuildContext context,
  MaterialBanner banner, {
  String? deduplicationKey,
  Duration cooldown = const Duration(seconds: 3),
  bool replaceCurrent = false,
  SessionFeedbackPriority priority = SessionFeedbackPriority.normal,
}) {
  if (!context.mounted || !SessionUiLock().allowsTransientUi) return;
  showGlobalSessionMaterialBanner(
    banner,
    deduplicationKey: deduplicationKey,
    cooldown: cooldown,
    replaceCurrent: replaceCurrent,
    priority: priority,
  );
}

/// BuildContext taşımayan servislerin kullanabileceği global banner girişi.
bool showGlobalSessionMaterialBanner(
  MaterialBanner banner, {
  String? deduplicationKey,
  Duration cooldown = const Duration(seconds: 3),
  bool replaceCurrent = false,
  SessionFeedbackPriority priority = SessionFeedbackPriority.normal,
}) {
  final key = _materialBannerKey(banner, deduplicationKey);
  return SessionFeedbackQueue().enqueueMaterialBanner(
    banner,
    key: key,
    cooldown: cooldown,
    replaceCurrent: replaceCurrent,
    priority: priority,
  );
}

SnackBar sessionActionSnackBar({
  required String message,
  required SessionFeedbackAction action,
  Duration duration = const Duration(seconds: 6),
  SnackBarBehavior? behavior,
}) {
  return SnackBar(
    content: Row(
      children: [
        Expanded(child: Text(message)),
        SessionFeedbackSnackAction(action: action),
      ],
    ),
    duration: duration,
    behavior: behavior,
  );
}
