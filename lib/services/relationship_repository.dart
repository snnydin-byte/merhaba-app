import 'auth_api_client.dart';
import 'auth_exception.dart';

class RelationshipRepository {
  RelationshipRepository({required AuthApiClient apiClient})
      : _apiClient = apiClient;

  final AuthApiClient _apiClient;

  Future<void> reportFriend({
    required String token,
    required String friendId,
    required String reason,
    String? note,
  }) async {
    final response = await _apiClient.post(
      '/friends/${Uri.encodeComponent(friendId)}/report',
      token: token,
      body: {
        'reason': reason,
        if (note != null) 'note': note,
      },
    );
    _apiClient.decodeOrThrow(response);
  }

  Future<List<String>> toggleCloseFriend({
    required String token,
    required String friendId,
  }) async {
    final response = await _apiClient.post(
      '/friends/${Uri.encodeComponent(friendId)}/close-friend',
      token: token,
      body: const {},
    );
    final data = _apiClient.decodeOrThrow(response);
    final rawIds = data['closeFriendIds'];
    if (rawIds is! List) {
      throw AuthException('Sunucudan yakın arkadaş listesi alınamadı.');
    }
    return rawIds.map((value) => value.toString()).toList(growable: false);
  }
}
