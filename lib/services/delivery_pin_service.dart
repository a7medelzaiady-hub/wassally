import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'order_gateway.dart';
import 'performance_monitor.dart';

/// خطأ من خدمة رمز التسليم، ومعاه الكود اللي بيرجعه الـWorker (pin_wrong, pin_locked...).
class DeliveryPinError extends StateError {
  final String code;
  DeliveryPinError(super.message, this.code);
}

/// رمز التسليم: العميل بيجيبه من الـWorker، والمندوب بيبعته للـWorker عشان يأكد التسليم.
/// الرمز مش بيتخزن في Firestore خالص.
class DeliveryPinService {
  const DeliveryPinService._();

  /// صيغة الرمز: 4 أرقام بالظبط (أرقام إنجليزي أو عربي).
  static String? normalize(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buf = StringBuffer();
    for (final ch in input.trim().split('')) {
      final i = arabic.indexOf(ch);
      buf.write(i >= 0 ? '$i' : ch);
    }
    final out = buf.toString();
    return RegExp(r'^[0-9]{4}$').hasMatch(out) ? out : null;
  }

  /// للعميل: رمز تسليم طلبه وهو في الطريق.
  static Future<String> fetchPin(String orderId) async {
    final body = await _call('GET', orderId, 'delivery-pin');
    final pin = (body['pin'] ?? '').toString();
    if (normalize(pin) == null) throw DeliveryPinError('تعذر عرض رمز التسليم.', 'bad_response');
    return pin;
  }

  /// للمندوب: تأكيد التسليم بالرمز. بيرجع true لو الطلب اتقفل «تم التسليم»
  /// (مندوب المحل)، وfalse لو فاضل تسوية النقدية مع المحل (مندوب خارجي).
  static Future<bool> deliver(String orderId, String pin) async {
    final clean = normalize(pin);
    if (clean == null) throw DeliveryPinError('اكتب رمز من 4 أرقام.', 'pin_invalid');
    final body = await _call('POST', orderId, 'deliver', {'pin': clean});
    final delivered = body['delivered'];
    if (delivered is! bool) {
      throw DeliveryPinError('رد تأكيد التسليم غير صحيح. تحقق من حالة الطلب وحاول مرة أخرى.', 'bad_response');
    }
    return delivered;
  }

  static Future<Map<String, dynamic>> _call(
    String method,
    String orderId,
    String action, [
    Map<String, dynamic>? payload,
  ]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw DeliveryPinError('سجّل دخول الأول.', 'auth');
    final idToken = await user.getIdToken();
    final root = OrderGateway.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root/v1/orders/${Uri.encodeComponent(orderId)}/$action');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw DeliveryPinError('خدمة رمز التسليم غير مهيأة.', 'config');
    }
    final headers = {
      ...await OrderGateway.appCheckHeaders(),
      'Authorization': 'Bearer $idToken',
      'Accept': 'application/json',
      if (payload != null) 'Content-Type': 'application/json',
    };
    late final http.Response res;
    try {
      res = await PerformanceMonitor.trace('worker_delivery_pin', () {
        final f = method == 'GET'
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(payload ?? const {}));
        return f.timeout(const Duration(seconds: 20));
      });
    } catch (_) {
      throw DeliveryPinError('تعذر الاتصال. تأكد من الإنترنت وحاول تاني.', 'network');
    }
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (body['error'] ?? '').toString().trim();
      throw DeliveryPinError(
        msg.isNotEmpty ? msg : 'تعذر تنفيذ العملية (${res.statusCode}).',
        (body['code'] ?? 'http_${res.statusCode}').toString(),
      );
    }
    return body;
  }
}
