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

  List<AppUser> _friends = [];
  bool _loadingFriends = true;
  bool _creating = false;

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Yeni Grup', style: AppText.subheading),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16 + kToolbarHeight, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  maxLength: 80,
                  decoration: const InputDecoration(hintText: 'Grup adı'),
                ),
                const SizedBox(height: 8),
                Text('Üye ekle', style: AppText.subheading.copyWith(fontSize: 14)),
                const SizedBox(height: 8),
                Expanded(child: _buildFriendsList()),
                GradientButton(
                  height: 48,
                  onPressed: (_selected.isEmpty || _creating) ? null : _submit,
                  child: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Grubu Oluştur (${_selected.length})', style: AppText.button),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_loadingFriends) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_friends.isEmpty) {
      return Center(
        child: Text('Grup oluşturmak için önce arkadaş eklemelisin.',
            style: TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
      );
    }
    return ListView.builder(
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final friend = _friends[index];
        final selected = _selected.contains(friend.id);
        return CheckboxListTile(
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
          title: Text(friend.displayName, style: const TextStyle(color: Colors.white)),
          secondary: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.25),
            backgroundImage: friend.photoUrl != null ? NetworkImage(friend.photoUrl!) : null,
            child: friend.photoUrl == null
                ? Text(friend.displayName.isNotEmpty ? friend.displayName[0].toUpperCase() : '?')
                : null,
          ),
        );
      },
    );
  }
}
