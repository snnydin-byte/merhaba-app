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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final achievements = await _service.fetchAchievements();
      if (mounted) setState(() { _achievements = achievements; _loading = false; });
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _claiming.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Görevler'), backgroundColor: Colors.transparent, elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (user != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GlassCard(
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                                child: Text('${user.level}',
                                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Seviye ${user.level} · ${user.xp} XP',
                                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ..._achievements.map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Icon(
                                  a.claimed
                                      ? Icons.emoji_events_rounded
                                      : (a.unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                                  color: a.claimed
                                      ? Colors.amber
                                      : (a.unlocked ? AppColors.secondary : AppColors.textFaint),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(a.title,
                                          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                      Text(a.description,
                                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                if (a.claimed)
                                  Icon(Icons.check_circle_rounded, color: AppColors.secondary)
                                else if (a.unlocked)
                                  _claiming.contains(a.id)
                                      ? const SizedBox(
                                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : TextButton(onPressed: () => _claim(a), child: const Text('Al'))
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
        ),
      ),
    );
  }
}
