import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// وضع الاختبار الآلي (Maestro). بيشتغل فقط في نسخة debug ولما يتبني التطبيق بـ
/// --dart-define=WASALLY_E2E=true. في نسخة الإنتاج [enabled] ثابتة false فبيتشال الكود كله.
/// بيوصّل التطبيق بـ Firebase Emulators (Auth + Firestore) ولا يلمس بيانات حقيقية.
class E2eSupport {
  const E2eSupport._();

  static const bool _flag = bool.fromEnvironment('WASALLY_E2E');
  static const String host = String.fromEnvironment(
    'WASALLY_E2E_HOST',
    defaultValue: '10.0.2.2',
  );

  static bool get enabled => kDebugMode && _flag;

  static Future<void> connectEmulators() async {
    if (!enabled) return;
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  }

  /// دخول بحساب وهمي بمزوّد google.com (الـ Emulator بيقبل JSON فيه sub و email).
  static Future<void> signInAs(String sub, String email) async {
    if (!enabled) return;
    final token = jsonEncode({
      'sub': sub,
      'email': email,
      'email_verified': true,
    });
    await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: token),
    );
  }
}
