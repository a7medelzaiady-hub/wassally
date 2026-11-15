// ملف إعدادات Firebase لكل المنصات.
//
// القيم مأخوذة من مشروعك (wasally-12259). لو عملت تطبيقات iOS / macOS / Windows
// في Firebase Console، شغّل الأمر ده مرة واحدة عشان يحدّث القيم تلقائيًا:
//
//   flutterfire configure --project=wasally-12259
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'المنصة دي مش مدعومة. شغّل flutterfire configure عشان تضيفها.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBg3V46v7_GpOoP9IaJykHl_0A-AyiEaoo',
    appId: '1:244081237486:web:30db4ef35d9c1df8d4c2ff',
    messagingSenderId: '244081237486',
    projectId: 'wasally-12259',
    authDomain: 'wasally-12259.firebaseapp.com',
    storageBucket: 'wasally-12259.firebasestorage.app',
    measurementId: 'G-ZK2JVNYPTZ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAiXnivMROVANPuqCE6_bBOn2ZgycbDeQM',
    appId: '1:244081237486:android:82a134e150bb8f2ed4c2ff',
    messagingSenderId: '244081237486',
    projectId: 'wasally-12259',
    storageBucket: 'wasally-12259.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCMz4quJtVc4KL4f08t7H8lQhd05AlZfUQ',
    appId: '1:244081237486:ios:21cda55f28cf3041d4c2ff',
    messagingSenderId: '244081237486',
    projectId: 'wasally-12259',
    storageBucket: 'wasally-12259.firebasestorage.app',
    androidClientId: '244081237486-6anha45a5g1db5a7feeblgjccm2893cl.apps.googleusercontent.com',
    iosClientId: '244081237486-u51am08l9jqnne9ig2fn9v5fl7u004l4.apps.googleusercontent.com',
    iosBundleId: 'com.example.cityStore',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCMz4quJtVc4KL4f08t7H8lQhd05AlZfUQ',
    appId: '1:244081237486:ios:21cda55f28cf3041d4c2ff',
    messagingSenderId: '244081237486',
    projectId: 'wasally-12259',
    storageBucket: 'wasally-12259.firebasestorage.app',
    androidClientId: '244081237486-6anha45a5g1db5a7feeblgjccm2893cl.apps.googleusercontent.com',
    iosClientId: '244081237486-u51am08l9jqnne9ig2fn9v5fl7u004l4.apps.googleusercontent.com',
    iosBundleId: 'com.example.cityStore',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBg3V46v7_GpOoP9IaJykHl_0A-AyiEaoo',
    appId: '1:244081237486:web:4ecbd9ab723b40a1d4c2ff',
    messagingSenderId: '244081237486',
    projectId: 'wasally-12259',
    authDomain: 'wasally-12259.firebaseapp.com',
    storageBucket: 'wasally-12259.firebasestorage.app',
    measurementId: 'G-WQWWQ8WB0H',
  );
}
