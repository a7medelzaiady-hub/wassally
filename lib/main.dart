import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/error_guard.dart';
import 'services/navigation.dart' show rootNavigatorKey;
import 'services/notification_service.dart';
import 'services/performance_monitor.dart';
import 'theme/app_theme.dart';
import 'theme/brand.dart';
import 'theme/theme_controller.dart';

void main() => ErrorGuard.run(_bootstrap);

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // على أندرويد Firebase بيقرا الإعدادات من android/app/google-services.json،
  // فمش محتاجين نحدّث appId يدويًا لما نسجّل تطبيق جديد.
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  await Firebase.initializeApp(
    options: isAndroid ? null : DefaultFirebaseOptions.currentPlatform,
  );
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS)) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  }
  await PerformanceMonitor.configure();
  await _activateAppCheck();
  await ThemeController.instance.load();
  runApp(const WasallyApp());
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
    // لما المستخدم يغيّر السمة، التطبيق كله بيتبني من جديد بالألوان الجديدة.
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'وصلي',
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigatorKey,
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
          // نحترم إعدادات حجم الخط وإمكانية الوصول في الجهاز دون تصغير إجباري.
          // خطوط أصغر في التطبيق كله (بدل التكبير الافتراضي).
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 0.8,
                maxScaleFactor: 0.88,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(Brand.palette.id),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: const AuthGate(),
      ),
    );
  }
}
