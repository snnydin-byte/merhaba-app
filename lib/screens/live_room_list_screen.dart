import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/webrtc_service.dart' show signalingServerUrl;
import '../theme/app_theme.dart';
import 'live_room_screen.dart';

/// Aktif canlı odaların keşif listesi (Faz 1) - GET /live-rooms.
/// leaderboard/achievements ekranlarıyla aynı basit REST-poll deseni;
/// gerçek zamanlı 'live-room-list-updated' push'u Faz 2/3'te eklenebilir.
class LiveRoomListScreen extends StatefulWidget {
  const LiveRoomListScreen({super.key});

  @override
  State<LiveRoomListScreen> createState() => _LiveRoomListScreenState();
}

class _LiveRoomListScreenState extends State<LiveRoomListScreen> {
  List<Map<String, dynamic>> _rooms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = AuthService().token;
      final response = await http.get(
        Uri.parse('$signalingServerUrl/live-rooms'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200)
        throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rooms = (data['rooms'] as List<dynamic>? ?? [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Canlı odalar yüklenemedi, tekrar dene.';
        _loading = false;
      });
    }
  }

  Future<void> _startHosting() async {
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Canlı Yayın Başlat',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: titleController,
          style: TextStyle(color: AppColors.textPrimary),
          decoration:
              const InputDecoration(hintText: 'Yayın başlığı (isteğe bağlı)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(titleController.text),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );
    if (title == null || !mounted) return;
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => LiveRoomScreen.host(title: title)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Text(
          'Canlı',
          style: AppText.display.copyWith(fontSize: 26, height: 1),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      // Bu ekran daha önce uygulamanın geri kalanından farklı (düz Material
      // Card/varsayılan AppBar) görünüyordu - Canva mockup'ının video-bento
      // kart dilini alırken aynı zamanda uygulamanın kendi tema
      // token'larına (GlassCard/GradientButton) da uydurduk.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startHosting,
        backgroundColor: AppColors.surfaceElevated,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.42)),
        ),
        icon: Icon(Icons.add_rounded, color: AppColors.secondary),
        label: Text('Yayın aç', style: AppText.button.copyWith(fontSize: 14)),
      ),
      body: AppBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceElevated,
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    if (_rooms.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 84, 16, 100),
      itemCount: _rooms.length,
      itemBuilder: (context, index) {
        final room = _rooms[index];
        final title = (room['title'] as String?)?.trim();
        final viewerCount = room['viewerCount'] as int? ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.surfaceBorder),
              boxShadow: neonGlow(
                AppColors.primary,
                opacity: 0.08,
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () async {
                await Navigator.of(context).push(
                  AppPageRoute(
                      builder: (_) =>
                          LiveRoomScreen.viewer(roomId: room['id'] as String)),
                );
                if (mounted) _load();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.lg),
                      ),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.7),
                                  AppColors.backgroundDeep,
                                  AppColors.secondary.withValues(alpha: 0.48),
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.live_tv_rounded,
                                color: Colors.white.withValues(alpha: 0.72),
                                size: 48),
                          ),
                          const Positioned(
                            top: 12,
                            left: 12,
                            child: PillBadge(
                                label: 'CANLI', color: Color(0xFFFF5A79)),
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: PillBadge(
                              label: '$viewerCount izliyor',
                              color: Colors.white,
                              icon: Icons.visibility_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppGradients.warmSignal,
                          ),
                          child: const Icon(Icons.person_rounded,
                              color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title == null || title.isEmpty
                                ? 'Canlı yayın'
                                : title,
                            style: AppText.subheading.copyWith(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded,
                            color: AppColors.secondary, size: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppGradients.warmSignal,
                boxShadow: neonGlow(AppColors.primary, opacity: 0.26),
              ),
              child: const Icon(Icons.live_tv_rounded,
                  color: Colors.white, size: 34),
            ),
            const SizedBox(height: 18),
            Text('İlk yayını sen başlat', style: AppText.subheading),
            const SizedBox(height: 8),
            Text(
              'Şu an açık yayın yok. Kameranı açıp topluluğa merhaba de.',
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
          ],
        ),
      ),
    );
  }
}
