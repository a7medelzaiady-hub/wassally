import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'cart_book.dart';
import 'navigation.dart';
import 'notification_service.dart';
import 'order_gateway.dart';
import 'image_cache.dart';

class AuthService {
  const AuthService._();

  // معرّف OAuth من نوع Web (client_type 3 في google-services.json). معرّف عام وليس سرًّا.
  static const _serverClientId =
      '244081237486-ohkfj9eil50s4m6d7qsem82tvb4fhrol.apps.googleusercontent.com';

  static bool _googleInitialized = false;

  /// Ephemeral invite onboarding shown only for a brand-new Google account.
  /// No pending invitation is restored for users who registered previously.
  static final ValueNotifier<String?> newAccountInvitation = ValueNotifier(null);

  static Future<void> _onGoogleLogin(UserCredential credential) async {
    // Register every Google account on this device, not only customers who
    // choose to enter an invitation. A second account cannot claim a second
    // new-user reward simply because the first account skipped the code.
    // Failure never blocks normal Google login; the claim endpoint fails closed.
    bool deviceEligible = false;
    try {
      deviceEligible = await OrderGateway.registerReferralDevice();
    } catch (_) {
      debugPrint('Referral device verification unavailable (sign-in unaffected).');
    }
    // A second Google account on this phone, or a missing verification,
    // must not even see a "new customer" invitation form.
    newAccountInvitation.value =
        deviceEligible && credential.additionalUserInfo?.isNewUser == true
            ? credential.user?.uid
            : null;
  }

  static void dismissNewAccountInvitation(String uid) {
    if (newAccountInvitation.value == uid) {
      newAccountInvitation.value = null;
    }
  }


  /// تسجيل الدخول بجوجل.
  /// - ويب: نافذة منبثقة.
  /// - أندرويد: نافذة جوجل الأصلية المنبثقة لاختيار الحساب، بدون متصفح خارجي وبدون
  ///   رجوع تلقائي للمتصفح لو فشلت (بتظهر رسالة بسبب الفشل بدل كده).
  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _onGoogleLogin(await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider()));
      await carts.attachAfterSignIn();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // نافذة اختيار الحساب المنبثقة (الأصلية). مفيش رجوع للمتصفح: صفحة المتصفح كانت
      // بتطلب بصمة وبتعرض صفحة برابط بدل ما ترجع للتطبيق.
      try {
        await _onGoogleLogin(await _nativeGoogleSignIn());
        await carts.attachAfterSignIn();
        return;
      } on GoogleSignInException catch (e) {
        debugPrint('Native Google sign-in failed: ${e.code} | ${e.description}');
        if (e.code == GoogleSignInExceptionCode.canceled) {
          throw FirebaseAuthException(code: 'canceled', message: e.description);
        }
        if (e.code == GoogleSignInExceptionCode.interrupted) {
          throw FirebaseAuthException(
            code: 'google-sign-in-interrupted',
            message: e.description,
          );
        }
        throw FirebaseAuthException(
          code: 'google-sign-in-failed',
          message: '${e.code}: ${e.description}',
        );
      }
    }
    await _onGoogleLogin(await _providerSignInWithRetry());
    await carts.attachAfterSignIn();
  }

  static Future<UserCredential> _nativeGoogleSignIn() async {
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
    return FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  /// إعادة تأكيد جوجل على أندرويد بنفس المسار الأصلي المستخدم عند تسجيل الدخول.
  static Future<void> _nativeGoogleReauthenticate(User user) async {
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
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await user.reauthenticateWithCredential(credential);
  }

  /// الطريقة القديمة (متصفح) مع إعادة محاولة تلقائية لو رجع خطأ unknown.
  static Future<UserCredential> _providerSignInWithRetry() async {
    try {
      return await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      const transient = {'unknown', 'web-internal-error', 'internal-error'};
      if (!transient.contains(e.code)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
    }
  }

  /// لو اتبعت context بنقفل أي شاشات مفتوحة فوق البوابة (زي "عرض كعميل")
  /// قبل الخروج، عشان متفضلش ظاهرة بعد تسجيل الخروج.
  static Future<void> signOut([BuildContext? context]) async {
    newAccountInvitation.value = null;
    if (context != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    await carts.detachForSignOut(); // لا تمسح سلة الحساب، فقط افصلها من الذاكرة.
    shellTab.value = 0;
    await WasallyImageCache.clear();
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
    newAccountInvitation.value = null;
    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser == null) return;
    if (!OrderGateway.isConfigured) {
      throw StateError('حذف الحساب الآمن غير متاح في هذه النسخة. حدّث التطبيق أو تواصل مع الدعم.');
    }

    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await initialUser.reauthenticateWithPopup(provider);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      await _nativeGoogleReauthenticate(initialUser);
    } else {
      await initialUser.reauthenticateWithProvider(provider);
    }

    final user = FirebaseAuth.instance.currentUser ?? initialUser;
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('تعذر تأكيد هويتك. سجّل الدخول من جديد وحاول مرة أخرى.');
    }

    // Worker removes Firestore records first and deletes Firebase Auth last.
    // On any failure the account remains available and app listeners stay active.
    await OrderGateway.deleteAccount(idToken: idToken);
    await NotificationService.dispose();
    carts.clearAll(); // حذف الحساب: امسح سلال الحساب المحفوظة.
    await carts.flush();
    shellTab.value = 0;
    await WasallyImageCache.clear();
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
