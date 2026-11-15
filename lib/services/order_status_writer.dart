import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/order.dart';

/// يغيّر حالة الطلب ويسجّل الحدث في نفس الـ batch.
///
/// لا يوجد fallback لتحديث الحالة وحدها عند رفض الـ batch؛ لأن رفض Firestore
/// قد يكون بسبب عدم امتلاك المستخدم للصلاحية، وليس بسبب غياب statusHistory.
/// القواعد تظل المرجع النهائي للتحقق من صلاحية المستخدم وانتقال الحالة.
class OrderStatusWriter {
  const OrderStatusWriter._();

  /// مستند قايمة المناديب (من غير بيانات العميل).
  static Map<String, dynamic> feedData(
    Map<String, dynamic> o, [
    Map<String, dynamic> extra = const {},
  ]) {
    final m = <String, dynamic>{
      'storeId': o['storeId'],
      'storeName': o['storeName'],
      'area': o['area'] ?? '',
      'items': o['items'],
      'subtotal': o['subtotal'],
      'deliveryFee': o['deliveryFee'],
      'finalDeliveryFee': extra['finalDeliveryFee'] ?? o['finalDeliveryFee'],
      'discount': o['discount'] ?? 0,
      'total': o['total'],
      'status': 'preparing',
      'createdAt': o['createdAt'],
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }

  static Future<void> change({
    required String orderId,
    required OrderStatus to,
    required String actorRole, // customer | courier | admin | storeOwner
    OrderStatus? from,
    Map<String, dynamic> extra = const {},
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('لازم تسجّل دخول الأول لتحديث حالة الطلب.');
    }

    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      throw ArgumentError.value(orderId, 'orderId', 'رقم الطلب غير صالح.');
    }

    const allowedRoles = {'customer', 'courier', 'admin', 'storeOwner'};
    if (!allowedRoles.contains(actorRole)) {
      throw ArgumentError.value(actorRole, 'actorRole', 'دور المستخدم غير صالح.');
    }

    final db = FirebaseFirestore.instance;
    final orderRef = db.collection('orders').doc(normalizedOrderId);

    // نقرأ الحالة الفعلية دائمًا حتى لا نسجل انتقالًا مبنيًا على حالة قديمة
    // موجودة في الواجهة. قواعد Firestore تتحقق مرة أخرى عند تنفيذ الـ batch.
    final snapshot = await orderRef.get();
    if (!snapshot.exists) {
      throw StateError('الطلب غير موجود أو تم حذفه.');
    }

    final currentStatus = snapshot.data()?['status']?.toString();
    if (currentStatus == null || currentStatus.isEmpty) {
      throw StateError('حالة الطلب الحالية غير معروفة.');
    }

    if (from != null && from.key != currentStatus) {
      throw StateError('حالة الطلب اتغيرت بالفعل. حدّث الصفحة وحاول تاني.');
    }

    // لا ننشئ سجل انتقال جديد إذا كانت الحالة بالفعل هي المطلوبة.
    if (currentStatus == to.key) return;

    if (extra.containsKey('status')) {
      throw ArgumentError('لا يمكن تمرير status داخل extra؛ استخدم to لتحديد الحالة.');
    }

    final update = <String, dynamic>{
      ...extra,
      'status': to.key,
    };

    final batch = db.batch();
    batch.update(orderRef, update);
    batch.set(orderRef.collection('statusHistory').doc(to.key), {
      'from': currentStatus,
      'to': to.key,
      'actorUid': uid,
      'actorRole': actorRole,
      'at': FieldValue.serverTimestamp(),
    });

    final feedRef =
        db.collection('courier_available_orders').doc(normalizedOrderId);
    final data = snapshot.data()!;
    if (to == OrderStatus.preparing &&
        (data['courierId'] ?? '').toString().isEmpty &&
        (actorRole == 'admin' || actorRole == 'storeOwner')) {
      batch.set(feedRef, feedData(data, extra));
    }
    // طلب اتلغى وهو في القايمة: شيله (للمدير/المحل بس، العميل ماله صلاحية حذف).
    if (to == OrderStatus.cancelled &&
        currentStatus == 'preparing' &&
        (actorRole == 'admin' || actorRole == 'storeOwner')) {
      batch.delete(feedRef);
    }

    // أي رفض هنا يظهر للطبقة المستدعية؛ لا نحاول تنفيذ تحديث أضعف بدونه.
    await batch.commit();
  }
}
