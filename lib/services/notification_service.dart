import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/order_details_page.dart';
import '../screens/quick_courier_order_page.dart';
import '../screens/quick_courier_orders_page.dart';
import '../screens/quick_order_customer_detail_page.dart';
import '../models/app_role.dart';
import 'navigation.dart' show activePanel, rootNavigatorKey;
import 'live_alerts_service.dart';
import '../screens/admin_inbox_page.dart';

/// إشعارات الأجهزة (FCM). شغّالة على أندرويد بس حاليًا.
///
/// - بتسجل FCM registration token الحقيقي في users/{uid}.fcmTokens بعد الموافقة.
/// - الإشعارات الموثوقة تُرسل من أحداث الخادم؛ إشعار الطلب الجديد يرسله Order Gateway.
/// - لما التطبيق يكون مفتوح بنعرض الإشعار كشريط في أسفل الشاشة.
class NotificationService {
  const NotificationService._();

  /// بنربطه بـ MaterialApp عشان نعرض الإشعار من أي شاشة.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static StreamSubscription<RemoteMessage>? _foreground;
  static StreamSubscription<RemoteMessage>? _opened;
  static StreamSubscription<String>? _tokenRefresh;
  static String? _fcmToken;
  static bool? _verifiedCourierRole;

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

  /// Synchronize the courier push topic using the already-loaded, verified role.
  /// No additional Firestore reads or listeners. Do not subscribe based on a
  /// cached role: RoleGate invokes this only after RoleService.load() completes.
  static bool _verifiedQuickCourier = false;

  static Future<void> syncCourierTopic({
    required bool isCourier,
    required bool isQuickCourier,
  }) async {
    _verifiedQuickCourier = isCourier && isQuickCourier;
    _verifiedCourierRole = isCourier;
    if (!_supported || FirebaseAuth.instance.currentUser == null) return;
    if (!await hasPermission()) return;
    try {
      final messaging = FirebaseMessaging.instance;
      if (isCourier) {
        await messaging.subscribeToTopic('couriers');
      } else {
        await messaging.unsubscribeFromTopic('couriers');
      }
      if (_verifiedQuickCourier) {
        await messaging.subscribeToTopic('quick_couriers');
      } else {
        await messaging.unsubscribeFromTopic('quick_couriers');
      }
    } catch (e) {
      debugPrint('تعذر تحديث اشتراك إشعارات المندوب: $e');
    }
  }

  /// توبيك admins: إشعارات طلبات الانضمام وبلاغات التسليم للإدارة بس.
  /// زي المندوب: بيتحدد من الدور اللي اتأكد من السيرفر، من غير قراءات زيادة.
  static bool? _verifiedAdminRole;

  static Future<void> syncAdminTopic({required bool isAdmin}) async {
    _verifiedAdminRole = isAdmin;
    if (!_supported || FirebaseAuth.instance.currentUser == null) return;
    if (!await hasPermission()) return;
    try {
      final messaging = FirebaseMessaging.instance;
      if (isAdmin) {
        await messaging.subscribeToTopic('admins');
      } else {
        await messaging.unsubscribeFromTopic('admins');
      }
    } catch (e) {
      debugPrint('تعذر تحديث اشتراك إشعارات الإدارة: $e');
    }
  }

