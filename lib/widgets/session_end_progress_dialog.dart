import 'package:flutter/material.dart';

import '../services/session_end_progress.dart';
import '../services/session_ui_lock.dart';
import '../theme/app_theme.dart';

Future<void> showSessionEndProgressDialog(BuildContext context) {
  if (SessionUiLock().isLocked.value) return Future<void>.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const _SessionEndProgressDialog(),
  );
}

void closeSessionEndProgressDialog(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) navigator.pop();
}

class _SessionEndProgressDialog extends StatelessWidget {
  const _SessionEndProgressDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        content: ValueListenableBuilder<SessionEndProgress>(
          valueListenable: SessionEndProgressController().state,
          builder: (context, progress, _) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        progress.operation == SessionEndOperation.deleteAccount
                            ? 'Hesap siliniyor'
                            : 'Güvenli çıkış yapılıyor',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        progress.message.isEmpty
                            ? 'Hazırlanıyor…'
                            : progress.message,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      if (progress.timedOut) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Temizlik beklenenden uzun sürdü; çıkış güvenli biçimde devam ediyor.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
