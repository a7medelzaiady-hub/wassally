import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

import 'cart_model.dart';
import 'navigation.dart';
import 'notification_service.dart';

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

  static const _activeOrderStatuses = ['new', 'preparing', 'on_the_way'];
  static const _finishedOrderStatuses = ['delivered', 'cancelled'];

  /// هل عند العميل طلب لسه شغال؟ لو آه مينفعش يحذف حسابه قبل ما الطلب يخلص.
  static Future<bool> hasActiveOrders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final snap = await FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: user.uid)
        .where('status', whereIn: _activeOrderStatuses)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  static const _roleDocs = {
    'admins': 'مدير',
    'couriers': 'مندوب توصيل',
    'storeOwners': 'صاحب محل',
    'supervisors': 'مشرف',
  };

  /// الأدوار المربوطة بالحساب (مستندات admins/couriers/storeOwners/supervisors).
  /// الحساب اللي عليه دور مينفعش يتحذف قبل ما الإدارة تشيل الدور (تسويات وطلبات شغالة).
  /// لو القراءة فشلت بيرمي الاستثناء (الحذف ما يكملش على تخمين).
  static Future<List<String>> linkedRoles() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    final db = FirebaseFirestore.instance;
    final found = <String>[];
    for (final e in _roleDocs.entries) {
      final snap = await db.collection(e.key).doc(user.uid).get();
      if (snap.exists) found.add(e.value);
    }
    return found;
  }

  /// بيسجّل طلب إزالة الدور في account_deletions (الأدمن بيقراه). مرة واحدة لكل حساب.
  static Future<void> requestRoleRemoval(List<String> roles) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('account_deletions')
          .doc('role_${user.uid}')
          .set({
        'userId': user.uid,
        'reason': 'طلب حذف حساب مرتبط بدور: ${roles.join('، ')}',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // لو الطلب اتسجّل قبل كده، القاعدة بترفض التكرار وده مقبول.
    }
  }

  /// حذف الحساب نهائيًا. بيطلب تأكيد الهوية بجوجل الأول (شرط من Firebase).
  /// على خطة Spark مفيش Cloud Functions، فالتطبيق نفسه بينضّف بيانات المستخدم قبل ما
  /// يحذف الحساب (انظر [_eraseUserData]). لو الحساب ليه أدوار (مندوب/صاحب محل/مشرف/مدير)
  /// بيفضل مستند الدور لحد ما الإدارة تشيله.
  static Future<void> deleteAccount([BuildContext? context]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (await hasActiveOrders()) throw const ActiveOrdersException();
    final roles = await linkedRoles();
    if (roles.isNotEmpty) throw RoleLinkedException(roles);

    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await user.reauthenticateWithPopup(provider);
    } else {
      await user.reauthenticateWithProvider(provider);
    }

    if (context != null && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    cart.clear();
    shellTab.value = 0;
    await NotificationService.dispose();
    await _eraseUserData(user.uid);
    await user.delete();
  }

  /// بيمسح بيانات المستخدم من Firestore بأفضل مجهود (كل خطوة مستقلة، وفشل خطوة
  /// ما بيوقفش حذف الحساب). بيرجّع عدد الخطوات اللي فشلت.
  ///  • بيتمسح: الإشعارات، الشكاوى، طلبات الانضمام، محادثة الدعم ورسائلها، بيانات الاتصال
  ///    (الاسم والهاتف والعنوان) من الطلبات المنتهية، ومستند المستخدم.
  ///  • بيتخفى: اسم العميل وملاحظاته في الطلبات المنتهية (بتتحط "عميل محذوف").
  ///  • بيفضل (سجل محاسبي/تشغيلي): الطلبات المنتهية نفسها بالأصناف والإجمالي ومعرّف
  ///    الحساب المحذوف، والتقييمات، وسجل الحالات.
  static Future<int> _eraseUserData(String uid) async {
    final db = FirebaseFirestore.instance;
    var failures = 0;

    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
      } catch (e) {
        failures++;
        debugPrint('account erase step "$name" failed: $e');
      }
    }

    Future<void> deleteQuery(Query<Map<String, dynamic>> q) async {
      for (var i = 0; i < 50; i++) {
        final page = await q.limit(100).get();
        if (page.docs.isEmpty) return;
        final batch = db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (page.docs.length < 100) return;
      }
    }

    await step('notifications', () => deleteQuery(
        db.collection('notifications').where('userId', isEqualTo: uid)));
    await step('complaints', () => deleteQuery(
        db.collection('complaints').where('userId', isEqualTo: uid)));
    await step('role_requests', () => deleteQuery(
        db.collection('role_requests').where('userId', isEqualTo: uid)));

    await step('support_chat', () async {
      final chat = db.collection('support_chats').doc(uid);
      await deleteQuery(chat.collection('messages'));
      await chat.delete();
    });

    // الطلبات المنتهية: امسح بيانات الاتصال وأخفِ الاسم والملاحظات. 5 طلبات في الـ batch
    // (10 عمليات) عشان حد قراءات القواعد في الـ batch الواحد.
    await step('orders', () async {
      final q = db
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('status', whereIn: _finishedOrderStatuses);
      DocumentSnapshot<Map<String, dynamic>>? last;
      for (var i = 0; i < 80; i++) {
        var page = q.limit(5);
        if (last != null) page = page.startAfterDocument(last);
        final snap = await page.get();
        if (snap.docs.isEmpty) return;
        final batch = db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference.collection('private').doc('contact'));
          batch.update(d.reference, {'customerName': 'عميل محذوف', 'notes': ''});
        }
        await batch.commit();
        last = snap.docs.last;
        if (snap.docs.length < 5) return;
      }
    });

    await step('user_doc', () => db.collection('users').doc(uid).delete());
    return failures;
  }
}

/// بيترمي لما العميل يحاول يحذف حسابه وعنده طلب لسه شغال.
class ActiveOrdersException implements Exception {
  const ActiveOrdersException();
  @override
  String toString() => 'ActiveOrdersException';
}

/// بيترمي لما الحساب عليه دور (مندوب/صاحب محل/مشرف/مدير) والإدارة لسه ما شالتوش.
class RoleLinkedException implements Exception {
  const RoleLinkedException(this.roles);
  final List<String> roles;
  @override
  String toString() => 'RoleLinkedException($roles)';
}
