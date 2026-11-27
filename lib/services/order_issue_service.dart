import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order.dart';
import 'admin_notify.dart';

/// أنواع «عندي مشكلة في الطلب» (نفس القايمة في firestore.rules).
enum OrderIssueType {
  missingItem('missing_item', 'صنف ناقص'),
  wrongItem('wrong_item', 'صنف غلط أو مش زي ما طلبت'),
  late('late', 'الطلب اتأخر'),
  courier('courier', 'مشكلة مع المندوب'),
  price('price', 'الحساب أو السعر غلط'),
  other('other', 'حاجة تانية');

  final String key;
  final String label;
  const OrderIssueType(this.key, this.label);

  static OrderIssueType? parse(Object? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// بلاغ واحد لكل طلب (رقم المستند = رقم الطلب) بيروح لصندوق الإدارة.
///
/// القراءات: صفر للعميل. إن البلاغ اتبعت بيتحفظ على الموبايل، فتفاصيل الطلب
/// ما بتقراش مستند البلاغ. لو اتبعت من موبايل تاني، الكتابة التانية بترفضها
/// القواعد ونعتبره متبعت.
class OrderIssueService {
  const OrderIssueService._();

  static const maxNote = 300;
  static String _sentKey(String orderId) => 'order_issue_sent_$orderId';

  static Future<bool> alreadySent(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_sentKey(orderId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// البيانات اللي بتتكتب (من غير الوقت). منفصلة عشان الاختبار.
  static Map<String, Object> payload({
    required AppOrder order,
    required String uid,
    required OrderIssueType type,
    required String note,
  }) {
    final trimmed = note.trim();
    final store = order.storeName.trim();
    return {
      'orderId': order.id,
      'customerId': uid,
      'storeId': order.storeId,
      'storeName': store.length > 120 ? store.substring(0, 120) : store,
      'type': type.key,
      'note': trimmed.length > maxNote ? trimmed.substring(0, maxNote) : trimmed,
      'status': 'open',
      'createdBy': uid,
    };
  }

  /// بيرجع true لو البلاغ اتسجل (أو كان متسجل قبل كده).
  static Future<bool> report(
    AppOrder order, {
    required OrderIssueType type,
    String note = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل الدخول الأول.');
    final ref = FirebaseFirestore.instance.collection('order_issues').doc(order.id);
    try {
      await ref.set({
        ...payload(order: order, uid: uid, type: type, note: note),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      // البلاغ موجود (اتبعت من الموبايل ده قبل ما يتحفظ أو من موبايل تاني):
      // القواعد بترفض الكتابة فوقه. نتأكد بقراية واحدة إنه بتاعنا.
      if (e.code != 'permission-denied') rethrow;
      final existing = await ref.get();
      if (!existing.exists || existing.data()?['customerId'] != uid) rethrow;
      await _markSent(order.id);
      return true;
    }
    await _markSent(order.id);
    AdminNotify.orderIssue(order.id);
    return true;
  }

  static Future<void> _markSent(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sentKey(orderId), true);
    } catch (_) {}
  }

  /// الإدارة: قفل البلاغ بقرار مختصر.
  static Future<void> resolve(String orderId, String decision) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل الدخول الأول.');
    final text = decision.trim();
    await FirebaseFirestore.instance.collection('order_issues').doc(orderId).update({
      'status': 'resolved',
      'adminDecision': text.length > maxNote ? text.substring(0, maxNote) : text,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }
}
