import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'webrtc_service.dart' show signalingServerUrl;

/// Eşleşme (Dating) katmanı - "Keşfet" (Batch E). Rastgele video
/// eşleştirmeden (WebRTCService) TAMAMEN AYRI - burada her şey REST
/// üzerinden, kalıcı (bkz. signaling_server/discoverStore.js). Gerçek
/// zamanlı eşleşme bildirimleri (discover-matched vb.) MessagingService'in
/// zaten kalıcı olan soketi üzerinden geliyor (bkz. orada) - burada AYRI
/// bir soket bağlantısı YOK.
class DiscoverCandidate {
  final AppUser user;
  final bool isBoosted;
  final int? compatibilityPercent;
  final int? distanceKm;

  DiscoverCandidate({
    required this.user,
    required this.isBoosted,
    this.compatibilityPercent,
    this.distanceKm,
  });

  factory DiscoverCandidate.fromJson(Map<String, dynamic> json) => DiscoverCandidate(
        user: AppUser.fromJson(json),
        isBoosted: json['isBoosted'] as bool? ?? false,
        compatibilityPercent: json['compatibilityPercent'] as int?,
        distanceKm: json['distanceKm'] as int?,
      );
}

class LikedYouEntry {
  final String swipeId;
  final AppUser user;
  final bool isSuperlike;
  final String? note;
  final DateTime createdAt;

  LikedYouEntry({
    required this.swipeId,
    required this.user,
    required this.isSuperlike,
    this.note,
    required this.createdAt,
  });

  factory LikedYouEntry.fromJson(Map<String, dynamic> json) => LikedYouEntry(
        swipeId: json['swipeId'] as String,
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        isSuperlike: json['isSuperlike'] as bool? ?? false,
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class DateMatch {
  final String matchId;
  final AppUser user;
  final DateTime createdAt;
  final bool? weMet;

  DateMatch({required this.matchId, required this.user, required this.createdAt, this.weMet});

  factory DateMatch.fromJson(Map<String, dynamic> json) => DateMatch(
        matchId: json['matchId'] as String,
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
        weMet: json['weMet'] as bool?,
      );
}

class CompatibilityQuestion {
  final String id;
  final String question;
  final List<String> options;

  CompatibilityQuestion({required this.id, required this.question, required this.options});

  factory CompatibilityQuestion.fromJson(Map<String, dynamic> json) => CompatibilityQuestion(
        id: json['id'] as String,
        question: json['question'] as String,
        options: (json['options'] as List<dynamic>).map((e) => e.toString()).toList(),
      );
}

class DiscoverService {
  final AuthService _auth = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.token}',
      };

  Future<List<DiscoverCandidate>> fetchCandidates({double? myLat, double? myLng}) async {
    final query = <String, String>{};
    if (myLat != null && myLng != null) {
      query['myLat'] = myLat.toString();
      query['myLng'] = myLng.toString();
    }
    final uri = Uri.parse('$signalingServerUrl/discover/candidates')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    return (data['candidates'] as List<dynamic>)
        .map((e) => DiscoverCandidate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Dönüş: eşleşme oluştuysa eşleşen kişinin [AppUser]'ı, oluşmadıysa null.
  Future<AppUser?> swipe({required String toId, required String action, String? note}) async {
    final response = await http
        .post(
          Uri.parse('$signalingServerUrl/discover/swipe'),
          headers: _headers,
          body: jsonEncode({'toId': toId, 'action': action, if (note != null) 'note': note}),
        )
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    if (data['matched'] == true) {
      return AppUser.fromJson(data['user'] as Map<String, dynamic>);
    }
    return null;
  }

  Future<void> rewind() async {
    final response = await http
        .post(Uri.parse('$signalingServerUrl/discover/rewind'), headers: _headers, body: '{}')
        .timeout(const Duration(seconds: 10));
    _decodeOrThrow(response);
  }

  Future<List<LikedYouEntry>> fetchLikesMe() async {
    final response = await http
        .get(Uri.parse('$signalingServerUrl/discover/likes-me'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    return (data['likes'] as List<dynamic>)
        .map((e) => LikedYouEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<DateMatch>> fetchMatches() async {
    final response = await http
        .get(Uri.parse('$signalingServerUrl/discover/matches'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    return (data['matches'] as List<dynamic>)
        .map((e) => DateMatch.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> submitWeMet(String matchId, bool met) async {
    final response = await http
        .post(
          Uri.parse('$signalingServerUrl/discover/matches/$matchId/we-met'),
          headers: _headers,
          body: jsonEncode({'met': met}),
        )
        .timeout(const Duration(seconds: 10));
    _decodeOrThrow(response);
  }

  Future<AppUser> activateBoost() async {
    final response = await http
        .post(Uri.parse('$signalingServerUrl/discover/boost'), headers: _headers, body: '{}')
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<List<CompatibilityQuestion>> fetchQuizQuestions() async {
    final response = await http
        .get(Uri.parse('$signalingServerUrl/discover/quiz-questions'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    return (data['questions'] as List<dynamic>)
        .map((e) => CompatibilityQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<String>> fetchBadgeCatalog() async {
    final response = await http
        .get(Uri.parse('$signalingServerUrl/discover/badge-catalog'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final data = _decodeOrThrow(response);
    return (data['badges'] as List<dynamic>).map((e) => e.toString()).toList();
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
