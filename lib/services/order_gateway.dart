import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
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

  static Future<void> _send({
    required String idToken,
    required String method,
    required String path,
    required Map<String, dynamic> payload,
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
      throw StateError('تعذر الاتصال بخدمة تأكيد الأسعار. حاول مرة أخرى.');
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
      throw StateError(
        message.isNotEmpty
            ? message
            : 'تعذر تنفيذ الطلب (${result.statusCode}).',
      );
    }
    if ((body['orderId'] ?? '').toString().isEmpty) {
      throw StateError('لم يصل تأكيد العملية من الخادم.');
    }
  }
}
