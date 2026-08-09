import 'auth_api_client.dart';
import 'auth_repository.dart';
import 'account_repository.dart';
import 'google_auth_provider.dart';
import 'profile_repository.dart';
import 'relationship_repository.dart';
import 'session_storage.dart';
import 'utility_repository.dart';
import 'webrtc_service.dart' show signalingServerUrl;

/// AuthService'in platform ve ağ bağımlılıklarını tek yerde toplar.
///
/// Production kurulumu [AuthDependencies.production] ile oluşturulur. Testler
/// yalnızca ihtiyaç duyduğu bağımlılığı [copyWith] üzerinden değiştirir; böylece
/// AuthService içinde repository yeniden kurma ayrıntıları bulunmaz.
class AuthDependencies {
  final SessionStorage sessionStorage;
  final AuthApiClient apiClient;
  final GoogleAuthProvider googleAuthProvider;
  final AuthRepository authRepository;
  final ProfileRepository profileRepository;
  final AccountRepository accountRepository;
  final RelationshipRepository relationshipRepository;
  final UtilityRepository utilityRepository;

  const AuthDependencies({
    required this.sessionStorage,
    required this.apiClient,
    required this.googleAuthProvider,
    required this.authRepository,
    required this.profileRepository,
    required this.accountRepository,
    required this.relationshipRepository,
    required this.utilityRepository,
  });

  factory AuthDependencies.production() {
    final apiClient = AuthApiClient(baseUrl: signalingServerUrl);
    final googleAuthProvider = GoogleSignInProvider();
    return AuthDependencies.fromCore(
      sessionStorage: SecureSessionStorage(),
      apiClient: apiClient,
      googleAuthProvider: googleAuthProvider,
    );
  }

  factory AuthDependencies.fromCore({
    required SessionStorage sessionStorage,
    required AuthApiClient apiClient,
    required GoogleAuthProvider googleAuthProvider,
  }) {
    return AuthDependencies(
      sessionStorage: sessionStorage,
      apiClient: apiClient,
      googleAuthProvider: googleAuthProvider,
      authRepository: AuthRepository(
        apiClient: apiClient,
        googleAuthProvider: googleAuthProvider,
      ),
      profileRepository: ProfileRepository(apiClient: apiClient),
      accountRepository: AccountRepository(apiClient: apiClient),
      relationshipRepository: RelationshipRepository(apiClient: apiClient),
      utilityRepository: UtilityRepository(apiClient: apiClient),
    );
  }

  /// Ağ istemcisi değiştiğinde ona bağlı bütün repository'leri atomik olarak
  /// yeniden kurar. Testlerde eski ve yeni istemci kullanan karışık bir graph
  /// oluşmasını engeller.
  AuthDependencies withApiClient(AuthApiClient client) {
    return AuthDependencies.fromCore(
      sessionStorage: sessionStorage,
      apiClient: client,
      googleAuthProvider: googleAuthProvider,
    );
  }

  /// Google sağlayıcısı değiştiğinde AuthRepository de aynı anda yenilenir.
  AuthDependencies withGoogleAuthProvider(GoogleAuthProvider provider) {
    return AuthDependencies(
      sessionStorage: sessionStorage,
      apiClient: apiClient,
      googleAuthProvider: provider,
      authRepository: AuthRepository(
        apiClient: apiClient,
        googleAuthProvider: provider,
      ),
      profileRepository: profileRepository,
      accountRepository: accountRepository,
      relationshipRepository: relationshipRepository,
      utilityRepository: utilityRepository,
    );
  }

  AuthDependencies copyWith({
    SessionStorage? sessionStorage,
    AuthRepository? authRepository,
    ProfileRepository? profileRepository,
    AccountRepository? accountRepository,
    RelationshipRepository? relationshipRepository,
    UtilityRepository? utilityRepository,
  }) {
    return AuthDependencies(
      sessionStorage: sessionStorage ?? this.sessionStorage,
      apiClient: apiClient,
      googleAuthProvider: googleAuthProvider,
      authRepository: authRepository ?? this.authRepository,
      profileRepository: profileRepository ?? this.profileRepository,
      accountRepository: accountRepository ?? this.accountRepository,
      relationshipRepository:
          relationshipRepository ?? this.relationshipRepository,
      utilityRepository: utilityRepository ?? this.utilityRepository,
    );
  }
}
