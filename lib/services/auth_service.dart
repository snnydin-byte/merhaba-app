import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import 'auth_api_client.dart';
import 'auth_dependencies.dart';
import 'auth_repository.dart';
import 'auth_session_state.dart';
import 'auth_exception.dart';
import 'account_repository.dart';
import 'active_media_session_coordinator.dart';
import 'profile_repository.dart';
import 'relationship_repository.dart';
import 'utility_repository.dart';
import 'google_auth_provider.dart';
import 'orphan_media_cleanup_queue.dart';
import 'session_storage.dart';
import 'session_end_progress.dart';

export '../models/app_user.dart';
export 'auth_exception.dart';
export 'auth_session_state.dart';
export 'google_auth_provider.dart' show isGoogleSignInConfigured;

/// Uygulamanın kimlik doğrulama durumunu ve sinyalleşme sunucusundaki
/// /auth/* + /profile uçlarıyla haberleşmeyi yönetir.
///
/// Kısa ömürlü erişim tokenı ve döndürülebilir refresh token platformun
/// güvenli kasasında; hassas olmayan kullanıcı özeti SharedPreferences içinde
/// saklanır. Refresh token sunucuda hash'li bir oturum kaydına bağlıdır ve her
/// yenilemede rotate edilir.
///
/// Basit bir singleton: uygulama boyunca tek bir örnek kullanılır ki
/// splash/login/home/profile ekranları aynı oturum durumunu görsün.
class AuthService {
  AuthService._internal() : _dependencies = AuthDependencies.production();
  static final AuthService instance = AuthService._internal();
  factory AuthService() => instance;

  AuthDependencies _dependencies;
  String? _refreshToken;
  Timer? _accessRefreshTimer;
  Future<bool>? _refreshInFlight;

  SessionStorage get _sessionStorage => _dependencies.sessionStorage;
  AuthRepository get _authRepository => _dependencies.authRepository;
  ProfileRepository get _profileRepository => _dependencies.profileRepository;
  AccountRepository get _accountRepository => _dependencies.accountRepository;
  RelationshipRepository get _relationshipRepository =>
      _dependencies.relationshipRepository;
  UtilityRepository get _utilityRepository => _dependencies.utilityRepository;

  /// Ekranların giriş, çıkış ve profil değişikliklerini reaktif biçimde
  /// dinleyebilmesi için tek, atomik oturum kaynağı.
  final ValueNotifier<AuthSessionState> sessionState =
      ValueNotifier<AuthSessionState>(const AuthSessionState.signedOut());

  String? get token => sessionState.value.token;
  AppUser? get currentUser => sessionState.value.user;
  bool get isLoggedIn => sessionState.value.isAuthenticated;

  /// Cihazda daha önce saklanmış bir oturum var mı diye bakar (sunucuya
  /// gitmeden). Splash ekranında sunucuya sormadan önce hızlı bir "muhtemelen
  /// giriş yapılmış" durumu vermek için kullanılır.
  Future<bool> restoreSession() async {
    final session = await _sessionStorage.read();
    if (session == null) {
      _clearSession();
      return false;
    }

    _refreshToken = session.refreshToken;
    _setSession(
      token: session.token,
      user: AppUser(
        id: session.userId,
        email: session.email,
        displayName: session.displayName,
      ),
    );
    _scheduleAccessRefresh(session.token);
    return true;
  }

