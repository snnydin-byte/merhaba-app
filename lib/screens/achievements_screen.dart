import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/gamification_service.dart';
import '../theme/app_theme.dart';

/// Görevler/başarımlar (Batch G) - HİÇBİR parasal/jeton ödülü YOK, yalnızca
/// sembolik bir rozet + XP katkısı (bkz. server.js ACHIEVEMENTS/computeXp).
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final GamificationService _service = GamificationService();
  List<Achievement> _achievements = [];
  bool _loading = true;
  final Set<String> _claiming = {};
  // Canva mockup'ındaki ALL/LOCKED sekmeleri - gerçek unlocked/claimed
  // durumuna göre filtreliyor, sahte bir sayı üretmiyor.
  bool _showLockedOnly = false;

  List<Achievement> get _visibleAchievements => _showLockedOnly
      ? _achievements.where((a) => !a.unlocked).toList()
      : _achievements;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final achievements = await _service.fetchAchievements();
      if (mounted)
        setState(() {
          _achievements = achievements;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claim(Achievement a) async {
    setState(() => _claiming.add(a.id));
    try {
      await _service.claimAchievement(a.id);
      if (mounted) _load();
    } on AuthException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _claiming.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Görevler'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: PillBadge(label: '${user.xp} XP', color: Colors.amber),
              ),
            ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                      child: AppScreenIntro(
                        icon: Icons.emoji_events_rounded,
                        title: 'İlerlemeni gör',
                        subtitle: 'Sohbet ettikçe rozetlerini ve XP’ni büyüt',
                        trailing: user == null
                            ? null
                            : PillBadge(
                                label: 'Sv. ${user.level}',
                                color: Colors.amber),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          _tabChip('Tümü', !_showLockedOnly,
                              () => setState(() => _showLockedOnly = false)),
                          const SizedBox(width: 8),
                          _tabChip('Kilitli', _showLockedOnly,
                              () => setState(() => _showLockedOnly = true)),
                          const Spacer(),
                          Text(
                            '${_achievements.where((a) => a.unlocked).length}/${_achievements.length} rozet',
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: constraints.maxWidth >= 780
                                ? 4
                                : constraints.maxWidth >= 560
                                    ? 3
                                    : 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.95,
                          ),
                          itemCount: _visibleAchievements.length,
                          itemBuilder: (_, i) {
                            final a = _visibleAchievements[i];
                            return GlassCard(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    a.claimed
                                        ? Icons.emoji_events_rounded
                                        : (a.unlocked
                                            ? Icons.lock_open_rounded
                                            : Icons.lock_outline_rounded),
                                    color: a.claimed
                                        ? Colors.amber
                                        : (a.unlocked
                                            ? AppColors.secondary
                                            : AppColors.textFaint),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(a.title,
                                      style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(a.description,
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const Spacer(),
                                  if (a.claimed)
                                    Icon(Icons.check_circle_rounded,
                                        color: AppColors.secondary, size: 20)
                                  else if (a.unlocked)
                                    _claiming.contains(a.id)
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : SizedBox(
                                            width: double.infinity,
                                            child: TextButton(
                                                onPressed: () => _claim(a),
                                                style: TextButton.styleFrom(
                                                    padding: EdgeInsets.zero),
                                                child: const Text('Al')),
                                          ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _tabChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.surfaceBorder),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}
