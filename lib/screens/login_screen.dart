import 'dart:async';

import 'package:flutter/material.dart';

import '../services/adult_age_policy.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/warm_signal_mark.dart';
import 'home_screen.dart';

/// Giriş ve kayıt için tek bir ekran; ikisi arasında geçiş yapılabilir.
/// Gerçek kimlik doğrulama sinyalleşme sunucusundaki /auth/* uçlarıyla
/// yapılır. Merhaba yalnızca doğum tarihiyle 18+ doğrulamasını tamamlamış
/// hesaplara açıktır; v108 itibarıyla misafir modu bulunmaz.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isRegisterMode = false;
  bool _requiresAgeVerification = false;
  bool _adultConfirmed = false;
  DateTime? _birthDate;
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _showsAgeGate => _isRegisterMode || _requiresAgeVerification;

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: AdultAgePolicy.earliestEligibleBirthDate(now),
      lastDate: AdultAgePolicy.latestEligibleBirthDate(now),
      helpText: 'Doğum tarihini seç',
    );
    if (picked != null && mounted) {
      setState(() => _birthDate = picked);
    }
  }

  bool _validateAgeGate() {
    if (!_showsAgeGate) return true;
    final birthDate = _birthDate;
    if (birthDate == null) {
      setState(() => _errorText = 'Devam etmek için doğum tarihini seç.');
      return false;
    }
    if (!AdultAgePolicy.isAdult(birthDate)) {
      setState(() => _errorText =
          'Merhaba yalnızca 18 yaşını doldurmuş kullanıcılara açıktır.');
      return false;
    }
    if (!_adultConfirmed) {
      setState(() => _errorText =
          '18 yaşını doldurduğunu ve kullanım koşullarını kabul ettiğini onayla.');
      return false;
    }
    return true;
  }

  String? get _birthDateForRequest =>
      _birthDate == null ? null : AdultAgePolicy.toApiDate(_birthDate!);

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_validateAgeGate()) return;

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      if (_isRegisterMode) {
        await _authService.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
          birthDate: _birthDateForRequest!,
          adultConfirmed: _adultConfirmed,
        );
      } else {
        await _authService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          birthDate: _requiresAgeVerification ? _birthDateForRequest : null,
          adultConfirmed: _requiresAgeVerification ? _adultConfirmed : false,
        );
      }
      if (!mounted) return;
      _goToHome();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e.message;
          if (e.requiresAgeVerification) {
            _requiresAgeVerification = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _errorText = 'Beklenmeyen bir hata oluştu, tekrar dene.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitWithGoogle() async {
    if (_showsAgeGate && !_validateAgeGate()) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final user = await _authService.signInWithGoogle(
        birthDate: _showsAgeGate ? _birthDateForRequest : null,
        adultConfirmed: _showsAgeGate ? _adultConfirmed : false,
      );
      if (user == null) {
        // Kullanıcı hesap seçiciyi iptal etti - sessizce dön, hata gösterme.
        return;
      }
      if (!mounted) return;
      _goToHome();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e.message;
          if (e.requiresAgeVerification) {
            _requiresAgeVerification = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _errorText = 'Beklenmeyen bir hata oluştu, tekrar dene.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      AppPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  // Kompozisyon: merkezi-sütun form yerine, üstte sabit bir "aurora" atmosfer
  // alanı (ekranın ~%38'i, hiç kaymıyor) + alttan yükselen yuvarlak köşeli bir
  // "sheet" kart (form içeriği bunun içinde, kendi içinde kaydırılabilir).
  // Popüler eşleşme uygulamalarının (Bumble/Hinge tarzı) giriş ekranlarındaki
  // "atmosfer üstte, aksiyon altta sabit" hiyerarşisinden ilham alındı - ama
  // marka öğeleri (ConnectionMark, neon palet) tamamen bu projeye özel.
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
      body: Stack(
        children: [
          _buildAurora(screenHeight),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                SizedBox(
                  height: screenHeight * 0.34,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const WarmSignalMark(size: 88),
                        const SizedBox(height: 14),
                        Text('MERHABA',
                            style: AppText.display
                                .copyWith(fontSize: 20, letterSpacing: 5)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(32)),
                      border: Border(
                        top: BorderSide(color: AppColors.surfaceBorder),
                        left: BorderSide(color: AppColors.surfaceBorder),
                        right: BorderSide(color: AppColors.surfaceBorder),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Alt sheet'i tutan küçük "grabber" çubuğu -
                            // bottom sheet paternini görsel olarak çağrıştırır.
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceBorder,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Text(
                              _isRegisterMode
                                  ? 'Hesap oluştur'
                                  : 'Tekrar hoş geldin',
                              style: AppText.heading.copyWith(fontSize: 24),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isRegisterMode
                                  ? 'Merhaba yalnızca 18 yaşını doldurmuş kullanıcılara açıktır.'
                                  : 'Devam etmek için giriş yap.',
                              style: AppText.body,
                            ),
                            const SizedBox(height: 24),
                            if (_errorText != null) _buildError(),
                            if (_isRegisterMode) ...[
                              _buildNameField(),
                              const SizedBox(height: 14),
                            ],
                            if (_showsAgeGate) ...[
                              _buildBirthDateField(),
                              const SizedBox(height: 8),
                              _buildAdultConfirmation(),
                              const SizedBox(height: 14),
                            ],
                            _buildEmailField(),
                            const SizedBox(height: 14),
                            _buildPasswordField(),
                            const SizedBox(height: 22),
                            _buildSubmitButton(),
                            const SizedBox(height: 14),
                            _buildModeToggle(),
                            if (isGoogleSignInConfigured) ...[
                              const SizedBox(height: 20),
                              _buildDivider(),
                              const SizedBox(height: 16),
                              _buildGoogleButton(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Üstteki sabit atmosfer alanı - iki örtüşen, farklı büyüklükte neon
  /// radyal glow (mor + camgöbeği), sheet'in arkasında kalacak şekilde
  /// konumlandırılmış. Gerçek bir video/görsel arka plan DEĞİL (performans +
  /// bakım maliyeti gereksiz) - salt gradyan kompozisyonu.
  Widget _buildAurora(double screenHeight) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: screenHeight * 0.42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.45),
                  AppColors.primary.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.secondary.withValues(alpha: 0.35),
                  AppColors.secondary.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorText!,
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      textCapitalization: TextCapitalization.words,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _fieldDecoration('İsim', Icons.person_outline),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'İsmini gir' : null,
    );
  }

  Widget _buildBirthDateField() {
    return InkWell(
      onTap: _loading ? null : _pickBirthDate,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: _fieldDecoration(
          'Doğum tarihi',
          Icons.cake_outlined,
        ),
        child: Text(
          _birthDate == null
              ? '18+ doğrulaması için seç'
              : AdultAgePolicy.displayDate(_birthDate!),
          style: TextStyle(
            color: _birthDate == null
                ? AppColors.textMuted
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildAdultConfirmation() {
    return CheckboxListTile(
      value: _adultConfirmed,
      onChanged: _loading
          ? null
          : (value) => setState(() => _adultConfirmed = value ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        '18 yaşını doldurdum ve kullanım koşullarını kabul ediyorum.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _fieldDecoration('E-posta', Icons.mail_outline),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'E-posta adresini gir';
        final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());
        return ok ? null : 'Geçerli bir e-posta gir';
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: true,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: _fieldDecoration('Şifre', Icons.lock_outline),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Şifreni gir';
        if (_isRegisterMode && v.length < 8) return 'En az 8 karakter olmalı';
        return null;
      },
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    // Doldurma rengi/köşe yuvarlaklığı/hata rengi artık MaterialApp'in
    // InputDecorationTheme'inden geliyor (bkz. theme/app_theme.dart) - burada
    // yalnızca bu alana özgü olanları (etiket, ikon) belirtiyoruz.
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.textMuted),
      prefixIcon: Icon(icon, color: AppColors.textFaint, size: 20),
      errorStyle: TextStyle(color: AppColors.danger, fontSize: 11),
    );
  }

  Widget _buildSubmitButton() {
    return GradientButton(
      onPressed: _loading ? null : _submit,
      height: 54,
      child: _loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
          : Text(
              _isRegisterMode ? 'Hesap Oluştur' : 'Giriş Yap',
              style: AppText.button,
            ),
    );
  }

  Widget _buildModeToggle() {
    return Center(
      child: TextButton(
        onPressed: _loading
            ? null
            : () => setState(() {
                  _isRegisterMode = !_isRegisterMode;
                  _requiresAgeVerification = false;
                  _birthDate = null;
                  _adultConfirmed = false;
                  _errorText = null;
                }),
        child: Text(
          _isRegisterMode
              ? 'Zaten hesabın var mı? Giriş yap'
              : 'Hesabın yok mu? Hesap oluştur',
          style: TextStyle(color: AppColors.primaryLight, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('veya', style: AppText.caption),
        ),
        Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: _loading ? null : _submitWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.g_mobiledata_rounded,
                size: 26, color: AppColors.textPrimary),
            const SizedBox(width: 4),
            const Text('Google ile devam et'),
          ],
        ),
      ),
    );
  }
}
