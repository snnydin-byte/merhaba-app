import 'package:flutter/material.dart';

import '../services/app_connection_state.dart';
import '../services/connection_retry_controller.dart';
import '../services/session_feedback_actions.dart';
import '../theme/app_theme.dart';

class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({
    super.key,
    this.channel,
    this.margin = const EdgeInsets.only(top: 10),
    this.compact = false,
    this.showRetry = true,
  });

  final AppConnectionChannel? channel;
  final EdgeInsetsGeometry margin;
  final bool compact;
  final bool showRetry;

  @override
  Widget build(BuildContext context) {
    final retryController = ConnectionRetryController();
    return ValueListenableBuilder<AppConnectionState>(
      valueListenable: AppConnectionController().state,
      builder: (context, state, _) {
        return ValueListenableBuilder<int>(
          valueListenable: retryController.changes,
          builder: (context, _, __) => _buildBanner(
            context,
            state,
            retryController,
          ),
        );
      },
    );
  }

  Widget _buildBanner(
    BuildContext context,
    AppConnectionState state,
    ConnectionRetryController retryController,
  ) {
    final channels = channel == null
        ? const [AppConnectionChannel.messaging, AppConnectionChannel.call]
        : [channel!];
    final statuses = channels.map(state.statusFor).toList(growable: false);
    if (statuses.every((status) =>
        status.phase == SocketConnectionPhase.connected ||
        status.phase == SocketConnectionPhase.disconnected)) {
      return const SizedBox.shrink();
    }

    final status = statuses.firstWhere(
      (item) => item.phase == SocketConnectionPhase.error,
      orElse: () => statuses.firstWhere(
        (item) => item.isBusy,
        orElse: () => statuses.first,
      ),
    );
    final hasError = status.phase == SocketConnectionPhase.error;
    final isBusy = status.isBusy;
    final text = status.message ??
        (hasError
            ? 'Bağlantı kurulamadı.'
            : isBusy
                ? 'Bağlantı yenileniyor…'
                : 'Bağlantı kesildi.');

    final retryChannels = channels
        .where((item) =>
            state.statusFor(item).phase == SocketConnectionPhase.error &&
            state.statusFor(item).retryable)
        .toList(growable: false);
    final remaining = retryChannels.map(retryController.remainingFor).fold(
        Duration.zero, (longest, item) => item > longest ? item : longest);
    final retryAvailable = retryChannels.isNotEmpty &&
        retryChannels.every(retryController.canRetry);
    final retrySeconds = remaining.inSeconds +
        (remaining.inMilliseconds % Duration.millisecondsPerSecond == 0
            ? 0
            : 1);

    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        width: double.infinity,
        margin: margin,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: hasError
              ? AppColors.danger.withValues(alpha: 0.12)
              : AppColors.secondary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hasError
                ? AppColors.danger.withValues(alpha: 0.35)
                : AppColors.secondary.withValues(alpha: 0.30),
          ),
        ),
        child: Row(
          children: [
            if (isBusy)
              SizedBox(
                width: compact ? 14 : 16,
                height: compact ? 14 : 16,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                status.failureKind == ConnectionFailureKind.sessionExpired
                    ? Icons.lock_clock_rounded
                    : status.failureKind == ConnectionFailureKind.offline
                        ? Icons.wifi_off_rounded
                        : hasError
                            ? Icons.cloud_off_rounded
                            : Icons.wifi_off_rounded,
                size: compact ? 16 : 18,
                color: hasError ? AppColors.danger : AppColors.secondary,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showRetry && hasError) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (_) {
                  final sessionExpired = status.failureKind ==
                      ConnectionFailureKind.sessionExpired;
                  final action = channel == null
                      ? SessionFeedbackActions.forPersistentConnections(
                          statuses)
                      : SessionFeedbackActions.forConnectionStatus(
                          status,
                          channel!,
                        );
                  if (action == null) return const SizedBox.shrink();
                  if (!sessionExpired && retrySeconds > 0) {
                    return TextButton(
                      onPressed: null,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 7 : 9,
                          vertical: compact ? 4 : 5,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '$retrySeconds sn',
                        style: TextStyle(fontSize: compact ? 10 : 11),
                      ),
                    );
                  }
                  return SessionFeedbackActionButton(
                    action: action,
                    compact: compact,
                    enabled: sessionExpired || retryAvailable,
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
