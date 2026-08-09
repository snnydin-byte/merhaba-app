import 'package:flutter/material.dart';

import '../services/navigation_service.dart';

import 'session_transient_ui.dart';

/// Closes transient UI owned by the current screen before a security-driven
/// navigation (access revoked, room ended, membership removed, etc.).
///
/// A dialog or bottom sheet is represented by a [PopupRoute]. Popping until
/// the first [PageRoute] keeps the current page in place while removing those
/// transient routes. The keyboard and any stale snackbar are cleared as well.
void dismissTransientUi(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();

  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.popUntil((route) => route is PageRoute<dynamic>);
}

/// Replaces the current protected surface with a safe destination after first
/// removing dialogs, sheets, menus and keyboard state that belong to it.
///
/// [message] is displayed on the destination screen, not on the revoked
/// screen, so it remains visible after the route replacement.
void navigateAfterAccessLoss(
  BuildContext context, {
  required WidgetBuilder destination,
  required String message,
}) {
  dismissTransientUi(context);
  if (!context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: destination),
    (route) => route.isFirst,
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.context.mounted) return;
    showSessionSnackBar(
      navigator.context,
      SessionFeedbackActions.securitySnackBar(
        message: message,
        onSafeDestination: () {
          final state = navigatorKey.currentState;
          if (state == null) return;
          state.pushAndRemoveUntil(
            MaterialPageRoute(builder: destination),
            (route) => route.isFirst,
          );
        },
      ),
      deduplicationKey: 'access-loss:$message',
      replaceCurrent: true,
      priority: SessionFeedbackPriority.high,
    );
  });
}
