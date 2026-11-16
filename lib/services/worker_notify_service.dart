import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WorkerNotifyService {
  const WorkerNotifyService._();

  static const String _workerUrl =
      'https://throbbing-water-4ef7.a7medelzaiady.workers.dev';

  static Future?> _post(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('Worker Error (${response.statusCode}): ${response.body}');
    } catch (e) {
      debugPrint('Worker Exception: $e');
    }
    return null;
  }

  /// إشعار رسالة دعم جديدة (بديل onSupportMessageCreated)
  static Future<void> notifySupportMessage({
    required String chatUid,
    required String messageId,
    required String senderRole, // 'user' أو 'admin'
    String? userName,
  }) async {
    await _post({
      'action': 'support_message',
      'chatUid': chatUid,
      'messageId': messageId,
      'senderRole': senderRole,
      'userName': userName ?? '',
    });
  }

  /// إشعار نشر تحديث جديد للتطبيق (بديل onAppVersionPublished)
  static Future<void> notifyAppVersionPublished({
    required String latestVersion,
    required bool forceUpdate,
  }) async {
    await _post({
      'action': 'app_version_published',
      'latestVersion': latestVersion,
      'forceUpdate': forceUpdate,
    });
  }

  /// إشعار طلب جديد (بديل onOrderCreated)
  static Future<void> notifyOrderCreated({
    required String orderId,
    required String userId,
    required String storeId,
    required String customerName,
    required String storeName,
    required num total,
  }) async {
    await _post({
      'action': 'order_created',
      'orderId': orderId,
      'userId': userId,
      'storeId': storeId,
      'customerName': customerName,
      'storeName': storeName,
      'total': total,
    });
  }

  /// إشعار تحديث حالة طلب أو تعيين مندوب (بديل onOrderUpdated)
  static Future<void> notifyOrderUpdated({
    required String orderId,
    String? status,
    String? userId,
    String? storeId,
    String? courierId,
    String? previousCourierId,
    String? customerName,
    String? storeName,
    num? total,
  }) async {
    await _post({
      'action': 'order_updated',
      'orderId': orderId,
      if (status != null) 'status': status,
      if (userId != null) 'userId': userId,
      if (storeId != null) 'storeId': storeId,
      if (courierId != null) 'courierId': courierId,
      if (previousCourierId != null) 'previousCourierId': previousCourierId,
      if (customerName != null) 'customerName': customerName,
      if (storeName != null) 'storeName': storeName,
      if (total != null) 'total': total,
    });
  }

  /// إشعار قبول/رفض طلب انضمام (بديل onRoleRequestUpdated)
  static Future<void> notifyRoleRequestUpdated({
    required String requestId,
    required String userId,
    required String status, // 'approved' أو 'rejected'
    String? adminNote,
  }) async {
    await _post({
      'action': 'role_request_updated',
      'requestId': requestId,
      'userId': userId,
      'status': status,
      if (adminNote != null) 'adminNote': adminNote,
    });
  }
}
