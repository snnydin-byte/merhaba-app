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
  final PageController _pageController = PageController();
  List<CompatibilityQuestion> _questions = [];
  final Map<String, int> _answers = {};
  bool _loading = true;
  bool _saving = false;
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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

  // Kompozisyon: önceki "hepsi tek sayfada kaydırılabilir liste" yerine
  // tek-soru-tek-sayfa (Typeform/Duolingo tarzı) bir PageView. Bir seçenek
  // işaretlenince kısa bir gecikmeyle otomatik sıradaki soruya geçiyor -
  // kullanıcı "İleri" butonuna basmak zorunda kalmıyor.
  void _selectAnswer(String questionId, int optionIndex) {
    setState(() => _answers[questionId] = optionIndex);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      if (_page < _questions.length - 1) {
        _pageController.nextPage(
            duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      } else {
        setState(() => _page = _questions.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final onLastPage = _questions.isNotEmpty && _page >= _questions.length;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_page > 0 ? Icons.arrow_back_rounded : Icons.close_rounded,
              color: AppColors.textSecondary),
          onPressed: () {
            if (_page > 0) {
              setState(() => _page--);
              _pageController.previousPage(
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _questions.isEmpty
                  ? Center(
                      child: Text('Anket şu an kullanılamıyor.',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Segmentli ilerleme göstergesi - tek çubuk yerine
                          // her soru için ayrı bir segment (chip listesi
                          // gibi tıklanabilir değil, salt ilerleme).
                          Row(
                            children: List.generate(_questions.length, (i) {
                              final done = i < _page || onLastPage;
                              return Expanded(
                                child: Container(
                                  height: 5,
                                  margin: EdgeInsets.only(
                                      right: i == _questions.length - 1 ? 0 : 6),
                                  decoration: BoxDecoration(
                                    color: done
                                        ? AppColors.secondary
                                        : AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 28),
                          Expanded(
                            child: onLastPage
                                ? _buildSummaryPage()
                                : PageView.builder(
                                    controller: _pageController,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _questions.length,
                                    onPageChanged: (i) => setState(() => _page = i),
                                    itemBuilder: (_, i) => _buildQuestionPage(_questions[i]),
                                  ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildQuestionPage(CompatibilityQuestion q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(q.question,
            style: AppText.heading.copyWith(fontSize: 22, height: 1.3)),
        const SizedBox(height: 6),
        Text(
          'Cevapların yalnızca uyum yüzdesi olarak paylaşılır, kimseye gösterilmez.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 24),
        ...List.generate(q.options.length, (i) {
          final selected = _answers[q.id] == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _selectAnswer(q.id, i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.secondary.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: selected ? AppColors.secondary : AppColors.surfaceBorder,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(q.options[i],
                          style: TextStyle(
                              color: selected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 15,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w400)),
                    ),
                    if (selected)
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.secondary, size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSummaryPage() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 56),
          const SizedBox(height: 16),
          Text('Tüm sorular cevaplandı!', style: AppText.heading.copyWith(fontSize: 20)),
          const SizedBox(height: 24),
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
    );
  }
}
