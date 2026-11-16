import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WorkerNotifyService {
  const WorkerNotifyService._();

  static const String _workerUrl =
      'https://throbbing-water-4ef7.a7medelzaiady.workers.dev';

  static Future<Map<String, dynamic>?> _post(
      Map<String, dynamic> payload) async {
    try {
      // جلب معرف المصادقة للمستخدم الحالي من Firebase Auth
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('WorkerNotifyError: User not logged in');
        return null;
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('WorkerNotifyError: Failed to get ID token');
        return null;
      }

      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer $idToken', // إرسال رمز المصادقة للتحقق في الـ Worker
        },
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

  /// إشعار طلب جديد للإدارة والمحل
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

  /// إشعار رسالة دعم فني جديدة
  static Future<void> notifySupportMessage({
    required String chatUid,
    required String messageId,
    required String senderRole,
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
}
