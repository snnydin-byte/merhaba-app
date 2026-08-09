import 'auth_api_client.dart';

class AccountRepository {
  AccountRepository({required AuthApiClient apiClient})
      : _apiClient = apiClient;

  final AuthApiClient _apiClient;

  Future<void> deleteAccount({required String token}) async {
    final response = await _apiClient.delete('/profile', token: token);
    _apiClient.decodeOrThrow(response);
  }
}
