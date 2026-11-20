import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../models/product.dart';
import '../models/store.dart';
import 'order_status_writer.dart';
import 'price_check.dart';
import 'read_meter.dart';

/// إحصائيات التسليم (للمندوب أو للمدير).
class DeliveryStats {
  final int delivered;
  final double collected;
  final double earnings;
  const DeliveryStats({
    this.delivered = 0,
    this.collected = 0,
    this.earnings = 0,
  });
}

/// بداية اليوم بتوقيت الجهاز.
DateTime startOfToday() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class Courier {
  final String id;
  final String name;
  final String phone;
  final String storeId;
  const Courier({required this.id, required this.name, this.phone = '', this.storeId = ''});
}

/// عمليات المدير والمندوب على الطلبات. الصلاحيات الحقيقية في firestore.rules.
class StaffOrderService {
  const StaffOrderService._();

  static CollectionReference<Map<String, dynamic>> get _orders =>
      FirebaseFirestore.instance.collection('orders');

  // رسائل العميل حسب حالة الطلب.
  static const Map<String, List<String>> _messages = {
    'preparing': ['جاري تجهيز طلبك', 'المحل بدأ يجهّز طلبك.'],
    'on_the_way': ['طلبك في الطريق', 'المندوب استلم طلبك وهو في الطريق إليك.'],
    'delivered': ['تم تسليم طلبك', 'بالهنا والشفا! شكرًا لاختيارك وصلي.'],
    'cancelled': ['تم إلغاء طلبك', 'تم إلغاء الطلب.'],
  };

  /// بيكتب إشعار في Firestore. فشله ما يوقفش العملية الأساسية.
  static Future<void> _notify(
    String? userId,
    String title,
    String body,
    String orderId,
  ) async {
    if (userId == null || userId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': userId,
        'title': title,
        'body': body,
        'orderId': orderId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Notify error: $e');
    }
  }

  static List<AppOrder> _toList(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs
        .map((d) => AppOrder.fromMap(d.id, d.data()))
        .toList();
    list.sort((a, b) {
      // الطلب اللي لسه بيتحفظ (createdAt فاضي) بيظهر الأول.
      final aMs = a.createdAt?.millisecondsSinceEpoch ?? 1 << 53;
      final bMs = b.createdAt?.millisecondsSinceEpoch ?? 1 << 53;
      return bMs.compareTo(aMs);
    });
    return list;
  }

  /// للمدير: آخر [limit] طلب (الأحدث الأول). بنحدّ العدد عشان القراءات ما تكبرش
  /// مع الوقت. الطلبات الأقدم بتتحمّل بزيادة [limit] ("عرض المزيد").
  static Stream<List<AppOrder>> watchAll({int limit = 50}) => _orders
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots().metered('orders:admin')
      .map(_toList);