  static Future<void> _registerGrantedDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!_supported || user == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await _tokenRefresh?.cancel();
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        final previousToken = _fcmToken;
        _fcmToken = token;
        if (previousToken != null && previousToken != token) {
          await _removeToken(user.uid, previousToken);
        }
        await _saveToken(user.uid, token);
      }
      // الاشتراك في تنبيهات تحديث التطبيق القادمة من Cloudflare Worker
      await messaging.subscribeToTopic('app_updates');
      final verifiedRole = _verifiedCourierRole;
      if (verifiedRole != null) {
        await syncCourierTopic(
          isCourier: verifiedRole,
          isQuickCourier: _verifiedQuickCourier,
        );
      }
      final verifiedAdmin = _verifiedAdminRole;
      if (verifiedAdmin != null) {
        await syncAdminTopic(isAdmin: verifiedAdmin);
      }

      _tokenRefresh = messaging.onTokenRefresh.listen((nextToken) async {
        final previousToken = _fcmToken;
        _fcmToken = nextToken;
        final current = FirebaseAuth.instance.currentUser;
        if (current == null) return;
        try {
          if (previousToken != null && previousToken != nextToken) {
            await _removeToken(current.uid, previousToken);
          }
          await _saveToken(current.uid, nextToken);
        } catch (e) {
          debugPrint('تعذر تحديث رمز الإشعارات: $e');
        }
      });

      await _foreground?.cancel();
      await _opened?.cancel();
      _foreground = FirebaseMessaging.onMessage.listen(_showInApp);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _openMessage(initialMessage));
      }
    } catch (e) {
      debugPrint('تعذر تسجيل جهاز الإشعارات: $e');
    }
  }

  /// بتتنادي قبل تسجيل الخروج عشان الرمز ما يفضلش مربوط بالحساب السابق.
  static Future<void> dispose() async {
    await LiveAlerts.stop();
    await _foreground?.cancel();
    await _opened?.cancel();
    await _tokenRefresh?.cancel();
    _foreground = null;
    _opened = null;
    _tokenRefresh = null;
    _verifiedCourierRole = null;
    _verifiedQuickCourier = false;
    _verifiedAdminRole = null;
    if (!_supported) return;

    // منع بقاء الجهاز مشتركًا في إشعارات الحساب السابق بعد تسجيل الخروج.
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.unsubscribeFromTopic('couriers');
      await messaging.unsubscribeFromTopic('admins');
      await messaging.unsubscribeFromTopic('quick_couriers');
      await messaging.unsubscribeFromTopic('all');
    } catch (e) {
      debugPrint('تعذر إلغاء اشتراكات الإشعارات: $e');
    }

    final user = FirebaseAuth.instance.currentUser;
    final token = _fcmToken;
    _fcmToken = null;
    if (user != null && token != null) {
      try {
        await _removeToken(user.uid, token);
      } catch (e) {
        debugPrint('تعذر إلغاء ربط رمز الإشعارات: $e');
      }
    }
  }

  static Future<void> _saveToken(String uid, String token) {
    return _userDoc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  static Future<void> _removeToken(String uid, String token) {
    return _userDoc(uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
    }, SetOptions(merge: true));
  }

  static Future<void> _openAppStore() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final uri = Uri.https(
        'play.google.com',
        '/store/apps/details',
        {'id': info.packageName},
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Google Play could not be opened');
    } catch (e) {
      debugPrint('تعذر فتح Google Play: $e');
      messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('تعذر فتح Google Play')),
      );
    }
  }

  static void _openMessage(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString();
    if (type == 'app_update') {
      unawaited(_openAppStore());
      return;
    }
    // إشعارات الشات القديمة (support_chat) اتشالت: الدعم بقى على واتساب.
    if (type == 'support_chat') return;
    if (type == 'admin_inbox') {
      rootNavigatorKey.currentState?.push(MaterialPageRoute<void>(
        builder: (_) => const AdminInboxPage(),
      ));
      return;
    }
    if (type == 'store_order_update') {
      activePanel.value = AppRole.storeOwner;
      return;
    }
    if (type == 'available_order' || type == 'courier_order_update') {
      // This is an unassigned order. Couriers may view the available-order
      // queue, but not the private order details until assigned.
      // RoleGate only activates panels held by the signed-in user.
      activePanel.value = AppRole.courier;
      return;
    }
    if (type == 'quick_order') {
      rootNavigatorKey.currentState?.push(MaterialPageRoute<void>(
        builder: (_) => const QuickCourierOrdersPage(),
      ));
      return;
    }
    _openOrder(message);
  }

  static void _openOrder(RemoteMessage message) {
    final orderId = (message.data['orderId'] ?? '').toString().trim();
    if (orderId.isEmpty) return;
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => switch (message.data['type']) {
        'quick_customer_update' => QuickOrderCustomerDetailPage(orderId: orderId),
        'quick_courier_update' => QuickCourierOrderPage(orderId: orderId),
        _ => OrderDetailsPage(orderId: orderId),
      },
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

    final type = (message.data['type'] ?? '').toString();
    final orderId = (message.data['orderId'] ?? '').toString().trim();
    final actionLabel = switch (type) {
      'available_order' || 'quick_order' => 'عرض الطلبات المتاحة',
      'store_order_update' || 'courier_order_update' => 'عرض الطلبات',
      'app_update' => 'تحديث الآن',
      'admin_inbox' => 'فتح صندوق الإدارة',
      'support_chat' => null,
      _ => orderId.isEmpty ? null : 'عرض الطلب',
    };

    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(parts.join(' — ')),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  onPressed: () => _openMessage(message),
                ),
        ),
      );
  }
}
