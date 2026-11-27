import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/brand_splash.dart';
import 'login_screen.dart';
import 'role_gate.dart';
import 'store_link_page.dart';
import '../services/navigation.dart' show rootNavigatorKey;

enum AuthGateView { loading, signedIn, signedOut }

/// بوابة الدخول: لو المستخدم مسجّل يفتح التطبيق، وإلا شاشة تسجيل الدخول.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  /// الجلسة المحفوظة بتبقى معروفة فورًا بعد Firebase.initializeApp (currentUser)،
  /// فبنفتح التطبيق على طول بدل فريم تحميل لحد ما الـstream يرد (#326).
  /// من غير جلسة بنستنى أول رد قبل ما نعرض شاشة الدخول.
  static AuthGateView viewFor(ConnectionState state, {required bool hasUser}) {
    if (hasUser) return AuthGateView.signedIn;
    if (state == ConnectionState.waiting || state == ConnectionState.none) {
      return AuthGateView.loading;
    }
    return AuthGateView.signedOut;
  }

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      initialData: auth.currentUser,
      builder: (context, snapshot) {
        final view = viewFor(snapshot.connectionState, hasUser: snapshot.data != null);
        if (view == AuthGateView.loading) return const BrandSplash();
        if (view == AuthGateView.signedIn) {
          // رابط محل اتفتح قبل تسجيل الدخول: نفتحه بعد الدخول (مرة واحدة).
          if (StoreLinkPage.pendingStoreId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = rootNavigatorKey.currentContext;
              if (ctx != null) StoreLinkPage.openPending(ctx);
            });
          }
          return const RoleGate();
        }
        return const LoginScreen();
      },
    );
  }
}