  /// لصاحب المحل: آخر [limit] طلب على محله هو بس (الأحدث الأول).
  /// محتاج فهرس (storeId + createdAt) في firestore.indexes.json.
  static Stream<List<AppOrder>> watchForStore(
    String storeId, {
    int limit = 50,
  }) => _orders
      .where('storeId', isEqualTo: storeId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots().metered('orders:store')
      .map(_toList);

  /// للمندوب: أحدث الطلبات المسندة إليه. القائمة محدودة لتقليل القراءات.
  static Stream<List<AppOrder>> watchForCourier(
    String uid, {
    int limit = 50,
  }) => _orders
      .where('courierId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit.clamp(1, 100).toInt())
      .snapshots().metered('orders:courier')
      .map(_toList);

  /// الطلبات المتاحة للمندوبين، مع حد أقصى للقراءة في كل تحديث.
  static Stream<List<AppOrder>> watchAvailableOrders({int limit = 50}) =>
      FirebaseFirestore.instance
          .collection('courier_available_orders')
          .orderBy('createdAt', descending: true)
          .limit(limit.clamp(1, 100).toInt())
          .snapshots().metered('orders:courier-feed')
          .map((s) => s.docs.map((d) => AppOrder.fromMap(d.id, d.data())).toList());

  /// إحصائيات المندوب من Firestore Aggregation، مستقلة عن قائمة الطلبات المعروضة.
  static Future<DeliveryStats> loadCourierStats(
    String uid, {
    DateTime? since,
  }) async {
    Query<Map<String, dynamic>> query = _orders
        .where('courierId', isEqualTo: uid)
        .where('deliveredBy', isEqualTo: uid)
        .where('status', isEqualTo: OrderStatus.delivered.key);
    if (since != null) {
      query = query.where(
        'deliveredAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(since),
      );
    }
    final aggregate = await query
        .aggregate(count(), sum('collectedAmount'), sum('courierEarning'))
        .get();
    return DeliveryStats(
      delivered: aggregate.count ?? 0,
      collected: (aggregate.getSum('collectedAmount') as num?)?.toDouble() ?? 0,
      earnings: (aggregate.getSum('courierEarning') as num?)?.toDouble() ?? 0,
    );
  }

  /// إحصائيات المندوب من طلباته هو (deliveredBy == uid) من بداية [since].
  /// بتتحسب من طلباته المحمّلة أصلًا، فمفيش قراءات إضافية.
  static DeliveryStats courierStats(
    Iterable<AppOrder> mine,
    String uid, {
    DateTime? since,
  }) {
    var n = 0;
    var collected = 0.0;
    var earn = 0.0;
    for (final o in mine) {
      if (o.status != OrderStatus.delivered || o.deliveredBy != uid) continue;
      final at = o.deliveredAt;
      if (since != null && (at == null || at.isBefore(since))) continue;
      n++;
      collected += o.collectedAmount;
      earn += o.courierEarning;
    }
    return DeliveryStats(delivered: n, collected: collected, earnings: earn);
  }

  /// المندوب بيستلم طلب جاهز مباشرة. batch بدل transaction لأن المندوب
  /// مايقدرش يقرا طلب مش متعيّن له، والقواعد نفسها بتضمن إن الأول بس ينجح.
  static Future<void> claimOrder(AppOrder order) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('سجّل دخول الأول.');
    final db = FirebaseFirestore.instance;
    final courierSnap = await db.collection('couriers').doc(user.uid).get();
    final c = courierSnap.data();
    if (c == null || c['active'] == false) {
      throw StateError('حساب المندوب غير موجود أو غير نشط.');
    }
    if ((c['storeId'] ?? '').toString().trim().isNotEmpty) {
      throw StateError('مندوب المحل لا يستلم طلبات خارجية من القائمة العامة.');
    }
    var name = (c['name'] ?? user.displayName ?? 'مندوب').toString().trim();
    var phone = (c['phone'] ?? '').toString().trim();
    if (name.isEmpty) name = 'مندوب';
    if (name.length > 80) name = name.substring(0, 80);
    if (phone.length > 20) phone = '';

    final batch = db.batch();
    batch.update(_orders.doc(order.id), {
      'courierId': user.uid,
      'courierName': name,
      'courierPhone': phone,
      'courierAt': FieldValue.serverTimestamp(),
      'deliveryMode': 'external',
    });
    batch.delete(db.collection('courier_available_orders').doc(order.id));
    await batch.commit(); // permission-denied = حد سبقك أو الطلب اتغيّر

    try {
      final snap = await _orders.doc(order.id).get(); // دلوقتي مسموح لأنه متعيّن لك
      await _notify(snap.data()?['userId']?.toString(), 'تم تعيين مندوب',
          '$name هيتولى توصيل طلبك.', order.id);
    } catch (e) {
      debugPrint('Claim notify error: $e');
    }
  }

  /// المندوب يسجل بلاغ التسليم فقط؛ العميل هو من يؤكد الاستلام.
  /// نعيد قراءة الطلب وملف المندوب مرة واحدة هنا لتقديم سبب واضح قبل الكتابة،
  /// مع إبقاء قواعد Firestore هي الحاجز الأمني النهائي.
  static Future<void> reportCustomerDelivery(AppOrder order) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('سجّل دخول الأول.');

    final courierRef = FirebaseFirestore.instance.collection('couriers').doc(uid);
    final orderRef = _orders.doc(order.id);
    final results = await Future.wait([orderRef.get(), courierRef.get()]);
    final orderSnapshot = results[0];
    final courierSnapshot = results[1];

    if (!courierSnapshot.exists ||
        (courierSnapshot.data()!.containsKey('active') &&
            courierSnapshot.data()!['active'] != true)) {
      throw StateError('حساب المندوب غير نشط أو غير معتمد. راجع الإدارة.');
    }
    final data = orderSnapshot.data();
    if (data == null) throw StateError('الطلب غير موجود أو تم حذفه.');
    if ((data['courierId'] ?? '').toString() != uid) {
      throw StateError('الطلب غير معيّن لحسابك. لا يمكن تسجيل التسليم.');
    }
    if (data['status'] != OrderStatus.onTheWay.key) {
      throw StateError('لازم يكون الطلب في حالة «في الطريق» قبل تسجيل التسليم.');
    }
    if (data['ready'] != true) {
      throw StateError('المحل لم يؤكد جاهزية الطلب للاستلام بعد.');
    }
    if (data['courierArrivedAt'] is! Timestamp) {
      throw StateError('سجّل وصولك إلى عنوان العميل أولاً.');
    }
    if (data.containsKey('activeDeliveryIssueId')) {
      throw StateError('يوجد بلاغ توصيل مفتوح لهذا الطلب؛ لا يمكن تسجيل التسليم الآن.');
    }
    if (data.containsKey('customerDeliveryReportedAt')) {
      throw StateError('تم تسجيل بلاغ التسليم بالفعل، انتظر تأكيد العميل.');
    }
    if (data['deliveryMode'] != 'store' && data['deliveryMode'] != 'external') {
      throw StateError('نوع المندوب غير محدد على الطلب. راجع تعيين الطلب.');
    }

    await orderRef.update({
      'customerDeliveryReportedAt': FieldValue.serverTimestamp(),
      'customerDeliveryReportedBy': uid,
    });
  }

