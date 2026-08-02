import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/friends_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';

/// Grup bilgi/yönetim ekranı (Batch B) - üye listesi, admin atama (yalnızca
/// sahibi), üye ekleme/çıkarma (adminler), yeniden adlandırma, duyuru kanalı
/// aç-kapat, gruptan ayrılma/grubu silme. Geri dönerken güncel [Group]
/// nesnesini pop ile döner (bkz. group_chat_screen.dart'taki kullanım).
class GroupInfoScreen extends StatefulWidget {
  final Group group;
  const GroupInfoScreen({super.key, required this.group});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late Group _group = widget.group;

  String get _myId => AuthService().currentUser?.id ?? '';
  bool get _isOwner => _group.isOwner(_myId);
  bool get _isAdmin => _group.isAdmin(_myId);

  @override
  void initState() {
    super.initState();
    MessagingService().onGroupUpdated = (group) {
      if (!mounted || group.id != _group.id) return;
      setState(() => _group = group);
    };
    MessagingService().onGroupDeleted = (groupId) {
      if (!mounted || groupId != _group.id) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    };
    MessagingService().onGroupError = (clientId, message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    };
  }

  @override
  void dispose() {
    MessagingService().onGroupUpdated = null;
    MessagingService().onGroupDeleted = null;
    MessagingService().onGroupError = null;
    super.dispose();
  }

