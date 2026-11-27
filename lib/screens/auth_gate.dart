import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'role_gate.dart';
import 'store_link_page.dart';
import '../services/navigation.dart' show rootNavigatorKey;

/// بوابة الدخول: لو المستخدم مسجّل يفتح التطبيق، وإلا شاشة تسجيل الدخول.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: kBg,
            body: Center(child: CircularProgressIndicator(color: kPrimary)),
          );
        }
        if (snapshot.hasData) {
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
