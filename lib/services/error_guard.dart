import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show FlutterError, kDebugMode, debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

/// حماية من الأعطال المفاجئة: أي خطأ غير متوقع (في Flutter أو في كود async خارج أي try/catch)
/// بيتسجّل ومش بيوقّع التطبيق. بدل الشاشة الحمراء المخيفة بنعرض كارت هادي في مكان الودجت المعطلة بس.
/// في وضع التطوير (debug) بنسيب السلوك الافتراضي عشان المطوّر يشوف الخطأ كامل.
class ErrorGuard {
  const ErrorGuard._();

  /// آخر أخطاء متسجّلة (للتشخيص فقط، محدودة العدد).
  static final List<String> recent = <String>[];

  static void _log(String where, Object error, StackTrace? stack, {bool fatal = false}) {
    final line = '[$where] $error';
    recent.add(line);
    if (recent.length > 20) recent.removeAt(0);
    debugPrint(line);
    if (stack != null && kDebugMode) debugPrint(stack.toString());
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
         defaultTargetPlatform == TargetPlatform.iOS ||
         defaultTargetPlatform == TargetPlatform.macOS);
    if (supported && Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal)
          .catchError((_) {});
    }
  }

  /// بيشغّل [body] جوه zone محمية، ويركّب معالجات الأعطال العامة.
  static void run(FutureOr<void> Function() body) {
    runZonedGuarded<Future<void>>(
      () async {
        _install();
        await body();
      },
      (error, stack) => _log('zone', error, stack, fatal: true),
    );
  }

  static void _install() {
    final defaultOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _log('flutter', details.exception, details.stack);
      // في التطوير نخلّي Flutter يعرض الخطأ زي العادة.
      defaultOnError?.call(details);
    };

    // أخطاء async/native اللي مفيش حد ماسكها: نعتبرها اتعالجت عشان التطبيق ما يقفلش.
    PlatformDispatcher.instance.onError = (error, stack) {
      _log('platform', error, stack, fatal: true);
      // لا نعلن أن العطل عولج؛ اترك Flutter/النظام يتعامل مع الخطأ غير المعالج.
      return false;
    };

    // في الإنتاج: كارت صغير هادي بدل الشاشة الحمراء لو ودجت معيّنة فشلت في الرسم.
    if (!kDebugMode) {
      ErrorWidget.builder = (details) => const Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'حصلت مشكلة في عرض الجزء ده. ارجع وافتحه تاني.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      );
    }
  }
}
