import 'package:flutter/material.dart';

import '../services/session_feedback_actions.dart';
import '../theme/app_theme.dart';

/// Yalnız geliştirici derlemelerinde açılan, kişisel veri içermeyen feedback
/// aksiyon tanılama ekranı.
class FeedbackDiagnosticsScreen extends StatelessWidget {
  const FeedbackDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final runner = SessionFeedbackActionRunner();
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback Tanılama')),
      body: ValueListenableBuilder<int>(
        valueListenable: runner.changes,
        builder: (context, _, __) {
          final entries = runner.diagnosticSnapshot();
          if (entries.isEmpty) {
            return const Center(
              child: Text('Henüz feedback aksiyon kaydı yok.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final status = entry.status;
              final metrics = entry.metrics;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _metric('Başlatıldı', metrics.started),
                          _metric('Başarılı', metrics.succeeded),
                          _metric('Başarısız', metrics.failed),
                          _metric('Engellendi', metrics.blocked),
                          _metric('Timeout', metrics.timedOut),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Durum: ${status.running ? "çalışıyor" : status.exhausted ? "tükendi" : status.remaining > Duration.zero ? "bekliyor" : "hazır"}'
                        ' • Hata: ${status.failureCount}'
                        ' • Bekleme: ${status.remaining.inSeconds} sn',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Widget _metric(String label, int value) {
    return Text('$label: $value');
  }
}
