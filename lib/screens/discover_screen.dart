import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/auth_service.dart';
import '../services/discover_service.dart';
import '../services/messaging_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'discover_likes_me_screen.dart';
import 'discover_matches_screen.dart';
import 'discover_quiz_screen.dart';

/// Eşleşme (Dating) katmanı ana ekranı - "Keşfet" (Batch E). Kaydırma
/// kartları TAMAMEN bu projede yazıldı (yeni bir paket/native bağımlılık
/// EKLENMEDİ) - basit bir GestureDetector + AnimatedContainer/Transform
/// kombinasyonu.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with SingleTickerProviderStateMixin {
  final DiscoverService _discover = DiscoverService();
  List<DiscoverCandidate> _candidates = [];
  bool _loading = true;
  String? _error;
  Offset _dragOffset = Offset.zero;
  bool _swiping = false;
  String? _pendingNote;
  int _likesMeCount = 0;

  @override
  void initState() {
    super.initState();
    _wireCallbacks();
    _load();
    _loadLikesMeCount();
  }

  void _wireCallbacks() {
    MessagingService().onDiscoverMatched = (matchId, user, firstMessageIsYours) {
      if (!mounted) return;
      _showMatchDialog(user, firstMessageIsYours);
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Yollarınız kesişti (madde 81) - konum İSTEĞE BAĞLI, izin yoksa/
      // alınamazsa sessizce konumsuz devam edilir (bkz. discoverStore.js -
      // konum HİÇ profile kaydedilmiyor, yalnızca bu istekte taşınıyor).
      double? lat;
      double? lng;
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        final granted = permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever;
        if (granted && await Geolocator.isLocationServiceEnabled()) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          ).timeout(const Duration(seconds: 8));
          lat = position.latitude;
          lng = position.longitude;
        }
      } catch (_) {
        // Konumsuz devam - bkz. yukarıdaki not.
      }

      final candidates = await _discover.fetchCandidates(myLat: lat, myLng: lng);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
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
        _error = 'Adaylar yüklenemedi, tekrar dene.';
        _loading = false;
      });
    }
  }

  Future<void> _loadLikesMeCount() async {
    try {
      final likes = await _discover.fetchLikesMe();
      if (mounted) setState(() => _likesMeCount = likes.length);
    } catch (_) {
      // Sessizce yok say - rozet sayacı, kritik değil.
    }
  }

  Future<void> _performSwipe(String action) async {
    if (_candidates.isEmpty || _swiping) return;
    setState(() => _swiping = true);
    final candidate = _candidates.first;
    final note = action == 'pass' ? null : _pendingNote;
    try {
      final matchedUser = await _discover.swipe(toId: candidate.user.id, action: action, note: note);
      if (!mounted) return;
      setState(() {
        _candidates.removeAt(0);
        _dragOffset = Offset.zero;
        _pendingNote = null;
        _swiping = false;
      });
      if (matchedUser != null) {
        // firstMessageIsYours bilgisi burada yok (yalnızca discover-matched
        // event'inde geliyor) - kendi attığımız swipe'ın SONUCUNDA anlık
        // olarak biliyoruz ki karşı taraf zaten bizi önceden beğenmişti,
        // yani "sıra sende" hesaplaması matematik olarak simetrik değil -
        // basitlik için burada her zaman "ikiniz de mesaj atabilirsiniz"
        // diyoruz, katı bir kural zaten YOK (bkz. server.js notu).
        _showMatchDialog(matchedUser, true);
      }
      if (_candidates.length < 3) _load();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _swiping = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _swiping = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bir şeyler ters gitti, tekrar dene.')));
    }
  }

  void _showMatchDialog(AppUser user, bool firstMessageIsYours) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Eşleştiniz! 🎉', style: TextStyle(color: Colors.white)),
        content: Text(
          '${user.displayName} ile karşılıklı beğendiniz.'
          '${firstMessageIsYours ? ' İlk mesajı sen atabilirsin.' : ''}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context)
                  .push(AppPageRoute(builder: (_) => ChatScreen(friend: user)));
            },
            child: const Text('Sohbet Et'),
          ),
        ],
      ),
    );
  }

  Future<void> _rewind() async {
    try {
      await _discover.rewind();
      if (mounted) _load();
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Geri alınamadı.')));
      }
    }
  }

  Future<void> _activateBoost() async {
    try {
      await _discover.activateBoost();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Boost aktif! 30 dakika boyunca öne çıkıyorsun.')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Boost aktifleştirilemedi.')));
      }
    }
  }

  void _showNoteDialog() {
    final controller = TextEditingController(text: _pendingNote ?? '');
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Ön-mesaj ekle', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 300,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Beğeninle birlikte bir not gönder...'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _pendingNote = null);
              Navigator.pop(context);
            },
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _pendingNote = controller.text.trim().isEmpty ? null : controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(child: _buildBody()),
              if (!_loading && _error == null && _candidates.isNotEmpty) _buildActionBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          ),
          const Expanded(
            child: Text('Keşfet', style: AppText.heading, textAlign: TextAlign.center),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () async {
                  await Navigator.of(context)
                      .push(AppPageRoute(builder: (_) => const DiscoverLikesMeScreen()));
                  if (mounted) {
                    _wireCallbacks();
                    _load();
                    _loadLikesMeCount();
                  }
                },
                icon: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent),
              ),
              if (_likesMeCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: Text('$_likesMeCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: () async {
              await Navigator.of(context)
                  .push(AppPageRoute(builder: (_) => const DiscoverMatchesScreen()));
              if (mounted) _wireCallbacks();
            },
            icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white70),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            color: AppColors.surfaceElevated,
            onSelected: (value) async {
              if (value == 'boost') {
                _activateBoost();
              } else if (value == 'quiz') {
                await Navigator.of(context)
                    .push(AppPageRoute(builder: (_) => const DiscoverQuizScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'boost', child: Text('Boost (30dk öne çık)')),
              PopupMenuItem(value: 'quiz', child: Text('Uyumluluk anketi')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tekrar Dene')),
          ],
        ),
      );
    }
    if (_candidates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_rounded, color: Colors.white24, size: 56),
            const SizedBox(height: 12),
            const Text('Şu an gösterilecek yeni kişi yok.',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Yenile')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_candidates.length > 1) _buildCard(_candidates[1], interactive: false),
          _buildCard(_candidates[0], interactive: true),
        ],
      ),
    );
  }

  Widget _buildCard(DiscoverCandidate candidate, {required bool interactive}) {
    final card = _cardContent(candidate);
    if (!interactive) {
      return Transform.scale(scale: 0.95, child: card);
    }
    final rotation = _dragOffset.dx / 800;
    return GestureDetector(
      onPanUpdate: (details) => setState(() => _dragOffset += details.delta),
      onPanEnd: (details) {
        if (_dragOffset.dx > 120) {
          _performSwipe('like');
        } else if (_dragOffset.dx < -120) {
          _performSwipe('pass');
        } else {
          setState(() => _dragOffset = Offset.zero);
        }
      },
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(angle: rotation, child: card),
      ),
    );
  }

  Widget _cardContent(DiscoverCandidate candidate) {
    final user = candidate.user;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          image: user.photoUrl != null
              ? DecorationImage(image: NetworkImage(user.photoUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          children: [
            if (user.photoUrl == null)
              Center(
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white24, fontSize: 96),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${user.displayName}${user.age != null ? ', ${user.age}' : ''}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        if (user.verified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded, color: AppColors.secondary, size: 18),
                        ],
                        if (user.selfieVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.face_retouching_natural_rounded,
                              color: AppColors.primaryLight, size: 18),
                        ],
                      ],
                    ),
                    if (candidate.compatibilityPercent != null || candidate.distanceKm != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [
                            if (candidate.compatibilityPercent != null)
                              '%${candidate.compatibilityPercent} uyum',
                            if (candidate.distanceKm != null) '${candidate.distanceKm} km uzakta',
                          ].join(' · '),
                          style: const TextStyle(color: AppColors.primaryLight, fontSize: 12),
                        ),
                      ),
                    if (user.bio.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(user.bio,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    if (user.profileBadges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          children: user.profileBadges
                              .map((b) => PillBadge(label: b, color: AppColors.primary))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: Icons.replay_rounded,
            color: Colors.amber,
            size: 44,
            onTap: _rewind,
          ),
          _roundButton(
            icon: Icons.close_rounded,
            color: Colors.redAccent,
            size: 56,
            onTap: () => _performSwipe('pass'),
          ),
          _roundButton(
            icon: Icons.star_rounded,
            color: Colors.blueAccent,
            size: 44,
            onTap: () => _performSwipe('superlike'),
          ),
          _roundButton(
            icon: Icons.favorite_rounded,
            color: AppColors.secondary,
            size: 56,
            onTap: () => _performSwipe('like'),
          ),
          _roundButton(
            icon: _pendingNote != null ? Icons.edit_note_rounded : Icons.message_outlined,
            color: _pendingNote != null ? AppColors.primary : Colors.white54,
            size: 44,
            onTap: _showNoteDialog,
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceElevated,
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Icon(icon, color: color, size: size * 0.45),
      ),
    );
  }
}
