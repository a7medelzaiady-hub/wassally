import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'notification_service.dart';
import 'play_update.dart';

/// فحص وجود إصدار أحدث من التطبيق.
///
/// بيقرا المستند `app_info/version` من Firestore، وحقوله:
///   latest_version : نص، مثال "1.0.2"
///   force_update   : true/false (true = مينفعش المستخدم يتخطى التحديث)
///   apk_url        : (اختياري) رابط صفحة التطبيق على Google Play.
class UpdateService {
  const UpdateService._();

  static bool _checked = false;
  static bool _available = false;
  static bool _force = false;
  static String _url = '';
  static DateTime? _lastCheck;
  static bool _lifecycleAttached = false;

  static const _snoozeKey = 'update_dialog_snooze_until';

  /// بنفكّر المستخدم بالتحديث: نافذة عند فتح التطبيق (لو مش مؤجّلة 24 ساعة)،
  /// وشريط تذكير ثابت أعلى الشاشة طول ما فيه تحديث، وبيتجدد كل ما التطبيق يرجع للواجهة.
  static Future<void> checkForUpdates(BuildContext context) async {
    attachLifecycle();
    if (_checked) return;
    final result = await _fetch();
    if (result == null) return; // فشل الاتصال: اسمح بإعادة المحاولة لاحقًا.
    _checked = true;
    final hasUpdate = result;
    if (hasUpdate && await PlayUpdate.tryUpdate(force: _force)) return;
    if (!hasUpdate) return;
    if (!context.mounted) return;
    final showDialogNow = _force || !await _isSnoozed();
    if (!context.mounted) return;
    if (showDialogNow) {
      _showUpdateDialog(context, _url, _force);
    } else {
      _showBanner();
    }
  }

  /// بتتنادي مرة من main(): بتراقب رجوع التطبيق من الخلفية.
  static void attachLifecycle() {
    if (_lifecycleAttached) return;
    _lifecycleAttached = true;
    WidgetsBinding.instance.addObserver(_ResumeObserver());
  }

  static Future<void> _onResume() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last).inHours < 6) {
      if (_available) _showBanner();
      return;
    }
    final result = await _fetch();
    if (result == true) _showBanner();
  }

  /// بتقرا app_info/version وتحدّث الحالة. بترجّع true لو فيه إصدار أحدث.
  static Future<bool?> _fetch() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final doc = await FirebaseFirestore.instance
          .collection('app_info')
          .doc('version')
          .get();
      final data = doc.data();
      if (data == null) {
        _lastCheck = DateTime.now();
        _available = false;
        _force = false;
        _url = '';
        return false;
      }

      final latest = (data['latest_version'] ?? '').toString().trim();
      final url = _playUrl(
        info.packageName,
        (data['apk_url'] ?? '').toString(),
      );
      _force = data['force_update'] == true && _validUrl(url);
      _url = url;
      _available = latest.isNotEmpty && isNewer(info.version, latest);
      _lastCheck = DateTime.now();
      return _available;
    } catch (e) {
      debugPrint('تعذر فحص التحديثات: $e');
      return null;
    }
  }

  /// يفتح صفحة التطبيق الرسمية على Google Play عند الضغط على إشعار التحديث.
  static Future<void> openStoreFromNotification() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final url = _playUrl(info.packageName, '');
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('تعذر فتح Google Play: $e');
      NotificationService.messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح Google Play')),
      );
    }
  }

  static Future<bool> _isSnoozed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_snoozeKey) ?? 0;
      return DateTime.now().millisecondsSinceEpoch < until;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _snooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _snoozeKey,
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  static Future<void> _openStore() async {
    var opened = false;
    if (_validUrl(_url)) {
      try {
        opened = await launchUrl(
          Uri.parse(_url),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }
    if (!opened) {
      NotificationService.messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح رابط التحديث')),
      );
    }
  }

  /// شريط تذكير ثابت (بيفضل لحد ما المستخدم يقفله أو يحدّث).
  static void _showBanner() {
    final m = NotificationService.messengerKey.currentState;
    if (m == null) return;
    m
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: kPrimarySoft,
          leading: Icon(Icons.system_update, color: kPrimary),
          content: const Text(
            'فيه تحديث جديد لوصلي. افتح Google Play وحدّث التطبيق عشان تستفيد بكل المميزات.',
          ),
          actions: [
            TextButton(
              onPressed: () => m.hideCurrentMaterialBanner(),
              child: const Text('لاحقاً'),
            ),
            FilledButton(
              onPressed: _openStore,
              child: const Text('تحديث الآن'),
            ),
          ],
        ),
      );
  }

  /// رابط التحديث دايمًا صفحة التطبيق على Google Play.
  static String _playUrl(String packageName, String configured) {
    final uri = Uri.tryParse(configured.trim());
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'play.google.com' &&
        uri.queryParameters['id'] == packageName) {
      return uri.toString();
    }
    return 'https://play.google.com/store/apps/details?id=$packageName';
  }

  static bool _validUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// true لو [latest] أحدث من [current]. بتتجاهل رقم البناء بعد علامة +.
  @visibleForTesting
  static bool isNewer(String current, String latest) {
    final a = _parts(current);
    final b = _parts(latest);
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (y > x) return true;
      if (y < x) return false;
    }
    return false;
  }

  static List<int> _parts(String v) => v
      .split('+')
      .first
      .split('.')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();

  static void _showUpdateDialog(BuildContext context, String url, bool force) {
    showDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (dialogContext) {
        return PopScope(
          canPop: !force,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.system_update, color: kPrimary),
                SizedBox(width: 8),
                Expanded(child: Text('تحديث جديد متوفر')),
              ],
            ),
            content: Text(
              force
                  ? 'لازم تحدّث التطبيق عشان تكمّل استخدامه.'
                  : 'فيه إصدار جديد من وصلي فيه تحسينات ومميزات جديدة.',
            ),
            actions: [
              if (!force)
                TextButton(
                  onPressed: () {
                    _snooze();
                    Navigator.of(dialogContext).pop();
                    _showBanner();
                  },
                  child: const Text('لاحقاً'),
                ),
              FilledButton(
                onPressed: _openStore,
                child: const Text('تحديث الآن'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) UpdateService._onResume();
  }
}
