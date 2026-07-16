import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/call_ui_controller.dart';
import '../services/friends_service.dart';
import '../theme/app_theme.dart';
import '../utils/online_status.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

/// Arkadaşlar sayfası - ana ekrandaki çevrimiçi sayısının altındaki
/// "Arkadaşlar" girişinden açılır. Arkadaş listesini gösterir/kaldırır,
/// mesajlaşmaya (bkz. chat_screen.dart) ve sesli/görüntülü aramaya (bkz.
/// call_service.dart, call_ui_controller.dart) buradan geçilir.
///
/// Arama başlatma bu ekrandan tetiklenir ama gelen arama davetlerinin
/// gösterilmesi (diyalog, CallScreen'e geçiş) artık bu ekranın açık
/// olmasına bağlı DEĞİL - bkz. call_ui_controller.dart, CallService'in
/// sinyal bağlantısı artık uygulama boyunca kalıcı.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendsService _friendsService = FriendsService();

  bool _loading = true;
  String? _error;
  List<AppUser> _friends = [];
  Timer? _statusRefreshTimer;

  bool get _isGuest => !AuthService().isLoggedIn;

  @override
  void initState() {
    super.initState();
    if (!_isGuest) {
      _load();
      // Çevrimiçi/son görülme durumu zamanla değiştiği (arkadaş çevrimiçi
      // olabilir/çıkabilir) için listeyi periyodik olarak sessizce (yükleniyor
      // döndürmeden) tazeliyoruz - home_screen.dart'taki online-count
      // yenilemesiyle aynı yaklaşım.
      _statusRefreshTimer =
          Timer.periodic(const Duration(seconds: 20), (_) => _silentRefresh());
    } else {
      _loading = false;
    }
  }

  /// _load()'un aksine yükleniyor/hata durumlarını değiştirmez - yalnızca
  /// arka planda listeyi güncel tutar. Başarısız olursa (ör. sunucu anlık
  /// ulaşılamaz) sessizce yok sayılır, mevcut liste ekranda kalmaya devam
  /// eder - kullanıcıyı gereksiz hata mesajlarıyla rahatsız etmemek için.
  Future<void> _silentRefresh() async {
    try {
      final friends = await _friendsService.fetchFriends();
      if (!mounted) return;
      setState(() => _friends = friends);
    } catch (_) {
      // sessizce yok say
    }
  }

  /// Bir arkadaşı sesli/görüntülü arar - "Aranıyor..." diyaloğu ve gelen
  /// yanıt/kabul akışı artık bu ekrana değil, call_ui_controller.dart'a
  /// bağlı (bkz. sınıf üstündeki not), böylece görüşme kabul edildiğinde
  /// kullanıcı bu ekrandan başka bir yere gitmiş olsa bile CallScreen'e
  /// doğru geçilir.
  Future<void> _startCall(AppUser friend, String callType) async {
    await CallUiController().startCall(
      friendId: friend.id,
      friendDisplayName: friend.displayName,
      callType: callType,
    );
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final friends = await _friendsService.fetchFriends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Arkadaş listesi yüklenemedi, tekrar dene.';
        _loading = false;
      });
    }
  }

  Future<void> _confirmRemove(AppUser friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Arkadaşlıktan çıkar',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '${friend.displayName} arkadaş listenden kaldırılacak.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _friendsService.removeFriend(friend.id);
      if (!mounted) return;
      setState(() => _friends.removeWhere((f) => f.id == friend.id));
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bir şeyler ters gitti, tekrar dene.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Arkadaşlar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isGuest) return _buildGuestState();
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) return _buildErrorState();
    if (_friends.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _friends.length,
        itemBuilder: (context, index) => _buildFriendTile(_friends[index]),
      ),
    );
  }

  Widget _buildGuestState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Arkadaş eklemek için giriş yapmalısın',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Misafir olarak arkadaş listesi tutulamaz. Bir hesap oluştur '
              'ya da giriş yap.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: GradientButton(
                height: 48,
                onPressed: () {
                  pushAppRoute(context, (_) => const LoginScreen());
                },
                child: const Text('Giriş Yap', style: AppText.button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_rounded,
                color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Henüz arkadaşın yok',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Görüntülü sohbette eşleştiğin kişilere arkadaşlık isteği '
              'gönderebilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendTile(AppUser friend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                child: Text(
                  friend.displayName.isNotEmpty
                      ? friend.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              // Çevrimiçi durumu avatarın sağ-alt köşesinde küçük, hafifçe
              // titreşen bir noktayla gösteriliyor - birçok mesajlaşma
              // uygulamasındaki tanıdık desen, artık statik değil canlı.
              if (friend.online)
                const Positioned(
                  right: -1,
                  bottom: -1,
                  child: PulsingDot(color: Colors.greenAccent, size: 12),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  lastSeenLabel(
                      online: friend.online,
                      lastSeen: friend.lastSeen,
                      now: DateTime.now()),
                  style: TextStyle(
                    color: friend.online
                        ? Colors.greenAccent
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontWeight:
                        friend.online ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _friendActionIcon(
            icon: Icons.chat_bubble_outline_rounded,
            onTap: () {
              pushAppRoute(context, (_) => ChatScreen(friend: friend));
            },
          ),
          _friendActionIcon(
            icon: Icons.call_outlined,
            onTap: () => _startCall(friend, 'audio'),
          ),
          _friendActionIcon(
            icon: Icons.videocam_outlined,
            onTap: () => _startCall(friend, 'video'),
          ),
          IconButton(
            onPressed: () => _confirmRemove(friend),
            icon: const Icon(Icons.person_remove_outlined,
                color: Colors.white38, size: 20),
            tooltip: 'Arkadaşlıktan çıkar',
          ),
        ],
      ),
    );
  }

  Widget _friendActionIcon(
      {required IconData icon, required VoidCallback onTap}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white70, size: 20),
    );
  }
}
