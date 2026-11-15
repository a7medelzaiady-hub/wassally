import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../models/product.dart';
import '../models/store.dart';
import 'order_status_writer.dart';
import 'price_check.dart';

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
  const Courier({required this.id, required this.name, this.phone = ''});
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
    'delivered': ['تم تسليم طلبك', 'بالهنا والشفا! شكرًا لاختيارك وصّللي.'],
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
      .snapshots()
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
      .snapshots()
      .map(_toList);

  /// للمندوب: أحدث الطلبات المسندة إليه. القائمة محدودة لتقليل القراءات.
  static Stream<List<AppOrder>> watchForCourier(
    String uid, {
    int limit = 50,
  }) => _orders
      .where('courierId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(limit.clamp(1, 100).toInt())
      .snapshots()
      .map(_toList);

  /// الطلبات المتاحة للمندوبين، مع حد أقصى للقراءة في كل تحديث.
  static Stream<List<AppOrder>> watchAvailableOrders({int limit = 50}) =>
      FirebaseFirestore.instance
          .collection('courier_available_orders')
          .orderBy('createdAt', descending: true)
          .limit(limit.clamp(1, 100).toInt())
          .snapshots()
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

  /// المندوب بيسلّم: الحالة + ختم التسليم في نفس العملية.
  static Future<void> markDelivered(AppOrder order) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return setStatus(
      order.id,
      OrderStatus.delivered,
      from: order.status,
      actorRole: 'courier',
      deliveryStamp: deliveryStampFor(order, uid),
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
        .where('active', isEqualTo: true)
        .limit(limit.clamp(1, 200).toInt())
        .snapshots()
        .map((
      snap,
    ) {
      final list = <Courier>[];
      for (final d in snap.docs) {
        final m = d.data();
        list.add(
          Courier(
            id: d.id,
            name: (m['name'] ?? 'مندوب').toString(),
            phone: (m['phone'] ?? '').toString(),
          ),
        );
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
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
      final names = {for (final i in order.items) i.name}.take(30).toList();
      final extra = <Product>[];
      if (names.isNotEmpty) {
        final prods = await FirebaseFirestore.instance
            .collection('stores')
            .doc(order.storeId)
            .collection('products')
            .where('name', whereIn: names)
            .get();
        for (final d in prods.docs) {
          final m = d.data();
          final price = m['price'];
          extra.add(
            Product(
              (m['name'] ?? '').toString(),
              price is num ? price.toDouble() : 0,
              (m['image'] ?? '').toString(),
            ),
          );
        }
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

  static Future<void> assignCourier(String orderId, Courier courier) async {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجّل دخول الأول.');
    final orderRef = _orders.doc(orderId);
    final courierRef = db.collection('couriers').doc(courier.id);
    final feedRef = db.collection('courier_available_orders').doc(orderId);
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
      if (courierData['active'] != true) {
        throw StateError('المندوب غير نشط.');
      }
      tx.update(orderRef, {
        'courierId': courier.id,
        'courierName': courier.name,
        'courierPhone': courier.phone,
        'courierAt': FieldValue.serverTimestamp(),
      });
      // الطلب اتعيّن: شيله من قايمة المناديب المتاحة.
      tx.delete(feedRef);
    });

    try {
      final snap = await orderRef.get();
      await _notify(courier.id, 'طلب جديد ليك', 'تم تكليفك بطلب جديد.', orderId);
      await _notify(snap.data()?['userId']?.toString(), 'تم تعيين مندوب',
          '${courier.name} هيتولى توصيل طلبك.', orderId);
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
      });
      // رجّع الطلب للقايمة عشان باقي المناديب يشوفوه.
      tx.set(db.collection('courier_available_orders').doc(orderId),
          OrderStatusWriter.feedData(data));
    });
  }
}