  /// المندوب الخارجي يسجل تسليم النقدية للمحل بعد تأكيد العميل.
  static Future<void> recordCashHandedToStore(String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final ref = _orders.doc(orderId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null ||
        data['status'] != 'on_the_way' ||
        data['deliveryMode'] != 'external' ||
        data['courierId'] != uid ||
        data['customerConfirmedAt'] is! Timestamp ||
        data['cashHandedToStoreAt'] is Timestamp) {
      throw StateError('لا يمكن تسجيل تسليم النقدية في الحالة الحالية.');
    }
    await ref.update({
      'cashHandedToStoreAt': FieldValue.serverTimestamp(),
      'cashHandedToStoreBy': uid,
    });
  }

  /// صاحب المحل يؤكد استلام النقدية، وبذلك يُغلق الطلب الخارجي.
  static Future<void> confirmCashReceived(AppOrder order) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    if (order.deliveryMode != 'external' ||
        order.status != OrderStatus.onTheWay ||
        order.customerConfirmedAt == null ||
        order.cashHandedToStoreAt == null) {
      throw StateError('الطلب لم يستوفِ مراحل التسليم النقدي.');
    }
    await setStatus(
      order.id,
      OrderStatus.delivered,
      from: order.status,
      actorRole: 'storeOwner',
      deliveryStamp: deliveryStampFor(order, order.courierId),
    );
  }

  /// بيانات ختم التسليم. القواعد بتتأكد إنها مطابقة للطلب.
  static Map<String, dynamic> deliveryStampFor(
    AppOrder order,
    String courierUid, {
    double? verifiedTotal,
    double? fee,
  }) => {
    'deliveredBy': courierUid,
    'deliveredAt': FieldValue.serverTimestamp(),
    'collectedAmount': verifiedTotal ?? order.payable,
    'courierEarning': fee ?? order.courierFee,
  };

  /// إحصائيات كل المناديب (للمدير فقط): عدد التسليمات والمبالغ المحصّلة وعمولات المناديب،
  /// بتتحسب في السيرفر (aggregation) من غير ما نحمّل الطلبات. [since] = null يعني الإجمالي الكلي.
  static Future<DeliveryStats> adminStats({DateTime? since}) async {
    // نحافظ على نطاق ختم التسليم السابق، دون fallback محدود قد يعرض إجماليات ناقصة.
    final from = Timestamp.fromDate(since ?? DateTime(2020));
    final query = _orders
        .where('status', isEqualTo: OrderStatus.delivered.key)
        .where('deliveredAt', isGreaterThanOrEqualTo: from);
    try {
      final aggregate = await query
          .aggregate(count(), sum('collectedAmount'), sum('courierEarning'))
          .get();
      return DeliveryStats(
        delivered: aggregate.count ?? 0,
        collected: (aggregate.getSum('collectedAmount') as num?)?.toDouble() ?? 0,
        earnings: (aggregate.getSum('courierEarning') as num?)?.toDouble() ?? 0,
      );
    } on FirebaseException catch (error) {
      throw StateError(
        'تعذر تحميل إحصائيات التسليم (${error.code}). '
        'تحقق من فهارس Firestore وصلاحيات القراءة ثم أعد المحاولة.',
      );
    }
  }

  /// للمدير: المناديب النشطين.
  static Stream<List<Courier>> watchCouriers({int limit = 100}) {
    return FirebaseFirestore.instance
        .collection('couriers')
        .limit(limit.clamp(1, 200).toInt())
        .snapshots()
        .map((
      snap,
    ) {
      final list = <Courier>[];
      for (final d in snap.docs) {
        final m = d.data();
        // قواعد Firestore تعتبر غياب active نشطًا للتوافق مع السجلات القديمة.
        if (m.containsKey('active') && m['active'] != true) continue;
        list.add(
          Courier(
            id: d.id,
            name: (m['name'] ?? 'مندوب').toString(),
            phone: (m['phone'] ?? '').toString(),
            storeId: (m['storeId'] ?? '').toString(),
          ),
        );
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  /// مناديب المحل النشطين المرتبطين بمحل واحد؛ الاستعلام لا يعمل إلا عند فتح اختيار المندوب.
  static Stream<List<Courier>> watchStoreCouriers(String storeId, {int limit = 100}) {
    return FirebaseFirestore.instance
        .collection('couriers')
        .where('storeId', isEqualTo: storeId)
        .where('active', isEqualTo: true)
        .limit(limit.clamp(1, 100).toInt())
        .snapshots()
        .map((snap) => snap.docs.map((d) {
          final m = d.data();
          return Courier(
            id: d.id,
            name: (m['name'] ?? 'مندوب').toString(),
            phone: (m['phone'] ?? '').toString(),
            storeId: (m['storeId'] ?? '').toString(),
          );
        }).toList()..sort((a, b) => a.name.compareTo(b.name)));
  }

  /// بيغيّر الحالة. لو [verifiedTotal] اتبعت، بيعتمد الإجمالي في نفس العملية
  /// (المندوب هيحصّل المبلغ ده). القواعد بتسمح بالحقلين ده للمدير فقط.
  static Future<void> setStatus(
    String orderId,
    OrderStatus status, {
    double? verifiedTotal,
    OrderStatus? from,
    String actorRole = 'admin',
    Map<String, dynamic>? deliveryStamp,
    double? finalDeliveryFee,
  }) async {
    await OrderStatusWriter.change(
      orderId: orderId,
      to: status,
      from: from,
      actorRole: actorRole,
      extra: {
        if (verifiedTotal != null) ...{
          'verifiedTotal': verifiedTotal,
          'verifiedAt': FieldValue.serverTimestamp(),
        },
        'finalDeliveryFee': ?finalDeliveryFee,
        ...?deliveryStamp,
      },
    );

    final msg = _messages[status.key];
    if (msg == null) return;
    try {
      final snap = await _orders.doc(orderId).get();
      await _notify(
        snap.data()?['userId']?.toString(),
        msg[0],
        msg[1],
        orderId,
      );
    } catch (e) {
      debugPrint('Status notify error: $e');
    }
  }

  /// المحل (أو الأدمن) بيأكّد إن الطلب جاهز للاستلام. الحالة بتفضل «جاري التحضير»،
  /// والمندوب بيقدر يبدأ التوصيل بعد كده. القواعد بتسمح بحقلين بس: ready و readyAt.
  static Future<void> markReady(String orderId) async {
    await _orders.doc(orderId).update({
      'ready': true,
      'readyAt': FieldValue.serverTimestamp(),
    });
    try {
      final snap = await _orders.doc(orderId).get();
      await _notify(
        snap.data()?['userId']?.toString(),
        'طلبك جاهز',
        'طلبك جاهز وهيتسلّم للمندوب حالًا.',
        orderId,
      );
    } catch (e) {
      debugPrint('Ready notify error: $e');
    }
  }

  /// تسجيل وصول المندوب لعنوان العميل. لا يغيّر حالة الطلب.
  static Future<void> recordCourierArrival(String orderId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final ref = _orders.doc(orderId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null ||
        data['status'] != 'on_the_way' ||
        data['courierId'] != uid ||
        (data['activeDeliveryIssueId'] ?? '').toString().isNotEmpty) {
      throw StateError('لا يمكن تسجيل الوصول لهذه الحالة من الطلب.');
    }
    await ref.update({'courierArrivedAt': FieldValue.serverTimestamp()});
  }

  /// تسجيل تعذر التسليم بعد الوصول: يبدأ الرجوع للمحل مباشرة دون انتظار الإدارة.
  static Future<String> reportDeliveryIssue(
    AppOrder order, {
    required String reason,
    required String note,
    required bool contactAttempted,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    const allowed = {
      'no_answer',
      'wrong_address',
      'refused_order',
      'no_cash',
      'customer_requested_delay',
      'unsafe_location',
      'other',
    };
    if (!allowed.contains(reason)) throw ArgumentError.value(reason, 'reason');
    if (!contactAttempted) {
      throw StateError('سجّل محاولة الاتصال بالعميل أولًا.');
    }
    final cleanNote = note.trim();
    if (cleanNote.length > 300) throw StateError('الملاحظة أطول من المسموح.');

    final db = FirebaseFirestore.instance;
    final orderRef = _orders.doc(order.id);
    final current = await orderRef.get();
    final data = current.data();
    if (data == null ||
        data['status'] != 'on_the_way' ||
        data['courierId'] != uid ||
        data['courierArrivedAt'] is! Timestamp ||
        (data['activeDeliveryIssueId'] ?? '').toString().isNotEmpty) {
      throw StateError('سجّل وصولك للعنوان أولًا، أو حدّث الطلب قبل المحاولة.');
    }

    final issueRef = db.collection('delivery_issues').doc();
    final batch = db.batch();
    batch.set(issueRef, {
      'orderId': order.id,
      'courierId': uid,
      'customerId': order.userId,
      'storeId': order.storeId,
      'reason': reason,
      'note': cleanNote,
      'contactAttempted': true,
      'status': 'return_to_store',
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(orderRef, {'activeDeliveryIssueId': issueRef.id});
    await batch.commit();
    const reasonLabels = <String, String>{
      'no_answer': 'العميل لا يرد',
      'wrong_address': 'العنوان غير صحيح',
      'refused_order': 'رفض الاستلام',
      'no_cash': 'عدم توفر قيمة الطلب النقدي',
      'customer_requested_delay': 'طلب تأجيل التسليم',
      'unsafe_location': 'المكان غير آمن',
      'other': 'سبب آخر',
    };
    final reasonText = reasonLabels[reason] ?? 'تعذر التسليم';
    await _notify(
      order.userId,
      'تعذر تسليم طلبك — جارٍ إرجاعه للمحل',
      'السبب: $reasonText.${cleanNote.isEmpty ? '' : ' التفاصيل: $cleanNote'}',
      order.id,
    );
    return issueRef.id;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchDeliveryIssue(
    String issueId,
  ) => FirebaseFirestore.instance
      .collection('delivery_issues')
      .doc(issueId)
      .snapshots();

  /// الإدارة تحدد إعادة المحاولة أو الإرجاع للمحل بعد مراجعة البلاغ.
  static Future<void> decideDeliveryIssue({
    required String issueId,
    required String orderId,
    required String status,
    required String decision,
  }) async {
    if (!['in_review', 'retry', 'return_to_store', 'store_confirmed_return'].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final db = FirebaseFirestore.instance;
    final issueRef = db.collection('delivery_issues').doc(issueId);
    final snap = await issueRef.get();
    final data = snap.data();
    if (data == null || data['orderId'] != orderId) {
      throw StateError('بلاغ التسليم غير موجود أو لا يخص هذا الطلب.');
    }
    await issueRef.update({
      'status': status,
      'adminDecision': decision.trim().substring(
        0,
        decision.trim().length.clamp(0, 300).toInt(),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
    });
    final courierId = (data['courierId'] ?? '').toString();
    final customerId = (data['customerId'] ?? '').toString();
    final message = status == 'retry'
        ? 'الإدارة وافقت على إعادة محاولة التسليم. تواصل مع العميل واستأنف التوصيل.'
        : status == 'return_to_store'
            ? 'الإدارة طلبت إرجاع الطلب للمحل. لا تغلق الطلب قبل تأكيد الإرجاع.'
            : status == 'store_confirmed_return'
                ? 'الإدارة اعتمدت استلام المحل للمرتجع.'
                : 'الإدارة تراجع بلاغ تعذر التسليم.';
    await _notify(courierId, 'تحديث بلاغ التسليم', message, orderId);
    await _notify(customerId, 'تحديث بخصوص طلبك', message, orderId);
  }

  /// المندوب يستأنف التوصيل بعد قرار الإدارة بإعادة المحاولة.
  static Future<void> resumeDeliveryAfterIssue({
    required String orderId,
    required String issueId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final db = FirebaseFirestore.instance;
    final orderRef = _orders.doc(orderId);
    final issueRef = db.collection('delivery_issues').doc(issueId);
    final batch = db.batch();
    batch.update(issueRef, {
      'status': 'resolved',
      'courierResumedAt': FieldValue.serverTimestamp(),
      'courierResumedBy': uid,
    });
    batch.update(orderRef, {'activeDeliveryIssueId': FieldValue.delete()});
    await batch.commit();
  }

  /// صاحب المحل يؤكد استلام المرتجع فعليًا قبل أن تغلق الإدارة الطلب.
  static Future<void> confirmStoreReceivedReturn({
    required String orderId,
    required String issueId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final ref = FirebaseFirestore.instance.collection('delivery_issues').doc(issueId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null || data['orderId'] != orderId ||
        data['status'] != 'returned_to_store') {
      throw StateError('البلاغ لا ينتظر تأكيد استلام المحل.');
    }
    await ref.update({
      'status': 'store_confirmed_return',
      'storeReceivedAt': FieldValue.serverTimestamp(),
      'storeReceivedBy': uid,
    });
    await _notify(
      (data['customerId'] ?? '').toString(),
      'تم استلام مرتجع طلبك في المحل',
      'أكد المحل استلام الطلب المرتجع. يمكنك مراجعة السبب في تفاصيل الطلب.',
      orderId,
    );
  }

  /// المندوب يؤكد رجوع الطلب للمحل بعد قرار الإدارة.
  static Future<void> confirmDeliveryReturnedToStore({
    required String orderId,
    required String issueId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final ref = FirebaseFirestore.instance.collection('delivery_issues').doc(issueId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null || data['orderId'] != orderId ||
        data['courierId'] != uid || data['status'] != 'return_to_store') {
      throw StateError('قرار الإرجاع لا يخص هذا الطلب أو لم يصدر من الإدارة.');
    }
    await ref.update({
      'status': 'returned_to_store',
      'returnedAt': FieldValue.serverTimestamp(),
      'returnedBy': uid,
    });
  }

  /// المحل بيعلّم أصناف «غير متاحة» على طلب جديد (أو بيشيل العلامة لو [names] فاضية).
  /// الطلب بيفضل «جديد» والعميل بيتبلّغ يقرر: يكمّل من غيرها أو يلغي.
  static Future<void> setUnavailableItems(
    AppOrder order,
    Iterable<String> names,
  ) async {
    final clean = <String>[];
    for (final n in names) {
      final t = n.trim();
      if (t.isNotEmpty && !clean.contains(t)) clean.add(t);
    }
    if (clean.length > 20) {
      throw StateError('عدد الأصناف غير المتاحة أكبر من المسموح.');
    }
    try {
      await _orders.doc(order.id).update({
        'unavailableItems': clean.isEmpty ? FieldValue.delete() : clean,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError('الطلب اتغيّرت حالته ومبقاش ينفع تعلّم أصناف. حدّث وحاول تاني.');
      }
      if (e.code == 'unavailable') {
        throw StateError('مفيش اتصال بالإنترنت. حاول تاني.');
      }
      throw StateError('تعذر تحديث الطلب (${e.code}).');
    }
    if (clean.isEmpty) return;
    await _notify(
      order.userId,
      'صنف غير متاح في طلبك',
      '${order.storeName}: ${clean.join('، ')} غير متاح حاليًا. '
          'افتح الطلب وكمّل من غيره أو ألغيه.',
      order.id,
    );
  }

  /// اعتماد الإجمالي من غير تغيير الحالة. الحالة بتفضل زي ما هي.
  static Future<void> verifyTotal(AppOrder order, double total) {
    if (!total.isFinite || total < 0) {
      throw ArgumentError.value(total, 'total', 'المبلغ غير صالح.');
    }
    return _orders.doc(order.id).update({
      'verifiedTotal': total,
      'verifiedAt': FieldValue.serverTimestamp(),
    });
  }

  /// بيجيب المحل من Firestore (قراءة واحدة) ويقارن أسعار الطلب بالكتالوج.
  /// أي فشل في التحميل بيرجّع unknown بدل ما يوقف المدير.
  static Future<PriceCheck> checkPrices(AppOrder order) async {
    if (order.storeId.isEmpty) return const PriceCheck.unknown();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stores')
          .doc(order.storeId)
          .get();
      final data = snap.data();
      if (data == null) return const PriceCheck.unknown();

      // أصناف النظام الجديد (subcollection): بنجيب الأصناف اللي في الطلب بس.
      // الاسم في سطر الطلب ممكن يشمل اختيارات العميل، فبنعتمد على productId لو موجود.
      final ids = {
        for (final i in order.items)
          if (i.productId.isNotEmpty) i.productId,
      }.take(30).toList();
      final names = {
        for (final i in order.items)
          if (i.productId.isEmpty) i.name,
      }.take(30).toList();
      final extra = <Product>[];
      final col = FirebaseFirestore.instance
          .collection('stores')
          .doc(order.storeId)
          .collection('products');
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      if (ids.isNotEmpty) {
        docs.addAll(
          (await col.where(FieldPath.documentId, whereIn: ids).get()).docs,
        );
      }
      if (names.isNotEmpty) {
        docs.addAll((await col.where('name', whereIn: names).get()).docs);
      }
      for (final d in docs) {
        final m = d.data();
        final price = m['price'];
        extra.add(
          Product(
            (m['name'] ?? '').toString(),
            price is num ? price.toDouble() : 0,
            (m['image'] ?? '').toString(),
            d.id,
            true,
            0,
            '',
            null,
            (m['description'] ?? '').toString(),
            parseOptionGroups(m['optionGroups']),
          ),
        );
      }
      return checkOrderPrices(
        order,
        Store.fromMap(snap.id, data),
        extraProducts: extra,
      );
    } catch (e) {
      debugPrint('Price check error: $e');
      return const PriceCheck.unknown();
    }
  }

  /// يسجل توريد المندوب بأمان ويمنع تجاوز صافي المبلغ المستحق.
  ///
  /// إجمالي المستحق = النقدية المحصلة - عمولة المندوب من الطلبات المسلّمة.
  /// نقرأ إجمالي الطلبات والتوريدات القديمة قبل المعاملة؛ أي تسليم متزامن جديد
  /// يزيد المستحق فقط، لذلك قد نطلب إعادة المحاولة لكنه لا يسمح بتوريد زائد.
  /// مستند الرصيد يُحدّث داخل Transaction لتسلسل عمليات التوريد المتزامنة.
  static Future<void> recordCourierSettlement({
    required String courierId,
    required String courierName,
    required double amount,
    String note = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الإدارة.');
    if (courierId.trim().isEmpty ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 1000000 ||
        (amount * 100 - (amount * 100).round()).abs() > 0.000001) {
      throw ArgumentError('بيانات التوريد أو المبلغ غير صالح.');
    }
    final cleanNote = note.trim();
    if (cleanNote.length > 200) {
      throw ArgumentError('الملاحظة أطول من المسموح.');
    }

    final db = FirebaseFirestore.instance;
    final delivered = db.collection('orders')
        .where('deliveredBy', isEqualTo: courierId)
        .where('status', isEqualTo: OrderStatus.delivered.key);
    final totals = await delivered
        .aggregate(sum('collectedAmount'), sum('courierEarning'))
        .get();
    final collected =
        (totals.getSum('collectedAmount') as num?)?.toDouble() ?? 0;
    final earnings =
        (totals.getSum('courierEarning') as num?)?.toDouble() ?? 0;
    final totalDueMinor = ((collected - earnings) * 100).round().clamp(0, 1 << 62).toInt();

    final settlements = db.collection('courier_settlements');
    final previous = await settlements
        .where('courierId', isEqualTo: courierId)
        .aggregate(sum('amount'))
        .get();
    final legacySettled =
        (previous.getSum('amount') as num?)?.toDouble() ?? 0;
    final legacySettledMinor = (legacySettled * 100).round();
    final amountMinor = (amount * 100).round();

    final balanceRef =
        db.collection('courier_settlement_balances').doc(courierId);
    final settlementRef = settlements.doc();
    final trimmedName = courierName.trim();
    final cleanName = trimmedName.isEmpty
        ? 'مندوب'
        : trimmedName.substring(0, trimmedName.length.clamp(0, 80).toInt());

    await db.runTransaction((tx) async {
      final balanceSnap = await tx.get(balanceRef);
      final settledMinor = balanceSnap.exists
          ? ((balanceSnap.data()?['settledAmountMinor'] as num?)?.toInt() ?? 0)
          : legacySettledMinor;
      final remainingMinor = totalDueMinor - settledMinor;
      if (amountMinor > remainingMinor) {
        final remainingText =
            (remainingMinor.clamp(0, 1 << 62) / 100).toStringAsFixed(2);
        throw StateError(
          'المبلغ أكبر من المتبقي على المندوب '
          '$remainingText جنيه. حدّث البيانات وحاول تاني.',
        );
      }
      final newSettledMinor = settledMinor + amountMinor;
      tx.set(settlementRef, {
        'courierId': courierId,
        'courierName': cleanName,
        'amount': amount,
        'amountMinor': amountMinor,
        'note': cleanNote,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final balanceData = {
        'courierId': courierId,
        'settledAmountMinor': newSettledMinor,
        'lastSettlementId': settlementRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (balanceSnap.exists) {
        tx.update(balanceRef, balanceData);
      } else {
        tx.set(balanceRef, balanceData);
      }
    });
  }

  static Future<void> assignCourier(String orderId, Courier courier) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final orderRef = _orders.doc(orderId);
    final courierRef = db.collection('couriers').doc(courier.id);
    final feedRef = db.collection('courier_available_orders').doc(orderId);
    var assignedName = 'مندوب';
    await db.runTransaction((tx) async {
      final orderSnap = await tx.get(orderRef);
      final courierSnap = await tx.get(courierRef);
      if (!orderSnap.exists || !courierSnap.exists) {
        throw StateError('الطلب أو المندوب غير موجود.');
      }
      final order = orderSnap.data()!;
      final courierData = courierSnap.data()!;
      if (order['status'] != 'preparing' ||
          (order['courierId'] ?? '').toString().isNotEmpty) {
        throw StateError('الطلب لم يعد متاحًا للتعيين.');
      }
      // نفس تعريف النشاط في قواعد Firestore: غياب active يعني نشطًا
      // للتوافق مع سجلات المندوبين القديمة، والقيمة false وحدها توقف الحساب.
      if (courierData.containsKey('active') && courierData['active'] != true) {
        throw StateError('المندوب غير نشط.');
      }
      // نستخدم أحدث بيانات المندوب من المستند الذي قرأته الـ Transaction،
      // وليس نسخة قديمة محفوظة في شاشة الاختيار.
      final courierStoreId = (courierData['storeId'] ?? '').toString().trim();
      if (courierStoreId.isNotEmpty && courierStoreId != (order['storeId'] ?? '').toString()) {
        throw StateError('مندوب المحل لا يمكن تعيينه إلا لطلبات محله.');
      }
      final deliveryMode = courierStoreId.isNotEmpty ? 'store' : 'external';
      assignedName = (courierData['name'] ?? 'مندوب').toString().trim();
      if (assignedName.isEmpty) assignedName = 'مندوب';
      if (assignedName.length > 80) assignedName = assignedName.substring(0, 80);
      var assignedPhone = (courierData['phone'] ?? '').toString().trim();
      if (assignedPhone.length > 20) assignedPhone = '';
      tx.update(orderRef, {
        'courierId': courier.id,
        'courierName': assignedName,
        'courierPhone': assignedPhone,
        'courierAt': FieldValue.serverTimestamp(),
        'deliveryMode': deliveryMode,
      });
      // الطلب اتعيّن: شيله من قايمة المناديب المتاحة في نفس الـ Transaction.
      tx.delete(feedRef);
    });

    try {
      final snap = await orderRef.get();
      await _notify(courier.id, 'طلب جديد ليك', 'تم تكليفك بطلب جديد.', orderId);
      await _notify(snap.data()?['userId']?.toString(), 'تم تعيين مندوب',
          '$assignedName هيتولى توصيل طلبك.', orderId);
    } catch (e) { debugPrint('Assign notify error: $e'); }
  }

  static Future<void> unassignCourier(String orderId) async {
    final db = FirebaseFirestore.instance;
    final ref = _orders.doc(orderId);
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('الطلب غير موجود.');
      final data = snap.data()!;
      if (data['status'] != 'preparing' ||
          (data['courierId'] ?? '').toString().isEmpty) {
        throw StateError('لا يمكن إلغاء تعيين المندوب في الحالة الحالية.');
      }
      tx.update(ref, {
        'courierId': FieldValue.delete(),
        'courierName': FieldValue.delete(),
        'courierPhone': FieldValue.delete(),
        'courierAt': FieldValue.delete(),
        'deliveryMode': FieldValue.delete(),
      });
      // رجّع الطلب للقايمة عشان باقي المناديب يشوفوه.
      tx.set(db.collection('courier_available_orders').doc(orderId),
          OrderStatusWriter.feedData(data));
    });
  }
}
