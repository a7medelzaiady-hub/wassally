import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'order_gateway.dart';

/// بيطلب من الـWorker يبعت إشعار لموبايلات الإدارة (توبيك admins) بعد ما المستخدم
/// يعمل طلب انضمام أو المندوب يسجل تعذر تسليم. محاولة واحدة في الخلفية:
/// فشلها ما يأثرش على العملية نفسها (العدادات في التطبيق بتفضل شغالة).
class AdminNotify {
  const AdminNotify._();

  static void joinRequest(String requestId) => unawaited(_send('join_request', requestId));

  static void deliveryIssue(String issueId) => unawaited(_send('delivery_issue', issueId));

  static Future<void> _send(String kind, String id) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || id.isEmpty || !OrderGateway.isConfigured) return;
      final idToken = await user.getIdToken();
      final root = OrderGateway.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final uri = Uri.parse('$root/v1/notify-admins');
      await http
          .post(
            uri,
            headers: {
              ...await OrderGateway.appCheckHeaders(),
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'kind': kind, 'id': id}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Admin notify skipped: $e');
    }
  }
}
