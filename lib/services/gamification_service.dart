import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'webrtc_service.dart' show signalingServerUrl;

/// Sosyal/Oyunlaştırma (Batch G) - görevler/başarımlar + liderlik tablosu.
/// Seviye/XP AYRICA çekilmiyor - zaten her AppUser'ın (bkz. auth_service
/// .dart) bir parçası, sunucuda türetiliyor.
class Achievement {
  final String id;
  final String title;
  final String description;
  final bool unlocked;
  final bool claimed;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.unlocked,
    required this.claimed,
  });

  factory Achievement.fromJson(Map<String, dynamic> json) => Achievement(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        unlocked: json['unlocked'] as bool,
        claimed: json['claimed'] as bool,
      );
}

class LeaderboardEntry {
  final String id;
  final String displayName;
  final String? photoUrl;
  final int xp;
  final int level;
  final int rank;

  LeaderboardEntry({
    required this.id,
    required this.displayName,
    this.photoUrl,
    required this.xp,
    required this.level,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        photoUrl: json['photoUrl'] as String?,
        xp: json['xp'] as int,
        level: json['level'] as int,
        rank: json['rank'] as int,
      );
}

class GamificationService {
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService().token}',
      };

  Future<List<Achievement>> fetchAchievements() async {
    final response = await http
        .get(Uri.parse('$signalingServerUrl/achievements'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    return (data['achievements'] as List<dynamic>)
        .map((e) => Achievement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> claimAchievement(String id) async {
    final response = await http
        .post(Uri.parse('$signalingServerUrl/achievements/$id/claim'),
            headers: _headers, body: '{}')
        .timeout(const Duration(seconds: 10));
    _decodeOrThrow(response);
  }

  Future<(List<LeaderboardEntry>, LeaderboardEntry?)> fetchLeaderboard() async {
    final response = await http
        .get(Uri.parse('$signalingServerUrl/leaderboard'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    final list = (data['leaderboard'] as List<dynamic>)
        .map((e) =>
            LeaderboardEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final myRank = data['myRank'] != null
        ? LeaderboardEntry.fromJson(
            Map<String, dynamic>.from(data['myRank'] as Map))
        : null;
    return (list, myRank);
  }

  Map<String, dynamic> _decodeOrThrow(http.Response response) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException('Sunucudan beklenmeyen bir yanıt geldi.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(data['error'] as String? ?? 'Bir şeyler ters gitti.');
    }
    return data;
  }
}
