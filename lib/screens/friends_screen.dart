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
        title: Text('Arkadaşlıktan çıkar', style: AppText.subheading),
        content: Text(
          '${friend.displayName} arkadaş listenden kaldırılacak.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır', style: TextStyle(color: AppColors.danger)),
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
        title: Text('Arkadaşlar', style: AppText.subheading),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(child: SafeArea(child: _buildBody())),
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
        // bkz. profile_screen.dart'taki aynı düzeltme - extendBodyBehindAppBar:
        // true yüzünden gövde şeffaf AppBar'ın arkasına kadar uzuyor. Bu ekran
        // ayrıca SafeArea kullanıyor ama SafeArea yalnızca durum çubuğunu
        // hesaba katıyor, AppBar'ın kendi (kToolbarHeight) yüksekliğini değil
        // - o yüzden listenin ilk öğesi (ilk arkadaş satırı) hâlâ AppBar'ın
        // dokunuş yakalayan bölgesiyle çakışıyordu.
        padding: EdgeInsets.fromLTRB(16, 16 + kToolbarHeight, 16, 16),
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
            Icon(Icons.people_outline, color: AppColors.textFaint, size: 56),
            const SizedBox(height: 16),
            Text(
              'Arkadaş eklemek için giriş yapmalısın',
              textAlign: TextAlign.center,
              style: AppText.subheading,
            ),
            const SizedBox(height: 8),
            Text(
              'Misafir olarak arkadaş listesi tutulamaz. Bir hesap oluştur '
              'ya da giriş yap.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: 24),
            GradientButton(
              height: 48,
              onPressed: () {
                Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: Text('Giriş Yap', style: AppText.button),
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
            Icon(Icons.error_outline, color: AppColors.textFaint, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.divider),
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
            Icon(Icons.person_search_rounded,
                color: AppColors.textFaint, size: 56),
            const SizedBox(height: 16),
            Text('Henüz arkadaşın yok', style: AppText.subheading),
            const SizedBox(height: 8),
            Text(
              'Görüntülü sohbette eşleştiğin kişilere arkadaşlık isteği '
              'gönderebilirsin.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendTile(AppUser friend) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                  backgroundImage: friend.photoUrl != null
                      ? NetworkImage(friend.photoUrl!)
                      : null,
                  child: friend.photoUrl != null
                      ? null
                      : Text(
                          friend.displayName.isNotEmpty
                              ? friend.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                ),
                // Çevrimiçi durumu avatarın sağ-alt köşesinde küçük bir
                // noktayla gösteriliyor - birçok mesajlaşma uygulamasındaki
                // tanıdık desen.
                if (friend.online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                    ),
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
                    style: AppText.subheading.copyWith(fontSize: 15),
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
                          ? AppColors.secondary
                          : AppColors.textMuted,
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
                Navigator.of(context).push(
                  AppPageRoute(builder: (_) => ChatScreen(friend: friend)),
                );
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
      ),
    );
  }

  Widget _friendActionIcon(
      {required IconData icon, required VoidCallback onTap}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: AppColors.textSecondary, size: 20),
    );
  }
}
