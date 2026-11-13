import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_role.dart';
import 'role_service.dart';

/// أنواع الرسائل في complaints. القيم لازم تطابق firestore.rules (validComplaint).
enum FeedbackKind {
  complaint('complaint', 'شكوى'),
  suggestion('suggestion', 'اقتراح'),
  orderIssue('order_issue', 'مشكلة في طلب');

  final String key;
  final String label;
  const FeedbackKind(this.key, this.label);

  static FeedbackKind parse(String? k) => FeedbackKind.values.firstWhere(
    (e) => e.key == k,
    orElse: () => FeedbackKind.complaint,
  );
}

class FeedbackService {
  const FeedbackService._();

  static const int maxLength = 1000; // يطابق القواعد
  static const int minLength = 5;

  static String _roleKey(AppRole? r) => switch (r) {
    AppRole.admin => 'admin',
    AppRole.courier => 'courier',
    AppRole.storeOwner => 'store_owner',
    AppRole.supervisor => 'supervisor',
    _ => 'customer',
  };

  /// بيسجّل الشكوى/الاقتراح في complaints. [orderId] إجباري لنوع "مشكلة في طلب".
  static Future<void> send({
    required FeedbackKind kind,
    required String message,
    String? orderId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    final text = message.trim();
    if (text.length < minLength) {
      throw ArgumentError('اكتب $minLength حروف على الأقل.');
    }
    if (kind == FeedbackKind.orderIssue && (orderId ?? '').isEmpty) {
      throw ArgumentError('اختار الطلب.');
    }
    var name = user.displayName ?? '';
    if (name.length > 80) name = name.substring(0, 80);
    await FirebaseFirestore.instance.collection('complaints').add({
      'userId': user.uid,
      'userEmail': user.email ?? '',
      'userName': name,
      'kind': kind.key,
      'message': text.length > maxLength ? text.substring(0, maxLength) : text,
      if (kind == FeedbackKind.orderIssue) 'orderId': orderId,
      'appRole': _roleKey(RoleService.cachedFor(user.uid)?.role),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
