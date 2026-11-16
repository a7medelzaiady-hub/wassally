import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/order_details_page.dart';
import 'navigation.dart' show rootNavigatorKey;
import 'live_alerts_service.dart';

/// إشعارات الأجهزة (FCM). شغّالة على أندرويد بس حاليًا.
///
/// - بتقرأ حالة الإذن، وتُسجّل معرّف تثبيت الجهاز في users/{uid}.fcmInstallationIds بعد الموافقة.
/// - الإشعارات نفسها بتتبعت من Cloud Functions (فولدر functions).
/// - لما التطبيق يكون مفتوح بنعرض الإشعار كشريط في أسفل الشاشة.
class NotificationService {
  const NotificationService._();

  /// بنربطه بـ MaterialApp عشان نعرض الإشعار من أي شاشة.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static StreamSubscription<RemoteMessage>? _foreground;
  static StreamSubscription<RemoteMessage>? _opened;
  static StreamSubscription<String>? _registered;
  static StreamSubscription<String>? _unregistered;
  static String? _installationId;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  static bool _isGranted(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  /// قراءة حالة الإذن فقط؛ لا تفتح نافذة النظام تلقائيًا عند تسجيل الدخول.
  static Future<bool> hasPermission() async {
    if (!_supported) return false;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return _isGranted(settings.authorizationStatus);
    } catch (e) {
      debugPrint('تعذر قراءة إذن الإشعارات: $e');
      return false;
    }
  }

  /// يطلب الإذن بعد عرض شرح داخل التطبيق، ثم يسجل معرّف التثبيت عند الموافقة.
  static Future<bool> requestPermissionAndRegister() async {
    if (!_supported) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (!_isGranted(settings.authorizationStatus)) return false;
      await _registerGrantedDevice();
      return true;
    } catch (e) {
      debugPrint('تعذر طلب إذن الإشعارات: $e');
      return false;
    }
  }

  /// بتتنادي بعد تسجيل الدخول. لا تطلب الإذن؛ تسجل الجهاز فقط لو الإذن ممنوح.
  static Future<void> init() async {
    if (!await hasPermission()) return;
    await _registerGrantedDevice();
  }

  static Future<void> _registerGrantedDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!_supported || user == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await _registered?.cancel();
      await _unregistered?.cancel();
      _registered = messaging.onRegistered.listen((fid) {
        _installationId = fid;
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) {
          _saveInstallationId(current.uid, fid).catchError((e) {
            debugPrint('تعذر حفظ معرّف تثبيت الإشعارات: $e');
          });
        }
      });
      _unregistered = messaging.onUnregistered.listen((fid) {
        if (_installationId == fid) _installationId = null;
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) {
          _removeInstallationId(current.uid, fid).catchError((e) {
            debugPrint('تعذر حذف معرّف تثبيت الإشعارات: $e');
          });
        }
      });
      await messaging.register();

      await _foreground?.cancel();
      await _opened?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen(_showInApp);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_openOrder);

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openOrder(initialMessage),
        );
      }
    } catch (e) {
      debugPrint('تعذر تسجيل جهاز الإشعارات: $e');
    }
  }

  /// بتتنادي قبل تسجيل الخروج، عشان الجهاز ميستلمش إشعارات الحساب ده.
  static Future<void> dispose() async {
    await LiveAlerts.stop();
    await _foreground?.cancel();
    await _opened?.cancel();
    await _registered?.cancel();
    await _unregistered?.cancel();
    _foreground = null;
    _opened = null;
    _registered = null;
    _unregistered = null;
    if (!_supported) return;

    final user = FirebaseAuth.instance.currentUser;
    final fid = _installationId;
    _installationId = null;
    try {
      if (user != null && fid != null) {
        await _removeInstallationId(user.uid, fid);
      }
      await FirebaseMessaging.instance.unregister();
    } catch (e) {
      debugPrint('تعذر إلغاء تسجيل الإشعارات: $e');
    }
  }

  static Future<void> _saveInstallationId(String uid, String fid) {
    return _userDoc(uid).set({
      'fcmInstallationIds': FieldValue.arrayUnion([fid]),
    }, SetOptions(merge: true));
  }

  static Future<void> _removeInstallationId(String uid, String fid) {
    return _userDoc(uid).set({
      'fcmInstallationIds': FieldValue.arrayRemove([fid]),
    }, SetOptions(merge: true));
  }

  static void _openOrder(RemoteMessage message) {
    final orderId = (message.data['orderId'] ?? '').toString().trim();
    if (orderId.isEmpty) return;
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => OrderDetailsPage(orderId: orderId),
    ));
  }

  static void _showInApp(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    final parts = [
      n.title,
      n.body,
    ].whereType<String>().where((s) => s.isNotEmpty);
    if (parts.isEmpty) return;

    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(parts.join(' — ')),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          action: (message.data['orderId'] ?? '').toString().isNotEmpty
              ? SnackBarAction(label: 'عرض الطلب', onPressed: () => _openOrder(message))
              : null,
        ),
      );
  }
}
