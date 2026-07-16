// Bu dosya normalde `flutterfire configure` komutuyla otomatik üretilir.
// Bu proje o CLI'ı interaktif olarak çalıştıramadığımız bir ortamda
// geliştirildiği için elle yazıldı - Sinan'ın Firebase konsolundan
// (console.firebase.google.com) gönderdiği google-services.json
// dosyasındaki değerler buraya işlendi (proje: merhaba-93ddb).
//
// Bu değerler ARTIK GERÇEK - push_notification_service.dart bunu fark edip
// Firebase'i başlatıyor (bkz. isFirebaseConfigured).
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const String _placeholderApiKey = 'REPLACE_WITH_REAL_API_KEY';

/// firebase_options.dart gerçek değerlerle doldurulana kadar true kalır -
/// push_notification_service.dart bunu kontrol edip Firebase'i hiç
/// başlatmadan atlıyor (STUN-only TURN fallback'iyle aynı "zarif geri
/// düşme" deseni, bkz. webrtc_service.dart).
bool get isFirebaseConfigured => DefaultFirebaseOptions.android.apiKey != _placeholderApiKey;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  // google-services.json (Sinan'ın gönderdiği, merhaba-93ddb projesi) içinden.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD9VxYaYccruRxjKANEdw8tWx2EKjchILw',
    appId: '1:237640279761:android:76c4385679a04a3edc07f0',
    messagingSenderId: '237640279761',
    projectId: 'merhaba-93ddb',
    storageBucket: 'merhaba-93ddb.firebasestorage.app',
  );
}
