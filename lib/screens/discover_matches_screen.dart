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
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _matches.length,
                      itemBuilder: (_, i) {
                        final match = _matches[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                                  backgroundImage: match.user.photoUrl != null
                                      ? NetworkImage(match.user.photoUrl!)
                                      : null,
                                  child: match.user.photoUrl == null
                                      ? Text(match.user.displayName.isNotEmpty
                                          ? match.user.displayName[0].toUpperCase()
                                          : '?')
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(match.user.displayName,
                                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                                ),
                                if (match.weMet == null)
                                  IconButton(
                                    tooltip: 'Buluştunuz mu?',
                                    onPressed: () => _askWeMet(match),
                                    icon: Icon(Icons.event_available_outlined, color: AppColors.textMuted),
                                  ),
                                IconButton(
                                  onPressed: () => Navigator.of(context)
                                      .push(AppPageRoute(builder: (_) => ChatScreen(friend: match.user))),
                                  icon: Icon(Icons.chat_bubble_rounded, color: AppColors.primaryLight),
                                ),
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
