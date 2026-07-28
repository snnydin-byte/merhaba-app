import 'package:flutter/material.dart';

import '../services/discover_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

/// Aktif Keşfet eşleşmeleri listesi (Batch E). Eşleşen kişiler otomatik
/// arkadaş oldukları için (bkz. server.js POST /discover/swipe) "Sohbet Et"
/// doğrudan mevcut ChatScreen'i açar - AYRI bir dating-chat ekranı YOK.
class DiscoverMatchesScreen extends StatefulWidget {
  const DiscoverMatchesScreen({super.key});

  @override
  State<DiscoverMatchesScreen> createState() => _DiscoverMatchesScreenState();
}

class _DiscoverMatchesScreenState extends State<DiscoverMatchesScreen> {
  final DiscoverService _discover = DiscoverService();
  List<DateMatch> _matches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final matches = await _discover.fetchMatches();
      if (mounted) setState(() { _matches = matches; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Buluşma sonrası geri bildirim (madde 84, "We Met") - yalnızca kendi
  /// bir kez kaydedebiliyor, sunucu tarafında da bu şekilde (bkz.
  /// discoverStore.setWeMetFeedback).
  Future<void> _askWeMet(DateMatch match) async {
    final met = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Buluştunuz mu?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('${match.user.displayName} ile gerçek hayatta buluştun mu?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hayır')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Evet')),
        ],
      ),
    );
    if (met == null) return;
    try {
      await _discover.submitWeMet(match.matchId, met);
      if (mounted) _load();
    } catch (_) {
      // Sessizce yok say - kritik olmayan bir geri bildirim.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eşleşmelerim'), backgroundColor: Colors.transparent, elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _matches.isEmpty
                  ? Center(
                      child: Text('Henüz bir eşleşmen yok.', style: TextStyle(color: AppColors.textSecondary)))
                  // Kademeli (masonry) 2 sütun - Pinterest tarzı, aynı yükseklikte
                  // tekdüze grid yerine sol/sağ sütun farklı hizada başlıyor.
                  // LikesMe ekranındaki tekdüze grid'den KASITLI olarak farklı,
                  // ikisi aynı veriye benzese de görsel olarak ayrışıyor.
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _matchColumn(startIndex: 0, topOffset: 0)),
                          const SizedBox(width: 12),
                          Expanded(child: _matchColumn(startIndex: 1, topOffset: 28)),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _matchColumn({required int startIndex, required double topOffset}) {
    final items = <Widget>[];
    for (var i = startIndex; i < _matches.length; i += 2) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _matchCard(_matches[i], tall: i.isEven),
      ));
    }
    return Padding(
      padding: EdgeInsets.only(top: topOffset),
      child: Column(children: items),
    );
  }

  Widget _matchCard(DateMatch match, {required bool tall}) {
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(AppPageRoute(builder: (_) => ChatScreen(friend: match.user))),
      child: AspectRatio(
        aspectRatio: tall ? 0.68 : 0.9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.surfaceBorder),
              image: match.user.photoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(match.user.photoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: Stack(
              children: [
                if (match.user.photoUrl == null)
                  Center(
                    child: Text(
                      match.user.displayName.isNotEmpty
                          ? match.user.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(color: AppColors.textFaint, fontSize: 56),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: PillBadge(label: 'Yeni Eşleşme', color: AppColors.secondary),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(match.user.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                        if (match.weMet == null)
                          IconButton(
                            tooltip: 'Buluştunuz mu?',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _askWeMet(match),
                            icon: const Icon(Icons.event_available_outlined,
                                color: Colors.white70, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
