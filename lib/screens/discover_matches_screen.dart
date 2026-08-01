import 'package:flutter/material.dart';

import '../services/discover_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

/// Aktif Keşfet eşleşmeleri listesi (Batch E). Kalıcı sohbet yalnızca
/// arkadaşlar arasında çalıştığı için, eski eşleşmeler önce buradaki
/// "Arkadaş ekle" eylemiyle arkadaşlığa çevrilir; sohbet sonra aynı karttan
/// açılır. Yeni eşleşmeler sunucu tarafından zaten arkadaş olabilir.
class DiscoverMatchesScreen extends StatefulWidget {
  const DiscoverMatchesScreen({super.key});

  @override
  State<DiscoverMatchesScreen> createState() => _DiscoverMatchesScreenState();
}

class _DiscoverMatchesScreenState extends State<DiscoverMatchesScreen> {
  final DiscoverService _discover = DiscoverService();
  List<DateMatch> _matches = [];
  bool _loading = true;
  final Set<String> _addingFriendIds = {};
  final Set<String> _unmatchingIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final matches = await _discover.fetchMatches();
      if (mounted) {
        setState(() {
          _matches = matches;
          _loading = false;
        });
      }
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
        title: Text('Buluştunuz mu?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            '${match.user.displayName} ile gerçek hayatta buluştun mu?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hayır')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Evet')),
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

  void _openChat(DateMatch match) {
    if (!match.isFriend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesajlaşmak için önce arkadaş ekle.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => ChatScreen(friend: match.user)),
    );
  }

  Future<void> _addFriend(DateMatch match) async {
    if (_addingFriendIds.contains(match.matchId)) return;
    setState(() => _addingFriendIds.add(match.matchId));
    try {
      await _discover.addMatchFriend(match.matchId);
      if (!mounted) return;
      setState(() {
        _addingFriendIds.remove(match.matchId);
        _matches = _matches
            .map(
              (item) => item.matchId == match.matchId
                  ? DateMatch(
                      matchId: item.matchId,
                      user: item.user,
                      createdAt: item.createdAt,
                      weMet: item.weMet,
                      isFriend: true,
                    )
                  : item,
            )
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${match.user.displayName} arkadaşlarına eklendi.')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _addingFriendIds.remove(match.matchId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arkadaş eklenemedi, tekrar dene.')),
        );
      }
    }
  }

  Future<void> _confirmUnmatch(DateMatch match) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eşleşmeyi kaldır?'),
        content: Text(
          '${match.user.displayName} artık eşleşmelerinde görünmeyecek. '
          'Arkadaşlığınız ve mevcut mesajların silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Eşleşmeyi kaldır',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || _unmatchingIds.contains(match.matchId)) return;

    setState(() => _unmatchingIds.add(match.matchId));
    try {
      await _discover.unmatch(match.matchId);
      if (!mounted) return;
      setState(() {
        _unmatchingIds.remove(match.matchId);
        _matches.removeWhere((item) => item.matchId == match.matchId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eşleşme kaldırıldı.')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _unmatchingIds.remove(match.matchId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eşleşme kaldırılamadı, tekrar dene.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Eşleşmelerim'),
          backgroundColor: Colors.transparent,
          elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _matches.isEmpty
                  ? Center(
                      child: Text('Henüz bir eşleşmen yok.',
                          style: TextStyle(color: AppColors.textSecondary)))
                  // Kademeli (masonry) 2 sütun - Pinterest tarzı, aynı yükseklikte
                  // tekdüze grid yerine sol/sağ sütun farklı hizada başlıyor.
                  // LikesMe ekranındaki tekdüze grid'den KASITLI olarak farklı,
                  // ikisi aynı veriye benzese de görsel olarak ayrışıyor.
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          child: AppScreenIntro(
                            icon: Icons.forum_rounded,
                            title: 'Eşleşmelerin',
                            subtitle: 'Sohbet etmek için birini seç',
                            trailing: PillBadge(
                              label: '${_matches.length}',
                              color: AppColors.primaryLight,
                            ),
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) => Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth >= 700
                                      ? 640
                                      : double.infinity,
                                ),
                                child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: _matchColumn(
                                              startIndex: 0, topOffset: 0)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: _matchColumn(
                                              startIndex: 1, topOffset: 28)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
      onTap: () => _openChat(match),
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
                      image: NetworkImage(match.user.photoUrl!),
                      fit: BoxFit.cover)
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
                      style:
                          TextStyle(color: AppColors.textFaint, fontSize: 56),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: PillBadge(
                        label: 'Yeni Eşleşme', color: AppColors.secondary),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: PopupMenuButton<String>(
                    tooltip: 'Eşleşme seçenekleri',
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.32),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.more_horiz_rounded,
                          color: Colors.white, size: 18),
                    ),
                    color: AppColors.surfaceElevated,
                    onSelected: (value) {
                      if (value == 'unmatch') _confirmUnmatch(match);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'unmatch',
                        child: Row(
                          children: [
                            Icon(Icons.person_remove_outlined,
                                color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Text('Eşleşmeyi kaldır',
                                style: TextStyle(color: AppColors.danger)),
                          ],
                        ),
                      ),
                    ],
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
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85)
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(match.user.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
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
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: GradientButton(
                            height: 36,
                            onPressed: _unmatchingIds.contains(match.matchId)
                                ? null
                                : match.isFriend
                                    ? () => _openChat(match)
                                    : () => _addFriend(match),
                            child: _addingFriendIds.contains(match.matchId)
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        match.isFriend
                                            ? Icons.chat_bubble_rounded
                                            : Icons.person_add_alt_1_rounded,
                                        color: Colors.white,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        match.isFriend
                                            ? 'Mesaj gönder'
                                            : 'Arkadaş ekle',
                                        style: AppText.button
                                            .copyWith(fontSize: 12),
                                      ),
                                    ],
                                  ),
                          ),
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
