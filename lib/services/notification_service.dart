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
/// - بتقرأ حالة الإذن، وتُسجّل توكن الجهاز في users/{uid}.fcmTokens بعد الموافقة.
/// - الإشعارات نفسها بتتبعت من Cloud Functions (فولدر functions).
/// - لما التطبيق يكون مفتوح بنعرض الإشعار كشريط في أسفل الشاشة.
class NotificationService {
  const NotificationService._();

  /// بنربطه بـ MaterialApp عشان نعرض الإشعار من أي شاشة.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static StreamSubscription<RemoteMessage>? _foreground;
  static StreamSubscription<RemoteMessage>? _opened;
  static StreamSubscription<String>? _refresh;
  static String? _token;

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

  /// يطلب الإذن بعد عرض شرح داخل التطبيق، ثم يسجل التوكن عند الموافقة.
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
      final token = await messaging.getToken();
      if (token != null) {
        _token = token;
        await _saveToken(user.uid, token);
      }

      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh.listen((newToken) {
        _token = newToken;
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) {
          _saveToken(current.uid, newToken).catchError((e) {
            debugPrint('تعذر تحديث توكن الإشعارات: $e');
          });
        }
      });

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
    await _refresh?.cancel();
    _foreground = null;
    _opened = null;
    _refresh = null;
    if (!_supported) return;

    final user = FirebaseAuth.instance.currentUser;
    final token = _token;
    _token = null;
    try {
      if (user != null && token != null) {
        await _userDoc(user.uid).set({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('تعذر إلغاء تسجيل الإشعارات: $e');
    }
  }

  static Future<void> _saveToken(String uid, String token) {
    return _userDoc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
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
