import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/discover_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import '../utils/session_transient_ui.dart';

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
      if (mounted) {
        setState(() {
          _likes = likes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(LikedYouEntry entry, String action) async {
    setState(() => _processing.add(entry.swipeId));
    try {
      final matchedUser =
          await _discover.swipe(toId: entry.user.id, action: action);
      if (!mounted) return;
      setState(() {
        _likes.removeWhere((l) => l.swipeId == entry.swipeId);
        _processing.remove(entry.swipeId);
      });
      if (matchedUser != null) {
        showSessionDialog<void>(
          deduplicationKey: 'discover_likes_me_screen.dialog.1',
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            title: Text('Eşleştiniz! 🎉',
                style: TextStyle(color: AppColors.textPrimary)),
            content: Text(
                '${matchedUser.displayName} ile artık sohbet edebilirsin.',
                style: TextStyle(color: AppColors.textSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat')),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(AppPageRoute(
                      builder: (_) => ChatScreen(friend: matchedUser)));
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
        showSessionSnackBar(
          context,
          SnackBar(content: Text(e.message)),
          priority: SessionFeedbackPriority.normal,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _processing.remove(entry.swipeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Kim Beğendi'),
          backgroundColor: Colors.transparent,
          elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _likes.isEmpty
                  ? Center(
                      child: Text('Henüz seni beğenen olmadı.',
                          style: TextStyle(color: AppColors.textSecondary)))
                  // Canva mockup'ı burada bulanıklaştırma+kilit+"Unlock Now"
                  // ödeme tuzağı (paywall) gösteriyordu - Sinan'ın 18 Tem
                  // kararıyla yasaklanan jeton/ödeme ekonomisi paternine
                  // girdiği için UYGULANMADI. Yalnızca kart-grid görsel dili
                  // (fotoğraf öncelikli, pembe accent) alındı, liste tamamen
                  // ücretsiz ve açık kalıyor.
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          child: AppScreenIntro(
                            icon: Icons.favorite_rounded,
                            title: 'Seni beğenenler',
                            subtitle:
                                '${_likes.length} kişi profilini keşfetti',
                            trailing: PillBadge(
                              label: '${_likes.length}',
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) => GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: constraints.maxWidth >= 720
                                    ? 4
                                    : constraints.maxWidth >= 520
                                        ? 3
                                        : 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.78,
                              ),
                              itemCount: _likes.length,
                              itemBuilder: (_, i) {
                                final entry = _likes[i];
                                final processing =
                                    _processing.contains(entry.swipeId);
                                return ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      border: Border.all(
                                          color: AppColors.surfaceBorder),
                                      image: entry.user.photoUrl != null
                                          ? DecorationImage(
                                              image: NetworkImage(
                                                  entry.user.photoUrl!),
                                              fit: BoxFit.cover)
                                          : null,
                                    ),
                                    child: Stack(
                                      children: [
                                        if (entry.user.photoUrl == null)
                                          Center(
                                            child: Text(
                                              entry.user.displayName.isNotEmpty
                                                  ? entry.user.displayName[0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                  color: AppColors.textFaint,
                                                  fontSize: 56),
                                            ),
                                          ),
                                        if (entry.isSuperlike)
                                          const Positioned(
                                            left: 8,
                                            top: 8,
                                            child: Icon(Icons.star_rounded,
                                                color: Colors.blueAccent,
                                                size: 20),
                                          ),
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.fromLTRB(
                                                10, 28, 10, 8),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.black
                                                      .withValues(alpha: 0.85)
                                                ],
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(entry.user.displayName,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13)),
                                                if (entry.note != null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 2),
                                                    child: Text(
                                                        '"${entry.note}"',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            color:
                                                                Colors.white70,
                                                            fontSize: 11)),
                                                  ),
                                                const SizedBox(height: 4),
                                                processing
                                                    ? const SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Colors
                                                                    .white))
                                                    : Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceEvenly,
                                                        children: [
                                                          IconButton(
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                            onPressed: () =>
                                                                _respond(entry,
                                                                    'pass'),
                                                            icon: const Icon(
                                                                Icons
                                                                    .close_rounded,
                                                                color: Colors
                                                                    .white54,
                                                                size: 20),
                                                          ),
                                                          IconButton(
                                                            padding:
                                                                EdgeInsets.zero,
                                                            constraints:
                                                                const BoxConstraints(),
                                                            onPressed: () =>
                                                                _respond(entry,
                                                                    'like'),
                                                            icon: Icon(
                                                                Icons
                                                                    .favorite_rounded,
                                                                color: AppColors
                                                                    .secondary,
                                                                size: 20),
                                                          ),
                                                        ],
                                                      ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
}
