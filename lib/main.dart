import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/e2e_support.dart';
import 'services/error_guard.dart';
import 'screens/main_shell.dart';
import 'services/navigation.dart' show rootNavigatorKey, customerShellBuilder;
import 'screens/store_link_page.dart';
import 'services/notification_service.dart';
import 'services/order_gateway.dart';
import 'services/performance_monitor.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'services/cart_book.dart';
import 'services/cart_reminder.dart';
import 'services/data_saver.dart';
import 'services/photo_library.dart';
import 'services/resume_session.dart';

void main() => ErrorGuard.run(_bootstrap);

Future<void> _bootstrap() async {
  final startup = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // على أندرويد Firebase بيقرا الإعدادات من android/app/google-services.json،
  // فمش محتاجين نحدّث appId يدويًا لما نسجّل تطبيق جديد.
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  await Firebase.initializeApp(
    options: isAndroid ? null : DefaultFirebaseOptions.currentPlatform,
  );
  await E2eSupport.connectEmulators();
  // الخطوات دي مستقلة عن بعض، فبتشتغل مع بعض بدل ورا بعض (كلها لازم تخلص قبل runApp).
  await Future.wait([
    _configureCrashlytics(),
    PerformanceMonitor.configure(),
    if (!E2eSupport.enabled) _activateAppCheck(),
    ThemeController.instance.load(), // هوية وصّلي الموحدة حتى بعد تحديث النسخة
    carts.load(), // «سلّاتي» المحفوظة على الموبايل من آخر مرة
    DataSaver.load(), // «وضع توفير الباقة» (اختيار محلي)
    ResumeSession.load(), // رجوع بعد ما أندرويد قفل التطبيق في الخلفية؟ (#326)
  ]);
  final bootstrap = startup.elapsed;
  customerShellBuilder = (_) => const MainShell();
  runApp(const WasallyApp());
  ResumeSession.startObserving();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PerformanceMonitor.recordStartup(PerformanceMonitor.startupMetrics(
      bootstrap: bootstrap,
      firstFrame: startup.elapsed,
    ));
    // إنشاء قناة أندرويد قبل وصول FCM في الخلفية، حتى قبل إعطاء إذن الإشعارات.
    if (isAndroid) unawaited(NotificationService.initializeOrdersChannel());
    // تذكير السلة المنسية (إشعار محلي على أندرويد بس؛ أي فشل بيتجاهل).
    if (isAndroid && !E2eSupport.enabled) unawaited(CartReminder.instance.start());
    // استعادة إشعارات أحداث الطلبات المؤجلة من الموبايل فقط (بدون قراءات Firestore).
    unawaited(OrderGateway.startPendingPushRecovery());
    // مكتبة صور وصّلي: من الموبايل فورًا، ومن Firestore بعد تسجيل الدخول (مرة كل 6 ساعات).
    unawaited(PhotoLibrary.load());
    FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null).then(
          (_) {
            unawaited(PhotoLibrary.load());
            unawaited(OrderGateway.replayPendingPushes());
          },
          onError: (_) {},
        );
  });
}

Future<void> _configureCrashlytics() async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.macOS) {
    return;
  }
  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  } catch (e) {
    debugPrint('Crashlytics config failed: $e');
  }
}

/// App Check: بيثبت إن الطلبات جاية من تطبيق وصلي الأصلي (Play Integrity على أندرويد)،
/// فمفتاح Firebase ما يتستخدمش من تطبيقات أو سكريبتات تانية. فشله ما يوقفش التطبيق.
/// في وضع التطوير بنستخدم Debug provider (التوكن بيظهر في logcat وتسجّله في Firebase Console).
Future<void> _activateAppCheck() async {
  if (kIsWeb) return;
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  } catch (e) {
    debugPrint('App Check activation failed: $e');
  }
}

class WasallyApp extends StatelessWidget {
  const WasallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'وصلي',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      // Android can restore the Navigator's restorable state after process death.
      // Individual pushed routes must also opt into restorable navigation.
      restorationScopeId: 'wasally_app',
      scaffoldMessengerKey: NotificationService.messengerKey,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            // Respect the phone's font-size setting (no more forced
            // shrinking), capped so layouts stay intact.
            textScaler: mq.textScaler.clamp(
              minScaleFactor: AppTypography.minTextScale,
              maxScaleFactor: AppTypography.maxTextScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGate(),
      // روابط مشاركة المحلات (/s/<id>) بتفتح المحل على طول؛ أي مسار تاني بيتجاهل.
      onGenerateRoute: StoreLinkPage.routeFor,
      onUnknownRoute: StoreLinkPage.dismissRoute,
    );
  }
}
