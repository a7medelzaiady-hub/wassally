import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WorkerNotifyService {
  static const String _workerUrl =
      'https://throbbing-water-4ef7.a7medelzaiady.workers.dev';

  /// إرسال إشعار FCM إلى جهاز محدد (fcmToken) أو مجموعة (topic مثل: couriers أو admins)
  static Future<bool> sendNotification({
    String? fcmToken,
    String? topic,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if ((fcmToken == null || fcmToken.isEmpty) &&
        (topic == null || topic.isEmpty)) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'send_fcm',
          if (fcmToken != null && fcmToken.isNotEmpty) 'token': fcmToken,
          if (topic != null && topic.isNotEmpty) 'topic': topic,
          'title': title,
          'message': body,
          'data': data ?? <String, dynamic>{},
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint('Worker FCM Error (${response.statusCode}): ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Worker Connection Exception: $e');
      return false;
    }
  }

  /// تحديث مستند في Firestore عبر السيرفر (تخطي قيود الصلاحيات عند الحاجة)
  static Future<bool> updateFirestoreDoc({
    required String collection,
    required String docId,
    required Map<String, dynamic> fields,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'firestore_patch',
          'collection': collection,
          'docId': docId,
          'firestoreData': fields,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Worker Firestore Exception: $e');
      return false;
    }
  }
}
