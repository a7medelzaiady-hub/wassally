import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'order_event_outbox.dart';
import 'performance_monitor.dart';
import 'referral_device.dart';

/// عنوان بوابة الطلبات الموثوقة يمرر وقت البناء، ولا يحتوي أي أسرار.
class OrderGateway {
  const OrderGateway._();

  static const String baseUrl = String.fromEnvironment(
    'WASALLY_ORDER_GATEWAY_URL',
    // الرابط عام (مش سر) وهو نفسه المستخدم في CI؛ وجوده كقيمة افتراضية يمنع أي بناء
    // (محلي أو Release) من الخروج من غير رفع الصور وحذف الحساب وتنظيف المرفقات.
    defaultValue: 'https://throbbing-water-4ef7.a7medelzaiady.workers.dev',
  );

  static const referralCampaignEnabled = bool.fromEnvironment(
    'WASALLY_REFERRAL_REGISTRATION',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// هيدر App Check (لو متاح) لكل طلبات الـ Worker.
  /// الفشل هنا لا يوقف الطلب أبدًا: الـ Worker هو اللي يقرر (off / monitor / enforce).
  static Future<Map<String, String>> appCheckHeaders() async {
    if (kIsWeb) return const {};
    try {
      final token = await FirebaseAppCheck.instance
          .getToken()
          .timeout(const Duration(seconds: 3));
      if (token == null || token.isEmpty) return const {};
      return {'X-Firebase-AppCheck': token};
    } catch (_) {
      return const {};
    }
  }

  /// Order writes stay on Firestore's Spark-compatible path until the Worker
  /// has been deployed, verified, and Firestore serverOrders is enabled.
  /// The same Worker URL can still be used for signed image uploads.
  static const bool serverOrdersEnabled = bool.fromEnvironment(
    'WASALLY_SERVER_ORDERS',
    defaultValue: false,
  );

  static final OrderEventOutbox _notificationOutbox = OrderEventOutbox(
    send: _sendOrderPushOnce,
  );
  static Timer? _outboxTimer;
  static bool _outboxRecoveryInitialized = false;
  static bool _flushingOutbox = false;

  /// An already committed order change is queued locally before the first request.
  /// Network errors and Worker 5xx get 3 additional attempts (2, 5, 15 seconds).
  static Future<void> notifyEvent(String orderId, String event, {String? status}) async {
    if (!isConfigured) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _notificationOutbox.recordAndSend(PendingOrderPush(
        uid: uid,
        orderId: orderId,
        event: event,
        status: status,
        occurredAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {
      debugPrint('تعذر إرسال إشعار حالة الطلب. سيتم الاحتفاظ به مؤقتًا.');
    } finally {
      unawaited(_ensureOutboxTimer());
    }
  }

  /// Only used for order-event pushes; unrelated order and payment APIs are unchanged.
  static Future<void> _sendOrderPushOnce(PendingOrderPush item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != item.uid) {
      throw const RetryableOrderPushException();
    }
    final uri = Uri.tryParse('${baseUrl.trim().replaceFirst(RegExp(r'/+, '')}/v1/order-events');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw const PermanentOrderPushException();
    }
    final token = await user.getIdToken().catchError((Object _) => null);
    if (token == null || token.isEmpty) throw const RetryableOrderPushException();
    final client = http.Client();
    late final http.Response response;
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          ...await appCheckHeaders(),
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode({
          'orderId': item.orderId,
          'event': item.event,
          if (item.status != null) 'status': item.status,
        });
      final stream = await client.send(request).timeout(const Duration(seconds: 12));
      response = await http.Response.fromStream(stream).timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const RetryableOrderPushException();
    } finally {
      client.close();
    }
    if (response.statusCode >= 500) throw const RetryableOrderPushException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const PermanentOrderPushException();
    }
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map && parsed['orderId'] == item.orderId) return;
    } catch (_) {
      // Malformed success from the gateway: keep a bounded retry.
    }
    throw const RetryableOrderPushException();
  }

  /// Called at app start and again on resume; pending entries retry every 25s
  /// only while they exist. No network listener, Firestore listener or read.
  static Future<void> startPendingPushRecovery() async {
    if (!_outboxRecoveryInitialized) {
      _outboxRecoveryInitialized = true;
      WidgetsBinding.instance.addObserver(_OrderPushAppObserver());
    }
    await replayPendingPushes();
  }

  static Future<void> replayPendingPushes() async {
    if (_flushingOutbox) return;
    _flushingOutbox = true;
    try {
      await _notificationOutbox.replay(FirebaseAuth.instance.currentUser?.uid);
    } catch (_) {
      debugPrint('تعذر إعادة إرسال الإشعارات المؤجلة.');
    } finally {
      _flushingOutbox = false;
      await _ensureOutboxTimer();
    }
  }

  static Future<void> _ensureOutboxTimer() async {
    final pending = await _notificationOutbox.hasPending;
    if (!pending) {
      _outboxTimer?.cancel();
      _outboxTimer = null;
      return;
    }
    _outboxTimer ??= Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(replayPendingPushes());
    });
  }

  static Future<Map<String, dynamic>> referralCampaign({
    required String channel,
    String? marketerUid,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/campaign',
      payload: {
        'channel': channel,
        if (marketerUid != null) 'marketerUid': marketerUid,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة الدعوات.',
    );
  }

  static Future<Map<String, dynamic>?> referralSettings({
    Map<String, dynamic>? settings,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    final response = await _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/settings',
      payload: {if (settings != null) 'settings': settings},
      connectivityMessage: 'تعذر الاتصال بخدمة الدعوات.',
    );
    return response['settings'] as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>> quoteReferralPoints(int itemsSubtotalMinor) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/points/quote',
      payload: {'itemsSubtotalMinor': itemsSubtotalMinor},
      connectivityMessage: 'تعذر حساب خصم النقاط.',
    );
  }

  static Future<Map<String, dynamic>> referralRedemption(
    String orderId,
    String action, {
    String? reference,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/redemption',
      payload: {
        'orderId': orderId,
        'action': action,
        if (reference != null) 'reference': reference,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة تسوية خصم النقاط.',
    );
  }

  static Future<Map<String, dynamic>> settleReferralCommission({
    required String ownerUid,
    required String storeId,
    required String reference,
    required int dueMinor,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/commissions',
      payload: {
        'ownerUid': ownerUid,
        'storeId': storeId,
        'reference': reference,
        'dueMinor': dueMinor,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة تسوية عمولة الدعوات.',
    );
  }

  static Future<Map<String, dynamic>> referralPayout({
    required String action,
    String? requestId,
    String? payoutId,
    String? reference,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/payouts',
      payload: {
        'action': action,
        if (requestId != null) 'requestId': requestId,
        if (payoutId != null) 'payoutId': payoutId,
        if (reference != null) 'reference': reference,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة صرف مكافآت الدعوات.',
    );
  }

  /// Associates a verified Google account with one Android device for
  /// first-time invitation eligibility. Safe for repeat login. No Firestore
  /// listener or paid service; other Google accounts can still sign in.
  static String? _referralDeviceBoundUid;
  static Future<bool>? _referralDeviceBinding;

  static Future<bool> registerReferralDevice() async {
    if (!referralCampaignEnabled) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    if (_referralDeviceBoundUid == uid && _referralDeviceBinding == null) {
      return true;
    }
    if (_referralDeviceBoundUid == uid && _referralDeviceBinding != null) {
      return _referralDeviceBinding!;
    }
    _referralDeviceBoundUid = uid;
    final pending = _performReferralDeviceBinding();
    _referralDeviceBinding = pending;
    try {
      final allowed = await pending;
      if (!allowed) _referralDeviceBoundUid = null;
      return allowed;
    } catch (_) {
      _referralDeviceBoundUid = null;
      rethrow;
    } finally {
      _referralDeviceBinding = null;
    }
  }

  static Future<bool> _performReferralDeviceBinding() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول من جديد.');
    final deviceId = await ReferralDevice.androidScopedId();
    final result = await _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/device-binding',
      payload: {'deviceId': deviceId},
      connectivityMessage: 'تعذر الاتصال بخدمة حماية الدعوات.',
    );
    return result['eligible'] == true;
  }

  static Future<void> claimRegistrationReferral({
    required String idToken,
    required String code,
  }) async {
    final deviceId = await ReferralDevice.androidScopedId();
    final body = await _request(
      idToken: idToken,
      method: 'POST',
      path: '/v1/referrals/registration',
      payload: {'code': code, 'deviceId': deviceId},
      connectivityMessage: 'تعذر الاتصال بخدمة الدعوات.',
    );
    if (body['accepted'] != true) {
      throw StateError('لم يصل تأكيد حفظ كود الدعوة.');
    }
  }

  static Future<void> submit({
    required String idToken,
    required Map<String, dynamic> payload,
  }) => _send(
        idToken: idToken,
        method: 'POST',
        path: '/v1/orders',
        payload: payload,
      );

  static Future<void> update({
    required String idToken,
    required String orderId,
    required Map<String, dynamic> payload,
  }) => _send(
        idToken: idToken,
        method: 'PATCH',
        path: '/v1/orders/${Uri.encodeComponent(orderId)}',
        payload: payload,
      );

  /// Removes this order's uploaded attachments only after customer receipt confirmation.
  static Future<void> cleanupAttachments({
    required String idToken,
    required String orderId,
  }) async {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    final uri = Uri.tryParse(root + '/v1/orders/' + Uri.encodeComponent(orderId) + '/cleanup-attachments');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('خدمة تنظيف مرفقات الطلب غير مهيأة.');
    }
    final appCheck = await appCheckHeaders();
    final client = http.Client();
    late final http.Response result;
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          ...appCheck,
          'Authorization': 'Bearer ' + idToken,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = '{}';
      final streamed = await client.send(request).timeout(const Duration(seconds: 45));
      result = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 45));
    } finally {
      client.close();
    }
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (result.statusCode < 200 || result.statusCode >= 300 || body['cleaned'] != true) {
      throw StateError((body['error'] ?? 'تعذر حذف مرفقات الطلب.').toString());
    }
  }
  /// Deletes the authenticated account and its server-owned data.
  static Future<void> deleteAccount({required String idToken}) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root/v1/account/delete');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('خدمة حذف الحساب غير مهيأة. حدّث التطبيق أو تواصل مع الدعم.');
    }

    final appCheck = await appCheckHeaders();
    final client = http.Client();
    late final http.Response result;
    try {
      final streamed = await client
          .send(http.Request('POST', uri)
            ..headers.addAll({
              ...appCheck,
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            })
            ..body = '{}')
          .timeout(const Duration(seconds: 90));
      result = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw StateError('تعذر الاتصال بخدمة حذف الحساب. لم يتم تأكيد الحذف؛ حاول مرة أخرى.');
    } finally {
      client.close();
    }

    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (result.statusCode < 200 || result.statusCode >= 300 ||
        body['deleted'] != true) {
      final message = (body['error'] ?? '').toString().trim();
      throw StateError(message.isNotEmpty
          ? message
          : 'لم يؤكد الخادم حذف الحساب (${result.statusCode}).');
    }
  }

  /// البوابة رفضت لأن سعر/توفر صنف في السلة مختلف عن الكتالوج الحالي (مش أي خطأ تاني).
  /// الـ Worker الجديد بيبعت code = catalog_mismatch؛ النسخة القديمة بنعرفها من الرسالة.
  @visibleForTesting
  static bool isCatalogMismatch({
    required int status,
    String? code,
    required String message,
  }) {
    if (code != null && code.isNotEmpty) return code == 'catalog_mismatch';
    if (status != 409) return false;
    // الـ Worker القديم (من غير code): الرسايل دي بالظبط بس، مش أي رسالة فيها "اتغير".
    return _legacyMismatchMessages.contains(message.trim());
  }

  static const _legacyMismatchMessages = {
    'أحد الأصناف لم يعد موجودًا في كتالوج المحل.',
    'أحد الأصناف غير متاح حاليًا.',
    'سعر أحد الأصناف أو إضافاته اتغير. راجع السلة قبل تأكيد الطلب.',
    'سعر إضافات أحد الأصناف اتغير. راجع اختياراتك.',
    'أحد الاختيارات لم يعد متاحًا أو اسمه مكرر في الكتالوج.',
  };

  static Future<void> _send({
    required String idToken,
    required String method,
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    final body = await _request(
      idToken: idToken,
      method: method,
      path: path,
      payload: payload,
    );
    if ((body['orderId'] ?? '').toString().isEmpty) {
      throw StateError('لم يصل تأكيد العملية من الخادم.');
    }
  }

  static Future<Map<String, dynamic>> _request({
    required String idToken,
    required String method,
    required String path,
    required Map<String, dynamic> payload,
    String connectivityMessage = 'تعذر الاتصال بخدمة تأكيد الأسعار. حاول مرة أخرى.',
  }) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root$path');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('إعداد بوابة الطلبات غير صحيح.');
    }

    final appCheck = await appCheckHeaders();
    late final http.Response result;
    final client = http.Client();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          ...appCheck,
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode(payload);
      result = await PerformanceMonitor.trace(
        'worker_api_request',
        () async {
          final streamed = await client
              .send(request)
              .timeout(const Duration(seconds: 25));
          return http.Response.fromStream(streamed);
        },
      );
    } catch (_) {
      throw StateError(connectivityMessage);
    } finally {
      client.close();
    }

    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (result.statusCode < 200 || result.statusCode >= 300) {
      final message = (body['error'] ?? '').toString().trim();
      final text = message.isNotEmpty
          ? message
          : 'تعذر تنفيذ الطلب (${result.statusCode}).';
      if (isCatalogMismatch(
        status: result.statusCode,
        code: body['code']?.toString(),
        message: message,
      )) {
        throw CatalogMismatchError(text);
      }
      final code = body['code']?.toString() ?? '';
      if (code == 'invalid_group' || code.startsWith('group_')) {
        throw OrderGroupError(text);
      }
      throw StateError(text);
    }
    return body;
  }
}

