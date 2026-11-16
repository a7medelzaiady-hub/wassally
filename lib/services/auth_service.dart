import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

import 'cart_model.dart';
import 'navigation.dart';
import 'notification_service.dart';
import 'order_gateway.dart';

class AuthService {
  const AuthService._();

  // معرّف OAuth من نوع Web (client_type 3 في google-services.json). معرّف عام وليس سرًّا.
  static const _serverClientId =
      '244081237486-ohkfj9eil50s4m6d7qsem82tvb4fhrol.apps.googleusercontent.com';

  static bool _googleInitialized = false;

  /// تسجيل الدخول بجوجل.
  /// - ويب: نافذة منبثقة.
  /// - أندرويد: تسجيل دخول جوجل الأصلي (بدون متصفح خارجي)، وده بيحل خطأ
  ///   "unknown" اللي كان بيحتاج مسح الكاش، لأنه ناتج عن حالة قديمة في
  ///   Custom Tab بتاع المتصفح. لو فشل لأي سبب غير إلغاء المستخدم، بنرجع للطريقة القديمة.
  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _nativeGoogleSignIn();
        return;
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted) {
          throw FirebaseAuthException(code: 'canceled');
        }
        debugPrint('Native Google sign-in failed: ${e.code}, fallback.');
      } on FirebaseAuthException {
        rethrow;
      } catch (e) {
        debugPrint('Native Google sign-in failed: $e, fallback.');
      }
    }
    await _providerSignInWithRetry();
  }

  static Future<void> _nativeGoogleSignIn() async {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(serverClientId: _serverClientId);
      _googleInitialized = true;
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token');
    }
    await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  /// الطريقة القديمة (متصفح) مع إعادة محاولة تلقائية لو رجع خطأ unknown.
  static Future<void> _providerSignInWithRetry() async {
    try {
      await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      const transient = {'unknown', 'web-internal-error', 'internal-error'};
      if (!transient.contains(e.code)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
    }
  }

  /// رسالة عربية مفهومة لأخطاء الدخول (من غير ما نعرض كود الخطأ للمستخدم).
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

  /// لو اتبعت context بنقفل أي شاشات مفتوحة فوق البوابة (زي "عرض كعميل")
  /// قبل الخروج، عشان متفضلش ظاهرة بعد تسجيل الخروج.
  static Future<void> signOut([BuildContext? context]) async {
    if (context != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    cart.clear();
    shellTab.value = 0;
    // لازم قبل الخروج، لأن مسح توكن الجهاز بيحتاج المستخدم لسه مسجّل.
    await NotificationService.dispose();
    await FirebaseAuth.instance.signOut();
    // نخرج من حساب جوجل على الجهاز كمان، عشان الدخول الجاي يسألك تختار الحساب.
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  /// حذف الحساب نهائيًا بعد إعادة تأكيد الهوية وتنظيف البيانات عبر Worker.
  static Future<void> deleteAccount([BuildContext? context]) async {
    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser == null) return;
    if (!OrderGateway.isConfigured) {
      throw StateError('حذف الحساب الآمن غير متاح في هذه النسخة. حدّث التطبيق أو تواصل مع الدعم.');
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

    // Worker removes Firestore records first and deletes Firebase Auth last.
    // On any failure the account remains available so the user can retry.
    await OrderGateway.deleteAccount(idToken: idToken);
    await NotificationService.dispose();
    cart.clear();
    shellTab.value = 0;
    await FirebaseAuth.instance.signOut();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    if (context != null && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
