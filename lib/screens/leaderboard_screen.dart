import 'package:flutter/material.dart';

import '../services/gamification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_session_builder.dart';

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
      if (mounted) {
        setState(() {
          _entries = entries;
          _myRank = myRank;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Canva mockup'ındaki 3'lü podyum - yalnızca gerçek liderlik verisindeki
  // ilk 3 kişi (isim/foto/xp), sahte bir "dünya çapında" iddiası yok.
  Widget _buildPodium() {
    final second = _entries[1];
    final first = _entries[0];
    final third = _entries[2];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
              child: _podiumTile(second,
                  size: 52, medalColor: const Color(0xFFC0C0C0))),
          Expanded(
              child: _podiumTile(first,
                  size: 68, medalColor: Colors.amber, crown: true)),
          Expanded(
              child: _podiumTile(third,
                  size: 52, medalColor: const Color(0xFFCD7F32))),
        ],
      ),
    );
  }

  Widget _podiumTile(LeaderboardEntry entry,
      {required double size, required Color medalColor, bool crown = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crown)
          Icon(Icons.emoji_events_rounded, color: medalColor, size: 20),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: medalColor, width: 2)),
          child: CircleAvatar(
            radius: size / 2,
            backgroundColor: AppColors.primary.withValues(alpha: 0.25),
            backgroundImage:
                entry.photoUrl != null ? NetworkImage(entry.photoUrl!) : null,
            child: entry.photoUrl == null
                ? Text(entry.displayName.isNotEmpty
                    ? entry.displayName[0].toUpperCase()
                    : '?')
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(entry.displayName,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
        Text('${entry.xp} XP',
            style: TextStyle(
                color: medalColor, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthSessionBuilder(
      builder: (context, _, user) {
        final myId = user?.id;
        return Scaffold(
          appBar: AppBar(
              title: const Text('Liderlik Tablosu'),
              backgroundColor: Colors.transparent,
              elevation: 0),
          body: AppBackground(
            child: SafeArea(
              child: _loading
                  ? Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: AppScreenIntro(
                            icon: Icons.leaderboard_rounded,
                            title: 'Topluluk sıralaması',
                            subtitle: 'Seviyeni yükselt, zirveye yaklaş.',
                          ),
                        ),
                        if (_entries.length >= 3) _buildPodium(),
                        if (_myRank != null &&
                            !_entries.any((e) => e.id == myId))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: GlassCard(
                              child: Row(
                                children: [
                                  Text('#${_myRank!.rank}',
                                      style: TextStyle(
                                          color: AppColors.primaryLight,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                        'Sen · Seviye ${_myRank!.level}',
                                        style: TextStyle(
                                            color: AppColors.textPrimary)),
                                  ),
                                  Text('${_myRank!.xp} XP',
                                      style: TextStyle(
                                          color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            // İlk 3 podyumda gösterildiği için listede tekrar
                            // etmiyor.
                            itemCount: _entries.length >= 3
                                ? _entries.length - 3
                                : _entries.length,
                            itemBuilder: (_, i) {
                              final entry =
                                  _entries[_entries.length >= 3 ? i + 3 : i];
                              final isMe = entry.id == myId;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? AppColors.primary
                                            .withValues(alpha: 0.15)
                                        : AppColors.surface,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                    border: Border.all(
                                        color: isMe
                                            ? AppColors.primary
                                            : AppColors.surfaceBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        child: Text('${entry.rank}',
                                            style: TextStyle(
                                                color: entry.rank <= 3
                                                    ? Colors.amber
                                                    : AppColors.textMuted,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: AppColors.primary
                                            .withValues(alpha: 0.25),
                                        backgroundImage: entry.photoUrl != null
                                            ? NetworkImage(entry.photoUrl!)
                                            : null,
                                        child: entry.photoUrl == null
                                            ? Text(entry.displayName.isNotEmpty
                                                ? entry.displayName[0]
                                                    .toUpperCase()
                                                : '?')
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(entry.displayName,
                                            style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                      Text('Sv. ${entry.level}',
                                          style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 12)),
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
      },
    );
  }
}
