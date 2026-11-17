import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'cart_model.dart';
import 'navigation.dart';
import 'notification_service.dart';
import 'order_gateway.dart';

class AuthService {
  const AuthService._();

  /// تسجيل الدخول بجوجل عبر Firebase Auth كما كان قبل إضافة التدفق الأصلي
  /// المعتمد على بصمة شهادة Android.
  static Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(provider);
    } else {
      await _providerSignInWithRetry(provider);
    }
  }

  static Future<void> _providerSignInWithRetry(
    GoogleAuthProvider provider,
  ) async {
    try {
      await FirebaseAuth.instance.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      const transient = {'unknown', 'web-internal-error', 'internal-error'};
      if (!transient.contains(e.code)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await FirebaseAuth.instance.signInWithProvider(provider);
    }
  }

  static String errorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'البريد الإلكتروني غير صحيح.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'البريد أو كلمة المرور غير صحيحة.';
      case 'email-already-in-use':
        return 'البريد ده مسجّل قبل كده. جرّب تسجّل دخول.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة. استخدم 6 حروف على الأقل.';
      case 'too-many-requests':
        return 'محاولات كتير. استنى شوية وجرّب تاني.';
      case 'user-disabled':
        return 'الحساب ده موقوف.';
      case 'network-request-failed':
        return 'مفيش اتصال بالإنترنت. جرّب تاني.';
      default:
        return 'تعذر تسجيل الدخول. حاول تاني.';
    }
  }

  /// استعادة تسجيل الدخول بالبريد الإلكتروني وكلمة المرور.
  static Future<void> signInWithEmail(String email, String password) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> registerWithEmail(
    String email,
    String password,
    String name,
  ) async {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final n = name.trim();
    if (n.isNotEmpty) await cred.user?.updateDisplayName(n);
  }

  static Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());

  static Future<void> signOut([BuildContext? context]) async {
    if (context != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    cart.clear();
    shellTab.value = 0;
    await NotificationService.dispose();
    await FirebaseAuth.instance.signOut();
  }

  /// حذف الحساب عبر Worker مع إعادة تأكيد الهوية من خلال Firebase Provider.
  static Future<void> deleteAccount([BuildContext? context]) async {
    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser == null) return;
    if (!OrderGateway.isConfigured) {
      throw StateError(
        'حذف الحساب الآمن غير متاح في هذه النسخة. حدّث التطبيق أو تواصل مع الدعم.',
      );
    }

    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await initialUser.reauthenticateWithPopup(provider);
    } else {
      await initialUser.reauthenticateWithProvider(provider);
    }

    final user = FirebaseAuth.instance.currentUser ?? initialUser;
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('تعذر تأكيد هويتك. سجّل الدخول من جديد وحاول مرة أخرى.');
    }

    await OrderGateway.deleteAccount(idToken: idToken);
    await NotificationService.dispose();
    cart.clear();
    shellTab.value = 0;
    await FirebaseAuth.instance.signOut();
    if (context != null && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
