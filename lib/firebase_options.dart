// Firebase configuration for the Merhaba app.
//
// Values are based on the Firebase files provided for project merhaba-93ddb:
// - Android package: com.merhaba.app
// - iOS bundle id: com.example.merhabaApp
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

const String _placeholderApiKey = 'REPLACE_WITH_REAL_API_KEY';

bool get isFirebaseConfigured {
  final options = DefaultFirebaseOptions.currentPlatform;
  return options.apiKey != _placeholderApiKey;
}

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return android;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return android;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD9VxYaYccruRxjKANEdw8tWx2EKjchILw',
    appId: '1:237640279761:android:647f720f9d92bb7ddc07f0',
    messagingSenderId: '237640279761',
    projectId: 'merhaba-93ddb',
    storageBucket: 'merhaba-93ddb.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD16OVTG3mmsa53dYg78fXYzogymGGu5Kw',
    appId: '1:237640279761:ios:d87bb4f75431ef56dc07f0',
    messagingSenderId: '237640279761',
    projectId: 'merhaba-93ddb',
    storageBucket: 'merhaba-93ddb.firebasestorage.app',
    iosBundleId: 'com.example.merhabaApp',
    iosClientId:
        '237640279761-9ni853ehfhkun2mvc4ln8da3g34ihndo.apps.googleusercontent.com',
  );
}
