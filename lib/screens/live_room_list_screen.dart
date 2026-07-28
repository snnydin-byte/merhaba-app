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
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
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
        title: Text('Canlı Yayın Başlat', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: titleController,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Yayın başlığı (isteğe bağlı)'),
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
        title: Text('Canlı Yayınlar', style: AppText.subheading),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      // Bu ekran daha önce uygulamanın geri kalanından farklı (düz Material
      // Card/varsayılan AppBar) görünüyordu - Canva mockup'ının video-bento
      // kart dilini alırken aynı zamanda uygulamanın kendi tema
      // token'larına (GlassCard/GradientButton) da uydurduk.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startHosting,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.videocam_rounded, color: Colors.white),
        label: Text('Yayın Aç', style: AppText.button.copyWith(fontSize: 14)),
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
    if (_rooms.isEmpty) {
      return Center(
        child: Text('Şu an aktif canlı yayın yok.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16 + kToolbarHeight, 16, 90),
      itemCount: _rooms.length,
      itemBuilder: (context, index) {
        final room = _rooms[index];
        final title = (room['title'] as String?)?.trim();
        final viewerCount = room['viewerCount'] as int? ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () async {
                await Navigator.of(context).push(
                  AppPageRoute(builder: (_) => LiveRoomScreen.viewer(roomId: room['id'] as String)),
                );
                if (mounted) _load();
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                          child: Icon(Icons.live_tv_rounded, color: AppColors.primary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Text('CANLI',
                              style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title == null || title.isEmpty ? 'Canlı Yayın' : title,
                            style: AppText.subheading.copyWith(fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.visibility_rounded, color: AppColors.textMuted, size: 14),
                              const SizedBox(width: 4),
                              Text('$viewerCount izleyici',
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
