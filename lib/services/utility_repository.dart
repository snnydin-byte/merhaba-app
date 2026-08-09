import '../models/app_user.dart';
import 'auth_api_client.dart';
import 'auth_exception.dart';

class UtilityRepository {
  UtilityRepository({required AuthApiClient apiClient})
      : _apiClient = apiClient;

  final AuthApiClient _apiClient;

  Future<String> translateText({
    required String token,
    required String text,
    required String targetLang,
  }) async {
    final response = await _apiClient.post(
      '/translate',
      token: token,
      body: {'text': text, 'targetLang': targetLang},
    );
    final data = _apiClient.decodeOrThrow(response);
    final translated = data['translatedText'];
    if (translated is! String) {
      throw AuthException('Sunucudan çeviri sonucu alınamadı.');
    }
    return translated;
  }

  Future<AppUser> updateTrustedContacts({
    required String token,
    required List<TrustedContact> contacts,
  }) async {
    final response = await _apiClient.put(
      '/profile/trusted-contacts',
      token: token,
      body: {'contacts': contacts.map((contact) => contact.toJson()).toList()},
    );
    final data = _apiClient.decodeOrThrow(response);
    final rawUser = data['user'];
    if (rawUser is! Map) {
      throw AuthException('Sunucudan güncel kullanıcı bilgisi alınamadı.');
    }
    return AppUser.fromJson(Map<String, dynamic>.from(rawUser));
  }
}
