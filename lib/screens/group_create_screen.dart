import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friends_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';

/// Yeni grup oluşturma ekranı (Batch B) - isim + üye olarak eklenecek
/// arkadaşların çoklu seçimi. Sunucu yalnızca oluşturanın ARKADAŞI olan
/// id'leri kabul ediyor (bkz. server.js 'group-create') - bu yüzden burada
/// yalnızca FriendsService'ten gelen liste gösteriliyor, başka kimse
/// seçilemiyor zaten.
class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _nameController = TextEditingController();
  final _friendsService = FriendsService();
  final Set<String> _selected = {};
  final _pageController = PageController();

  List<AppUser> _friends = [];
  bool _loadingFriends = true;
  bool _creating = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    // Eğer oluşturma isteği havada kaldıysa (ör. kullanıcı yanıt gelmeden
    // geri gitti) bu ekrana ait geçici dinleyicileri bırak - aksi halde
    // paylaşılan MessagingService alanları (bkz. sınıf üstü not) artık var
    // olmayan bir State'e ait kapanışları tutmaya devam ederdi.
    MessagingService().onGroupCreateAck = null;
    MessagingService().onGroupError = null;
    _nameController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final friends = await _friendsService.fetchFriends();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loadingFriends = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selected.isEmpty || _creating) return;
    setState(() => _creating = true);
    final clientId = 'grp${DateTime.now().microsecondsSinceEpoch}';

    late final void Function(String, Group) onAck;
    late final void Function(String?, String) onError;
    onAck = (cId, group) {
      if (cId != clientId) return;
      MessagingService().onGroupCreateAck = null;
      MessagingService().onGroupError = null;
      if (mounted) Navigator.of(context).pop();
    };
    onError = (cId, message) {
      if (cId != clientId) return;
      MessagingService().onGroupCreateAck = null;
      MessagingService().onGroupError = null;
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    };
    MessagingService().onGroupCreateAck = onAck;
    MessagingService().onGroupError = onError;

    MessagingService().createGroup(
      name: name,
      memberIds: _selected.toList(),
      clientId: clientId,
    );
  }

  bool get _nameValid => _nameController.text.trim().isNotEmpty;

  void _goToStep2() {
    if (!_nameValid) return;
    setState(() => _step = 1);
    _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic);
  }

  // Kompozisyon: tek sayfalık form yerine 2 adımlı bir akış (isim -> üye
  // seçimi), quiz ekranındaki segment göstergesiyle AYNI görsel dil ama
  // farklı bir amaç için (sihirbaz adımı, soru ilerlemesi değil). Gerçek
  // olmayan fotoğraf yükleme/açıklama adımları EKLENMEDİ (backend
  // desteklemiyor, bkz. Group modelindeki not).
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
              _step == 1 ? Icons.arrow_back_rounded : Icons.close_rounded,
              color: AppColors.textSecondary),
          onPressed: () {
            if (_step == 1) {
              setState(() => _step = 0);
              _pageController.previousPage(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text('Yeni Grup', style: AppText.subheading),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12 + kToolbarHeight, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: _step == 1
                              ? AppColors.primary
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildNameStep(),
                      _buildMembersStep(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Grubuna bir isim ver',
            style: AppText.heading.copyWith(fontSize: 22)),
        const SizedBox(height: 6),
        Text('Sonra üyelerini seçeceksin.', style: AppText.body),
        const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'ör. Kahve Molası'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _goToStep2(),
        ),
        const Spacer(),
        GradientButton(
          height: 52,
          onPressed: _nameValid ? _goToStep2 : null,
          child: Text('İleri', style: AppText.button),
        ),
      ],
    );
  }

  Widget _buildMembersStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kimler olsun?', style: AppText.heading.copyWith(fontSize: 22)),
        const SizedBox(height: 6),
        Text('En az bir arkadaş seç.', style: AppText.body),
        const SizedBox(height: 16),
        Expanded(child: _buildFriendsList()),
        GradientButton(
          height: 52,
          onPressed: (_selected.isEmpty || _creating) ? null : _submit,
          child: _creating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text('Grubu Oluştur (${_selected.length})',
                  style: AppText.button),
        ),
      ],
    );
  }

  Widget _buildFriendsList() {
    if (_loadingFriends) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_friends.isEmpty) {
      return Center(
        child: Text('Grup oluşturmak için önce arkadaş eklemelisin.',
            style: TextStyle(color: AppColors.textMuted),
            textAlign: TextAlign.center),
      );
    }
    return ListView.builder(
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final friend = _friends[index];
        final selected = _selected.contains(friend.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: CheckboxListTile(
              value: selected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(friend.id);
                  } else {
                    _selected.remove(friend.id);
                  }
                });
              },
              activeColor: AppColors.primary,
              title: Text(friend.displayName,
                  style: TextStyle(color: AppColors.textPrimary)),
              secondary: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                backgroundImage: friend.photoUrl != null
                    ? NetworkImage(friend.photoUrl!)
                    : null,
                child: friend.photoUrl == null
                    ? Text(friend.displayName.isNotEmpty
                        ? friend.displayName[0].toUpperCase()
                        : '?')
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
