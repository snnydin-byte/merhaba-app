import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'messaging_service.dart' show PersistentMessage;
import 'webrtc_service.dart' show signalingServerUrl;

class ConversationPage {
  const ConversationPage({
    required this.messages,
    required this.hasMore,
    this.nextBefore,
  });

  final List<PersistentMessage> messages;
  final bool hasMore;
  final String? nextBefore;
}

/// Sinyalleşme sunucusundaki /friends uçlarıyla haberleşir. Arkadaş
/// eklemenin kendisi (istek gönderme/kabul etme) video sohbet ekranında,
/// canlı bir eşleşme üzerinden soket ile yapılıyor (bkz. webrtc_service.dart)
/// - burası yalnızca mevcut arkadaş listesini okumak/kaldırmak için.
class FriendsService {
  /// Giriş yapmış kullanıcının arkadaş listesini döner. Giriş yapılmamışsa
  /// (oturum yoksa) boş liste döner - çağıran taraf bu durumda ayrı bir
  /// "giriş yap" ekranı göstermeli.
  Future<List<AppUser>> fetchFriends() async {
    final token = AuthService().token;
    if (token == null) return [];

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$signalingServerUrl/friends'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Sinyalleşme sunucusunun çalıştığından emin ol.');
    }

    if (response.statusCode == 401) {
      throw AuthException(
          'Oturumun sona ermiş, tekrar giriş yapman gerekiyor.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('Arkadaş listesi alınamadı, tekrar dene.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['friends'] as List<dynamic>? ?? []);
    return list
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Bir arkadaşlığı kaldırır (karşılıklı - iki taraf da birbirinin
  /// listesinden çıkar).
  Future<void> removeFriend(String friendId) async {
    final token = AuthService().token;
    if (token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }

    final http.Response response;
    try {
      response = await http.delete(
        Uri.parse('$signalingServerUrl/friends/$friendId'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Sinyalleşme sunucusunun çalıştığından emin ol.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('Arkadaş kaldırılamadı, tekrar dene.');
    }
  }

  /// Bir arkadaşla olan kalıcı sohbet geçmişini çeker. Kaybolan mesajlar
  /// sunucuda hiç saklanmadığı için burada asla görünmezler - bkz.
  /// messaging_service.dart'taki açıklama.
  Future<ConversationPage> fetchConversationPage(
    String friendId, {
    String? before,
    int limit = 100,
  }) async {
    final token = AuthService().token;
    if (token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }

    final uri = Uri.parse('$signalingServerUrl/messages/$friendId').replace(
      queryParameters: {
        'limit': limit.clamp(1, 200).toString(),
        if (before != null && before.isNotEmpty) 'before': before,
      },
    );
    final http.Response response;
    try {
      response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      throw AuthException(
          'Sunucuya ulaşılamıyor. Sinyalleşme sunucusunun çalıştığından emin ol.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('Sohbet geçmişi alınamadı, tekrar dene.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['messages'] as List<dynamic>? ?? []);
    return ConversationPage(
      messages: list
          .map((e) => PersistentMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasMore: data['hasMore'] as bool? ?? false,
      nextBefore: data['nextBefore'] as String?,
    );
  }

  Future<List<PersistentMessage>> fetchConversation(String friendId) async =>
      (await fetchConversationPage(friendId)).messages;
}