/// سعر أو توفر صنف اتغير عن اللي في سلة العميل (القائمة المجمّعة عنده ممكن تكون متأخرة).
class CatalogMismatchError extends StateError {
  CatalogMismatchError(super.message);
}

/// رقم التجميع اترفض (انتهى، اتملا، محل متكرر، أو مش تبع الحساب). الطلب نفسه ما اتعملش.
class OrderGroupError extends StateError {
  OrderGroupError(super.message);
}

class _OrderPushAppObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(OrderGateway.replayPendingPushes());
    }
  }
}
), '')}/v1/order-events');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw const PermanentOrderPushException();
    }
    final token = await user.getIdToken().catchError((Object _) => null);
    if (token == null || token.isEmpty) throw const RetryableOrderPushException();
    final client = http.Client();
    late final http.Response response;
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          ...await appCheckHeaders(),
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode({
          'orderId': item.orderId,
          'event': item.event,
          if (item.status != null) 'status': item.status,
        });
      final stream = await client.send(request).timeout(const Duration(seconds: 12));
      response = await http.Response.fromStream(stream).timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const RetryableOrderPushException();
    } finally {
      client.close();
    }
    if (response.statusCode >= 500) throw const RetryableOrderPushException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const PermanentOrderPushException();
    }
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map && parsed['orderId'] == item.orderId) return;
    } catch (_) {
      // Malformed success from the gateway: keep a bounded retry.
    }
    throw const RetryableOrderPushException();
  }

  /// Called at app start and again on resume; pending entries retry every 25s
  /// only while they exist. No network listener, Firestore listener or read.
  static Future<void> startPendingPushRecovery() async {
    if (!_outboxRecoveryInitialized) {
      _outboxRecoveryInitialized = true;
      WidgetsBinding.instance.addObserver(_OrderPushAppObserver());
    }
    await replayPendingPushes();
  }

  static Future<void> replayPendingPushes() async {
    if (_flushingOutbox) return;
    _flushingOutbox = true;
    try {
      await _notificationOutbox.replay(FirebaseAuth.instance.currentUser?.uid);
    } catch (_) {
      debugPrint('تعذر إعادة إرسال الإشعارات المؤجلة.');
    } finally {
      _flushingOutbox = false;
      await _ensureOutboxTimer();
    }
  }

  static Future<void> _ensureOutboxTimer() async {
    final pending = await _notificationOutbox.hasPending;
    if (!pending) {
      _outboxTimer?.cancel();
      _outboxTimer = null;
      return;
    }
    _outboxTimer ??= Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(replayPendingPushes());
    });
  }

  static Future<Map<String, dynamic>> referralCampaign({
    required String channel,
    String? marketerUid,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/campaign',
      payload: {
        'channel': channel,
        if (marketerUid != null) 'marketerUid': marketerUid,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة الدعوات.',
    );
  }

  static Future<Map<String, dynamic>?> referralSettings({
    Map<String, dynamic>? settings,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    final response = await _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/settings',
      payload: {if (settings != null) 'settings': settings},
      connectivityMessage: 'تعذر الاتصال بخدمة الدعوات.',
    );
    return response['settings'] as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>> quoteReferralPoints(int itemsSubtotalMinor) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/points/quote',
      payload: {'itemsSubtotalMinor': itemsSubtotalMinor},
      connectivityMessage: 'تعذر حساب خصم النقاط.',
    );
  }

  static Future<Map<String, dynamic>> referralRedemption(
    String orderId,
    String action, {
    String? reference,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/redemption',
      payload: {
        'orderId': orderId,
        'action': action,
        if (reference != null) 'reference': reference,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة تسوية خصم النقاط.',
    );
  }

  static Future<Map<String, dynamic>> settleReferralCommission({
    required String ownerUid,
    required String storeId,
    required String reference,
    required int dueMinor,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/commissions',
      payload: {
        'ownerUid': ownerUid,
        'storeId': storeId,
        'reference': reference,
        'dueMinor': dueMinor,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة تسوية عمولة الدعوات.',
    );
  }

  static Future<Map<String, dynamic>> referralPayout({
    required String action,
    String? requestId,
    String? payoutId,
    String? reference,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول الأول.');
    return _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/payouts',
      payload: {
        'action': action,
        if (requestId != null) 'requestId': requestId,
        if (payoutId != null) 'payoutId': payoutId,
        if (reference != null) 'reference': reference,
      },
      connectivityMessage: 'تعذر الاتصال بخدمة صرف مكافآت الدعوات.',
    );
  }

  /// Associates a verified Google account with one Android device for
  /// first-time invitation eligibility. Safe for repeat login. No Firestore
  /// listener or paid service; other Google accounts can still sign in.
  static String? _referralDeviceBoundUid;
  static Future<bool>? _referralDeviceBinding;

  static Future<bool> registerReferralDevice() async {
    if (!referralCampaignEnabled) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    if (_referralDeviceBoundUid == uid && _referralDeviceBinding == null) {
      return true;
    }
    if (_referralDeviceBoundUid == uid && _referralDeviceBinding != null) {
      return _referralDeviceBinding!;
    }
    _referralDeviceBoundUid = uid;
    final pending = _performReferralDeviceBinding();
    _referralDeviceBinding = pending;
    try {
      final allowed = await pending;
      if (!allowed) _referralDeviceBoundUid = null;
      return allowed;
    } catch (_) {
      _referralDeviceBoundUid = null;
      rethrow;
    } finally {
      _referralDeviceBinding = null;
    }
  }

  static Future<bool> _performReferralDeviceBinding() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('سجّل الدخول من جديد.');
    final deviceId = await ReferralDevice.androidScopedId();
    final result = await _request(
      idToken: token,
      method: 'POST',
      path: '/v1/referrals/device-binding',
      payload: {'deviceId': deviceId},
      connectivityMessage: 'تعذر الاتصال بخدمة حماية الدعوات.',
    );
    return result['eligible'] == true;
  }

  static Future<void> claimRegistrationReferral({
    required String idToken,
    required String code,
  }) async {
    final deviceId = await ReferralDevice.androidScopedId();
    final body = await _request(
      idToken: idToken,
      method: 'POST',
      path: '/v1/referrals/registration',
      payload: {'code': code, 'deviceId': deviceId},
      connectivityMessage: 'تعذر الاتصال بخدمة الدعوات.',
    );
    if (body['accepted'] != true) {
      throw StateError('لم يصل تأكيد حفظ كود الدعوة.');
    }
  }

  static Future<void> submit({
    required String idToken,
    required Map<String, dynamic> payload,
  }) => _send(
        idToken: idToken,
        method: 'POST',
        path: '/v1/orders',
        payload: payload,
      );

  static Future<void> update({
    required String idToken,
    required String orderId,
    required Map<String, dynamic> payload,
  }) => _send(
        idToken: idToken,
        method: 'PATCH',
        path: '/v1/orders/${Uri.encodeComponent(orderId)}',
        payload: payload,
      );

  /// Removes this order's uploaded attachments only after customer receipt confirmation.
  static Future<void> cleanupAttachments({
    required String idToken,
    required String orderId,
  }) async {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    final uri = Uri.tryParse(root + '/v1/orders/' + Uri.encodeComponent(orderId) + '/cleanup-attachments');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('خدمة تنظيف مرفقات الطلب غير مهيأة.');
    }
    final appCheck = await appCheckHeaders();
    final client = http.Client();
    late final http.Response result;
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          ...appCheck,
          'Authorization': 'Bearer ' + idToken,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = '{}';
      final streamed = await client.send(request).timeout(const Duration(seconds: 45));
      result = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 45));
    } finally {
      client.close();
    }
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (result.statusCode < 200 || result.statusCode >= 300 || body['cleaned'] != true) {
      throw StateError((body['error'] ?? 'تعذر حذف مرفقات الطلب.').toString());
    }
  }
  /// Deletes the authenticated account and its server-owned data.
  static Future<void> deleteAccount({required String idToken}) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root/v1/account/delete');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('خدمة حذف الحساب غير مهيأة. حدّث التطبيق أو تواصل مع الدعم.');
    }

    final appCheck = await appCheckHeaders();
    final client = http.Client();
    late final http.Response result;
    try {
      final streamed = await client
          .send(http.Request('POST', uri)
            ..headers.addAll({
              ...appCheck,
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            })
            ..body = '{}')
          .timeout(const Duration(seconds: 90));
      result = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw StateError('تعذر الاتصال بخدمة حذف الحساب. لم يتم تأكيد الحذف؛ حاول مرة أخرى.');
    } finally {
      client.close();
    }

    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (result.statusCode < 200 || result.statusCode >= 300 ||
        body['deleted'] != true) {
      final message = (body['error'] ?? '').toString().trim();
      throw StateError(message.isNotEmpty
          ? message
          : 'لم يؤكد الخادم حذف الحساب (${result.statusCode}).');
    }
  }

  /// البوابة رفضت لأن سعر/توفر صنف في السلة مختلف عن الكتالوج الحالي (مش أي خطأ تاني).
  /// الـ Worker الجديد بيبعت code = catalog_mismatch؛ النسخة القديمة بنعرفها من الرسالة.
  @visibleForTesting
  static bool isCatalogMismatch({
    required int status,
    String? code,
    required String message,
  }) {
    if (code != null && code.isNotEmpty) return code == 'catalog_mismatch';
    if (status != 409) return false;
    // الـ Worker القديم (من غير code): الرسايل دي بالظبط بس، مش أي رسالة فيها "اتغير".
    return _legacyMismatchMessages.contains(message.trim());
  }

  static const _legacyMismatchMessages = {
    'أحد الأصناف لم يعد موجودًا في كتالوج المحل.',
    'أحد الأصناف غير متاح حاليًا.',
    'سعر أحد الأصناف أو إضافاته اتغير. راجع السلة قبل تأكيد الطلب.',
    'سعر إضافات أحد الأصناف اتغير. راجع اختياراتك.',
    'أحد الاختيارات لم يعد متاحًا أو اسمه مكرر في الكتالوج.',
  };

  static Future<void> _send({
    required String idToken,
    required String method,
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    final body = await _request(
      idToken: idToken,
      method: method,
      path: path,
      payload: payload,
    );
    if ((body['orderId'] ?? '').toString().isEmpty) {
      throw StateError('لم يصل تأكيد العملية من الخادم.');
    }
  }

  static Future<Map<String, dynamic>> _request({
    required String idToken,
    required String method,
    required String path,
    required Map<String, dynamic> payload,
    String connectivityMessage = 'تعذر الاتصال بخدمة تأكيد الأسعار. حاول مرة أخرى.',
  }) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root$path');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('إعداد بوابة الطلبات غير صحيح.');
    }

    final appCheck = await appCheckHeaders();
    late final http.Response result;
    final client = http.Client();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          ...appCheck,
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode(payload);
      result = await PerformanceMonitor.trace(
        'worker_api_request',
        () async {
          final streamed = await client
              .send(request)
              .timeout(const Duration(seconds: 25));
          return http.Response.fromStream(streamed);
        },
      );
    } catch (_) {
      throw StateError(connectivityMessage);
    } finally {
      client.close();
    }

    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (result.statusCode < 200 || result.statusCode >= 300) {
      final message = (body['error'] ?? '').toString().trim();
      final text = message.isNotEmpty
          ? message
          : 'تعذر تنفيذ الطلب (${result.statusCode}).';
      if (isCatalogMismatch(
        status: result.statusCode,
        code: body['code']?.toString(),
        message: message,
      )) {
        throw CatalogMismatchError(text);
      }
      final code = body['code']?.toString() ?? '';
      if (code == 'invalid_group' || code.startsWith('group_')) {
        throw OrderGroupError(text);
      }
      throw StateError(text);
    }
    return body;
  }
}

/// سعر أو توفر صنف اتغير عن اللي في سلة العميل (القائمة المجمّعة عنده ممكن تكون متأخرة).
class CatalogMismatchError extends StateError {
  CatalogMismatchError(super.message);
}

/// رقم التجميع اترفض (انتهى، اتملا، محل متكرر، أو مش تبع الحساب). الطلب نفسه ما اتعملش.
class OrderGroupError extends StateError {
  OrderGroupError(super.message);
}

class _OrderPushAppObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(OrderGateway.replayPendingPushes());
    }
  }
}
