import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

import 'notification_service.dart';
import '../widgets/app_snack.dart';

/// تحديث داخل التطبيق عن طريق Google Play (In-App Updates). أندرويد فقط، ويشتغل بس لو
/// التطبيق متسطّب من Google Play (ومنها الاختبار المغلق). في أي حالة تانية (تشغيل من
/// الكمبيوتر، APK مباشر، iOS) بيرجّع false والتطبيق يكمّل بنافذة التحديث العادية.
class PlayUpdate {
  const PlayUpdate._();

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// true = Google Play تولّى التحديث (بدأ التنزيل أو التثبيت الفوري).
  /// [force] = تحديث إجباري: شاشة Google بملء الشاشة ومينفعش يتخطاها.
  static Future<bool> tryUpdate({required bool force}) async {
    if (!supported) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      if (force && info.immediateUpdateAllowed) {
        final r = await InAppUpdate.performImmediateUpdate();
        return r == AppUpdateResult.success;
      }
      if (info.flexibleUpdateAllowed) {
        final r = await InAppUpdate.startFlexibleUpdate();
        if (r == AppUpdateResult.success) _offerInstall();
        return r == AppUpdateResult.success;
      }
      return false;
    } catch (e) {
      debugPrint('Play in-app update unavailable: $e');
      return false;
    }
  }

  /// التحديث اتنزّل في الخلفية: نسيب المستخدم يثبّته وقت ما يحب (التثبيت بيعيد تشغيل التطبيق).
  static void _offerInstall() {
    NotificationService.messengerKey.currentState?.showSnackBar(
      appSnack(
        'تم تنزيل تحديث جديد للتطبيق.',
        duration: const Duration(seconds: 30),
        action: SnackBarAction(
          label: 'ثبّت الآن',
          onPressed: () {
            InAppUpdate.completeFlexibleUpdate().catchError((Object e) {
              debugPrint('Complete flexible update failed: $e');
            });
          },
        ),
      ),
    );
  }
}
