import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/discover_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

/// "Kim beğendi" listesi (Batch E, madde 72) - seni beğenen ama henüz
/// eşleşmediğin (karşılık vermediğin) kişiler. Birine dokunup beğenirsen
/// ANINDA eşleşme oluşur (o zaten seni beğenmişti).
class DiscoverLikesMeScreen extends StatefulWidget {
  const DiscoverLikesMeScreen({super.key});

  @override
  State<DiscoverLikesMeScreen> createState() => _DiscoverLikesMeScreenState();
}

class _DiscoverLikesMeScreenState extends State<DiscoverLikesMeScreen> {
  final DiscoverService _discover = DiscoverService();
  List<LikedYouEntry> _likes = [];
  bool _loading = true;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final likes = await _discover.fetchLikesMe();
      if (mounted) setState(() { _likes = likes; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(LikedYouEntry entry, String action) async {
    setState(() => _processing.add(entry.swipeId));
    try {
      final matchedUser = await _discover.swipe(toId: entry.user.id, action: action);
      if (!mounted) return;
      setState(() {
        _likes.removeWhere((l) => l.swipeId == entry.swipeId);
        _processing.remove(entry.swipeId);
      });
      if (matchedUser != null) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            title: Text('Eşleştiniz! 🎉', style: TextStyle(color: AppColors.textPrimary)),
            content: Text('${matchedUser.displayName} ile artık sohbet edebilirsin.',
                style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context)
                      .push(AppPageRoute(builder: (_) => ChatScreen(friend: matchedUser)));
                },
                child: const Text('Sohbet Et'),
              ),
            ],
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _processing.remove(entry.swipeId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) setState(() => _processing.remove(entry.swipeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kim Beğendi'), backgroundColor: Colors.transparent, elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _likes.isEmpty
                  ? Center(
                      child: Text('Henüz seni beğenen olmadı.',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _likes.length,
                      itemBuilder: (_, i) {
                        final entry = _likes[i];
                        final processing = _processing.contains(entry.swipeId);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                                backgroundImage:
                                    entry.user.photoUrl != null ? NetworkImage(entry.user.photoUrl!) : null,
                                child: entry.user.photoUrl == null
                                    ? Text(entry.user.displayName.isNotEmpty
                                        ? entry.user.displayName[0].toUpperCase()
                                        : '?')
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(entry.user.displayName,
                                            style: TextStyle(
                                                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                        if (entry.isSuperlike) ...[
                                          const SizedBox(width: 4),
                                          const Icon(Icons.star_rounded, color: Colors.blueAccent, size: 16),
                                        ],
                                      ],
                                    ),
                                    if (entry.note != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text('"${entry.note}"',
                                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                      ),
                                  ],
                                ),
                              ),
                              if (processing)
                                const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                              else ...[
                                IconButton(
                                  onPressed: () => _respond(entry, 'pass'),
                                  icon: Icon(Icons.close_rounded, color: AppColors.textFaint),
                                ),
                                IconButton(
                                  onPressed: () => _respond(entry, 'like'),
                                  icon: Icon(Icons.favorite_rounded, color: AppColors.secondary),
                                ),
                              ],
                            ],
                          ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
