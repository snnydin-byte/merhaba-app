import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/messaging_service.dart';
import '../theme/app_theme.dart';

/// Yeni bir durum/hikaye paylaşma akışını başlatır (#71 anket maddesi) -
/// "Metin durumu" (renkli arka plan + kısa metin) ya da "Fotoğraf durumu"
/// (kamera/galeri) seçilir. Gerçek paylaşım MessagingService.createStory
/// üzerinden - başarı/hata sunucudan asenkron gelir (bkz. onStoryCreateAck/
/// onStoryError, çağıran ekran bunları dinlemeli).
Future<void> showStoryCreatorSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.text_fields_rounded, color: Colors.white70),
            title: const Text('Metin durumu', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(sheetContext, 'text'),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: Colors.white70),
            title: const Text('Fotoğraf durumu', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(sheetContext, 'photo'),
          ),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return;
  if (choice == 'text') {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const _TextStoryComposerScreen()),
    );
  } else {
    await _createPhotoStory(context);
  }
}

Future<void> _createPhotoStory(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: Colors.white70),
            title: const Text('Kameradan çek', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined, color: Colors.white70),
            title: const Text('Galeriden seç', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  final picker = ImagePicker();
  XFile? picked;
  try {
    picked = await picker.pickImage(source: source, maxWidth: 1280, imageQuality: 80);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf alınamadı, tekrar dene.')),
      );
    }
    return;
  }
  if (picked == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Hikaye yükleniyor...')));
  try {
    final result =
        await MessagingService().uploadChatMedia(File(picked.path), mimeType: 'image/jpeg');
    final clientId = 'story${DateTime.now().microsecondsSinceEpoch}';
    MessagingService().createStory(
      kind: 'photo',
      clientId: clientId,
      mediaUrl: result['url'] as String,
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}

const List<String> _kStoryColors = [
  '#7C4DFF', // primary
  '#00BFA5', // secondary
  '#FF5470', // danger
  '#FFB74D', // warning
  '#1B1830', // koyu nötr
  '#2E7D32', // yeşil
];

class _TextStoryComposerScreen extends StatefulWidget {
  const _TextStoryComposerScreen();

  @override
  State<_TextStoryComposerScreen> createState() => _TextStoryComposerScreenState();
}

class _TextStoryComposerScreenState extends State<_TextStoryComposerScreen> {
  final _controller = TextEditingController();
  String _selectedColor = _kStoryColors.first;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    final value = int.parse(hex.replaceAll('#', ''), radix: 16);
    return Color(0xFF000000 | value);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final clientId = 'story${DateTime.now().microsecondsSinceEpoch}';
    MessagingService().createStory(
      kind: 'text',
      clientId: clientId,
      text: text,
      backgroundColor: _selectedColor,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _parseColor(_selectedColor),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('Paylaş', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: 6,
                    maxLength: 300,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: 'Ne düşünüyorsun?',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                      counterStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _kStoryColors.map((hex) {
                  final selected = hex == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = hex),
                    child: Container(
                      width: selected ? 34 : 28,
                      height: selected ? 34 : 28,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: _parseColor(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white, width: selected ? 3 : 1.5),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
