import 'dart:convert';

import 'package:http/http.dart' as http;

/// عنوان بوابة الطلبات الموثوقة يمرر وقت البناء، ولا يحتوي أي أسرار.
/// مثال: --dart-define=WASALLY_ORDER_GATEWAY_URL=https://wasally-order-gateway.<account>.workers.dev
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
  }) async {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root/v1/orders');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('إعداد بوابة الطلبات غير صحيح.');
    }

    final http.Response result;
    try {
      result = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw StateError('تعذر الاتصال بخدمة تأكيد الأسعار. حاول مرة أخرى.');
    }

    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (result.statusCode < 200 || result.statusCode >= 300) {
      final message = (body['error'] ?? '').toString().trim();
      throw StateError(
        message.isNotEmpty ? message : 'تعذر إنشاء الطلب (' + result.statusCode.toString() + ').',
      );
    }
    if ((body['orderId'] ?? '').toString().isEmpty) {
      throw StateError('لم يصل تأكيد إنشاء الطلب من الخادم.');
    }
  }
}