  Future<void> _renameDialog() async {
    final controller = TextEditingController(text: _group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Grup adını değiştir',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    MessagingService().renameGroup(groupId: _group.id, name: name);
  }

  Future<void> _addMembers() async {
    final friends = await FriendsService().fetchFriends();
    final candidates =
        friends.where((f) => !_group.members.contains(f.id)).toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eklenebilecek yeni bir arkadaşın yok.')),
      );
      return;
    }
    final selected = <String>{};
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Üye ekle',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: candidates
                        .map((f) => CheckboxListTile(
                              value: selected.contains(f.id),
                              onChanged: (v) => setSheetState(() {
                                if (v == true) {
                                  selected.add(f.id);
                                } else {
                                  selected.remove(f.id);
                                }
                              }),
                              activeColor: AppColors.primary,
                              title: Text(f.displayName,
                                  style:
                                      TextStyle(color: AppColors.textPrimary)),
                            ))
                        .toList(),
                  ),
                ),
                GradientButton(
                  height: 44,
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  child:
                      Text('Ekle (${selected.length})', style: AppText.button),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == true && selected.isNotEmpty) {
      MessagingService()
          .addGroupMembers(groupId: _group.id, memberIds: selected.toList());
    }
  }

  Future<void> _confirmRemove(String memberId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title:
            Text('Üyeyi çıkar', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('$displayName gruptan çıkarılacak.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Çıkar', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      MessagingService()
          .removeGroupMember(groupId: _group.id, memberId: memberId);
    }
  }

  Future<void> _confirmLeaveOrDelete() async {
    final isOwner = _isOwner;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(isOwner ? 'Grubu sil' : 'Gruptan ayrıl',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          isOwner
              ? 'Bu grup TÜM üyeler için kalıcı olarak silinecek.'
              : 'Bu gruptan ayrılacaksın.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isOwner ? 'Sil' : 'Ayrıl',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (isOwner) {
      MessagingService().deleteGroup(_group.id);
    } else {
      MessagingService().removeGroupMember(groupId: _group.id, memberId: _myId);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Grup Bilgisi', style: AppText.subheading),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16 + kToolbarHeight, 16, 16),
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      // Canva mockup'ındaki grup avatarını saran ince neon
                      // halka - önceki düz CircleAvatar'ın üstüne eklendi.
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                        boxShadow: neonGlow(AppColors.primary,
                            opacity: 0.4, blurRadius: 20, spreadRadius: 1),
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.25),
                        child: Icon(Icons.groups_rounded,
                            color: AppColors.primary, size: 32),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _isAdmin ? _renameDialog : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_group.name,
                              style: AppText.subheading.copyWith(fontSize: 18)),
                          if (_isAdmin) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.edit_outlined,
                                color: AppColors.textFaint, size: 16),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${_group.members.length} üye',
                        style: TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 10),
                    PillBadge(
                      label: _group.announcementOnly
                          ? 'Duyuru kanalı'
                          : 'Grup sohbeti',
                      icon: _group.announcementOnly
                          ? Icons.campaign_rounded
                          : Icons.forum_rounded,
                      color: _group.announcementOnly
                          ? AppColors.warning
                          : AppColors.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_isAdmin)
                GlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SwitchListTile(
                    value: _group.announcementOnly,
                    onChanged: (v) => MessagingService()
                        .setGroupAnnouncementOnly(groupId: _group.id, value: v),
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Duyuru kanalı',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                    subtitle: Text('Yalnızca yöneticiler mesaj gönderebilir',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Üyeler',
                      style: AppText.subheading.copyWith(fontSize: 15)),
                  if (_isAdmin)
                    TextButton.icon(
                      onPressed: _addMembers,
                      icon: Icon(Icons.person_add_alt_1_rounded,
                          color: AppColors.primaryLight, size: 18),
                      label: Text('Ekle',
                          style: TextStyle(color: AppColors.primaryLight)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ..._group.members.map((memberId) {
                final name = _group.displayNameFor(memberId);
                final isOwnerRow = _group.isOwner(memberId);
                final isAdminRow = _group.isAdmin(memberId);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.25),
                          backgroundImage: _group.photoUrlFor(memberId) != null
                              ? NetworkImage(_group.photoUrlFor(memberId)!)
                              : null,
                          child: _group.photoUrlFor(memberId) == null
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?')
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  memberId == _myId ? '$name (sen)' : name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13),
                                ),
                              ),
                              if (isOwnerRow)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text('Sahip',
                                      style: TextStyle(
                                          color: AppColors.warning,
                                          fontSize: 10)),
                                )
                              else if (isAdminRow)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text('Yönetici',
                                      style: TextStyle(
                                          color: AppColors.secondaryLight,
                                          fontSize: 10)),
                                ),
                            ],
                          ),
                        ),
                        if (_isOwner && memberId != _myId)
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert,
                                color: AppColors.textFaint, size: 18),
                            color: AppColors.surfaceElevated,
                            onSelected: (value) {
                              if (value == 'toggle-admin') {
                                MessagingService().setGroupAdmin(
                                    groupId: _group.id,
                                    memberId: memberId,
                                    isAdmin: !isAdminRow);
                              } else if (value == 'remove') {
                                _confirmRemove(memberId, name);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'toggle-admin',
                                child: Text(
                                  isAdminRow
                                      ? 'Yöneticilikten al'
                                      : 'Yönetici yap',
                                  style:
                                      TextStyle(color: AppColors.textPrimary),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Gruptan çıkar',
                                    style: TextStyle(color: AppColors.danger)),
                              ),
                            ],
                          )
                        else if (_isAdmin && !isOwnerRow && memberId != _myId)
                          IconButton(
                            icon: Icon(Icons.person_remove_outlined,
                                color: AppColors.danger, size: 18),
                            onPressed: () => _confirmRemove(memberId, name),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              // Mockup'taki gibi tam genişlikte, tehlike-rengi çerçeveli
              // bir kart - önceki sade TextButton.icon yerine.
              Material(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: _confirmLeaveOrDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            _isOwner
                                ? Icons.delete_outline_rounded
                                : Icons.logout_rounded,
                            color: AppColors.danger,
                            size: 18),
                        const SizedBox(width: 8),
                        Text(_isOwner ? 'Grubu sil' : 'Gruptan ayrıl',
                            style: TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600)),
                      ],
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
}
