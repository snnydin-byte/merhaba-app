import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/call_ui_controller.dart';
import '../services/friends_service.dart';
import '../services/messaging_service.dart';
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

  /// Toplu/broadcast liste (#31 anket maddesi) - seçilen her arkadaşa AYNI
  /// mesajı TEK TEK, birbirinden bağımsız kalıcı mesaj olarak gönderir
  /// (WhatsApp'ın "yayın listesi"yle aynı fikir: alıcılar birbirini
  /// GÖRMEZ, sanki her birine ayrı ayrı yazılmış gibi kendi sohbetlerinde
  /// görünür - grup sohbeti DEĞİL). Sunucu tarafında ek bir değişiklik
  /// gerekmiyor, zaten var olan persistent-message-send tek tek çağrılıyor.
  void _openBroadcastComposer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BroadcastComposerSheet(friends: _friends),
    );
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

  /// Bir arkadaşı bildirir - nedenler sunucunun kabul ettiği sabit liste
  /// (bkz. signaling_server/reportStore.js VALID_REASONS), video sohbet
  /// ekranındaki (video_chat_screen.dart _showReportDialog) diyalogla aynı
  /// desen. 'Reşit olmayan biri gibi görünüyor' seçeneği özellikle önemli -
  /// bu tür şikayetler sunucuda (bkz. GET /admin/reports) öncelikli olarak
  /// işaretlenir.
  Future<void> _showReportDialog(AppUser friend) async {
    const reasons = [
      ('uygunsuz-goruntu', 'Uygunsuz görüntü/içerik'),
      ('taciz', 'Taciz veya kötüye kullanım'),
      ('kucuk-yasta', 'Reşit olmayan biri gibi görünüyor'),
      ('spam', 'Spam / reklam'),
      ('sahte-hesap', 'Sahte hesap'),
      ('diger', 'Diğer'),
    ];

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Kullanıcıyı bildir', style: AppText.subheading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: reasons
              .map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.$2,
                        style: TextStyle(color: AppColors.textPrimary)),
                    onTap: () => Navigator.pop(context, r.$1),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );

    if (reason == null || !mounted) return;

    try {
      await AuthService().reportFriend(friend.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şikayetin alındı, teşekkürler.')),
      );
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
        actions: [
          if (_friends.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.campaign_outlined, color: Colors.white70),
              tooltip: 'Toplu mesaj gönder',
              onPressed: _openBroadcastComposer,
            ),
        ],
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

    // "Kendime Not" (#42 anket maddesi) - arkadaş listesi boş olsa bile
    // her zaman görünür, kendi kullanıcı id'sine giden özel bir sohbet.
    if (_friends.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16 + kToolbarHeight, 16, 0),
            child: Column(children: [_buildNoteToSelfTile(), _buildBotTile()]),
          ),
          Expanded(child: _buildEmptyState()),
        ],
      );
    }

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
        itemCount: _friends.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return _buildNoteToSelfTile();
          if (index == 1) return _buildBotTile();
          return _buildFriendTile(_friends[index - 2]);
        },
      ),
    );
  }

  /// "Kendime Not" girişi - AppUser.id'yi bilerek kendi kullanıcı id'mizle
  /// dolduruyoruz, böylece ChatScreen bunu normal bir arkadaş sohbeti gibi
  /// açar ama sunucu (persistent-message-send'deki self-mesaj istisnası)
  /// ve ChatScreen (_isNoteToSelf) bunun özel olduğunu anlar.
  Widget _buildNoteToSelfTile() {
    final me = AuthService().currentUser;
    if (me == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.of(context).push(
            AppPageRoute(builder: (_) => ChatScreen(friend: me)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.secondary.withValues(alpha: 0.25),
                child: const Icon(Icons.sticky_note_2_outlined,
                    color: AppColors.secondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kendime Not',
                        style: AppText.subheading.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('Kişisel notların, kimseyle paylaşılmaz',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  /// Basit kurallı yardımcı bot girişi - sunucudaki sabit BOT_USER_ID
  /// ('merhaba-bot') ile eşleşen sahte bir AppUser oluşturup ChatScreen'i
  /// normal bir arkadaş sohbeti gibi açıyoruz. Sunucu (persistent-message-send
  /// ve GET /messages/:friendId) bu id için arkadaşlık şartını atlıyor ve
  /// kullanıcı mesaj attığında botReplyFor() ile otomatik yanıt üretiyor.
  Widget _buildBotTile() {
    const bot = AppUser(
      id: 'merhaba-bot',
      email: '',
      displayName: 'Merhaba Asistan',
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => Navigator.of(context).push(
            AppPageRoute(builder: (_) => const ChatScreen(friend: bot)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                child: const Icon(Icons.smart_toy_outlined,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Merhaba Asistan',
                        style: AppText.subheading.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('Sorularını yanıtlayan basit yardımcı',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
              color: AppColors.surfaceElevated,
              tooltip: 'Diğer seçenekler',
              onSelected: (value) {
                if (value == 'report') {
                  _showReportDialog(friend);
                } else if (value == 'remove') {
                  _confirmRemove(friend);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      const Icon(Icons.flag_outlined,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 10),
                      Text('Bildir',
                          style: TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      const Icon(Icons.person_remove_outlined,
                          color: AppColors.danger, size: 18),
                      const SizedBox(width: 10),
                      Text('Arkadaşlıktan çıkar',
                          style: TextStyle(color: AppColors.danger)),
                    ],
                  ),
                ),
              ],
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

/// Toplu mesaj (#31 anket maddesi) diyaloğu - arkadaş listesinden çoklu
/// seçim + tek bir metin, "Gönder"e basınca her seçili kişiye ayrı ayrı
/// kalıcı mesaj olarak iletilir.
class _BroadcastComposerSheet extends StatefulWidget {
  final List<AppUser> friends;
  const _BroadcastComposerSheet({required this.friends});

  @override
  State<_BroadcastComposerSheet> createState() => _BroadcastComposerSheetState();
}

class _BroadcastComposerSheetState extends State<_BroadcastComposerSheet> {
  final Set<String> _selected = {};
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _selected.isEmpty) return;
    setState(() => _sending = true);
    final messaging = MessagingService();
    var counter = 0;
    for (final friendId in _selected) {
      messaging.sendPersistentMessage(
        toId: friendId,
        text: text,
        clientId: 'bcast_${DateTime.now().microsecondsSinceEpoch}_${counter++}',
      );
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Mesaj ${_selected.length} kişiye gönderildi.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_outlined, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                const Text('Toplu mesaj',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_selected.length} seçili',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Aynı mesaj seçtiğin herkese ayrı ayrı gönderilir - alıcılar birbirini görmez.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.friends.length,
                itemBuilder: (context, index) {
                  final friend = widget.friends[index];
                  final checked = _selected.contains(friend.id);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.primary,
                    value: checked,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(friend.id);
                      } else {
                        _selected.remove(friend.id);
                      }
                    }),
                    title: Text(friend.displayName, style: const TextStyle(color: Colors.white)),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Mesajını yaz...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_sending || _selected.isEmpty) ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Gönder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
