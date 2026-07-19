import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';

/// Tek bir kullanıcının hikayelerini Instagram/WhatsApp tarzı tam ekran,
/// otomatik ilerleyen bir gösterici ile sunar (#71 anket maddesi). Ekrana
/// giren her hikaye bir kez "görüldü" işaretlenir (bkz.
/// MessagingService.viewStory) - kendi hikayelerimiz için bu çağrı sunucu
/// tarafında zaten sessizce yok sayılıyor (bkz. storyStore.markViewed).
class StoryViewerScreen extends StatefulWidget {
  final List<Story> stories;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _storyDuration = Duration(seconds: 6);

  late int _index = widget.initialIndex.clamp(0, widget.stories.length - 1);
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _storyDuration,
  );
  final Set<String> _markedViewed = {};
  List<Story> _liveStories = [];

  bool get _isMine => _current.userId == AuthService().currentUser?.id;
  Story get _current => _liveStories[_index];

  @override
  void initState() {
    super.initState();
    _liveStories = List.of(widget.stories);
    MessagingService().onStoryRemoved = _onRemoved;
    MessagingService().onStoryDeleted = _onRemoved;
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
    _playCurrent();
  }

  @override
  void dispose() {
    // Bu ekran açıkken üzerine yazdığımız callback'leri bırak - altta duran
    // (varsa) başka bir ekranın kendi callback'lerini bozmayalım.
    if (MessagingService().onStoryRemoved == _onRemoved) {
      MessagingService().onStoryRemoved = null;
    }
    if (MessagingService().onStoryDeleted == _onRemoved) {
      MessagingService().onStoryDeleted = null;
    }
    _progress.dispose();
    super.dispose();
  }

  void _onRemoved(String storyId) {
    if (!mounted) return;
    final removedCurrent = _current.id == storyId;
    setState(() => _liveStories.removeWhere((s) => s.id == storyId));
    if (_liveStories.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (_index >= _liveStories.length) _index = _liveStories.length - 1;
    if (removedCurrent) _playCurrent();
  }

  void _playCurrent() {
    _progress
      ..stop()
      ..reset();
    if (!_markedViewed.contains(_current.id)) {
      _markedViewed.add(_current.id);
      MessagingService().viewStory(_current.id);
    }
    _progress.forward();
  }

  void _goNext() {
    if (_index >= _liveStories.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    _playCurrent();
  }

  void _goPrevious() {
    if (_index == 0) {
      _progress
        ..stop()
        ..reset();
      _progress.forward();
      return;
    }
    setState(() => _index--);
    _playCurrent();
  }

  Future<void> _confirmDelete() async {
    _progress.stop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Hikayeyi sil', style: TextStyle(color: Colors.white)),
        content: const Text('Bu hikaye herkes için kaldırılacak.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      MessagingService().deleteStory(_current.id);
      // onStoryDeleted/onStoryRemoved sunucudan gelince _onRemoved zaten
      // listeden düşürüp gerekirse ekranı kapatacak - burada iyimser
      // (optimistic) olarak beklemiyoruz, kısa bir gecikme normal.
    } else {
      _progress.forward();
    }
  }

  void _showViewers() {
    _progress.stop();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _ViewersSheet(storyId: _current.id),
    ).whenComplete(() {
      if (mounted) _progress.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final story = _current;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final w = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < w / 3) {
            _goPrevious();
          } else {
            _goNext();
          }
        },
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildContent(story),
            SafeArea(
              child: Column(
                children: [
                  Row(
                    children: List.generate(_liveStories.length, (i) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedBuilder(
                              animation: _progress,
                              builder: (context, _) {
                                double value;
                                if (i < _index) {
                                  value = 1;
                                } else if (i == _index) {
                                  value = _progress.value;
                                } else {
                                  value = 0;
                                }
                                return FractionallySizedBox(
                                  widthFactor: value,
                                  child: Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                          backgroundImage: story.authorPhotoUrl != null
                              ? NetworkImage(story.authorPhotoUrl!)
                              : null,
                          child: story.authorPhotoUrl == null
                              ? Text(story.authorDisplayName.isNotEmpty
                                  ? story.authorDisplayName[0].toUpperCase()
                                  : '?')
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(story.authorDisplayName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (_isMine)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                            onPressed: _confirmDelete,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isMine)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: GestureDetector(
                    onTap: _showViewers,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_outlined, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text('${story.viewCount} görüntüleme',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Story story) {
    if (story.kind == 'photo' && story.mediaUrl != null) {
      return Image.network(
        story.mediaUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryLight));
        },
      );
    }
    final bgColor = _parseColor(story.backgroundColor) ?? AppColors.primary;
    return Container(
      color: bgColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        story.text ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, height: 1.4),
      ),
    );
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.replaceAll('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}

class _ViewersSheet extends StatefulWidget {
  final String storyId;
  const _ViewersSheet({required this.storyId});

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  List<StoryViewer>? _viewers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final viewers = await MessagingService().fetchStoryViewers(widget.storyId);
      if (!mounted) return;
      setState(() => _viewers = viewers);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Görüntüleyenler alınamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Görüntüleyenler',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.white54))
            else if (_viewers == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
              )
            else if (_viewers!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Henüz kimse görüntülemedi.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
              )
            else
              ..._viewers!.map((v) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                      backgroundImage: v.photoUrl != null ? NetworkImage(v.photoUrl!) : null,
                      child: v.photoUrl == null
                          ? Text(v.displayName.isNotEmpty ? v.displayName[0].toUpperCase() : '?')
                          : null,
                    ),
                    title: Text(v.displayName, style: const TextStyle(color: Colors.white)),
                  )),
          ],
        ),
      ),
    );
  }
}
