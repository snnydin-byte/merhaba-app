import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/discover_service.dart';
import '../theme/app_theme.dart';

/// Uyumluluk anketi (Batch E, madde 75) - sabit 5 soru, gerçek bir ML modeli
/// DEĞİL (bkz. discoverStore.js computeCompatibility notu). Cevaplar
/// profile kaydedilir, iki kullanıcı arasındaki uyum yüzdesi Keşfet
/// kartlarında gösterilir.
class DiscoverQuizScreen extends StatefulWidget {
  const DiscoverQuizScreen({super.key});

  @override
  State<DiscoverQuizScreen> createState() => _DiscoverQuizScreenState();
}

class _DiscoverQuizScreenState extends State<DiscoverQuizScreen> {
  final DiscoverService _discover = DiscoverService();
  List<CompatibilityQuestion> _questions = [];
  final Map<String, int> _answers = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final questions = await _discover.fetchQuizQuestions();
      final existing = AuthService().currentUser?.compatibilityAnswers ?? {};
      if (mounted) {
        setState(() {
          _questions = questions;
          _answers.addAll(existing);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AuthService().updateProfile(compatibilityAnswers: _answers);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Cevapların kaydedildi.')));
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Uyumluluk Anketi'), backgroundColor: Colors.transparent, elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Cevapların diğer kullanıcılarla uyum yüzdeni hesaplamak için kullanılır - '
                      'cevapların kendisi asla başkalarına gösterilmez, yalnızca yüzde paylaşılır.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    ..._questions.map(_buildQuestion),
                    const SizedBox(height: 16),
                    GradientButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Kaydet', style: AppText.button),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildQuestion(CompatibilityQuestion q) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.question,
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            ...List.generate(q.options.length, (i) {
              final selected = _answers[q.id] == i;
              return RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: i,
                groupValue: _answers[q.id],
                activeColor: AppColors.primary,
                title: Text(q.options[i],
                    style: TextStyle(color: selected ? AppColors.textPrimary : AppColors.textSecondary, fontSize: 13)),
                onChanged: (v) => setState(() => _answers[q.id] = v!),
              );
            }),
          ],
        ),
      ),
    );
  }
}
