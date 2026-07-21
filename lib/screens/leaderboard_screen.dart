import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/gamification_service.dart';
import '../theme/app_theme.dart';

/// Liderlik tablosu (Batch G) - yalnızca isim/foto/seviye, hassas hiçbir
/// alan YOK. Gölge yasaklı kullanıcılar sunucu tarafında zaten hiç dönmüyor.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final GamificationService _service = GamificationService();
  List<LeaderboardEntry> _entries = [];
  LeaderboardEntry? _myRank;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final (entries, myRank) = await _service.fetchLeaderboard();
      if (mounted) setState(() { _entries = entries; _myRank = myRank; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = AuthService().currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Liderlik Tablosu'), backgroundColor: Colors.transparent, elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : Column(
                  children: [
                    if (_myRank != null && !_entries.any((e) => e.id == myId))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: GlassCard(
                          child: Row(
                            children: [
                              Text('#${_myRank!.rank}',
                                  style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text('Sen · Seviye ${_myRank!.level}',
                                    style: TextStyle(color: AppColors.textPrimary)),
                              ),
                              Text('${_myRank!.xp} XP', style: TextStyle(color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _entries.length,
                        itemBuilder: (_, i) {
                          final entry = _entries[i];
                          final isMe = entry.id == myId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(
                                    color: isMe ? AppColors.primary : AppColors.surfaceBorder),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text('${entry.rank}',
                                        style: TextStyle(
                                            color: entry.rank <= 3 ? Colors.amber : AppColors.textMuted,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                                    backgroundImage:
                                        entry.photoUrl != null ? NetworkImage(entry.photoUrl!) : null,
                                    child: entry.photoUrl == null
                                        ? Text(entry.displayName.isNotEmpty
                                            ? entry.displayName[0].toUpperCase()
                                            : '?')
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(entry.displayName,
                                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                  ),
                                  Text('Sv. ${entry.level}',
                                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
