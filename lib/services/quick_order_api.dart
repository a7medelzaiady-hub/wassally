import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'order_gateway.dart';

/// Worker-only writes for quick orders. No Firestore writes are permitted.
class QuickOrderApi {
  const QuickOrderApi._();

  static Future<Map<String, dynamic>> create(Map<String, dynamic> body) =>
      _request('', body);

  static Future<Map<String, dynamic>> action(
    String orderId,
    String action, [
    Map<String, dynamic> body = const {},
  ]) => _request(
        '${Uri.encodeComponent(orderId)}/${Uri.encodeComponent(action)}',
        body,
      );

  static Future<Map<String, dynamic>> deliveryPin(String orderId) =>
      _request('${Uri.encodeComponent(orderId)}/delivery-pin', null);

  static Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic>? body,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجل دخولك أولًا');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('تعذر التحقق من تسجيل الدخول');
    }
    final root = OrderGateway.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root/v1/quick${path.isEmpty ? '' : '/$path'}');
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      throw StateError('خدمة الطلبات السريعة غير مهيأة');
    }
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...await OrderGateway.appCheckHeaders(),
    };
    late final http.Response response;
    try {
      response = body == null
          ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 35))
          : await http.post(uri, headers: headers, body: jsonEncode(body))
              .timeout(const Duration(seconds: 35));
    } catch (_) {
      throw StateError('تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى');
    }
    Map<String, dynamic> decoded;
    try {
      final data = jsonDecode(response.body);
      decoded = data is Map<String, dynamic> ? data : <String, dynamic>{};
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = (decoded['error'] ?? decoded['code'] ?? 'تعذر إتمام العملية').toString();
      throw StateError(message);
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> accept(String id) => action(id, 'accept');
  static Future<Map<String, dynamic>> startPurchase(String id, int estimate) =>
      action(id, 'start-purchase', {'estimatedPurchasesPiastres': estimate});
  static Future<Map<String, dynamic>> advanceSent(String id, int amount, String reference) =>
      action(id, 'advance-sent', {'amountPiastres': amount, 'reference': reference});
  static Future<Map<String, dynamic>> advanceReceived(String id, int amount) =>
      action(id, 'advance-received', {'amountPiastres': amount});
  static Future<Map<String, dynamic>> addReceipt(String id, String imageUrl, int amount) =>
      action(id, 'receipt', {'imageUrl': imageUrl, 'amountPiastres': amount});
  static Future<Map<String, dynamic>> submitSummary(String id, int delivery) =>
      action(id, 'submit-summary', {'deliveryPiastres': delivery});
  static Future<Map<String, dynamic>> approveSummary(String id, int revision) =>
      action(id, 'approve-summary', {'expectedSummaryRevision': revision});
  static Future<Map<String, dynamic>> rejectSummary(String id) =>
      action(id, 'reject-summary');
  static Future<Map<String, dynamic>> deliver(String id, String pin) =>
      action(id, 'deliver', {'pin': pin});
}
