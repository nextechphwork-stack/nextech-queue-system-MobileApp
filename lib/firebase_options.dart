// firebase_options.dart
// Auto-generated from firebase-config.js — QueuePlus project
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDzK9bpl2C_n0YN5WJyTXYXdGUGDWD1TGA',
    authDomain: 'queue-system-45b56.firebaseapp.com',
    databaseURL:
        'https://queue-system-45b56-default-rtdb.asia-southeast1.firebasedatabase.app',
    projectId: 'queue-system-45b56',
    storageBucket: 'queue-system-45b56.firebasestorage.app',
    messagingSenderId: '675517760534',
    appId: '1:675517760534:web:da32b63a86f7c67d9b2137',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDBoGcO2_AAbmIZylb9_mCYJYkQuNj2atE',
    appId: '1:675517760534:android:2c29e35538ba51069b2137',
    messagingSenderId: '675517760534',
    projectId: 'queue-system-45b56',
    storageBucket: 'queue-system-45b56.firebasestorage.app'
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDzK9bpl2C_n0YN5WJyTXYXdGUGDWD1TGA',
    authDomain: 'queue-system-45b56.firebaseapp.com',
    databaseURL:
        'https://queue-system-45b56-default-rtdb.asia-southeast1.firebasedatabase.app',
    projectId: 'queue-system-45b56',
    storageBucket: 'queue-system-45b56.firebasestorage.app',
    messagingSenderId: '675517760534',
    appId: '1:675517760534:web:da32b63a86f7c67d9b2137',
    iosBundleId: 'com.queueplus.mobile',
  );
}
