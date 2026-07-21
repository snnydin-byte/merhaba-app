import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import 'group_chat_screen.dart';
import 'group_create_screen.dart';

/// Grup sohbetleri listesi (Batch B) - friends_screen.dart'taki gruplar
/// ikonundan açılır. Gerçek zamanlı güncelleme MessagingService'in
/// callback'leriyle (bkz. chat_screen.dart'taki aynı desen) - bu ekran
/// açıkken üzerine yazıyoruz, kapanırken bırakıyoruz.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Group> _groups = [];
  bool _loading = true;
  String? _error;

  String get _myId => AuthService().currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _wireCallbacks();
  }

  void _wireCallbacks() {
    MessagingService().onGroupCreateAck = (clientId, group) {
      if (!mounted) return;
      if (_groups.any((g) => g.id == group.id)) return;
      setState(() => _groups.insert(0, group));
    };
    MessagingService().onGroupCreated = (group, fromDisplayName) {
      if (!mounted) return;
      if (_groups.any((g) => g.id == group.id)) return;
      setState(() => _groups.insert(0, group));
    };
    MessagingService().onGroupUpdated = (group) {
      if (!mounted) return;
      setState(() {
        final i = _groups.indexWhere((g) => g.id == group.id);
        if (i == -1) {
          _groups.insert(0, group);
        } else {
          _groups[i] = group;
        }
      });
    };
    MessagingService().onGroupRemovedYou = (groupId) {
      if (!mounted) return;
      setState(() => _groups.removeWhere((g) => g.id == groupId));
    };
    MessagingService().onGroupDeleted = (groupId) {
      if (!mounted) return;
      setState(() => _groups.removeWhere((g) => g.id == groupId));
    };
  }

  @override
  void dispose() {
    MessagingService().onGroupCreateAck = null;
    MessagingService().onGroupCreated = null;
    MessagingService().onGroupUpdated = null;
    MessagingService().onGroupRemovedYou = null;
    MessagingService().onGroupDeleted = null;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await MessagingService().fetchGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Gruplar yüklenemedi, tekrar dene.';
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => const GroupCreateScreen()),
    );
    // GroupCreateScreen kendi geçici dinleyicilerini kullanıp oradaki
    // 'group-create-ack'i BURADAN önce yakalıyor (bkz. o ekranın kendi
    // _submit()'i) - bu yüzden yeni grup varsa listeye yansısın diye
    // burada da yeniden çekiyoruz, callback'leri de geri takıyoruz.
    if (mounted) {
      _wireCallbacks();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Gruplar', style: AppText.subheading),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: AppColors.textSecondary),
            tooltip: 'Yeni grup',
            onPressed: _openCreate,
          ),
        ],
      ),
      body: AppBackground(child: SafeArea(child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined, color: AppColors.textFaint, size: 56),
              const SizedBox(height: 16),
              Text('Henüz bir grubun yok', style: AppText.subheading, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Arkadaşlarınla bir grup sohbeti oluşturabilirsin.',
                textAlign: TextAlign.center,
                style: AppText.body,
              ),
              const SizedBox(height: 24),
              GradientButton(
                height: 48,
                onPressed: _openCreate,
                child: Text('Grup Oluştur', style: AppText.button),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16 + kToolbarHeight, 16, 16),
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () async {
                  await Navigator.of(context).push(
                    AppPageRoute(builder: (_) => GroupChatScreen(group: group)),
                  );
                  // Sohbet ekranı açıkken bu ekranın MessagingService
                  // callback'lerinin üzerine yazmıştı (paylaşılan tek alan,
                  // bkz. messaging_service.dart) - geri dönünce yeniden
                  // takıyoruz.
                  if (mounted) _wireCallbacks();
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                      backgroundImage: group.photoUrl != null ? NetworkImage(group.photoUrl!) : null,
                      child: group.photoUrl == null
                          ? Icon(Icons.groups_rounded, color: AppColors.primary, size: 20)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(group.name,
                              style: AppText.subheading.copyWith(fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            group.announcementOnly
                                ? '📢 Duyuru kanalı · ${group.members.length} üye'
                                : '${group.members.length} üye',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (group.isAdmin(_myId))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.shield_rounded,
                            color: AppColors.secondaryLight.withValues(alpha: 0.8), size: 16),
                      ),
                    Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
