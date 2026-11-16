import 'dart:convert';

import 'package:http/http.dart' as http;

/// عنوان بوابة الطلبات الموثوقة يمرر وقت البناء، ولا يحتوي أي أسرار.
class OrderGateway {
  const OrderGateway._();

  static const String baseUrl = String.fromEnvironment(
    'WASALLY_ORDER_GATEWAY_URL',
    defaultValue: '',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;

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

    late final http.Response result;
    final client = http.Client();
    try {
      final request = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode(payload);
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 25));
      result = await http.Response.fromStream(streamed);
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
