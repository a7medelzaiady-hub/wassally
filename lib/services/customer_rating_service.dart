import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// تقييم داخلي للعميل من طرف تعامل معه في طلب مكتمل.
class CustomerRatingService {
  const CustomerRatingService._();

  static const Map<String, String> reasonLabels = {
    'positive': 'تعامل محترم ومتعاون',
    'unavailable': 'لم يرد أو لم يكن متاحًا عند الوصول',
    'wrong_address': 'العنوان غير صحيح',
    'refused_order': 'رفض استلام طلب أكده',
    'no_cash': 'لم يتوفر مبلغ الطلب النقدي',
    'abusive_behavior': 'إساءة في التعامل',
    'other': 'سبب آخر',
  };

  static Future<void> rate({
    required String orderId,
    required String customerId,
    required String storeId,
    required String reviewerRole,
    required int rating,
    required String reason,
    String comment = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    if (!['courier', 'store_owner'].contains(reviewerRole)) {
      throw ArgumentError.value(reviewerRole, 'reviewerRole');
    }
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating');
    }
    if (!reasonLabels.containsKey(reason)) {
      throw ArgumentError.value(reason, 'reason');
    }

    var note = comment.trim();
    if (note.length > 300) note = note.substring(0, 300);
    final id = '${orderId}_${reviewerRole}';
    try {
      await FirebaseFirestore.instance.collection('customer_reviews').doc(id).set({
        'orderId': orderId,
        'customerId': customerId,
        'reviewerId': user.uid,
        'reviewerRole': reviewerRole,
        'storeId': storeId,
        'rating': rating,
        'reason': reason,
        'comment': note,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError('لم يُسجّل التقييم. ربما سبق تقييم العميل أو لم تكتمل شروط الطلب.');
      }
      rethrow;
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAllReviews() =>
      FirebaseFirestore.instance
          .collection('customer_reviews')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots();

  /// تقييد مؤقت بقرار إداري بعد مراجعة الواقعة، وليس نتيجة آلية للنجوم.
  static Future<void> restrictCustomer({
    required String customerId,
    required String sourceOrderId,
    required String reason,
    int durationDays = 3,
  }) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) throw StateError('سجّل دخول الإدارة.');
    final note = reason.trim();
    if (note.length < 5) throw ArgumentError('سبب التقييد قصير.');
    final days = durationDays.clamp(1, 7).toInt();
    final db = FirebaseFirestore.instance;
    await db.collection('customer_restrictions').doc(customerId).set({
      'customerId': customerId,
      'active': true,
      'reason': note.length > 300 ? note.substring(0, 300) : note,
      'sourceOrderId': sourceOrderId,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': admin.uid,
      'expiresAt': Timestamp.fromDate(DateTime.now().add(Duration(days: days))),
    });
    try {
      await db.collection('notifications').add({
        'userId': customerId,
        'title': 'تنبيه بخصوص حسابك',
        'body': 'تم فرض تقييد مؤقت على إنشاء الطلبات لمدة $days أيام بعد مراجعة شكوى مرتبطة بطلب. للتوضيح أو الاعتراض تواصل مع الإدارة.',
        'orderId': sourceOrderId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // فشل التنبيه لا يلغي قرار التقييد المسجل.
    }
  }

  static Future<void> liftRestriction(String customerId) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) throw StateError('سجّل دخول الإدارة.');
    final db = FirebaseFirestore.instance;
    final ref = db.collection('customer_restrictions').doc(customerId);
    final snap = await ref.get();
    final sourceOrderId = (snap.data()?['sourceOrderId'] ?? '').toString();
    await ref.update({
      'active': false,
      'clearedAt': FieldValue.serverTimestamp(),
      'clearedBy': admin.uid,
    });
    if (sourceOrderId.isNotEmpty) {
      try {
        await db.collection('notifications').add({
          'userId': customerId,
          'title': 'تم رفع التقييد عن حسابك',
          'body': 'راجعت الإدارة الحالة وتم رفع التقييد. يمكنك إرسال الطلبات مرة أخرى.',
          'orderId': sourceOrderId,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }
}
