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
/// - بتطلب إذن الإشعارات وتسجّل توكن الجهاز في users/{uid}.fcmTokens.
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

  /// بتتنادي بعد تسجيل الدخول. أي فشل هنا ما يوقفش التطبيق.
  static Future<void> init() async {
    if (!_supported) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token == null) return;
      _token = token;
      await _saveToken(user.uid, token);

      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh.listen((newToken) {
        _token = newToken;
        final current = FirebaseAuth.instance.currentUser;
        if (current != null) _saveToken(current.uid, newToken);
      });

      await _foreground?.cancel();
      await _opened?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen(_showInApp);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_openOrder);

      // لو التطبيق اتفتح من إشعار والتطبيق كان مقفول، افتح نفس الطلب بعد تجهيز الواجهة.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openOrder(initialMessage));
      }
    } catch (e) {
      debugPrint('تعذر تفعيل الإشعارات: $e');
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
