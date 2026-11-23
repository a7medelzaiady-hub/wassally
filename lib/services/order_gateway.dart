import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'performance_monitor.dart';

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

  /// Sends a push for a Firestore change that already committed.
  static Future<void> notifyEvent(
    String orderId,
    String event, {
    String? status,
  }) async {
    if (!isConfigured) return;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) return;
      await _send(
        idToken: token,
        method: 'POST',
        path: '/v1/order-events',
        payload: {
          'orderId': orderId,
          'event': event,
          if (status != null) 'status': status,
        },
      );
    } catch (_) {
      debugPrint('تعذر إرسال إشعار حالة الطلب.');
    }
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
      connectivityMessage: 'تعذر الاتصال بخدمة الإحالات.',
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
      connectivityMessage: 'تعذر الاتصال بخدمة الإحالات.',
    );
    return response['settings'] as Map<String, dynamic>?;
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
      connectivityMessage: 'تعذر الاتصال بخدمة تسوية عمولة الإحالة.',
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
      connectivityMessage: 'تعذر الاتصال بخدمة صرف الإحالات.',
    );
  }

  static Future<void> claimRegistrationReferral({
    required String idToken,
    required String code,
  }) async {
    final body = await _request(
      idToken: idToken,
      method: 'POST',
      path: '/v1/referrals/registration',
      payload: {'code': code},
      connectivityMessage: 'تعذر الاتصال بخدمة الإحالات.',
    );
    if (body['accepted'] != true) {
      throw StateError('لم يصل تأكيد حفظ كود الإحالة.');
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
