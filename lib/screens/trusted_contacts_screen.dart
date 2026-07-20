import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Güvenilir kişiler + panik butonu + buluşma detayı paylaşma (Batch F).
/// Noonlight gibi ÜÇÜNCÜ TARAF bir acil durum servisi YOK (backlog'daki
/// "Noonlight YOK" notuyla bilinçli) - yalnızca cihazın kendi SMS
/// uygulamasını (`sms:` şeması, url_launcher) önceden doldurulmuş bir
/// mesajla açıyoruz, gönderme kararı HER ZAMAN kullanıcıda kalıyor. Bu,
/// sunucu tamamen çökmüş olsa BİLE çalışır - gerçek bir acil durumda
/// sunucuya bağımlı bir çözüm riskli olurdu.
class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  final List<TrustedContact> _contacts =
      List.of(AuthService().currentUser?.trustedContacts ?? const []);
  bool _saving = false;
  bool _locating = false;

  Future<void> _addContact() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Güvenilir kişi ekle', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'İsim'),
            ),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(hintText: 'Telefon numarası'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ekle')),
        ],
      ),
    );
    if (added != true) return;
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) return;
    if (_contacts.length >= 5) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('En fazla 5 güvenilir kişi ekleyebilirsin.')));
      }
      return;
    }
    setState(() => _contacts.add(TrustedContact(name: name, phone: phone)));
    await _save();
  }

  Future<void> _removeContact(int index) async {
    setState(() => _contacts.removeAt(index));
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AuthService().updateTrustedContacts(_contacts);
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String> _locationSnippet() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted =
          permission != LocationPermission.denied && permission != LocationPermission.deniedForever;
      if (!granted || !await Geolocator.isLocationServiceEnabled()) return '';
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 8));
      return ' Konumum: https://maps.google.com/?q=${position.latitude},${position.longitude}';
    } catch (_) {
      return '';
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _sendToContact(TrustedContact contact, String body) async {
    final uri = Uri(
      scheme: 'sms',
      path: contact.phone,
      queryParameters: {'body': body},
    );
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contact.name} için SMS uygulaması açılamadı.')),
        );
      }
    }
  }

  /// Panik butonu (madde "panik/acil durum butonu") - Noonlight/gerçek acil
  /// çağrı entegrasyonu YOK (bkz. sınıf üstü not). Her güvenilir kişi için
  /// AYRI AYRI SMS uygulaması açılır (kullanıcı her birini kendi onaylayıp
  /// gönderir) - `sms:` şeması güvenilir şekilde tek alıcı destekliyor.
  Future<void> _triggerPanic() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Önce en az bir güvenilir kişi ekle.')));
      return;
    }
    final locationText = await _locationSnippet();
    if (!mounted) return;
    final body = 'Yardıma ihtiyacım olabilir, lütfen benimle iletişime geç.$locationText';
    for (final contact in _contacts) {
      await _sendToContact(contact, body);
    }
  }

  Future<void> _shareMeetingDetails() async {
    final controller = TextEditingController();
    final details = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Buluşma detayını paylaş', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Kiminle, nerede, ne zaman buluşuyorsun?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (details == null || details.isEmpty || !mounted) return;
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Önce en az bir güvenilir kişi ekle.')));
      return;
    }
    final locationText = await _locationSnippet();
    if (!mounted) return;
    final body = 'Buluşma detayım: $details.$locationText';
    for (final contact in _contacts) {
      await _sendToContact(contact, body);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Güvenilir Kişiler'), backgroundColor: Colors.transparent, elevation: 0),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Güvenilir kişiler gerçek bir hesap değil - yalnızca isim ve telefon '
                'numarası. Panik butonuna bastığında ya da buluşma detayını '
                'paylaştığında, her biri için telefonunun SMS uygulaması hazır bir '
                'mesajla açılır - göndermek sana kalmış.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ..._contacts.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.value.name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                Text(entry.value.phone,
                                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _saving ? null : () => _removeContact(entry.key),
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          ),
                        ],
                      ),
                    ),
                  )),
              OutlinedButton.icon(
                onPressed: _saving ? null : _addContact,
                icon: const Icon(Icons.add),
                label: const Text('Güvenilir kişi ekle'),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _locating ? null : _shareMeetingDetails,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Buluşma detayını paylaş'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _locating ? null : _triggerPanic,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                  icon: _locating
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.emergency_share_rounded, color: Colors.white),
                  label: const Text('Yardım İste', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