  /// Sunucudaki oturumu doğrular. Ağ geçici olarak erişilemezse yerel
  /// oturum korunur; yalnızca sunucu açıkça 401 döndürürse çıkış yapılır.
  Future<bool> verifySession() async {
    final token = this.token;
    if (token == null) return false;

    final verification = await _authRepository.verifySession(token);
    if (verification.isUnauthorized) {
      if (_refreshToken != null) {
        if (await refreshSession()) return true;
        // refreshSession only clears the local session when the server
        // definitively rejects the refresh token. Keep an offline session
        // when a timeout/network error leaves the current token intact.
        if (this.token != null) return true;
      }
      await logout();
      return false;
    }
    if (verification.user != null) {
      _setUser(verification.user!);
      await _persist();
    }
    return true;
  }

  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
    required String birthDate,
    required bool adultConfirmed,
  }) async {
    final session = await _authRepository.register(
      email: email,
      password: password,
      displayName: displayName,
      birthDate: birthDate,
      adultConfirmed: adultConfirmed,
    );
    return _applyAuthSession(session);
  }

  Future<AppUser> login({
    required String email,
    required String password,
    String? birthDate,
    bool adultConfirmed = false,
  }) async {
    final session = await _authRepository.login(
      email: email,
      password: password,
      birthDate: birthDate,
      adultConfirmed: adultConfirmed,
    );
    return _applyAuthSession(session);
  }

  /// Google hesap seçimini ve backend oturum değişimini repository yönetir.
  /// Kullanıcı hesap seçiciyi iptal ederse hata fırlatılmaz, null döner.
  Future<AppUser?> signInWithGoogle({
    String? birthDate,
    bool adultConfirmed = false,
  }) async {
    final session = await _authRepository.signInWithGoogle(
      birthDate: birthDate,
      adultConfirmed: adultConfirmed,
    );
    if (session == null) return null;
    return _applyAuthSession(session);
  }

  Future<void> updateDisplayName(String displayName) async {
    await updateProfile(displayName: displayName);
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? gender,
    List<String>? interests,
    String? country,
    String? language,
    bool? hideOnlineStatus,
    bool? hideLastSeen,
    bool? readReceiptsEnabled,
    String? birthDate,
    bool? discoverInvisible,
    List<String>? profileBadges,
    Map<String, int>? compatibilityAnswers,
    AvatarConfig? avatarConfig,
    bool clearAvatarConfig = false,
  }) async {
    final token = _requireToken();
    final updatedUser = await _profileRepository.updateProfile(
      token: token,
      fallbackDisplayName: currentUser?.displayName ?? '',
      displayName: displayName,
      bio: bio,
      gender: gender,
      interests: interests,
      country: country,
      language: language,
      hideOnlineStatus: hideOnlineStatus,
      hideLastSeen: hideLastSeen,
      readReceiptsEnabled: readReceiptsEnabled,
      birthDate: birthDate,
      discoverInvisible: discoverInvisible,
      profileBadges: profileBadges,
      compatibilityAnswers: compatibilityAnswers,
      avatarConfig: avatarConfig,
      clearAvatarConfig: clearAvatarConfig,
    );
    _setUser(updatedUser);
    await _persist();
  }

  Future<void> uploadProfilePhoto(File file) async {
    final updatedUser = await _profileRepository.uploadProfilePhoto(
      token: _requireToken(),
      file: file,
    );
    _setUser(updatedUser);
    await _persist();
  }

  Future<void> removeProfilePhoto() async {
    final updatedUser = await _profileRepository.removeProfilePhoto(
      token: _requireToken(),
    );
    _setUser(updatedUser);
    await _persist();
  }

  Future<void> uploadIntroVideo(File file) async {
    final updatedUser = await _profileRepository.uploadIntroVideo(
      token: _requireToken(),
      file: file,
    );
    _setUser(updatedUser);
    await _persist();
  }

  Future<void> removeIntroVideo() async {
    final updatedUser = await _profileRepository.removeIntroVideo(
      token: _requireToken(),
    );
    _setUser(updatedUser);
    await _persist();
  }

  Future<void> uploadSelfieVerification(File file) async {
    final updatedUser = await _profileRepository.uploadSelfieVerification(
      token: _requireToken(),
      file: file,
    );
    _setUser(updatedUser);
    await _persist();
  }

  static const Duration _logoutDeadline = Duration(seconds: 12);
  static const Duration _accountDeleteRequestDeadline = Duration(seconds: 15);
  static const Duration _postDeleteCleanupDeadline = Duration(seconds: 10);

  /// Hesabı sunucudan kalıcı olarak siler ve yerel oturumu temizler.
  ///
  /// Sunucu silme isteği doğrulanmadan yerel oturum zorla kapatılmaz. İstek
  /// başarılı olduktan sonraki yerel/medya temizliği takılırsa ise kullanıcıyı
  /// sonsuza kadar bekletmemek için yerel oturum üst süre sonunda zorla
  /// temizlenir; kalan uzak medya temizliği backend TTL mekanizmasına bırakılır.
  Future<void> deleteAccount() async {
    const operation = SessionEndOperation.deleteAccount;
    final progress = SessionEndProgressController();
    final generation = progress.begin(
      operation: operation,
      message: 'Hesap silme işlemi hazırlanıyor…',
    );
    final userId = currentUser?.id;
    final token = _requireToken();

    if (userId != null) {
      await _flushOrphanMediaWithTimeout(
        userId: userId,
        operation: operation,
        generation: generation,
      );
    }

    progress.update(
      generation: generation,
      operation: operation,
      phase: SessionEndPhase.deletingAccount,
      message: 'Sunucudaki hesap ve veriler siliniyor…',
    );

    try {
      await _accountRepository
          .deleteAccount(token: token)
          .timeout(_accountDeleteRequestDeadline);
    } on TimeoutException {
      progress.update(
        generation: generation,
        operation: operation,
        phase: SessionEndPhase.failed,
        message: 'Sunucu hesap silme isteğini zamanında doğrulayamadı.',
        timedOut: true,
      );
      throw AuthException(
        'Hesap silme isteği zaman aşımına uğradı. Hesabın silindiği '
        'doğrulanamadığı için oturumun açık bırakıldı; lütfen tekrar dene.',
      );
    } catch (_) {
      progress.update(
        generation: generation,
        operation: operation,
        phase: SessionEndPhase.failed,
        message: 'Hesap silme tamamlanamadı.',
      );
      rethrow;
    }

    try {
      await _completeDeletedAccountCleanup(
        userId: userId,
        generation: generation,
      ).timeout(_postDeleteCleanupDeadline);
    } on TimeoutException {
      await _forceLocalSessionClear(
        operation: operation,
        message: 'Hesap silindi; kalan yerel temizlik zaman aşımı nedeniyle '
            'güvenli biçimde tamamlandı.',
      );
    }
  }

  Future<void> _completeDeletedAccountCleanup({
    required String? userId,
    required int generation,
  }) async {
    if (userId != null) {
      await OrphanMediaCleanupQueue().removeEntriesForUser(userId);
    }
    await _logout(
      flushOrphanMedia: false,
      operation: SessionEndOperation.deleteAccount,
      generation: generation,
      applyOverallDeadline: false,
    );
  }

  Future<void> reportFriend(
    String friendId,
    String reason, {
    String? note,
  }) {
    return _relationshipRepository.reportFriend(
      token: _requireToken(),
      friendId: friendId,
      reason: reason,
      note: note,
    );
  }

  Future<String> translateText(String text, String targetLang) {
    return _utilityRepository.translateText(
      token: _requireToken(),
      text: text,
      targetLang: targetLang,
    );
  }

  Future<void> toggleCloseFriend(String friendId) async {
    final ids = await _relationshipRepository.toggleCloseFriend(
      token: _requireToken(),
      friendId: friendId,
    );
    final user = currentUser;
    if (user != null) {
      _setUser(user.copyWith(closeFriendIds: ids));
      await _persist();
    }
  }

  Future<void> updateTrustedContacts(List<TrustedContact> contacts) async {
    final updatedUser = await _utilityRepository.updateTrustedContacts(
      token: _requireToken(),
      contacts: contacts,
    );
    _setUser(updatedUser);
    await _persist();
  }

  Future<void> logout() async {
    const operation = SessionEndOperation.logout;
    final progress = SessionEndProgressController();
    final generation = progress.begin(
      operation: operation,
      message: 'Çıkış hazırlanıyor…',
    );
    await _logout(
      operation: operation,
      generation: generation,
      applyOverallDeadline: true,
    );
  }

  Future<void> _logout({
    bool flushOrphanMedia = true,
    SessionEndOperation operation = SessionEndOperation.logout,
    int? generation,
    bool applyOverallDeadline = false,
  }) async {
    final progress = SessionEndProgressController();
    final activeGeneration = generation ??
        progress.begin(
          operation: operation,
          message: 'Çıkış hazırlanıyor…',
        );

    final cleanup = _performLogoutCleanup(
      flushOrphanMedia: flushOrphanMedia,
      operation: operation,
      generation: activeGeneration,
    );

    if (!applyOverallDeadline) {
      await cleanup;
      return;
    }

    try {
      await cleanup.timeout(_logoutDeadline);
    } on TimeoutException {
      await _forceLocalSessionClear(
        operation: operation,
        message: 'Çıkış üst süreye ulaştı; yerel oturum güvenli biçimde '
            'temizlendi. Kalan uzak medya temizliği sunucu güvenlik ağına '
            'bırakıldı.',
      );
    }
  }

  Future<void> _performLogoutCleanup({
    required bool flushOrphanMedia,
    required SessionEndOperation operation,
    required int generation,
  }) async {
    final progress = SessionEndProgressController();
    final userId = currentUser?.id;
    if (flushOrphanMedia && userId != null) {
      await _flushOrphanMediaWithTimeout(
        userId: userId,
        operation: operation,
        generation: generation,
      );
    }
    progress.update(
      generation: generation,
      operation: operation,
      phase: SessionEndPhase.closingCalls,
      message: 'Aktif kamera, mikrofon ve bağlantılar kapatılıyor…',
    );
    try {
      await ActiveMediaSessionCoordinator()
          .closeAll()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Bir medya eklentisi kapanmayı geciktirse bile oturum temizliği sürer.
    }
    progress.update(
      generation: generation,
      operation: operation,
      phase: SessionEndPhase.clearingSession,
      message: 'Güvenli oturum bilgileri temizleniyor…',
    );
    final refreshToken = _refreshToken;
    if (operation == SessionEndOperation.logout && refreshToken != null) {
      await _authRepository.revokeRefreshToken(refreshToken);
    }
    _clearSession();
    await _sessionStorage.clear();
    progress.update(
      generation: generation,
      operation: operation,
      phase: SessionEndPhase.completed,
      message: operation == SessionEndOperation.deleteAccount
          ? 'Hesap silindi.'
          : 'Çıkış tamamlandı.',
    );
  }

  Future<void> _forceLocalSessionClear({
    required SessionEndOperation operation,
    required String message,
  }) async {
    final progress = SessionEndProgressController();
    // Zaman aşımına uğrayan eski Future arka planda tamamlanırsa ilerleme
    // durumunu tekrar değiştirememesi için yeni bir generation başlatılır.
    final forcedGeneration = progress.begin(
      operation: operation,
      message: 'Üst süreye ulaşıldı; yerel oturum kapatılıyor…',
    );
    _clearSession();
    try {
      await _sessionStorage.clear().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Bellek içi oturum hemen kapatıldı. Güvenli depo eklentisi yanıt
      // vermiyorsa uygulamanın kapanmasını engellemiyoruz.
    }
    progress.update(
      generation: forcedGeneration,
      operation: operation,
      phase: SessionEndPhase.completed,
      message: message,
      timedOut: true,
    );
  }

  Future<void> _flushOrphanMediaWithTimeout({
    required String userId,
    required SessionEndOperation operation,
    required int generation,
  }) async {
    final progress = SessionEndProgressController();
    progress.update(
      generation: generation,
      operation: operation,
      phase: SessionEndPhase.cleaningMedia,
      message: 'Bekleyen medya temizliği tamamlanıyor…',
    );
    try {
      await OrphanMediaCleanupQueue()
          .flushBeforeSessionEnd(userId: userId)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      progress.update(
        generation: generation,
        operation: operation,
        phase: SessionEndPhase.cleaningMedia,
        message: 'Medya temizliği arka plan güvenlik ağına bırakıldı.',
        timedOut: true,
      );
    }
  }

  /// Yalnızca testlerde platform eklentisi olmadan oturum davranışını
  /// doğrulamak için kullanılır.
  void setSessionStorageForTesting(SessionStorage storage) {
    _dependencies = _dependencies.copyWith(sessionStorage: storage);
  }

  void setApiClientForTesting(AuthApiClient client) {
    _dependencies = _dependencies.withApiClient(client);
  }

  void setProfileRepositoryForTesting(ProfileRepository repository) {
    _dependencies = _dependencies.copyWith(profileRepository: repository);
  }

  void setAccountRepositoryForTesting(AccountRepository repository) {
    _dependencies = _dependencies.copyWith(accountRepository: repository);
  }

  void setRelationshipRepositoryForTesting(RelationshipRepository repository) {
    _dependencies = _dependencies.copyWith(relationshipRepository: repository);
  }

  void setUtilityRepositoryForTesting(UtilityRepository repository) {
    _dependencies = _dependencies.copyWith(utilityRepository: repository);
  }

  void setGoogleAuthProviderForTesting(GoogleAuthProvider provider) {
    _dependencies = _dependencies.withGoogleAuthProvider(provider);
  }

  void setAuthRepositoryForTesting(AuthRepository repository) {
    _dependencies = _dependencies.copyWith(authRepository: repository);
  }

  /// Bir testin bütün bağımlılık grafiğini tek seferde ve tutarlı biçimde
  /// değiştirmesi gerektiğinde kullanılır.
  void setDependenciesForTesting(AuthDependencies dependencies) {
    _dependencies = dependencies;
  }

  String _requireToken() {
    final token = this.token;
    if (token == null) {
      throw AuthException('Bu işlem için giriş yapmış olman gerekiyor.');
    }
    return token;
  }

  Future<AppUser> _applyAuthSession(AuthSession session) async {
    _refreshToken = session.refreshToken ?? _refreshToken;
    _setSession(token: session.token, user: session.user);
    _scheduleAccessRefresh(session.token);
    await _persist();
    return session.user;
  }

  /// Access JWT kısa ömürlüdür; refresh token secure storage'da tutulur ve
  /// her yenilemede server tarafından rotate edilir. Eşzamanlı refresh
  /// istekleri tek Future üzerinde birleşir.
  Future<bool> refreshSession() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _refreshSessionInternal();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _refreshSessionInternal() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final session = await _authRepository.refreshSession(refreshToken);
      _refreshToken = session.refreshToken ?? refreshToken;
      _setSession(token: session.token, user: session.user);
      _scheduleAccessRefresh(session.token);
      await _persist();
      return true;
    } on AuthException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        _clearSession();
        await _sessionStorage.clear();
      } else {
        _scheduleRefreshRetry();
      }
      return false;
    } catch (_) {
      _scheduleRefreshRetry();
      return false;
    }
  }

  Future<bool> refreshIfNeeded() async {
    final token = this.token;
    if (token == null) return false;
    if (!_accessTokenNeedsRefresh(token)) return true;
    if (_refreshToken == null) {
      return true; // legacy session; /auth/me karar verir.
    }
    return refreshSession();
  }

  bool _accessTokenNeedsRefresh(String token,
      {Duration skew = const Duration(minutes: 5)}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      final exp = payload is Map<String, dynamic> ? payload['exp'] : null;
      if (exp is! num) return true;
      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      return !DateTime.now().toUtc().add(skew).isBefore(expiresAt);
    } catch (_) {
      return true;
    }
  }

  void _scheduleRefreshRetry() {
    if (_refreshToken == null || token == null) return;
    _accessRefreshTimer?.cancel();
    _accessRefreshTimer = Timer(
      const Duration(minutes: 1),
      () => unawaited(refreshSession()),
    );
  }

  void _scheduleAccessRefresh(String token) {
    _accessRefreshTimer?.cancel();
    if (_refreshToken == null) return;
    Duration delay = const Duration(minutes: 10);
    try {
      final parts = token.split('.');
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map<String, dynamic> ? payload['exp'] : null;
      if (exp is num) {
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
            exp.toInt() * 1000,
            isUtc: true);
        final target = expiresAt.subtract(const Duration(minutes: 5));
        delay = target.difference(DateTime.now().toUtc());
        if (delay < const Duration(seconds: 1)) {
          delay = const Duration(seconds: 1);
        }
      }
    } catch (_) {}
    _accessRefreshTimer = Timer(delay, () => unawaited(refreshSession()));
  }

  void _setSession({required String token, required AppUser user}) {
    sessionState.value = AuthSessionState.authenticated(
      token: token,
      user: user,
    );
  }

  void _setUser(AppUser user) {
    final token = this.token;
    if (token == null) return;
    _setSession(token: token, user: user);
  }

  void _clearSession() {
    _accessRefreshTimer?.cancel();
    _accessRefreshTimer = null;
    _refreshToken = null;
    sessionState.value = const AuthSessionState.signedOut();
  }

  Future<void> _persist() async {
    final token = this.token;
    final user = currentUser;
    if (token == null || user == null) return;
    await _sessionStorage.write(
      StoredSession(
        token: token,
        refreshToken: _refreshToken,
        userId: user.id,
        email: user.email,
        displayName: user.displayName,
      ),
    );
  }
}
